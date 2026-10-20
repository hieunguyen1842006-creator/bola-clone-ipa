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
        case .nvhBeta: return "CAMXA FullSkin"
        case .unlockSkin: return "4in1 LiqiMobi"
        }
    }

    public var subtitle: String {
        switch self {
        case .hudFull:
            return "HUD địch: máu, tên, CD chiêu, vòng + icon 5 hero, kèm unlock skin"
        case .nvhBeta:
            return "FullSkin + ESP Liqi — bản 20/10 (ghi HeroSkin_1 + HeroSkin_2)"
        case .unlockSkin:
            return "Gói 4in1 LiqiMobi 16/10 (FullSkin/HUD/ESP) — HeroSkin_1 + HeroSkin_2"
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
    private static let filesKey = "nvh.lq.files."

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

    /// Gói nhiều file: "LQ2\0" + u32 số file + [u8 lenTên][tên][u32 size][data]…
    public static func parseBundle(_ data: Data) -> [(name: String, data: Data)]? {
        let b = [UInt8](data)
        guard b.count >= 9, b[0] == 0x4C, b[1] == 0x51, b[2] == 0x32, b[3] == 0 else { return nil }
        func u32(_ p: Int) -> Int {
            Int(b[p]) | Int(b[p + 1]) << 8 | Int(b[p + 2]) << 16 | Int(b[p + 3]) << 24
        }
        var o = 4
        let n = u32(o)
        o += 4
        guard n > 0, n <= 8 else { return nil }
        var out: [(String, Data)] = []
        for _ in 0..<n {
            guard o < b.count else { return nil }
            let nl = Int(b[o])
            o += 1
            guard nl > 0, nl <= 64, o + nl + 4 <= b.count else { return nil }
            guard let name = String(bytes: b[o..<(o + nl)], encoding: .utf8) else { return nil }
            o += nl
            let sz = u32(o)
            o += 4
            guard sz > 0, o + sz <= b.count else { return nil }
            out.append((name, Data(b[o..<(o + sz)])))
            o += sz
        }
        return out
    }

    /// Tên các file đã ghi (bản cũ chỉ có HeroSkin_2).
    private var installedNames: [String] {
        UserDefaults.standard.stringArray(forKey: Self.filesKey + game.bundleID) ?? [Self.targetFileName]
    }

    /// Đã inject = mọi file trong game khớp SHA-256 của payload mình đã ghi.
    public func isInstalled() -> Bool {
        guard let target = try? resolveTarget() else { return false }
        let d = UserDefaults.standard
        for name in installedNames {
            guard let data = (try? access.read(relativePath: "\(target.relativePath)/\(name)", in: game)) ?? nil,
                  let expected = d.string(forKey: Self.shaKey + game.bundleID + "." + name),
                  SHA256.hex([UInt8](data)) == expected
            else { return false }
        }
        return true
    }

    // MARK: - cài / gỡ

    @discardableResult
    public func install(_ payload: Data, pack: LQPack, config: String? = nil) -> InstallOutcome {
        let files = Self.parseBundle(payload) ?? [(Self.targetFileName, payload)]
        return write(files, pack: pack, config: config)
    }

    private func write(_ files: [(name: String, data: Data)],
                       pack: LQPack, config: String?) -> InstallOutcome {
        do {
            let target = try resolveTarget()
            for f in files {
                let rel = "\(target.relativePath)/\(f.name)"
                if let cur = (try? access.read(relativePath: rel, in: game)) ?? nil {
                    try rememberOriginal(cur, version: target.version, name: f.name)
                } else {
                    clearOriginal(version: target.version, name: f.name)
                }
            }
            for f in files {
                try access.write(f.data, toRelative: "\(target.relativePath)/\(f.name)", in: game)
            }

            if let config {
                try access.write(Data(config.utf8), to: "lqcfg.txt", in: game)
            } else {
                try? access.remove("lqcfg.txt", in: game)
            }

            for f in files {
                let rel = "\(target.relativePath)/\(f.name)"
                guard let back = (try? access.read(relativePath: rel, in: game)) ?? nil else {
                    return .bad("Ghi xong nhưng không đọc lại được — thử lại")
                }
                guard back == f.data else {
                    return .bad("Đọc lại không khớp (\(f.name): \(back.count) B ≠ \(f.data.count) B)")
                }
            }

            let d = UserDefaults.standard
            d.set(target.version, forKey: Self.versionKey + game.bundleID)
            d.set(files.map { $0.name }, forKey: Self.filesKey + game.bundleID)
            for f in files {
                d.set(SHA256.hex([UInt8](f.data)), forKey: Self.shaKey + game.bundleID + "." + f.name)
            }
            log("lq: đã ghi \(target.relativePath) • \(pack.title) • \(files.map { $0.name }.joined(separator: " + "))")
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
            let d = UserDefaults.standard
            let names = installedNames
            var restored = 0
            var removed = 0
            var kept = 0

            for name in names {
                let rel = "\(target.relativePath)/\(name)"
                let current = (try? access.read(relativePath: rel, in: game)) ?? nil
                if let url = backupURL(version: target.version, name: name),
                   fm.fileExists(atPath: url.path),
                   let original = fm.contents(atPath: url.path) {
                    try access.write(original, toRelative: rel, in: game)
                    try? fm.removeItem(at: url)
                    restored += 1
                } else if let current,
                          let expected = d.string(forKey: Self.shaKey + game.bundleID + "." + name),
                          SHA256.hex([UInt8](current)) == expected {
                    try access.remove(relativePath: rel, in: game)
                    removed += 1
                } else if current != nil {
                    kept += 1
                }
            }

            d.removeObject(forKey: Self.filesKey + game.bundleID)
            d.removeObject(forKey: Self.versionKey + game.bundleID)
            for name in names {
                d.removeObject(forKey: Self.shaKey + game.bundleID + "." + name)
            }
            try? access.remove("lqcfg.txt", in: game)
            log("lq: gỡ xong — khôi phục \(restored), xoá \(removed), giữ \(kept)")
            if kept > 0, restored == 0, removed == 0 {
                return .bad("File trong game không phải của NVH — không xoá để tránh hỏng game")
            }
            return .good(restored > 0
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

    private func backupURL(version: String, name: String) -> URL? {
        backupRoot?.appendingPathComponent("\(version)-\(name)")
    }

    /// Chỉ lưu bản gốc lần đầu — không để bản mod ghi đè backup thật.
    private func rememberOriginal(_ data: Data, version: String, name: String) throws {
        guard let url = backupURL(version: version, name: name) else { return }
        guard !fm.fileExists(atPath: url.path) else { return }
        try fm.createDirectory(at: url.deletingLastPathComponent(),
                               withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
        log("lq: đã backup bản gốc \(version)/\(name) (\(data.count) B)")
    }

    private func clearOriginal(version: String, name: String) {
        if let url = backupURL(version: version, name: name) { try? fm.removeItem(at: url) }
    }

    private func log(_ text: String) { onLog?(text) }
}
