import Foundation
import Combine

// MARK: - VersionGate (_blocked _killed _message _downloadURL _latestVersion timer lastOkKey)

@MainActor
public final class VersionGate: ObservableObject {

    public static let shared = VersionGate()

    @Published public private(set) var blocked: Bool = false
    @Published public private(set) var killed: Bool = false
    @Published public private(set) var message: String = ""
    @Published public private(set) var downloadURL: URL?
    @Published public private(set) var latestVersion: String = ""

    private var config: ServerConfig?
    private var timer: Timer?
    private var session: URLSession = .shared

    public init() {}

    public func configure(_ config: ServerConfig) {
        self.config = config
    }

    /// Gọi lúc mở app + lặp mỗi 30 phút. `minVersion` đọc từ server (/download/latest).
    public func check(current: String = Version.appVersion, minRequired: String? = nil) {
        if let minRequired, Version.compare(current, minRequired) < 0 {
            killed = true
            message = "⛔ Bản này đã ngừng hoạt động."
        }
        guard let config = self.config else { return }
        Task {
            // endpoint thật: GET {base}/download/latest → { "version": "1.0.1", "minVersion": "1.0.0", "url": "…" }
            var req = URLRequest(url: config.endpoint(config.downloadPath))
            req.timeoutInterval = 15
            guard let (data, _) = try? await session.data(for: req),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { return }

            let latest = (json["version"] as? String) ?? ""
            let minV = (json["minVersion"] as? String) ?? latest
            let dl = (json["url"] as? String).flatMap(URL.init(string:))

            await MainActor.run {
                self.latestVersion = latest
                self.downloadURL = dl
                if !minV.isEmpty, Version.compare(current, minV) < 0 {
                    self.blocked = true
                    self.message = "Bạn đang sử dụng phiên bản cũ. Vui lòng tải bản mới nhất để tiếp tục!"
                } else if !self.killed {
                    self.blocked = false
                    self.message = ""
                }
            }
        }
        startTimer()
    }

    /// So sánh version kiểu "1.0.0" — trả -1/0/1.
        public static var appVersion: String { Version.appVersion }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1800, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.check() }
        }
    }
}
