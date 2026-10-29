import Foundation

/// Container ResD của Liên Quân (wrapper `.bytes` trong `Documents/Resources/<ver>/Thanos/`).
///
/// Layout:
///   u16 magic = 0x4A22 ("J)  |  u16 tag  |  u32 origLen  |  body
///
/// `body` có 2 dạng tuỳ `tag`:
///   - **mã hoá** (tag = 103 với HeroSkin): AES-128-CBC, PKCS7, IV = 16 byte 0
///   - **plain** (tag = 0 với LQHud): body là blob IFix trần, `origLen == body.count`
///
/// Khoá AES không nằm trong file — suy ra từ tên file:
///   key = mRawKeys XOR hash4(resName.ToUpper())
/// với `hash` kiểu .NET (`h = h*31 + ch`), `hash4` = 4 byte LE lặp 4 lần.
/// `mRawKeys` lấy từ `global-metadata.dat` (iOS, offset 0x19A3EE0).
public enum ResD {

    public static let magic: UInt16 = 0x4A22
    public static let rawKey: [UInt8] = [
        0x99, 0x64, 0xB1, 0xB0, 0x6B, 0x03, 0x8D, 0x7F,
        0xB7, 0x7D, 0xB6, 0xA7, 0x54, 0x90, 0x8B, 0x73,
    ]
    public static let iv0 = [UInt8](repeating: 0, count: 16)

    /// Magic của patch IFix (dùng để nhận biết body plaintext).
    public static let ifixLqmb: [UInt8] = [0xD0, 0xDB, 0x2C, 0x0E, 0x46, 0x5F, 0xD4, 0x1F]
    public static let ifixOld: [UInt8] = [0xCB, 0xA2, 0xB4, 0x0D, 0xB2, 0x19, 0xA3, 0x66]

    // MARK: - khoá

    /// Hash chuỗi kiểu .NET: `h = h*31 + ch` trên từng char 16-bit, tràn UInt32.
    public static func dotNetHashUpper(_ s: String) -> UInt32 {
        var h: UInt32 = 0
        for ch in s.uppercased().utf16 {
            h = h &* 31 &+ UInt32(ch)
        }
        return h
    }

    /// Khoá AES-128 cho một resName (tên file bỏ đuôi, ví dụ `HeroSkin_1`).
    public static func mixedKey(resName: String) -> [UInt8] {
        let h = dotNetHashUpper(resName)
        var key = [UInt8](repeating: 0, count: 16)
        for i in 0..<16 {
            key[i] = rawKey[i] ^ UInt8((h >> (8 * UInt32(i & 3))) & 0xFF)
        }
        return key
    }

    // MARK: - kết quả

    public struct Container {
        public let tag: UInt16
        public let origLen: Int
        public let plain: [UInt8]
        public let encrypted: Bool
        public var resName: String

        public init(tag: UInt16, origLen: Int, plain: [UInt8],
                    encrypted: Bool, resName: String = "") {
            self.tag = tag
            self.origLen = origLen
            self.plain = plain
            self.encrypted = encrypted
            self.resName = resName
        }
    }

    public enum ResDError: Error, CustomStringConvertible {
        case tooShort(Int)
        case badMagic(UInt16)
        case notBlockAligned(Int)
        case truncated(need: Int, have: Int)

        public var description: String {
            switch self {
            case .tooShort(let n):
                return "ResD: file chỉ \(n) byte (< 8)"
            case .badMagic(let m):
                return String(format: "ResD: magic 0x%04X != 0x4A22 — không phải container", m)
            case .notBlockAligned(let n):
                return "ResD: body \(n) byte không phải bội 16"
            case .truncated(let need, let have):
                return "ResD: cần \(need) byte, chỉ có \(have)"
            }
        }
    }

    // MARK: - đọc / ghi số nguyên nhỏ (LE)

