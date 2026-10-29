import Foundation

/// Sinh patch IFix LQMB **từ zero** — không cần payload của ai, không cần dump IL.
///
/// Ý tưởng: patch IFix không phải file bị tiêm vào binary game; nó là file độc lập
/// game load thêm lúc chạy. Vì vậy ta có thể tự viết một file patch tối giản chỉ
/// chứa đúng những hook mình cần, rồi để IFix resolve bằng reflection theo tên.
///
/// Đã kiểm chứng bằng `tools/gen_lq_patch.py` (cùng thuật toán):
///   - cấu trúc đối chiếu `HeroSkin_4.bytes` thật (patch tối giản 2.197 B của game)
///   - round-trip byte-exact qua `Lqmb.serialize` / `Lqmb.parse`
///   - container ResD decrypt lại khớp
///
/// Lưu ý: chưa chạy thử trên máy game thật — cần verify bằng cách thả file vào
/// `Documents/Resources/<ver>/Thanos/HeroSkin_1.bytes` rồi mở Liên Quân.
public enum LqGenerator {

    // MARK: - opcode (bảng LQMB v2.2)

    enum Op {
        static let blockHeader: Int32 = 0x92
        static let ldarg: Int32 = 0xA4
        static let callExtern: Int32 = 0x7A
        static let ldstr: Int32 = 0x27
        static let ldcR4: Int32 = 0x8D
        static let ldcI4: Int32 = 0x8F
        static let mul: Int32 = 0xB3
        static let stloc: Int32 = 0x24
        static let ldloc: Int32 = 0x48
        static let ret: Int32 = 0xAD
    }

    // MARK: - tên type đầy đủ (khớp dump.cs LQ 1.64.1)

    static let asmProject = "Project_d, Version=0.0.0.0, Culture=neutral, PublicKeyToken=null"
    static let asmMsCorLib = "mscorlib, Version=4.0.0.0, Culture=neutral, PublicKeyToken=b77a5c561934e089"
    static let asmUnityCore = "UnityEngine.CoreModule, Version=0.0.0.0, Culture=neutral, PublicKeyToken=null"

    static let tBridge = "IFix.ILFixInterfaceBridge, \(asmProject)"
    static let tBool = "System.Boolean, \(asmMsCorLib)"
    static let tSingle = "System.Single, \(asmMsCorLib)"
    static let tInt32 = "System.Int32, \(asmMsCorLib)"
    static let tUInt64 = "System.UInt64, \(asmMsCorLib)"
    static let tString = "System.String, \(asmMsCorLib)"
    static let tCamSys = "CameraSystem, \(asmProject)"
    static let tPrefs = "UnityEngine.PlayerPrefs, \(asmUnityCore)"
    static let tRoleMgr = "Assets.Scripts.GameSystem.CRoleInfoManager, \(asmProject)"
    static let tPrivMask = "Assets.Scripts.GameSystem.COM_USER_PRIVACY_MASK, \(asmProject)"
    static let tProfile = "Assets.Scripts.GameSystem.CPlayerProfile, \(asmProject)"

    static let wrapperImpl = "IFix.WrappersManagerImpl, \(asmProject)"
    static let idmapImpl = ", \(asmProject)"

    /// Prefix key PlayerPrefs mà patch dùng để đọc/ghi hệ số zoom.
    public static let zoomPrefKey = "iFix.Camera.Zoom.v1"

    // MARK: - helper

    @inline(__always)
    static func f32bits(_ x: Float) -> Int32 {
        Int32(bitPattern: x.bitPattern)
    }

    /// Một lệnh IL: (code, operand).
    struct Ins {
        let code: Int32
        let operand: Int32
    }

    // MARK: - builder

    /// Gom type / method / string theo nhu cầu, trả index ổn định.
    public final class Builder {
        var types: [String] = [tBridge]
        var methods: [Lqmb.MethodRec] = []
        var strings: [String] = []
        var blocks: [Lqmb.Block] = []
        var hooks: [Lqmb.Hook] = []

        func typeId(_ full: String) -> Int32 {
            if let i = types.firstIndex(of: full) { return Int32(i) }
            types.append(full)
            return Int32(types.count - 1)
        }

