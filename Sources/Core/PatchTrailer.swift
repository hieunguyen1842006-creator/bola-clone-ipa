import Foundation

/// PatchTrailer — 64 byte license trailer mà menu trong game đọc ở CUỐI file
/// `Assembly-CSharp-patch.bytes`.
///
/// Bóc từ IL `BolaminhducMenu.bytes`, vm4::OnGUI (khối license):
///
///   trailer = Encoding.UTF8.GetString(patch[patch.Length - 64 ..< patch.Length])
///   trailer.Substring(0, 9) == "|NVHTK01|"
///   f1 = trailer[9 ..< firstPipe]                  → so với hex(SHA256(.nvhtok))[:16]
///   f2 = trailer[firstPipe+1 ..< nextPipe]         → Int64.Parse, so với Unix now
///   f3 = trailer[nextPipe+1 ..< nextPipeAfter]     → độ dài 8, so với hex(SHA256(body))[:8]
///   body = patch[0 ..< patch.Length - 64]
///
/// Chuỗi ví dụ (46 byte, pad 0x00 cho đủ 64):
///
///   |NVHTK01|9f2c1d4a7b0e5c33|1791983788|a1b2c3d4|
///
/// `license` trong `validate(body:license:)` là NỘI DUNG FILE `.nvhtok` (không phải raw key),
/// đúng như IL: hash được tính trên chuỗi đọc từ `.nvhtok`.
public struct PatchTrailer: Equatable {

    public static let length = 64
    public static let marker = "|NVHTK01|"
    public static let keyHashHexLength = 16    // 8 byte đầu của SHA-256
    public static let bodySigHexLength = 8     // 4 byte đầu của SHA-256

    public var keyHash: String                 // 16 hex thường
    public var expiryUnix: Int64
    public var bodySig: String                 // 8 hex thường

    public init(keyHash: String, expiryUnix: Int64, bodySig: String) {
        self.keyHash = keyHash.lowercased()
        self.expiryUnix = expiryUnix
        self.bodySig = bodySig.lowercased()
    }

    public enum TrailerError: Error, CustomStringConvertible {
        case tooShort(Int)
        case badMarker(String)
        case tooFewFields(Int)
        case badExpiry(String)
        case badKeyHash(String)
        case badSignature(String)
        case overflow(Int)

        public var description: String {
            switch self {
            case .tooShort(let n): return "patch quá ngắn để có trailer: \(n) < \(PatchTrailer.length)"
            case .badMarker(let m): return "trailer thiếu marker \(PatchTrailer.marker): \(m.debugDescription)"
            case .tooFewFields(let n): return "trailer thiếu field (\(n) < 3)"
            case .badExpiry(let s): return "expiry không phải số: \(s)"
            case .badKeyHash(let s): return "key hash sai định dạng: \(s)"
            case .badSignature(let s): return "body sig sai định dạng: \(s)"
            case .overflow(let n): return "trailer \(n) byte > \(PatchTrailer.length)"
            }
        }
    }

    // MARK: - derive

    /// `hex(SHA256(license))[:16]` — đúng segment đầu mà vm4 so sánh.
    /// vm4 đọc `.nvhtok` bằng `String.Trim()` trước khi băm nên ở đây cũng trim.
    public static func keyHash(for license: String) -> String {
        let trimmed = license.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(SHA256.hexDigest(trimmed).prefix(keyHashHexLength)).lowercased()
    }

    /// `hex(SHA256(body))[:8]` — dấu xác nhận phần thân patch không bị sửa.
    public static func bodySignature(for body: Data) -> String {
        String(SHA256.hex(SHA256.digest([UInt8](body))).prefix(bodySigHexLength)).lowercased()
    }

    // MARK: - encode

    public func encoded(randomizePadding: Bool = false) throws -> Data {
        var text = Self.marker
        text += keyHash
        text += "|"
        text += String(expiryUnix)
        text += "|"
        text += bodySig
        text += "|"

        let raw = Array(text.utf8)
        guard raw.count <= Self.length else { throw TrailerError.overflow(raw.count) }
        var out = raw
        if randomizePadding {
            // Đệm bằng hex (không phải '|') để trailer vẫn đọc được bằng UTF-8,
            // các field keyHash/expiry/bodySig giữ nguyên vị trí.
            let hex = Array("0123456789abcdef")
            var rng = SystemRandomNumberGenerator()
            while out.count < Self.length {
                out.append(UInt8(ascii: hex[Int.random(in: 0..<16, using: &rng)]))
            }
        } else {
            out.append(contentsOf: [UInt8](repeating: 0, count: Self.length - raw.count))
        }
        return Data(out)
    }

    // MARK: - decode

    /// Trả nil nếu 64 byte cuối không phải trailer (patch chưa kích hoạt / bản gốc).
    public static func decode(from patch: Data) -> PatchTrailer? {
        guard patch.count >= length else { return nil }
        let tail = patch.suffix(length)
        guard let text = String(data: tail, encoding: .utf8) else { return nil }
        return try? decode(text: text)
    }

    public static func decode(text: String) throws -> PatchTrailer {
        guard text.hasPrefix(marker) else { throw TrailerError.badMarker(String(text.prefix(16))) }
        let body = String(text.dropFirst(marker.count))
        let fields = body.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        let clean = fields.filter { !$0.isEmpty }
        guard clean.count >= 3 else { throw TrailerError.tooFewFields(clean.count) }

        let keyHash = clean[0].lowercased()
        guard keyHash.count == keyHashHexLength, keyHash.allSatisfy({ $0.isHexDigit }) else {
            throw TrailerError.badKeyHash(clean[0])
        }
        guard let expiry = Int64(clean[1]) else { throw TrailerError.badExpiry(clean[1]) }
        let sig = clean[2].lowercased()
        guard sig.count == bodySigHexLength, sig.allSatisfy({ $0.isHexDigit }) else {
            throw TrailerError.badSignature(clean[2])
        }
        return PatchTrailer(keyHash: keyHash, expiryUnix: expiry, bodySig: sig)
    }

    // MARK: - validate

    public func validate(body: Data, license: String, now: Date = Date()) -> Bool {
        guard keyHash == Self.keyHash(for: license) else { return false }
        guard expiryUnix > Int64(now.timeIntervalSince1970) else { return false }
        guard bodySig == Self.bodySignature(for: body) else { return false }
        return true
    }

    public func isExpired(now: Date = Date()) -> Bool {
        expiryUnix <= Int64(now.timeIntervalSince1970)
    }

    // MARK: - patch helpers

    /// Nếu 64 byte cuối là trailer hợp lệ về cú pháp → trả phần thân, ngược lại trả nguyên patch.
    public static func strip(from patch: Data) -> Data {
        guard patch.count >= length, decode(from: patch) != nil else { return patch }
        return patch.prefix(patch.count - length)
    }

    /// Gắn trailer mới (tự bóc trailer cũ nếu có).
    public static func attach(to patch: Data, license: String, expiryUnix: Int64) throws -> Data {
        let body = strip(from: patch)
        let trailer = PatchTrailer(keyHash: keyHash(for: license),
                                   expiryUnix: expiryUnix,
                                   bodySig: bodySignature(for: body))
        var out = Data(body)
        out.append(try trailer.encoded(randomizePadding: true))
        return out
    }

    /// Kiểm tra một file patch đã có trailer khớp license và còn hạn chưa.
    public static func isValid(patch: Data, license: String, now: Date = Date()) -> Bool {
        guard let trailer = decode(from: patch) else { return false }
        let body = patch.prefix(patch.count - length)
        return trailer.validate(body: Data(body), license: license, now: now)
    }
}
