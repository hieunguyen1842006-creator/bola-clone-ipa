import Foundation

/// BolaConfig — codec cho `Documents/bolacfg.bin` (file app ghi vào container Free Fire,
/// patch trong game đọc ở `Application.persistentDataPath + "/bolacfg.bin"`).
///
/// LAYOUT (bóc từ IL của `BolaminhducMenu.bytes`):
///   vm1 instr 155–480  +  vm4 instr 524–1139  — cùng một reader, hai nơi dùng
///
///   cfg.Length >= 28                                  (gate: 20 → 24 → 28, instr 189–208)
///   cfg[0..3]  == "BOLA"                              (0x42 0x4F 0x4C 0x41, instr 351–373)
///   cfg[4]     == version byte                        (instr 374–378, so với hằng '1' = 0x31)
///   cfg[7]     = flags:  bit0 → bật nhóm ESP          (instr 381–404)
///                        bit2 → bật aim
///                        bit3 → cờ phụ
///   cfg[8]     = bone enum 0..2                       (instr 405–423, range-check 0...2)
///   cfg[15]    = aim FOV, clamp 5...100               (instr 424–442, mặc định 30)
///   cfg[19]    = byte clamp 5...100                   (instr 443–461, mặc định 30)
///   cfg[20]    = byte clamp 10...100                  (instr 462–480, mặc định 100)
///   cfg[len-4..len-1] = CRC32 LE (poly 0xEDB88320) của cfg[0..<len-4]
///                (instr 211–226: ba nhánh 16/20/24 = len-4 ứng với len 20/24/28;
///                 vòng CRC instr 255–307; so sánh instr 308–316)
///
///   ⚠️ Ở đây patch còn MÃ HOÁ lại từng byte trước khi so magic: vòng lặp instr 323–350
///   giải mã `dec[j] = mix(cfg[j], j)` với phần cộng đã đọc được là `+ 0x5A + j*0x37`
///   (90 và 55), rồi so `dec[0..3] == "BOLA"`. Phần trộn còn lại (0xB1/0x93/0x64/0xA4)
///   CHƯA giải hết — xem `Obfuscation` bên dưới và README.
public struct BolaConfig: Equatable {

    public static let magic: [UInt8] = Array("BOLA".utf8)   // 0x42 0x4F 0x4C 0x41
    public static let size = 28
    public static let version: UInt8 = 0x31                 // '1'

    // Flags bit trong cfg[7]
    public struct Flags: OptionSet, Equatable {
        public let rawValue: UInt8
        public init(rawValue: UInt8) { self.rawValue = rawValue }
        public static let esp    = Flags(rawValue: 1 << 0)   // nhóm ESP (khung, HP, tên...)
        public static let aim    = Flags(rawValue: 1 << 2)   // nhóm aim (khoá mục tiêu)
        public static let extra  = Flags(rawValue: 1 << 3)   // cờ phụ (đồng đội / bot)
    }

    public enum Bone: UInt8, CaseIterable {
        case head = 0, neck = 1, spine = 2

        public var vi: String {
            switch self {
            case .head: return "Đầu"
            case .neck: return "Cổ"
            case .spine: return "Thân"
            }
        }
    }

    public var flags: Flags
    public var bone: Bone
    public var aimFov: UInt8      // 5...100
    public var field19: UInt8     // 5...100
    public var field20: UInt8     // 10...100
    /// byte 21..27 — chưa xác minh, giữ nguyên khi parse để không phá file của app gốc
    public var reservedTail: [UInt8]

    public init(flags: Flags = [.esp, .aim],
                bone: Bone = .head,
                aimFov: UInt8 = 30,
                field19: UInt8 = 30,
                field20: UInt8 = 100,
                reservedTail: [UInt8] = [UInt8](repeating: 0, count: 3)) {   // byte 21..23
        self.flags = flags
        self.bone = bone
        self.aimFov = aimFov
        self.field19 = field19
        self.field20 = field20
        self.reservedTail = reservedTail
    }

    /// Mã hoá từng byte của file. `.plain` = như writer của clone; `.additive` = phần
    /// đã đọc được từ IL (`cfg[j] = dec[j] - 0x5A - j*0x37`), dùng khi cần khớp file thật.
    public enum Obfuscation {
        case plain
        case additive          // cfg[j] = (dec[j] - 0x5A - j*0x37) & 0xFF
    }

    public enum DecodeError: Error, CustomStringConvertible {
        case tooShort(Int)
        case badMagic([UInt8])
        case badVersion(UInt8)
        case badCRC(expected: UInt32, got: UInt32)