        func strId(_ s: String) -> Int32 {
            if let i = strings.firstIndex(of: s) { return Int32(i) }
            strings.append(s)
            return Int32(strings.count - 1)
        }

        func methodId(declType: Int32, name: String, params: [Int32]) -> Int32 {
            for (i, m) in methods.enumerated() {
                guard m.declType == declType, m.name == name,
                      m.params.count == params.count else { continue }
                if zip(m.params, params).allSatisfy({ $0.id == $1 }) { return Int32(i) }
            }
            var rec = Lqmb.MethodRec()
            rec.declType = declType
            rec.name = name
            rec.params = params.map { Lqmb.Param(isName: false, id: $0, name: "") }
            methods.append(rec)
            return Int32(methods.count - 1)
        }

        func method(_ typeFull: String, _ name: String, _ paramTypes: [String]) -> Int32 {
            methodId(declType: typeId(typeFull), name: name,
                     params: paramTypes.map { typeId($0) })
        }

        /// Thêm một block IL và hook nó vào method.
        /// - Parameter body: các lệnh sau BlockHeader, trước Ret.
        /// - Parameter locals: số biến cục bộ (BlockHeader high 16 bit).
        /// - Parameter maxStack: độ sâu stack tối đa (BlockHeader low 16 bit).
        ///
        /// Thứ tự đăng ký: method phụ thuộc trong `body` TRƯỚC, rồi mới tới method
        /// bị hook — khớp `tools/gen_lq_patch.py` để hai bản ra cùng bytes.
        @discardableResult
        func addHook(typeFull: String, name: String, paramTypes: [String],
                     locals: Int, maxStack: Int,
                     body: (Builder) -> [Ins]) -> Int {
            let vm = blocks.count
            let bodyIns = body(self)          // deps đăng ký trước
            let mid = method(typeFull, name, paramTypes)
            let decl = types[Int(methods[Int(mid)].declType)]

            var blk = Lqmb.Block()
            blk.instrs.append(Op.blockHeader)
            blk.instrs.append((Int32(locals) << 16) | Int32(maxStack))
            for ins in bodyIns {
                blk.instrs.append(ins.code)
                blk.instrs.append(ins.operand)
            }
            let retCount: Int32 = decl.hasPrefix("System.Void") ? 0 : 1
            blk.instrs.append(Op.ret)
            blk.instrs.append(retCount)
            blocks.append(blk)

            var h = Lqmb.Hook()
            h.method = methods[Int(mid)]
            h.vm = Int32(vm)
            hooks.append(h)
            return vm
        }

        func build() -> Lqmb.Patch {
            var pf = Lqmb.Patch()
            pf.magic = Lqmb.magicLqmb
            pf.bridge = tBridge
            pf.types = types
            pf.nextAlloc = Int32(blocks.count)
            pf.blocks = blocks
            pf.methods = methods
            pf.strings = strings
            pf.wrapper = wrapperImpl
            pf.idmap = idmapImpl
            pf.interpret = hooks
            return pf
        }
    }

    // MARK: - patch dựng sẵn

    /// Sinh patch chỉ có zoom (`CameraSystem.GetZoomRate`).
    public static func zoomPatch(zoom: Float) -> Lqmb.Patch {
        var cfg = LqConfig()
        cfg.zoom = zoom
        return makePatch(cfg) ?? Lqmb.Patch()
    }

