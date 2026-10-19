import Foundation

/// Gói hotfix của Liên Quân. Mỗi gói là một payload IFix LQMB đóng trong vault.
public enum LQPack: String, CaseIterable, Identifiable {
    case hudFull = "hud"
    case nvhBeta = "nvhbeta"
    case unlockSkin = "unlock"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .hudFull: return "Full HUD"
        case .nvhBeta: return "NVH Beta"
        case .unlockSkin: return "Unlock skin"
        }
    }

    public var subtitle: String {
        switch self {
        case .hudFull:
            return "HUD địch: máu, tên, CD chiêu, vòng + icon 5 hero, kèm unlock skin"
        case .nvhBeta:
            return "Full skin + kill notify + ESP line/box + HUD máu/tên/CD địch + FOV"
        case .unlockSkin:
            return "Mở khoá toàn bộ tủ skin + kill notify + chặn check MD5/không báo server"
        }
    }

    public var symbol: String {
        switch self {
        case .hudFull: return "rectangle.on.rectangle"
        case .nvhBeta: return "bolt.fill"
        case .unlockSkin: return "paintpalette"
        }
    }

    public var vaultResource: String {
        switch self {
        case .hudFull: return "LQHud"
        case .nvhBeta: return "NVHLQ"
        case .unlockSkin: return "LQUnlock"
        }
    }
}

public enum LQError: Error, CustomStringConvertible {
    case resourcesNotFound
    case thanosNotFound(String)

    public var description: String {
        switch self {
        case .resourcesNotFound:
            return "Không thấy Documents/Resources — mở Liên Quân 1 lần rồi thử lại"
        case .thanosNotFound(let v):
            return "Không thấy thư mục Thanos trong Resources/\(v)"
        }
    }
}

/// Ghi/gỡ hotfix payload của Liên Quân:
///   `Documents/Resources/<ver>/Thanos/HeroSkin_2.bytes`
///
/// Trước khi ghi luôn backup bản gốc (nếu có) vào sandbox của app; UN INJECT
/// khôi phục đúng bản đó, không đụng file lạ.
public final class LienQuanDeployer {

    public static let targetFileName = "HeroSkin_2.bytes"
    private static let backupFolder = "NVH-LQ-Backup"
    private static let versionKey = "nvh.lq.version."
    private static let shaKey = "nvh.lq.sha."

    public var onLog: ((String) -> Void)?

    private let access: ContainerAccess
    private let game: GameTarget
    private let fm = FileManager.default

    public init(access: ContainerAccess, game: GameTarget) {
        self.access = access
        self.game = game
    }

    // MARK: - dò thư mục đích

    public struct Target {
        public let version: String
        public let relativePath: String        // Resources/<ver>/Thanos
        public var filePath: String { "\(relativePath)/\(LienQuanDeployer.targetFileName)" }
    }

    /// Tìm version đang có HeroSkin_2.bytes; nếu chưa có thì dùng version mới nhất.
    public func resolveTarget() throws -> Target {
        let versions = ((try? access.list("Resources", in: game)) ?? [])
            .filter { !$0.hasPrefix(".") }
            .sorted(by: >)
        guard let newest = versions.first else { throw LQError.resourcesNotFound }

        for v in versions {
            let rel = "Resources/\(v)/Thanos"
            let entries = (try? access.list(rel, in: game)) ?? []
            if entries.contains(Self.targetFileName) {
                return Target(version: v, relativePath: rel)
            }
        }

        // Chưa thấy payload nào → tạo Thanos trong version mới nhất (game sẽ tạo khi cần).
        let rel = "Resources/\(newest)/Thanos"
        try access.write(Data(), toRelative: "\(rel)/.nvh_probe", in: game)
        try access.remove(relativePath: "\(rel)/.nvh_probe", in: game)
        return Target(version: newest, relativePath: rel)
    }

    /// Version đã ghi lần trước (hiển thị UI).
    public func installedVersion() -> String? {
        if let saved = UserDefaults.standard.string(forKey: Self.versionKey + game.bundleID) {
            return saved
        }
        return (try? resolveTarget())?.version
    }

    // MARK: - trạng thái

    /// Đã inject = file trong game khớp SHA-256 của payload mình đã ghi.
    public func isInstalled() -> Bool {
        guard let target = try? resolveTarget(),
              let data = (try? access.read(relativePath: target.filePath, in: game)) ?? nil
        else { return false }
        let sha = SHA256.hex([UInt8](data))
        if let expected = UserDefaults.standard.string(forKey: Self.shaKey + game.bundleID) {
            return sha == expected
        }
        // Sau khi cài lại app: nhận diện bằng hash các vault có sẵn.
        for pack in LQPack.allCases {
            if let plain = PatchVault.load(resource: pack.vaultResource),
               SHA256.hex([UInt8](plain)) == sha {
                return true
            }
        }
        return false
    }