        public var description: String {
            switch self {
            case .tooShort(let n): return "bolacfg.bin quá ngắn: \(n) < \(BolaConfig.size)"
            case .badMagic(let m): return "sai magic: \(m.map { String(format: "%02X", $0) }.joined()) ≠ 424F4C41"
            case .badVersion(let v): return String(format: "sai version: 0x%02X ≠ 0x31", v)
            case .badCRC(let e, let g): return String(format: "CRC32 lệch: file=0x%08X, tính=0x%08X", e, g)
            }
        }
    }

    // MARK: encode

    /// Sinh đúng 28 byte mà reader trong patch chấp nhận (magic + version + flags + CRC32).
    public func encoded() -> [UInt8] {
        var out = [UInt8](repeating: 0, count: BolaConfig.size)
        out.replaceSubrange(0..<4, with: BolaConfig.magic)
        out[4] = BolaConfig.version
        out[7] = flags.rawValue
        out[8] = bone.rawValue
        out[15] = clamp(aimFov, 5, 100)
        out[19] = clamp(field19, 5, 100)
        out[20] = clamp(field20, 10, 100)
        let idx = BolaConfig.crcOffset(for: BolaConfig.size)   // 24
        for (i, b) in reservedTail.enumerated() where 21 + i < idx {
            out[21 + i] = b
        }
        let crc = CRC32.hash(out[0..<idx])
        Self.writeLE32(crc, into: &out, at: idx)
        return out
    }

    // MARK: decode

    public static func decode(_ bytes: [UInt8]) throws -> BolaConfig {
        guard bytes.count >= BolaConfig.size else { throw DecodeError.tooShort(bytes.count) }
        guard Array(bytes[0..<4]) == magic else { throw DecodeError.badMagic(Array(bytes[0..<4])) }
        guard bytes[4] == version else { throw DecodeError.badVersion(bytes[4]) }

        let idx = crcOffset(for: bytes.count)
        let stored = readLE32(bytes, at: idx)
        let calc = CRC32.hash(bytes[0..<idx])
        guard stored == calc else { throw DecodeError.badCRC(expected: stored, got: calc) }

        return BolaConfig(
            flags: Flags(rawValue: bytes[7]),
            bone: Bone(rawValue: bytes[8]) ?? .head,
            aimFov: clamp(bytes[15], 5, 100),
            field19: clamp(bytes[19], 5, 100),
            field20: clamp(bytes[20], 10, 100),
            reservedTail: Array(bytes[21..<min(bytes.count, crcOffset(for: bytes.count))])
        )
    }

    /// idx của CRC32 theo độ dài file — đúng nhánh `len>=28 ? 24 : (len>=24 ? 20 : 16)`
    /// trong IL (instr 211–226): file chuẩn 28 byte ⇒ CRC ở offset 24 (4 byte cuối).
    public static func crcOffset(for length: Int) -> Int {
        // Ba nhánh 16/20/24 của reader = "4 byte cuối" cho độ dài 20/24/28.
        max(0, length - 4)
    }

    /// Nhánh range-check của reader: giá trị ngoài clamp coi như không hợp lệ → dùng default.
    public static func accepted(_ v: UInt8, in range: ClosedRange<UInt8>) -> UInt8 {
        range.contains(v) ? v : range.lowerBound
    }

    private func clamp(_ v: UInt8, _ lo: UInt8, _ hi: UInt8) -> UInt8 {
        min(max(v, lo), hi)
    }

    private static func clamp(_ v: UInt8, _ lo: UInt8, _ hi: UInt8) -> UInt8 {
        min(max(v, lo), hi)
    }

    /// Đảo của vòng giải mã trong patch (xem doc đầu file).
    public static func mix(_ decoded: [UInt8], _ mode: Obfuscation) -> [UInt8] {
        switch mode {
        case .plain:
            return decoded
        case .additive:
            return decoded.enumerated().map { j, b in
                UInt8((Int(b) - 0x5A - j * 0x37) & 0xFF)
            }
        }
    }

    public static func unmix(_ raw: [UInt8], _ mode: Obfuscation) -> [UInt8] {
        switch mode {
        case .plain:
            return raw
        case .additive:
            return raw.enumerated().map { j, b in
                UInt8((Int(b) + 0x5A + j * 0x37) & 0xFF)
            }
        }
    }

    private static func writeLE32(_ v: UInt32, into out: inout [UInt8], at i: Int) {
        out[i] = UInt8(v & 0xFF)
        out[i + 1] = UInt8((v >> 8) & 0xFF)
        out[i + 2] = UInt8((v >> 16) & 0xFF)
        out[i + 3] = UInt8((v >> 24) & 0xFF)
    }

