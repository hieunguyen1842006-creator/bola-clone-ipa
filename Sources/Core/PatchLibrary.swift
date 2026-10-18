import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking      // Linux: URLSession nằm ở đây; trên Apple platform thì bỏ qua
#endif

/// Nguồn patch: trong app (bundled) → server (`/api/client/patch`) → OTA GitHub.
/// Tên file/đường dẫn đúng như bản gốc:
///   bundled : "BolaminhducMenu.bytes" (trong bundle)
///   server  : "remote_patch.bytes"
///   github  : "github_patch.bin"  ← OTA public của bản gốc
public final class PatchLibrary {

    public static let patchFileName = "Assembly-CSharp-patch.bytes"
    public static let bundledName = "BolaminhducMenu.bytes"
    public static let remoteCacheName = "remote_patch.bytes"
    public static let githubCacheName = "github_patch.bin"

    private let config: ServerConfig
    private let session: URLSession
    private let cacheDir: URL
    private let fm = FileManager.default
    public var onLog: ((String) -> Void)?

    public enum Source: String {
        case bundled = "trong app"
        case server = "server"
        case ota = "GitHub OTA"
    }

    public init(config: ServerConfig, session: URLSession = .shared) {
        self.config = config
        self.session = session
        let base = fm.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        self.cacheDir = base.appendingPathComponent("BolaPatch", isDirectory: true)
        try? fm.createDirectory(at: cacheDir, withIntermediateDirectories: true)
    }

    /// URL patch trên server (bản gốc: `PatchLibrary.remoteURL`).
    public var remoteURL: URL { config.endpoint(config.patchPath) }

    /// File patch mới nhất đang có (cache remote → cache github → bundled) — không gọi mạng.
    /// Bản gốc: `PatchLibrary.latest()`.
    public func latest(bundle: Bundle = .main) -> PatchFile? {
        if let data = fm.contents(atPath: cacheDir.appendingPathComponent(PatchLibrary.remoteCacheName).path) {
            return PatchFile(url: remoteURL, name: PatchLibrary.remoteCacheName,
                             size: data.count, bundled: false)
        }
        if let data = fm.contents(atPath: cacheDir.appendingPathComponent(PatchLibrary.githubCacheName).path) {
            return PatchFile(url: config.otaPatchURL, name: PatchLibrary.githubCacheName,
                             size: data.count, bundled: false)
        }
        if let url = bundle.url(forResource: "BolaminhducMenu", withExtension: "bytes"),
           let data = try? Data(contentsOf: url) {
            return PatchFile(url: url, name: PatchLibrary.bundledName,
                             size: data.count, bundled: true)
        }
        return nil
    }

    /// Bản gốc: `PatchLibrary.hasValidTrailer(_:license:)` — đọc file và kiểm 64 byte cuối
    /// khớp license + còn hạn + body chưa bị sửa.
    public func hasValidTrailer(_ url: URL, license: String) -> Bool {
        guard let data = try? Data(contentsOf: url) else { return false }
        return PatchTrailer.isValid(patch: data, license: license)
    }

    // MARK: lấy patch

    /// Thứ tự giống bản gốc: patch cá nhân hoá từ server trước, rồi OTA, cuối cùng là bản trong app.
    public func fetchPatch(key: String?, bundle: Bundle = .main) async -> (data: Data, file: PatchFile) {
        if let key, !key.isEmpty, let data = try? await fetchServerPatch(key: key) {
            onLog?("patch: đã lấy patch cá nhân hoá từ server (\(data.count) B)")
            return (data, PatchFile(url: config.endpoint(config.patchPath),
                                    name: PatchLibrary.remoteCacheName,
                                    size: data.count, bundled: false))
        }
        if let otaURL = config.otaPatchURL, let data = try? await fetchOTA(otaURL) {
            onLog?("patch: đã tải patch mới từ GitHub (\(data.count) B)")
            return (data, PatchFile(url: otaURL, name: PatchLibrary.githubCacheName,
                                    size: data.count, bundled: false))
        }
        if let bundledURL = bundle.url(forResource: "BolaminhducMenu", withExtension: "bytes"),
           let data = try? Data(contentsOf: bundledURL) {
            onLog?("patch: dùng bản trong app (không tải được OTA)")
            return (data, PatchFile(url: bundledURL, name: PatchLibrary.bundledName,
                                    size: data.count, bundled: true))
        }
        onLog?("Patch chưa sẵn sàng — kiểm tra mạng + key rồi mở lại app.")
        return (Data(), PatchFile(url: nil, name: "-", size: 0, bundled: false))
    }

    /// Bản gốc: `PatchLibrary.refreshRemote(completion:)` — callback Bool, không cần key.
    public func refreshRemote(completion: @escaping (Bool) -> Void) {
        Task {
            let (data, _) = await fetchPatch(key: nil)
            completion(!data.isEmpty)
        }
    }

    /// Bản gốc: `PatchLibrary.refreshFromGitHub(completion:)`.
    public func refreshFromGitHub(completion: @escaping (Bool) -> Void) {
        guard let url = config.otaPatchURL else {
            completion(false)
            return
        }
        Task {
            do {
                _ = try await fetchOTA(url)
                completion(true)
            } catch {
                completion(false)
            }
        }
    }

    private func fetchServerPatch(key: String) async throws -> Data {        var req = URLRequest(url: config.endpoint(config.patchPath))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["key": key, "platform": "ios"])
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        try cache(data, as: PatchLibrary.remoteCacheName)
        return data
    }

    private func fetchOTA(_ url: URL) async throws -> Data {
        let (data, resp) = try await session.data(from: url)
        guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        try cache(data, as: PatchLibrary.githubCacheName)
        return data
    }

    // MARK: cache

    private func cache(_ data: Data, as name: String) throws {
        try data.write(to: cacheDir.appendingPathComponent(name), options: .atomic)
    }

    public func cachedPatch() -> Data? {
        for name in [PatchLibrary.remoteCacheName, PatchLibrary.githubCacheName] {
            if let d = fm.contents(atPath: cacheDir.appendingPathComponent(name).path) { return d }
        }
        return nil
    }

    /// "Xoá Bộ Nhớ Đệm" — trả về số file đã xoá để UI log "cache: đã xoá (N file)"
    @discardableResult
    public func clearCache() -> Int {
        var n = 0
        if let files = try? fm.contentsOfDirectory(atPath: cacheDir.path) {
            for f in files {
                try? fm.removeItem(at: cacheDir.appendingPathComponent(f))
                n += 1
            }
        }
        return n
    }

    /// patch_verify.dat / verify_cache.dat — dấu xác nhận đã cài (bản gốc giữ 2 file này)
    public func writeVerifyMarkers(patchSHA: String, into access: ContainerAccess, game: GameTarget) {
        let stamp = "\(patchSHA):\(Int(Date().timeIntervalSince1970))\n"
        try? access.write(Data(stamp.utf8), to: "patch_verify.dat", in: game)
        try? access.write(Data(stamp.utf8), to: "verify_cache.dat", in: game)
    }

    public func readVerifyMarker(from access: ContainerAccess, game: GameTarget) -> String? {
        guard let d = try? access.read("patch_verify.dat", in: game) else { return nil }
        return String(data: d, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