    // MARK: - cài / gỡ

    @discardableResult
    public func install(_ payload: Data, pack: LQPack, config: String? = nil) -> InstallOutcome {
        do {
            let target = try resolveTarget()
            let current = (try? access.read(relativePath: target.filePath, in: game)) ?? nil
            if let current {
                try rememberOriginal(current, version: target.version)
            } else {
                clearOriginal(version: target.version)
            }

            try access.write(payload, toRelative: target.filePath, in: game)

            if let config {
                try access.write(Data(config.utf8), to: "lqcfg.txt", in: game)
            } else {
                try? access.remove("lqcfg.txt", in: game)
            }

            guard let back = (try? access.read(relativePath: target.filePath, in: game)) ?? nil else {
                return .bad("Ghi xong nhưng không đọc lại được — thử lại")
            }
            guard back == payload else {
                return .bad("Đọc lại không khớp (\(back.count) B ≠ \(payload.count) B)")
            }

            let d = UserDefaults.standard
            d.set(target.version, forKey: Self.versionKey + game.bundleID)
            d.set(SHA256.hex([UInt8](payload)), forKey: Self.shaKey + game.bundleID)
            log("lq: đã ghi \(target.filePath) • \(pack.title) • \(payload.count) B")
            return .good("Đã inject \(game.name) (\(pack.title)) — mở game để áp dụng")
        } catch {
            let msg = (error as? LQError)?.description ?? error.localizedDescription
            log("lq: lỗi \(msg)")
            return .bad(msg)
        }
    }

    @discardableResult
    public func uninstall() -> InstallOutcome {
        do {
            let target = try targetForRemoval()
            let current = (try? access.read(relativePath: target.filePath, in: game)) ?? nil
            let d = UserDefaults.standard
            let expected = d.string(forKey: Self.shaKey + game.bundleID)
            var restored = false

            if let url = backupURL(version: target.version),
               fm.fileExists(atPath: url.path),
               let original = fm.contents(atPath: url.path) {
                try access.write(original, toRelative: target.filePath, in: game)
                try? fm.removeItem(at: url)
                restored = true
            } else if let current, let expected,
                      SHA256.hex([UInt8](current)) == expected {
                try access.remove(relativePath: target.filePath, in: game)
            } else if current != nil {
                return .bad("File trong game không phải của NVH — không xoá để tránh hỏng game")
            }

            d.removeObject(forKey: Self.shaKey + game.bundleID)
            d.removeObject(forKey: Self.versionKey + game.bundleID)
            try? access.remove("lqcfg.txt", in: game)
            log(restored ? "lq: đã khôi phục \(target.filePath) gốc"
                         : "lq: đã xoá \(target.filePath)")
            return .good(restored
                         ? "Đã gỡ LQ — khôi phục file gốc. Mở lại game nhé."
                         : "Đã gỡ LQ. Mở lại game nhé.")
        } catch {
            let msg = (error as? LQError)?.description ?? error.localizedDescription
            log("lq: lỗi gỡ — \(msg)")
            return .bad(msg)
        }
    }

    // MARK: - config cho patch NVH Beta (lqcfg.txt)

    @discardableResult
    public func writeConfig(_ text: String) -> Bool {
        do {
            try access.write(Data(text.utf8), to: "lqcfg.txt", in: game)
            return true
        } catch {
            log("lq: không ghi được lqcfg.txt — \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - backup

    private func targetForRemoval() throws -> Target {
        let saved = UserDefaults.standard.string(forKey: Self.versionKey + game.bundleID)
        if let saved, !saved.isEmpty {
            let rel = "Resources/\(saved)/Thanos"
            if (try? access.list(rel, in: game)) != nil {
                return Target(version: saved, relativePath: rel)
            }
        }
        return try resolveTarget()
    }

    private var backupRoot: URL? {
        guard let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }
        return docs.appendingPathComponent(Self.backupFolder, isDirectory: true)
            .appendingPathComponent(game.bundleID, isDirectory: true)
    }

    private func backupURL(version: String) -> URL? {
        backupRoot?.appendingPathComponent("\(version)-\(Self.targetFileName)")
    }

    /// Chỉ lưu bản gốc lần đầu — không để bản mod ghi đè backup thật.
    private func rememberOriginal(_ data: Data, version: String) throws {
        guard let url = backupURL(version: version) else { return }
        guard !fm.fileExists(atPath: url.path) else { return }
        try fm.createDirectory(at: url.deletingLastPathComponent(),
                               withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
        log("lq: đã backup bản gốc \(version) (\(data.count) B)")
    }

    private func clearOriginal(version: String) {
        if let url = backupURL(version: version) { try? fm.removeItem(at: url) }
    }

    private func log(_ text: String) { onLog?(text) }
}