    private static func readLE32(_ b: [UInt8], at i: Int) -> UInt32 {
        UInt32(b[i]) | (UInt32(b[i + 1]) << 8) | (UInt32(b[i + 2]) << 16) | (UInt32(b[i + 3]) << 24)
    }
}

// MARK: - Token .bola_tok

/// Codec cho `.bola_tok` — file loader ghi, patch trong game đọc & kiểm tra
/// (vm4 instr 1440–1830).
///
/// ⚠️ ĐÍNH CHÍNH so với bản đọc IL đầu tiên: chuỗi `|BOLATK1|…` mà vm4 kiểm tra KHÔNG
/// phải nội dung `.bola_tok` — nó là **64 byte cuối của file patch** (xem `PatchTrailer`).
/// `.bola_tok` chỉ được đọc lên, `Trim()`, rồi băm SHA-256; 16 hex đầu của hash đó được
/// so với field đầu trong trailer.
///
/// `BolaToken` ở đây vẫn là payload tiện dụng để ghi `.bola_tok`; `encodedString()` là
/// chuỗi được băm. Đừng nhầm nó với trailer.
public struct BolaToken: Equatable {
    public static let prefix = "|BOLATK1|"

    public var key: String
    public var expiryUnix: Int64
    public var sig: String          // hex thường (64 ký tự)
    public var extra: [String]

    public init(key: String, expiryUnix: Int64, sig: String, extra: [String] = []) {
        self.key = key
        self.expiryUnix = expiryUnix
        self.sig = sig
        self.extra = extra
    }

    /// Dựng chuỗi token đúng thứ tự field mà patch đọc.
    public func encodedString() -> String {
        var parts = [key, String(expiryUnix), sig]
        parts.append(contentsOf: extra)
        return BolaToken.prefix + parts.joined(separator: "|") + "|"
    }

    public func encoded() -> [UInt8] { Array(encodedString().utf8) }

    /// Mã hoá từng byte của file. `.plain` = như writer của clone; `.additive` = phần
    /// đã đọc được từ IL (`cfg[j] = dec[j] - 0x5A - j*0x37`), dùng khi cần khớp file thật.
    public enum Obfuscation {
        case plain
        case additive          // cfg[j] = (dec[j] - 0x5A - j*0x37) & 0xFF
    }

    public enum DecodeError: Error, CustomStringConvertible {
        case badPrefix
        case tooFewFields(Int)
        case badExpiry(String)
        case badSignature(String)

        public var description: String {
            switch self {
            case .badPrefix: return "token không bắt đầu bằng \(BolaToken.prefix)"
            case .tooFewFields(let n): return "token thiếu field (\(n) < 3)"
            case .badExpiry(let s): return "hạn dùng không phải số: \(s)"
            case .badSignature(let s): return "chữ ký không phải hex 64 ký tự: \(s)"
            }
        }
    }

    public static func decode(_ text: String) throws -> BolaToken {
        guard text.count >= 9, String(text.prefix(9)) == prefix else { throw DecodeError.badPrefix }
        let body = String(text.dropFirst(9))
        let fields = body.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        let clean = fields.filter { !$0.isEmpty }
        guard clean.count >= 3 else { throw DecodeError.tooFewFields(clean.count) }
        guard let expiry = Int64(clean[1]) else { throw DecodeError.badExpiry(clean[1]) }
        let sig = clean[2].lowercased()
        let isHex = sig.count == 64 && sig.allSatisfy { $0.isHexDigit }
        guard isHex else { throw DecodeError.badSignature(clean[2]) }
        return BolaToken(key: clean[0], expiryUnix: expiry, sig: sig,
                         extra: Array(clean.dropFirst(3)))
    }

    /// Kiểm tra chữ ký đúng cách patch làm: SHA256(key) → hex bằng bảng 0123456789abcdef.
    public func signatureIsValid() -> Bool {
        SHA256.hexDigest(key) == sig.lowercased()
    }

    public func isExpired(now: Date = Date()) -> Bool {
        Int64(now.timeIntervalSince1970) > expiryUnix
    }

    /// Unix giây → "còn N giờ" (AppModel.keyHoursLeft dùng cho UI).
    public func hoursLeft(now: Date = Date()) -> Int {
        let left = expiryUnix - Int64(now.timeIntervalSince1970)
        return left <= 0 ? 0 : Int(left / 3600)
    }

    /// Ngược lại của phép tính trong patch: ticks → Unix (để đối chiếu/debug).
    public static let dotNetUnixEpochTicks: Int64 = 621_355_968_000_000_000
    public static func unixSeconds(fromDotNetTicks ticks: Int64) -> Int64 {
        (ticks - dotNetUnixEpochTicks) / 10_000_000
    }
}
