import Foundation

/// BolaConfig — codec cho `Documents/nvhcfg.bin` (file app ghi vào container Free Fire,
/// patch trong game đọc ở `Application.persistentDataPath + "/nvhcfg.bin"`).
///
/// Layout lấy đúng từ source gốc (`AppModel.writeConfig`):
///   24 byte payload + 4 byte CRC32 LE = 28 byte.
///
///   [0..3]  "BOLA"
///   [4]     version = 1
///   [5]     ESP flags: bit0 box, bit1 line, bit2 hp, bit3 name, bit4 dist, bit5 bot, bit7 count
///   [6]     độ dày ESP, clamp 50...200
///   [7]     extra: bit0 aim, bit1 skeleton (bone), bit2 silent, bit3 skip-knocked,
///                bit4 show FOV, bit5 team, bit6 straight bullets
///   [8]     bone: 0 head, 1 neck, 2 chest
///   [9..14] RGB565 little-endian: box (9,10), line (11,12), bone (13,14)
///   [15]    silent FOV, clamp 5...100
///   [16]    misc1: bit0 fastfire, bit3 fastswap, bit5 emote, bit6 highjump, bit7 fps144
///   [17]    misc2: bit1 camwide, bit4 backjump, bit5 speedrun
///   [18]    camera FOV, clamp 50...130
///   [19]    aimbot FOV, clamp 5...100
///   [20]    headshot ratio, clamp 10...100
///   [21..23] 0
///
/// Toàn bộ 24 byte bị XOR với keystream `(0x5A + i*0x37) ^ (i << 4)`, CRC32 tính trên
/// **payload đã XOR** rồi ghi 4 byte little-endian ở cuối.
public struct BolaConfig: Equatable {

    public static let magic: [UInt8] = Array("BOLA".utf8)   // 0x42 0x4F 0x4C 0x41
    public static let size = 28
    public static let payloadSize = 24
    public static let version: UInt8 = 1

    public struct Flags: OptionSet, Equatable {          // byte 5
        public let rawValue: UInt8
        public init(rawValue: UInt8) { self.rawValue = rawValue }
        public static let box   = Flags(rawValue: 1 << 0)
        public static let line  = Flags(rawValue: 1 << 1)
        public static let hp    = Flags(rawValue: 1 << 2)
        public static let name  = Flags(rawValue: 1 << 3)
        public static let dist  = Flags(rawValue: 1 << 4)
        public static let bot   = Flags(rawValue: 1 << 5)
        public static let count = Flags(rawValue: 1 << 7)
    }

    public struct Extra: OptionSet, Equatable {          // byte 7
        public let rawValue: UInt8
        public init(rawValue: UInt8) { self.rawValue = rawValue }
        public static let aim       = Extra(rawValue: 1 << 0)
        public static let bones     = Extra(rawValue: 1 << 1)
        public static let silent    = Extra(rawValue: 1 << 2)
        public static let skipknock = Extra(rawValue: 1 << 3)
        public static let showfov   = Extra(rawValue: 1 << 4)
        public static let team      = Extra(rawValue: 1 << 5)
        public static let straight  = Extra(rawValue: 1 << 6)
    }

    public struct Misc1: OptionSet, Equatable {          // byte 16
        public let rawValue: UInt8
        public init(rawValue: UInt8) { self.rawValue = rawValue }
        public static let fastfire = Misc1(rawValue: 1 << 0)
        public static let fastswap = Misc1(rawValue: 1 << 3)
        public static let emote    = Misc1(rawValue: 1 << 5)
        public static let highjump = Misc1(rawValue: 1 << 6)
        public static let fps144   = Misc1(rawValue: 1 << 7)
    }

    public struct Misc2: OptionSet, Equatable {          // byte 17
        public let rawValue: UInt8
        public init(rawValue: UInt8) { self.rawValue = rawValue }
        public static let camwide  = Misc2(rawValue: 1 << 1)
        public static let backjump = Misc2(rawValue: 1 << 4)
        public static let speedrun = Misc2(rawValue: 1 << 5)
    }

    public enum Bone: UInt8, CaseIterable {
        case head = 0, neck = 1, chest = 2

        public var vi: String {
            switch self {
            case .head: return "Đầu"
            case .neck: return "Cổ"
            case .chest: return "Ngực"
            }
        }
    }

    public var flags: Flags
    public var extra: Extra
    public var misc1: Misc1
    public var misc2: Misc2
    public var bone: Bone
    public var espThick: UInt8     // 50...200
    public var silentFov: UInt8    // 5...100
    public var aimFov: UInt8       // 5...100
    public var camFov: UInt8       // 50...130
    public var headRate: UInt8     // 10...100
    public var boxColor: UInt16
    public var lineColor: UInt16
    public var boneColor: UInt16

    public init(flags: Flags = [],
                extra: Extra = [],
                misc1: Misc1 = [],
                misc2: Misc2 = [],
                bone: Bone = .head,
                espThick: UInt8 = 100,
                silentFov: UInt8 = 30,
                aimFov: UInt8 = 30,
                camFov: UInt8 = 88,
                headRate: UInt8 = 100,
                boxColor: UInt16 = 0xF925,
                lineColor: UInt16 = 0xF925,
                boneColor: UInt16 = 0xF925) {
        self.flags = flags
        self.extra = extra
        self.misc1 = misc1
        self.misc2 = misc2
        self.bone = bone
        self.espThick = espThick
        self.silentFov = silentFov
        self.aimFov = aimFov
        self.camFov = camFov
        self.headRate = headRate
        self.boxColor = boxColor
        self.lineColor = lineColor
        self.boneColor = boneColor
    }

