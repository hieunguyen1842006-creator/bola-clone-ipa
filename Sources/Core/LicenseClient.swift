import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking      // Linux: URLSession nằm ở đây; trên Apple platform thì bỏ qua
#endif

/// Client cho backend key (bản gốc: https://ds.tphat.store/api/client/{activate,check,secret,patch}).
///
/// URL để trong ServerConfig — clone này KHÔNG hard-code server của người khác.
/// Endpoint trả JSON; field nào thiếu thì dùng giá trị mặc định an toàn.
public final class LicenseClient {

    public enum APIError: Error, CustomStringConvertible {
        case transport(String)
        case serverStatus(String)
        case decoding(String)

        public var description: String {
            switch self {
            case .transport(let m): return "transport: \(m)"
            case .serverStatus(let s): return s
            case .decoding(let m): return "decoding: \(m)"
            }
        }
    }

    private let config: ServerConfig
    private let session: URLSession
    private let deviceID: () -> String

    public init(config: ServerConfig,
                session: URLSession = .shared,
                deviceID: @escaping () -> String = DeviceIdentity.identifier) {
        self.config = config
        self.session = session
        self.deviceID = deviceID
    }

    public func activate(key: String, packageToken: String, productId: String) async throws -> Lease {
        let body: [String: Any] = [
            "key": key,
            "device": deviceID(),
            "package": packageToken,
            "productId": productId,
            "platform": "ios",
            "ts": Int(Date().timeIntervalSince1970),
        ]
        let json = try await post(config.activatePath, body: body)
        return try lease(from: json, key: key)
    }

    public func check(key: String, packageToken: String) async throws -> Lease {
        let body: [String: Any] = [
            "key": key,
            "device": deviceID(),
            "package": packageToken,
            "platform": "ios",
        ]
        let json = try await post(config.checkPath, body: body)
        return try lease(from: json, key: key)
    }

    /// /api/client/secret — khoá công khai để verify chữ ký phản hồi (bản gốc Tserver làm việc này)
    public func fetchSecret() async throws -> [String: Any] {
        try await post(config.secretPath, body: ["package": config.packageToken])
    }

    /// /api/client/patch — patch "cá nhân hoá" theo key (bản gốc tải về remote_patch.bytes)
    public func fetchPatch(key: String) async throws -> Data {
        var req = URLRequest(url: config.endpoint(config.patchPath))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["key": key, "platform": "ios"])
        let (data, resp) = try await session.data(for: req)
        try Self.validate(resp)
        return data
    }

    // MARK: internals

    private func post(_ path: String, body: [String: Any]) async throws -> [String: Any] {
        var req = URLRequest(url: config.endpoint(path))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("ios", forHTTPHeaderField: "X-Platform")
        req.timeoutInterval = 20
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data
        let resp: URLResponse
        do {
            (data, resp) = try await session.data(for: req)
        } catch {
            throw APIError.transport(error.localizedDescription)
        }
        try Self.validate(resp)

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIError.decoding("JSON không hợp lệ")
        }
        if let ok = json["ok"] as? Bool, ok == false {
            let status = (json["status"] as? String) ?? (json["error"] as? String) ?? "UNKNOWN"
            throw APIError.serverStatus(status)
        }
        return json
    }

    private static func validate(_ resp: URLResponse) throws {
        guard let http = resp as? HTTPURLResponse else {
            throw APIError.transport("không có HTTP response")
        }
        switch http.statusCode {
        case 200...299: return
        case 401, 403: throw APIError.serverStatus("INVALID_API_KEY")
        case 404: throw APIError.serverStatus("KEY_NOT_FOUND")
        case 429: throw APIError.serverStatus("RATE_LIMITED")
        default: throw APIError.transport("HTTP \(http.statusCode)")
        }
    }

    /// Chuyển JSON server → Lease. Không có `sig` trong payload thì coi như lỗi
    /// (token phải do backend cấp; clone không tự ký thay chủ key).
    private func lease(from json: [String: Any], key: String) throws -> Lease {
        let data = (json["data"] as? [String: Any]) ?? json
        let sig = (data["sig"] as? String) ?? (data["signature"] as? String) ?? ""
        guard !sig.isEmpty else {
            throw APIError.decoding("payload thiếu chữ ký (sig)")
        }
        let isLifetime = (data["isLifetime"] as? Bool) ?? ((data["licenseType"] as? String) == "lifetime")
        let expiry = Self.int64(data["expiryUnix"])
            ?? Self.int64(data["effectiveExpiresAtUnix"])
            ?? Self.parseISO((data["effectiveExpiresAt"] as? String) ?? (data["expiresAt"] as? String))
            ?? 0
        return Lease(
            key: key,
            maskedKey: (data["maskedKey"] as? String) ?? KeyMask.mask(key),
            expiryUnix: isLifetime ? Int64.max / 2 : expiry,
            sig: sig,
            licenseType: (data["licenseType"] as? String) ?? (isLifetime ? "lifetime" : "time"),
            isLifetime: isLifetime,
            startsOnActivation: (data["startsOnActivation"] as? Bool) ?? true,
            maxDevices: (data["maxDevices"] as? Int) ?? 1,
            effectiveExpiresAt: data["effectiveExpiresAt"] as? String,
            licenseExpiresAt: data["licenseExpiresAt"] as? String,
            expiresAt: data["expiresAt"] as? String
        )
    }

    private static func int64(_ any: Any?) -> Int64? {
        if let v = any as? Int64 { return v }
        if let v = any as? Int { return Int64(v) }
        if let v = any as? Double { return Int64(v) }
        if let v = any as? String { return Int64(v) }
        return nil
    }

    private static func parseISO(_ s: String?) -> Int64? {
        guard let s = s else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return Int64(d.timeIntervalSince1970) }
        f.formatOptions = [.withInternetDateTime]
        if let d = f.date(from: s) { return Int64(d.timeIntervalSince1970) }
        return nil
    }
}

// MARK: - DeviceIdentity (device binding — TserverClientIdentity* trong bản gốc)

public enum DeviceIdentity {
    private static let key = "bola_device_id"

    /// ID ổn định theo app (không phải IDFV để tránh reset khi cài lại — gần với cách bản gốc
    /// "buộc key vào thiết bị").
    public static func identifier() -> String {
        if let existing = UserDefaults.standard.string(forKey: key), !existing.isEmpty {
            return existing
        }
        var bytes = [UInt8](repeating: 0, count: 16)
        for i in 0..<bytes.count { bytes[i] = UInt8.random(in: 0...255) }
        let hex = SHA256.hex(bytes)
        let id = String(hex.prefix(32))
        UserDefaults.standard.set(id, forKey: key)
        return id
    }
}
