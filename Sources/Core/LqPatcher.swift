import Foundation

/// Bảng opcode LQMB (v2.2) — chỉ những mã patcher cần dùng + tên để hiển thị.
///
/// Nguồn: `opcode_table_lqmb_v2.json`, neo bằng stack-depth solver trên 4 file
/// `HeroSkin_1..4.bytes` (HS3/HS4 ra 0 violation tuyệt đối).
public enum LqOpcode {
    public static let ldcR8Hi: Int32     = 0x00
    public static let ldcR8Lo: Int32     = 0x64
    public static let ldcR4: Int32       = 0x8D
    public static let ldcI4: Int32       = 0x8F
    public static let ldstr: Int32       = 0x27
    public static let blockHeader: Int32 = 0x92
    public static let ret: Int32         = 0xAD
    public static let mul: Int32         = 0xB3
    public static let br: Int32          = 0x5D

    static let names: [Int32: String] = [
        0x00: "Ldc_R8_hi", 0x02: "Cgt_Un", 0x05: "Op_0x05", 0x06: "Op_0x06",
        0x07: "Conv_I8", 0x08: "Op_0x08", 0x0B: "Bgt", 0x0D: "Ldloca",
        0x11: "Ble", 0x15: "Op_0x15", 0x16: "Constrained", 0x17: "Stelem_Any",
        0x18: "Castclass2", 0x22: "Box", 0x24: "Stloc", 0x25: "Op_0x25",
        0x27: "Ldstr", 0x28: "Cgt", 0x2A: "Op_0x2A", 0x2B: "Bne_Un",
        0x2C: "Nop2", 0x2D: "Call", 0x2F: "Blt", 0x30: "Op_0x30",
        0x36: "Op_0x36", 0x38: "Nop3", 0x3A: "Conv_R4", 0x3C: "Ldsfld",
        0x3E: "Op_0x3E", 0x44: "Sqrt", 0x45: "Conv_I4", 0x48: "Ldloc",
        0x49: "Newobj", 0x4B: "Stfld", 0x4D: "BrVar", 0x4F: "Op_0x4F",
        0x50: "Add", 0x54: "Div", 0x55: "PopVar", 0x57: "Throw",
        0x58: "Castclass", 0x59: "Newarr", 0x5A: "Op_0x5A", 0x5D: "Br",
        0x5E: "Ldtoken", 0x60: "StructCmp", 0x63: "Op_0x63", 0x64: "Ldc_R8_lo",
        0x67: "GetTypeFromHandle", 0x6D: "Clt", 0x6E: "Beq", 0x6F: "BrFam_Un",
        0x74: "Op_0x74", 0x75: "Ldnull", 0x77: "CeqNullVar", 0x78: "Box_I4",
        0x7A: "CallExtern", 0x7D: "Bge", 0x7E: "Sub", 0x7F: "Brtrue",
        0x80: "Pop", 0x81: "Ldelem_Ref", 0x83: "Op_0x83", 0x84: "Op_0x84",
        0x85: "Isinst", 0x86: "Brfalse", 0x8A: "Castclass3", 0x8B: "Ldlen",
        0x8C: "Op_0x8C", 0x8D: "Ldc_R4", 0x8F: "Ldc_I4", 0x90: "Dup",
        0x92: "BlockHeader", 0x94: "And", 0x95: "Op_0x95", 0x97: "Initobj",
        0x99: "Leave", 0x9C: "Ldelem_I4", 0x9E: "Stind_I4", 0xA0: "Op_0xA0",
        0xA1: "Op_0xA1", 0xA4: "Ldarg", 0xA6: "Ceq", 0xA7: "Ldfld",
        0xAA: "Op_0xAA", 0xAC: "Op_0xAC", 0xAD: "Ret", 0xAF: "Stelem_Ref",
        0xB0: "CmpFam", 0xB1: "Endfinally", 0xB3: "Mul",
    ]

    public static func name(_ code: Int32) -> String {
        names[code & 0xFF] ?? String(format: "0x%02X?", code & 0xFF)
    }
}

/// Cấu hình patch runtime cho một file `HeroSkin_*.bytes`.
public struct LqConfig {
    /// Hệ số zoom camera (`CameraSystem.GetZoomRate`). nil = không đụng.
    public var zoom: Float?
    /// true = `CRoleInfoManager.IsPrivaceOn` trả false (xem được profile người khác).
    public var privacyOff: Bool?
    /// true = `CPlayerProfile.get_IsHostProfile` trả true (giả host).
    public var fakeHost: Bool?
    /// Thay chuỗi tag trong patch. PHẢI cùng độ dài UTF-8 với bản gốc.
    public var tagText: String?

    public init(zoom: Float? = nil, privacyOff: Bool? = nil,
                fakeHost: Bool? = nil, tagText: String? = nil) {
        self.zoom = zoom
        self.privacyOff = privacyOff
        self.fakeHost = fakeHost
        self.tagText = tagText
    }

    public var isEmpty: Bool {
        zoom == nil && privacyOff == nil && fakeHost == nil && tagText == nil
    }
}

/// Kết quả patch — đủ để UI hiện "đã sửa gì" thay vì im lặng.
public struct LqPatchReport {
    public var zoomSites = 0
    public var privacySites = 0
    public var hostSites = 0
    public var stringSites = 0
    public var notes: [String] = []

    public init() {}

    public var totalSites: Int {
        zoomSites + privacySites + hostSites + stringSites
    }

