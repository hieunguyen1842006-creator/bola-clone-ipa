import Foundation

/// Patch IFix của Liên Quân (LQMB) — parser/serializer byte-exact.
///
/// Layout giống IFix 0.86 nhưng **không có byte pad** sau `idmap`:
/// ```
/// magic(8) | bridge(str) | types[] | next_alloc | blocks[] |
/// methods[] | strings[] | fields[] | fsvm[] | anon[] |
/// wrapper(str) | idmap(str) | [old: pad] | interpret[] | newClasses[] | trailer
/// ```
/// `str` = u7 độ dài UTF-8 + bytes.  Số phần tử mảng = i32 LE.
///
/// Ràng buộc round-trip: parse → serialize phải ra **đúng từng byte** (đã kiểm
/// chứng trên cả 4 file `HeroSkin_1..4.bytes` của LQ 1.64.1). Vì vậy mọi thứ
/// không hiểu hết (trailer) đều được giữ nguyên dạng bytes thô.
public enum Lqmb {

    public static let magicLqmb: [UInt8] = [0xD0, 0xDB, 0x2C, 0x0E, 0x46, 0x5F, 0xD4, 0x1F]
    public static let magicOld: [UInt8] = [0xCB, 0xA2, 0xB4, 0x0D, 0xB2, 0x19, 0xA3, 0x66]

    // MARK: - model

    public struct Param {
        public var isName: Bool
        public var id: Int32
        public var name: String
        public init(isName: Bool = false, id: Int32 = -1, name: String = "") {
            self.isName = isName; self.id = id; self.name = name
        }
    }

    public struct MethodRec {
        public var isGeneric: Bool = false
        public var declType: Int32 = -1
        public var name: String = ""
        public var typeArgs: [Int32] = []
        public var params: [Param] = []
        public init() {}
    }

    public struct FieldRec {
        public var isNew: Bool = false
        public var declType: Int32 = -1
        public var name: String = ""
        public var ftype: Int32 = -1
        public var ctor: Int32 = -1
        public init() {}
    }

    public struct AnonType {
        public var fieldIds: [Int32] = []
        public var ctor: Int32 = -1
        public var paramCount: Int32 = 0
        /// Cặp (interfaceId, methodId) — file lưu 2 i32 liền nhau.
        public var interfaces: [(Int32, Int32)] = []
        public var vtable: [Int32] = []
        public init() {}
    }

    /// Một block IL. `instrs` là danh sách phẳng `[code, operand, code, operand, …]`
    /// để sửa tại chỗ không phải dựng lại tuple.
    public struct Block {
        public var instrs: [Int32] = []
        /// Mỗi handler đúng 6 i32 (try/catch offset + type + …).
        public var handlers: [[Int32]] = []
        public init() {}
        public var instructionCount: Int { instrs.count / 2 }
    }

    public struct Hook {
        public var method = MethodRec()
        public var vm: Int32 = -1
        public init() {}
    }

    public struct Patch {
        public var magic: [UInt8] = Lqmb.magicLqmb
        public var bridge: String = ""
        public var types: [String] = []
        public var nextAlloc: Int32 = 0
        public var blocks: [Block] = []
        public var methods: [MethodRec] = []
        public var strings: [String] = []
        public var fields: [FieldRec] = []
        /// Cặp (a, b) đọc từ 2 i32 liền nhau.
        public var fsvm: [(Int32, Int32)] = []
        public var anon: [AnonType] = []
        public var wrapper: String = ""
        public var idmap: String = ""
        /// Byte pad của format old-0.86 (LQMB không có).
        public var pad: UInt8 = 0
        public var interpret: [Hook] = []
        public var newClasses: [String] = []
        public var trailer: [UInt8] = []

        public init() {}

        public var isLqmb: Bool { magic == Lqmb.magicLqmb }
        public var hasPad: Bool { !isLqmb }

        public var totalInstructions: Int {
            blocks.reduce(0) { $0 + $1.instructionCount }
        }

        /// Tên đầy đủ `Owner::Method` để hiển thị/log.
        public func qualifiedName(_ m: MethodRec) -> String {
            var owner = "<type?>"
            if m.declType >= 0 && Int(m.declType) < types.count {
                let t = types[Int(m.declType)]
                owner = t.split(separator: ",").first.map(String.init) ?? t
            }
            return "\(owner)::\(m.name)"
        }