    /// Sinh patch từ cấu hình UI. Trả nil nếu không có tính năng nào được chọn.
    public static func makePatch(_ cfg: LqConfig) -> Lqmb.Patch? {
        let hasZoom = (cfg.zoom ?? 0) > 0
        guard hasZoom || cfg.privacyOff != nil || cfg.fakeHost != nil else { return nil }

        let b = Builder()

        if let zoom = cfg.zoom, zoom > 0 {
            b.addHook(typeFull: tCamSys, name: "GetZoomRate", paramTypes: [],
                      locals: 1, maxStack: 3) { bb in
                let mAge = bb.method(tCamSys, "get_ZoomRateFromAge", [])
                let mGetF = bb.method(tPrefs, "GetFloat", [tString, tSingle])
                let sKey = bb.strId(zoomPrefKey)
                return [
                    Ins(code: Op.ldarg, operand: 0),
                    Ins(code: Op.callExtern, operand: (1 << 16) | mAge),
                    Ins(code: Op.ldstr, operand: sKey),
                    Ins(code: Op.ldcR4, operand: f32bits(zoom)),
                    Ins(code: Op.callExtern, operand: (2 << 16) | mGetF),
                    Ins(code: Op.mul, operand: 0),
                    Ins(code: Op.stloc, operand: 0),
                    Ins(code: Op.ldloc, operand: 0),
                ]
            }
        }

        if let off = cfg.privacyOff, off {
            // 2 overload: (ulong, COM_USER_PRIVACY_MASK) và (ulong, int)
            for maskType in [tPrivMask, tInt32] {
                b.addHook(typeFull: tRoleMgr, name: "IsPrivaceOn",
                          paramTypes: [tUInt64, maskType],
                          locals: 1, maxStack: 1) { bb in
                    [Ins(code: Op.ldcI4, operand: 0),
                     Ins(code: Op.stloc, operand: 0),
                     Ins(code: Op.ldloc, operand: 0)]
                }
            }
        }

        if let fake = cfg.fakeHost {
            b.addHook(typeFull: tProfile, name: "get_IsHostProfile", paramTypes: [],
                      locals: 1, maxStack: 1) { bb in
                [Ins(code: Op.ldcI4, operand: fake ? 1 : 0),
                 Ins(code: Op.stloc, operand: 0),
                 Ins(code: Op.ldloc, operand: 0)]
            }
        }

        return b.build()
    }

    // MARK: - kiểm tra

    /// Kết quả tự kiểm tra một patch vừa sinh.
    public struct Check {
        public let ok: Bool
        public let detail: String
    }

    /// Verify: round-trip byte-exact, hook trỏ đúng block, operand trong phạm vi.
    public static func verify(_ pf: Lqmb.Patch) -> Check {
        guard let blob = try? Lqmb.serialize(pf) else {
            return Check(ok: false, detail: "serialize thất bại")
        }
        guard let back = try? Lqmb.parse(blob) else {
            return Check(ok: false, detail: "parse lại thất bại")
        }
        guard let again = try? Lqmb.serialize(back), again == blob else {
            return Check(ok: false, detail: "round-trip không byte-exact")
        }
        guard back.nextAlloc == Int32(back.blocks.count) else {
            return Check(ok: false, detail: "next_alloc lệch")
        }
        guard back.blocks.count == pf.blocks.count,
              back.interpret.count == pf.interpret.count else {
            return Check(ok: false, detail: "số block/hook lệch")
        }
        for (a, b) in zip(pf.blocks, back.blocks) where a.instrs != b.instrs {
            return Check(ok: false, detail: "IL đổi sau round-trip")
        }
        for h in back.interpret {
            let vm = Int(h.vm)
            guard vm >= 0, vm < back.blocks.count else {
                return Check(ok: false, detail: "hook vm\(vm) ngoài phạm vi")
            }
        }
        for blk in back.blocks {
            var i = 0
            while i + 1 < blk.instrs.count {
                let code = blk.instrs[i], op = blk.instrs[i + 1]
                if code == Op.callExtern {
                    let mi = Int(op & 0xFFFF)
                    guard mi < back.methods.count else {
                        return Check(ok: false, detail: "method index ngoài phạm vi")
                    }
                } else if code == Op.ldstr {
                    guard Int(op) < back.strings.count else {
                        return Check(ok: false, detail: "string index ngoài phạm vi")
                    }
                }
                i += 2
            }
        }
        return Check(ok: true,
                     detail: "\(back.blocks.count) block, "
                        + "\(back.totalInstructions) lệnh, "
                        + "\(back.interpret.count) hook")
    }

    /// Mô tả ngắn để hiện trong log.
    public static func summary(_ pf: Lqmb.Patch) -> String {
        guard !pf.interpret.isEmpty else { return "patch rỗng" }
        return pf.interpret.map { h in
            let name = pf.qualifiedName(h.method)
            let short = name.split(separator: "::").last.map(String.init) ?? name
            return short
        }.joined(separator: ", ")
    }
}