    public var summary: String {
        var parts: [String] = []
        if zoomSites > 0 { parts.append("zoom ×\(zoomSites)") }
        if privacySites > 0 { parts.append("privacy ×\(privacySites)") }
        if hostSites > 0 { parts.append("host ×\(hostSites)") }
        if stringSites > 0 { parts.append("tag ×\(stringSites)") }
        return parts.isEmpty ? "không đổi gì" : parts.joined(separator: ", ")
    }
}

/// Sửa nội dung patch IFix theo `LqConfig`.
///
/// Nguyên tắc: **không đổi số lệnh, không đổi độ dài chuỗi** → file sau khi
/// serialize vẫn đúng layout, game đọc bình thường. Mọi thay đổi chỉ là ghi đè
/// operand của một lệnh có sẵn.
public enum LqPatcher {

    /// Tìm block được hook vào method có tên kết thúc bằng `suffix`.
    public static func blocks(hookedTo suffix: String, in pf: Lqmb.Patch) -> [Int] {
        pf.interpret.compactMap { h in
            let name = pf.qualifiedName(h.method)
            guard name.hasSuffix(suffix) else { return nil }
            let vm = Int(h.vm)
            return (vm >= 0 && vm < pf.blocks.count) ? vm : nil
        }
    }

    /// Ghi đè operand của lệnh `code` đầu tiên (hoặc tất cả) trong block.
    @discardableResult
    static func overwrite(_ code: Int32, in block: inout Lqmb.Block,
                          onlyValues values: Set<Int32>? = nil,
                          all: Bool = false,
                          with newValue: Int32) -> Int {
        var hits = 0
        var i = 0
        while i + 1 < block.instrs.count {
            if block.instrs[i] == code {
                let old = block.instrs[i + 1]
                let allowed = values == nil || values!.contains(old)
                if allowed {
                    block.instrs[i + 1] = newValue
                    hits += 1
                    if !all { return 1 }
                }
            }
            i += 2
        }
        return hits
    }

    @inline(__always)
    static func floatBits(_ f: Float) -> Int32 {
        Int32(bitPattern: f.bitPattern)
    }

    /// Áp cấu hình lên patch (sửa tại chỗ, trả báo cáo).
    public static func apply(_ pf: inout Lqmb.Patch, config: LqConfig) -> LqPatchReport {
        var rep = LqPatchReport()

        if let zoom = config.zoom, zoom > 0 {
            let targets = blocks(hookedTo: "CameraSystem::GetZoomRate", in: pf)
            if targets.isEmpty {
                rep.notes.append("không thấy hook GetZoomRate")
            }
            for vm in targets {
                let hits = overwrite(LqOpcode.ldcR4, in: &pf.blocks[vm],
                                     all: false, with: floatBits(zoom))
                rep.zoomSites += hits
                if hits == 0 {
                    rep.notes.append("vm\(vm): không có lệnh Ldc_R4 để đổi zoom")
                }
            }
        }

        if let off = config.privacyOff {
            let targets = blocks(hookedTo: "CRoleInfoManager::IsPrivaceOn", in: pf)
            if targets.isEmpty { rep.notes.append("không thấy hook IsPrivaceOn") }
            for vm in targets {
                // Chỉ đụng Ldc_I4 có giá trị 0/1 (đừng phá các hằng khác).
                let hits = overwrite(LqOpcode.ldcI4, in: &pf.blocks[vm],
                                     onlyValues: [0, 1], all: false,
                                     with: off ? 0 : 1)
                rep.privacySites += hits
            }
        }

        if let host = config.fakeHost {
            let targets = blocks(hookedTo: "CPlayerProfile::get_IsHostProfile", in: pf)
            if targets.isEmpty { rep.notes.append("không thấy hook get_IsHostProfile") }
            for vm in targets {
                let hits = overwrite(LqOpcode.ldcI4, in: &pf.blocks[vm],
                                     onlyValues: [0, 1], all: false,
                                     with: host ? 1 : 0)
                rep.hostSites += hits
            }
        }

        if let tag = config.tagText {
            let oldTag = "[skin v4]"
            let newTag = "[\(tag)]"
            let oldLen = oldTag.utf8.count
            let newLen = newTag.utf8.count
            if oldLen != newLen {
                rep.notes.append("tag phải cùng độ dài UTF-8 (\(oldLen) byte), "
                    + "\"\(newTag)\" là \(newLen) → bỏ qua")
            } else {
                for i in 0..<pf.strings.count {
                    if pf.strings[i].contains(oldTag) {
                        pf.strings[i] = pf.strings[i]
                            .replacingOccurrences(of: oldTag, with: newTag)
                        rep.stringSites += 1
                    }
                }
                if rep.stringSites == 0 {
                    rep.notes.append("không thấy chuỗi \"\(oldTag)\" trong patch")
                }
            }
        }

        return rep
    }

    /// Thông tin hook để UI hiện danh sách (vm, số lệnh, tên method).
    public struct HookInfo {
        public let vm: Int
        public let instructions: Int
        public let name: String
    }

    public static func hookList(_ pf: Lqmb.Patch) -> [HookInfo] {
        pf.interpret
            .filter { $0.vm >= 0 && Int($0.vm) < pf.blocks.count }
            .map { h in
                HookInfo(vm: Int(h.vm),
                         instructions: pf.blocks[Int(h.vm)].instructionCount,
                         name: pf.qualifiedName(h.method))
            }
            .sorted { $0.vm < $1.vm }
    }
}
