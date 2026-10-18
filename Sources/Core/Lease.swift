import Foundation

// Lease + KeyMask: tách riêng để tầng logic biên dịch được không cần Combine

// MARK: - Lease (payload server trả về — không tự sinh, phải do backend cấp)

public struct Lease: Equatable, Codable {
    public var key: String
    public var maskedKey: String
    public var expiryUnix: Int64
    public var sig: String
    public var licenseType: String       // "lifetime" | "time"
    public var isLifetime: Bool
    public var startsOnActivation: Bool
    public var maxDevices: Int
    public var effectiveExpiresAt: String?
    public var licenseExpiresAt: String?
    public var expiresAt: String?

    public init(key: String, maskedKey: String, expiryUnix: Int64, sig: String,
                licenseType: String = "time", isLifetime: Bool = false,
                startsOnActivation: Bool = true, maxDevices: Int = 1,
                effectiveExpiresAt: String? = nil, licenseExpiresAt: String? = nil,
                expiresAt: String? = nil) {
        self.key = key
        self.maskedKey = maskedKey
        self.expiryUnix = expiryUnix
        self.sig = sig
        self.licenseType = licenseType
        self.isLifetime = isLifetime
        self.startsOnActivation = startsOnActivation
        self.maxDevices = maxDevices
        self.effectiveExpiresAt = effectiveExpiresAt
        self.licenseExpiresAt = licenseExpiresAt
        self.expiresAt = expiresAt
    }
}

// MARK: - KeyMask (hiển thị "BOLA-****-9F2C" — boolean field `maskedKey`/`keyMaskedName`)

public enum KeyMask {
    public static func mask(_ key: String) -> String {
        let k = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard k.count > 6 else { return String(repeating: "•", count: max(k.count, 4)) }
        let head = k.prefix(4)
        let tail = k.suffix(4)
        return "\(head)-••••-\(tail)"
    }
}