        public func hook(ofVm vm: Int) -> Hook? {
            interpret.first { $0.vm == Int32(vm) }
        }
    }

    public enum LqmbError: Error, CustomStringConvertible {
        case badMagic([UInt8])
        case truncated(String, need: Int, have: Int)
        case negativeCount(String, Int32)
        case absurdCount(String, Int32)
        case varintTooLong
        case nextAllocMismatch(Int32, Int)
        case handlerSize(Int)

        public var description: String {
            switch self {
            case .badMagic(let b):
                return "IFix: magic \(b.map { String(format: "%02x", $0) }.joined()) không thuộc LQMB/old-0.86"
            case .truncated(let w, let need, let have):
                return "IFix: hết dữ liệu ở \(w) (cần \(need), còn \(have))"
            case .negativeCount(let w, let v):
                return "IFix: \(w) có count âm (\(v))"
            case .absurdCount(let w, let v):
                return "IFix: \(w) khai báo \(v) phần tử — vượt dữ liệu"
            case .varintTooLong:
                return "IFix: u7 varint quá 5 byte"
            case .nextAllocMismatch(let a, let b):
                return "IFix: next_alloc=\(a) nhưng có \(b) block"
            case .handlerSize(let n):
                return "IFix: handler phải có đúng 6 phần tử, nhận \(n)"
            }
        }
    }

    // MARK: - reader

    struct Reader {
        let buf: [UInt8]
        var pos = 0
        init(_ b: [UInt8]) { buf = b }
        var remaining: Int { buf.count - pos }

        mutating func need(_ k: Int, _ what: String) throws {
            guard remaining >= k else {
                throw LqmbError.truncated(what, need: k, have: remaining)
            }
        }

        mutating func u8(_ what: String) throws -> UInt8 {
            try need(1, what)
            let v = buf[pos]; pos += 1
            return v
        }

        mutating func i32(_ what: String) throws -> Int32 {
            try need(4, what)
            let v = Int32(bitPattern: UInt32(buf[pos])
                | (UInt32(buf[pos + 1]) << 8)
                | (UInt32(buf[pos + 2]) << 16)
                | (UInt32(buf[pos + 3]) << 24))
            pos += 4
            return v
        }

        mutating func u7(_ what: String) throws -> Int {
            var v = 0
            var shift = 0
            for _ in 0..<5 {
                let b = try u8(what)
                v |= Int(b & 0x7F) << shift
                if (b & 0x80) == 0 { return v }
                shift += 7
            }
            throw LqmbError.varintTooLong
        }

        mutating func string(_ what: String) throws -> String {
            let n = try u7(what)
            try need(n, what)
            let s = String(decoding: buf[pos..<(pos + n)], as: UTF8.self)
            pos += n
            return s
        }

        /// Đọc count và kiểm tra hợp lý: `minBytes` byte tối thiểu mỗi phần tử.
        mutating func count(_ what: String, minBytes: Int) throws -> Int {
            let v = try i32(what)
            if v < 0 { throw LqmbError.negativeCount(what, v) }
            if minBytes > 0 && Int(v) * minBytes > remaining {
                throw LqmbError.absurdCount(what, v)
            }
            return Int(v)
        }

        mutating func raw(_ n: Int, _ what: String) throws -> [UInt8] {
            try need(n, what)
            let s = Array(buf[pos..<(pos + n)])
            pos += n
            return s
        }
    }

    // MARK: - writer

    struct Writer {
        var out: [UInt8] = []
        mutating func u8(_ v: UInt8) { out.append(v) }

        mutating func i32(_ v: Int32) {
            let u = UInt32(bitPattern: v)
            out.append(UInt8(u & 0xFF))
            out.append(UInt8((u >> 8) & 0xFF))
            out.append(UInt8((u >> 16) & 0xFF))
            out.append(UInt8((u >> 24) & 0xFF))
        }

        mutating func u7(_ n: Int) {
            var v = n
            while true {
                if v < 0x80 { u8(UInt8(v)); return }
                u8(UInt8((v & 0x7F) | 0x80))
                v >>= 7
            }
        }

        mutating func string(_ s: String) {
            let b = Array(s.utf8)
            u7(b.count)
            out.append(contentsOf: b)
        }

        mutating func raw(_ b: [UInt8]) { out.append(contentsOf: b) }
    }

    // MARK: - method record

