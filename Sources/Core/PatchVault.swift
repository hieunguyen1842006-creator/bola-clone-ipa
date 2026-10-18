import Foundation

/// PatchVault — blob mã hoá chứa patch IFix.
///
/// IPA chỉ mang `NVHMenu.vault`; lúc inject app giải mã trong RAM rồi mới ghi
/// `Assembly-CSharp-patch.bytes` vào container game. Nhờ vậy trong bundle không có
/// file patch plaintext (không magic IFix, không string nhận dạng).
///
/// Format: "NVHV1" (5) | length u32 LE (4) | sha256(plain) (32) | ciphertext
/// Keystream: sha256(key || counter_u32_le), XOR từng block 32 byte.
public enum PatchVault {

    public static let resource = "NVHMenu"
    public static let ext = "vault"
    private static let magic: [UInt8] = Array("NVHV1".utf8)
    private static let key = SHA256.digest(Array("NVH-MOD-2026:vault:v1".utf8))

    /// Patch plaintext để đem đi ký + ghi container.
    public static func bundledPatch(bundle: Bundle = .main) -> Data? {
        if let url = bundle.url(forResource: resource, withExtension: ext),
           let blob = try? Data(contentsOf: url),
           let plain = decode(blob) {
            return plain
        }
        // Dev fallback: bản build cũ còn để patch plaintext trong bundle.
        if let url = bundle.url(forResource: resource, withExtension: "bytes"),
           let plain = try? Data(contentsOf: url) {
            return plain
        }
        return nil
    }

    public static func decode(_ blob: Data) -> Data? {
        let bytes = [UInt8](blob)
        guard bytes.count >= 41, Array(bytes[0..<5]) == magic else { return nil }
        let n = Int(bytes[5])
            | (Int(bytes[6]) << 8)
            | (Int(bytes[7]) << 16)
            | (Int(bytes[8]) << 24)
        guard n >= 0, bytes.count >= 41 + n else { return nil }
        let digest = Array(bytes[9..<41])

        var out = [UInt8](repeating: 0, count: n)
        var counter: UInt32 = 0
        var offset = 0
        while offset < n {
            var msg = key
            msg.append(UInt8(truncatingIfNeeded: counter))
            msg.append(UInt8(truncatingIfNeeded: counter >> 8))
            msg.append(UInt8(truncatingIfNeeded: counter >> 16))
            msg.append(UInt8(truncatingIfNeeded: counter >> 24))
            let ks = SHA256.digest(msg)
            let take = min(32, n - offset)
            for i in 0..<take {
                out[offset + i] = bytes[41 + offset + i] ^ ks[i]
            }
            offset += take
            counter &+= 1
        }
        guard SHA256.digest(out) == digest else { return nil }
        return Data(out)
    }
}