    @inline(__always)
    static func u16(_ b: [UInt8], _ o: Int) -> UInt16 {
        UInt16(b[o]) | (UInt16(b[o + 1]) << 8)
    }

    @inline(__always)
    static func u32(_ b: [UInt8], _ o: Int) -> UInt32 {
        UInt32(b[o]) | (UInt32(b[o + 1]) << 8)
            | (UInt32(b[o + 2]) << 16) | (UInt32(b[o + 3]) << 24)
    }

    /// Body có phải blob IFix trần không (tag 0 của LQHud là trường hợp này).
    public static func looksPlain(_ body: [UInt8]) -> Bool {
        guard body.count >= 8 else { return false }
        return Array(body[0..<8]) == ifixLqmb || Array(body[0..<8]) == ifixOld
    }

    // MARK: - giải mã

    public static func decrypt(_ blob: [UInt8], resName: String) throws -> Container {
        guard blob.count >= 8 else { throw ResDError.tooShort(blob.count) }
        let m = u16(blob, 0)
        guard m == magic else { throw ResDError.badMagic(m) }
        let tag = u16(blob, 2)
        let origLen = Int(u32(blob, 4))
        var body = Array(blob[8...])

        // Trường hợp plaintext: body đúng bằng origLen và bắt đầu bằng magic IFix.
        if body.count == origLen, looksPlain(body) {
            return Container(tag: tag, origLen: origLen, plain: body,
                             encrypted: false, resName: resName)
        }

        guard body.count % 16 == 0 else { throw ResDError.notBlockAligned(body.count) }
        guard let pt = AES128.cbcDecrypt(key: mixedKey(resName: resName), iv: iv0, data: body) else {
            throw ResDError.notBlockAligned(body.count)
        }
        guard pt.count >= origLen else { throw ResDError.truncated(need: origLen, have: pt.count) }
        body = Array(pt[0..<origLen])
        return Container(tag: tag, origLen: origLen, plain: body,
                         encrypted: true, resName: resName)
    }

    // MARK: - mã hoá

    /// Đóng gói plaintext thành container `.bytes`.
    /// - Parameter encrypt: false = giữ nguyên plain (tag 0, kiểu LQHud).
    public static func encrypt(_ plain: [UInt8], resName: String,
                               tag: UInt16, encrypt: Bool = true) -> [UInt8] {
        var body: [UInt8]
        if encrypt {
            let pad = 16 - (plain.count % 16)
            var padded = plain
            padded.append(contentsOf: [UInt8](repeating: UInt8(pad), count: pad))
            body = AES128.cbcEncrypt(key: mixedKey(resName: resName), iv: iv0, data: padded) ?? []
        } else {
            body = plain
        }
        var out = [UInt8](repeating: 0, count: 8 + body.count)
        out[0] = UInt8(magic & 0xFF)
        out[1] = UInt8((magic >> 8) & 0xFF)
        out[2] = UInt8(tag & 0xFF)
        out[3] = UInt8((tag >> 8) & 0xFF)
        let n = UInt32(plain.count)
        out[4] = UInt8(n & 0xFF)
        out[5] = UInt8((n >> 8) & 0xFF)
        out[6] = UInt8((n >> 16) & 0xFF)
        out[7] = UInt8((n >> 24) & 0xFF)
        for i in 0..<body.count { out[8 + i] = body[i] }
        return out
    }

    /// Tên resName chuẩn từ tên file: bỏ đuôi, bỏ thư mục, giữ nguyên hoa/thường.
    /// (`Thanos/HeroSkin_1.bytes` → `HeroSkin_1`; hàm hash tự upper nên không cần đổi.)
    public static func resName(forFile name: String) -> String {
        let base = name.split(separator: "/").last.map(String.init) ?? name
        if base.hasSuffix(".bytes") {
            return String(base.dropLast(".bytes".count))
        }
        if let dot = base.lastIndex(of: ".") { return String(base[..<dot]) }
        return base
    }
}