    static func readMethod(_ r: inout Reader, _ what: String) throws -> MethodRec {
        var m = MethodRec()
        m.isGeneric = try r.u8(what) != 0
        m.declType = try r.i32(what)
        m.name = try r.string(what + ".name")
        if m.isGeneric {
            let n = try r.count(what + ".targs", minBytes: 4)
            for _ in 0..<n { m.typeArgs.append(try r.i32(what)) }
        }
        let np = try r.count(what + ".params", minBytes: m.isGeneric ? 1 : 4)
        for _ in 0..<np {
            var p = Param()
            if m.isGeneric {
                p.isName = try r.u8(what) != 0
                if p.isName { p.name = try r.string(what) }
                else { p.id = try r.i32(what) }
            } else {
                p.id = try r.i32(what)
            }
            m.params.append(p)
        }
        return m
    }

    static func writeMethod(_ w: inout Writer, _ m: MethodRec) {
        w.u8(m.isGeneric ? 1 : 0)
        w.i32(m.declType)
        w.string(m.name)
        if m.isGeneric {
            w.i32(Int32(m.typeArgs.count))
            for v in m.typeArgs { w.i32(v) }
        }
        w.i32(Int32(m.params.count))
        for p in m.params {
            if m.isGeneric { w.u8(p.isName ? 1 : 0) }
            if p.isName { w.string(p.name) } else { w.i32(p.id) }
        }
    }

    // MARK: - parse

    public static func isLqmb(_ d: [UInt8]) -> Bool {
        d.count >= 8 && Array(d[0..<8]) == magicLqmb
    }

    public static func parse(_ data: [UInt8]) throws -> Patch {
        var r = Reader(data)
        var pf = Patch()
        let head = try r.raw(8, "magic")
        if head == magicLqmb {
            pf.magic = magicLqmb
        } else if head == magicOld {
            pf.magic = magicOld
        } else {
            throw LqmbError.badMagic(head)
        }
        let hasPad = pf.hasPad

        pf.bridge = try r.string("bridge")

        let nTypes = try r.count("types", minBytes: 1)
        pf.types = []
        pf.types.reserveCapacity(nTypes)
        for _ in 0..<nTypes { pf.types.append(try r.string("types")) }

        pf.nextAlloc = try r.i32("next_alloc")
        if pf.nextAlloc < 0 { throw LqmbError.negativeCount("next_alloc", pf.nextAlloc) }
        for bi in 0..<Int(pf.nextAlloc) {
            var blk = Block()
            let cnt = try r.count("block[\(bi)].instrs", minBytes: 8)
            blk.instrs.reserveCapacity(cnt * 2)
            for _ in 0..<cnt {
                let code = try r.i32("instr.code")
                let op = try r.i32("instr.op")
                blk.instrs.append(code)
                blk.instrs.append(op)
            }
            let ehc = try r.count("block[\(bi)].handlers", minBytes: 24)
            for _ in 0..<ehc {
                var h: [Int32] = []
                h.reserveCapacity(6)
                for _ in 0..<6 { h.append(try r.i32("handler")) }
                blk.handlers.append(h)
            }
            pf.blocks.append(blk)
        }

        let nMethods = try r.count("methods", minBytes: 6)
        pf.methods = []
        pf.methods.reserveCapacity(nMethods)
        for _ in 0..<nMethods { pf.methods.append(try readMethod(&r, "methods")) }

        let nStrings = try r.count("strings", minBytes: 1)
        pf.strings = []
        pf.strings.reserveCapacity(nStrings)
        for _ in 0..<nStrings { pf.strings.append(try r.string("strings")) }

        let nFields = try r.count("fields", minBytes: 6)
        for _ in 0..<nFields {
            var f = FieldRec()
            f.isNew = try r.u8("fields") != 0
            f.declType = try r.i32("fields")
            f.name = try r.string("fields.name")
            if f.isNew {
                f.ftype = try r.i32("fields")
                f.ctor = try r.i32("fields")
            }
            pf.fields.append(f)
        }

        let nFsvm = try r.count("fsvm", minBytes: 8)
        for _ in 0..<nFsvm {
            let a = try r.i32("fsvm")
            let b = try r.i32("fsvm")
            pf.fsvm.append((a, b))
        }

        let nAnon = try r.count("anon", minBytes: 20)
        for _ in 0..<nAnon {
            var an = AnonType()
            let nf = try r.count("anon.fields", minBytes: 4)
            for _ in 0..<nf { an.fieldIds.append(try r.i32("anon.fields")) }
            an.ctor = try r.i32("anon")
            an.paramCount = try r.i32("anon")
            let nif = try r.count("anon.interfaces", minBytes: 8)
            for _ in 0..<nif {
                let a = try r.i32("iface")
                let b = try r.i32("iface")
                an.interfaces.append((a, b))
            }
            let nv = try r.count("anon.vtable", minBytes: 4)
            for _ in 0..<nv { an.vtable.append(try r.i32("anon.vtable")) }
            pf.anon.append(an)
        }

        pf.wrapper = try r.string("wrapper")
        pf.idmap = try r.string("idmap")
        if hasPad { pf.pad = try r.u8("pad") }

        let nInterp = try r.count("interpret", minBytes: 6)
        for _ in 0..<nInterp {
            var h = Hook()
            h.method = try readMethod(&r, "interpret")
            h.vm = try r.i32("interpret.vm")
            pf.interpret.append(h)
        }

        let nClasses = try r.count("newClasses", minBytes: 1)
        pf.newClasses = []
        pf.newClasses.reserveCapacity(nClasses)
        for _ in 0..<nClasses { pf.newClasses.append(try r.string("newClasses")) }

        let tailLen = r.remaining
        pf.trailer = try r.raw(tailLen, "trailer")
        return pf
    }