    public enum DecodeError: Error, CustomStringConvertible {
        case tooShort(Int)
        case badMagic([UInt8])
        case badVersion(UInt8)
        case badCRC(expected: UInt32, got: UInt32)

        public var description: String {
            switch self {
            case .tooShort(let n): return "nvhcfg.bin quá ngắn: \(n) < \(BolaConfig.size)"
            case .badMagic(let m): return "sai magic: \(m.map { String(format: "%02X", $0) }.joined()) ≠ 424F4C41"
            case .badVersion(let v): return String(format: "sai version: 0x%02X ≠ 0x01", v)
            case .badCRC(let e, let g): return String(format: "CRC32 lệch: file=0x%08X, tính=0x%08X", e, g)
            }
        }
    }

    // MARK: keystream

    /// XOR keystream đúng như `writeConfig` của bản gốc (đối xứng khi áp 2 lần).
    public static func obfuscate(_ index: Int, _ byte: UInt8) -> UInt8 {
        byte ^ UInt8(truncatingIfNeeded: (0x5A + index * 0x37) ^ (index << 4))
    }

    // MARK: encode

    public func encoded() -> [UInt8] {
        var out = [UInt8](repeating: 0, count: BolaConfig.payloadSize)
        out.replaceSubrange(0..<4, with: BolaConfig.magic)
        out[4] = BolaConfig.version
        out[5] = flags.rawValue
        out[6] = clamp(espThick, 50, 200)
        out[7] = extra.rawValue
        out[8] = bone.rawValue
        Self.writeLE16(boxColor, into: &out, at: 9)
        Self.writeLE16(lineColor, into: &out, at: 11)
        Self.writeLE16(boneColor, into: &out, at: 13)
        out[15] = clamp(silentFov, 5, 100)
        out[16] = misc1.rawValue
        out[17] = misc2.rawValue
        out[18] = clamp(camFov, 50, 130)
        out[19] = clamp(aimFov, 5, 100)
        out[20] = clamp(headRate, 10, 100)

        for i in 0..<BolaConfig.payloadSize {
            out[i] = Self.obfuscate(i, out[i])
        }

        let crc = CRC32.hash(out)
        var data = out
        data.append(UInt8(crc & 0xFF))
        data.append(UInt8((crc >> 8) & 0xFF))
        data.append(UInt8((crc >> 16) & 0xFF))
        data.append(UInt8((crc >> 24) & 0xFF))
        return data
    }

    // MARK: decode

    public static func decode(_ bytes: [UInt8]) throws -> BolaConfig {
        guard bytes.count >= BolaConfig.size else { throw DecodeError.tooShort(bytes.count) }

        let idx = crcOffset(for: bytes.count)
        let stored = readLE32(bytes, at: idx)
        let calc = CRC32.hash(Array(bytes[0..<idx]))
        guard stored == calc else { throw DecodeError.badCRC(expected: stored, got: calc) }

        var plain = Array(bytes[0..<idx])
        for i in plain.indices {
            plain[i] = obfuscate(i, plain[i])
        }
        guard plain.count >= 21 else { throw DecodeError.tooShort(plain.count) }
        guard Array(plain[0..<4]) == magic else { throw DecodeError.badMagic(Array(plain[0..<4])) }
        guard plain[4] == version else { throw DecodeError.badVersion(plain[4]) }

        return BolaConfig(
            flags: Flags(rawValue: plain[5]),
            extra: Extra(rawValue: plain[7]),
            misc1: Misc1(rawValue: plain[16]),
            misc2: Misc2(rawValue: plain[17]),
            bone: Bone(rawValue: plain[8]) ?? .head,
            espThick: plain[6],
            silentFov: plain[15],
            aimFov: plain[19],
            camFov: plain[18],
            headRate: plain[20],
            boxColor: readLE16(plain, at: 9),
            lineColor: readLE16(plain, at: 11),
            boneColor: readLE16(plain, at: 13))
    }

    /// CRC nằm ở 4 byte cuối (28 → 24).
    public static func crcOffset(for length: Int) -> Int {
        max(0, length - 4)
    }

    private func clamp(_ v: UInt8, _ lo: UInt8, _ hi: UInt8) -> UInt8 {
        min(max(v, lo), hi)
    }

    private static func writeLE16(_ v: UInt16, into out: inout [UInt8], at i: Int) {
        out[i] = UInt8(v & 0xFF)
        out[i + 1] = UInt8((v >> 8) & 0xFF)
    }

    private static func readLE16(_ b: [UInt8], at i: Int) -> UInt16 {
        UInt16(b[i]) | (UInt16(b[i + 1]) << 8)
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

// MARK: - Token .nvhtok

/// Codec cho `.nvhtok` — file loader ghi, patch trong game đọc & kiểm tra
/// (vm4 instr 1440–1830).
///
/// ⚠️ ĐÍNH CHÍNH so với bản đọc IL đầu tiên: chuỗi `|NVHTK01|…` mà vm4 kiểm tra KHÔNG
/// phải nội dung `.nvhtok` — nó là **64 byte cuối của file patch** (xem `PatchTrailer`).
/// `.nvhtok` chỉ được đọc lên, `Trim()`, rồi băm SHA-256; 16 hex đầu của hash đó được
/// so với field đầu trong trailer.
///
/// `BolaToken` ở đây vẫn là payload tiện dụng để ghi `.nvhtok`; `encodedString()` là
/// chuỗi được băm. Đừng nhầm nó với trailer.
public struct BolaToken: Equatable {
    public static let prefix = "|NVHTK01|"

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