    // MARK: - serialize

    public static func serialize(_ pf: Patch) throws -> [UInt8] {
        if pf.nextAlloc != Int32(pf.blocks.count) {
            throw LqmbError.nextAllocMismatch(pf.nextAlloc, pf.blocks.count)
        }
        var w = Writer()
        w.out.reserveCapacity(1 << 18)
        w.raw(pf.magic)
        w.string(pf.bridge)
        w.i32(Int32(pf.types.count))
        for t in pf.types { w.string(t) }

        w.i32(pf.nextAlloc)
        for blk in pf.blocks {
            guard blk.instrs.count % 2 == 0 else {
                throw LqmbError.handlerSize(blk.instrs.count)
            }
            w.i32(Int32(blk.instrs.count / 2))
            for v in blk.instrs { w.i32(v) }
            w.i32(Int32(blk.handlers.count))
            for h in blk.handlers {
                guard h.count == 6 else { throw LqmbError.handlerSize(h.count) }
                for v in h { w.i32(v) }
            }
        }

        w.i32(Int32(pf.methods.count))
        for m in pf.methods { writeMethod(&w, m) }

        w.i32(Int32(pf.strings.count))
        for s in pf.strings { w.string(s) }

        w.i32(Int32(pf.fields.count))
        for f in pf.fields {
            w.u8(f.isNew ? 1 : 0)
            w.i32(f.declType)
            w.string(f.name)
            if f.isNew {
                w.i32(f.ftype)
                w.i32(f.ctor)
            }
        }

        w.i32(Int32(pf.fsvm.count))
        for (a, b) in pf.fsvm { w.i32(a); w.i32(b) }

        w.i32(Int32(pf.anon.count))
        for an in pf.anon {
            w.i32(Int32(an.fieldIds.count))
            for v in an.fieldIds { w.i32(v) }
            w.i32(an.ctor)
            w.i32(an.paramCount)
            w.i32(Int32(an.interfaces.count))
            for (a, b) in an.interfaces { w.i32(a); w.i32(b) }
            w.i32(Int32(an.vtable.count))
            for v in an.vtable { w.i32(v) }
        }

        w.string(pf.wrapper)
        w.string(pf.idmap)
        if pf.hasPad { w.u8(pf.pad) }

        w.i32(Int32(pf.interpret.count))
        for h in pf.interpret {
            writeMethod(&w, h.method)
            w.i32(h.vm)
        }

        w.i32(Int32(pf.newClasses.count))
        for c in pf.newClasses { w.string(c) }

        w.raw(pf.trailer)
        return w.out
    }

    /// Round-trip an toàn: parse rồi serialize, so từng byte.
    public static func roundTrip(_ data: [UInt8]) throws -> (ok: Bool, firstDiff: Int?, out: [UInt8]) {
        let pf = try parse(data)
        let out = try serialize(pf)
        if out.count != data.count { return (false, nil, out) }
        for i in 0..<out.count where out[i] != data[i] {
            return (false, i, out)
        }
        return (true, nil, out)
    }
}
