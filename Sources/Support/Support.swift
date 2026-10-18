import Foundation

// MARK: - BackgroundAudio (giữ app sống khi người dùng mở game — bola_silence.wav)

#if canImport(AVFoundation)
import AVFoundation

public final class BackgroundAudio {
    public static let shared = BackgroundAudio()

    private var player: AVAudioPlayer?
    private var session: AVAudioSession?

    public func start(resource: String = "bola_silence", ext: String = "wav") {
        guard let url = Bundle.main.url(forResource: resource, withExtension: ext) else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
            self.session = session

            let p = try AVAudioPlayer(contentsOf: url)
            p.numberOfLoops = -1          // lặp vô hạn
            p.volume = 0                  // im lặng — chỉ để giữ background mode
            p.prepareToPlay()
            p.play()
            self.player = p
        } catch {
            Logger.shared.log("audio: không giữ được nền (\(error.localizedDescription))")
        }
    }

    public func stop() {
        player?.stop()
        player = nil
        try? session?.setActive(false)
    }
}
#endif

// MARK: - Antiban (UI + hành vi "tắt = gỡ patch"; dọn dấu vết + decoy)

/// Hằng số dùng chung, đặt ngoài @MainActor để gọi được từ background.
enum AntibanDecoy {
    /// 9 thư mục telemetry bị khoá 0555 (đúng danh sách bản gốc).
    static let telemetryNames = [
        "Analytics", "CrashReporter", "Snapshots", "adjust-sdk", "bugly",
        "com.appsflyer", "com.crashlytics.data", "com.google.firebase", "crashes",
    ]
    /// File rác trộn patch thật (prefix của bản gốc).
    static let prefixes = ["BOLA_CHEAT_", "BOLA_MENU_", "MINHDUC_BAIT_"]
    static let patchSiblings = [
        "Assembly-CSharp-patch.bak", "Assembly-CSharp-patch_old.bytes",
        "Assembly-CSharp-patch2.bytes", "Assembly-CSharp-patch(1).bytes",
        "Assembly-CSharp-patch-copy.bytes",
    ]
    static let cachePrefix = "cache_data_"

    /// Số file rác + kích thước mỗi file. Bản gốc từng thả ~1000×512 KB rồi bỏ
    /// ở v213; ở đây giữ mức nhẹ để không ngốn dung lượng máy.
    static let count = 300
    static let size = 128 * 1024
}

@MainActor
public final class Antiban {
    /// "🛡️ Đã bật Anti-ban — tự dọn dấu vết liên tục (tắt sẽ tự gỡ patch)"
    public private(set) var enabled: Bool = false

    /// Danh sách lấy đúng từ binary gốc (`Antiban.clean(game:)`).
    static let documentsItems = [
        "contentcache", "integrity_db.sqlite", "patch_verify.dat", "verify_cache.dat",
    ]
    static let cachesItems = [
        "Analytics", "CrashReporter", "crashes", "com.crashlytics.data", "bugly",
        "com.google.firebase", "com.appsflyer", "adjust-sdk", "Snapshots", "GCloud", "GVoice",
    ]
    static let logDirs = [
        "analytics", "anti_cheat_logs", "beacon", "bugly", "crash", "crash_dump", "adp_log",
        "feedback", "garena_log", "gvoice", "log", "msdk_log", "oss_log", "pending_reports",
        "report", "shadow_tracker", "tdlog",
    ]
    static let globalCrashLogs = "/var/mobile/Library/Logs/CrashReporter"

    private var timer: Timer?
    private var deployer: PatchDeployer?
    private var access: ContainerAccess?
    private var game: GameTarget = .freefireMAX
    public var onLog: ((String) -> Void)?
    public var onForceOff: ((Int) -> Void)?     // số file đã gỡ
    public var onTick: (() -> Void)?

    public static let traceWipingImplemented = true

    public init() {}

    public func configure(deployer: PatchDeployer, game: GameTarget, access: ContainerAccess? = nil) {
        self.deployer = deployer
        self.game = game
        self.access = access
    }

    public func setEnabled(_ on: Bool, hasKey: Bool) {
        if on && !hasKey {
            onLog?("🔑 Nhập key xong rồi mới bật được Anti-ban nhé!")
            enabled = false
            return
        }
        enabled = on
        if on {
            onLog?("🛡️ Đã bật Anti-ban — tự dọn dấu vết liên tục (tắt sẽ tự gỡ patch)")
            let n = cleanNow()
            if n > 0 { onLog?("anti-ban: đã dọn \(n) mục") }
            // khoá telemetry + thả decoy chạy nền để không treo UI
            let root = containerRoot()
            let manifestDir = FileManager.default
                .urls(for: .documentDirectory, in: .userDomainMask).first?.path
            let gameRaw = game.rawValue
            Task.detached(priority: .utility) {
                var locked = 0, planted = 0
                if let root {
                    locked = Antiban.lockTelemetryDirs(root: root)
                    planted = Antiban.plantDecoys(root: root, manifestDir: manifestDir, gameRaw: gameRaw)
                }
                await MainActor.run {
                    self.onLog?("anti-ban: đã khoá \(locked) thư mục telemetry (0555)")
                    self.onLog?("anti-ban: đã thả \(planted) file rác trộn patch")
                }
            }
            startLoop()
        } else {
            stopLoop()
            let unlocked = unlockTelemetryDirs()
            let removed = removeDecoys()
            onLog?("anti-ban: mở khoá \(unlocked) thư mục, gỡ \(removed) file rác")
            let n = deployer?.uninstall(game: game) ?? 0
            onLog?("Đã tắt Anti-ban → tự gỡ patch (\(n))")
            onForceOff?(n)
        }
    }

    /// Dọn dấu vết đúng các mục bản gốc xoá. Trả về số mục đã xoá được.
    @discardableResult
    public func cleanNow() -> Int {
        guard let access, let docs = access.documentsPath(for: game) else { return 0 }
        let fm = FileManager.default
        let root = (docs as NSString).deletingLastPathComponent
        let caches = (root as NSString).appendingPathComponent("Library/Caches")
        var removed = 0

        for name in Self.documentsItems {
            if Self.remove(fm, (docs as NSString).appendingPathComponent(name)) { removed += 1 }
        }
        for name in Self.cachesItems {
            if Self.remove(fm, (caches as NSString).appendingPathComponent(name)) { removed += 1 }
        }
        // log dir của game có thể nằm ở Documents hoặc Library/Caches
        for name in Self.logDirs {
            if Self.remove(fm, (docs as NSString).appendingPathComponent(name)) { removed += 1 }
            if Self.remove(fm, (caches as NSString).appendingPathComponent(name)) { removed += 1 }
        }
        // crash log hệ thống — không có quyền thì bỏ qua
        if let entries = try? fm.contentsOfDirectory(atPath: Self.globalCrashLogs) {
            for e in entries {
                if Self.remove(fm, (Self.globalCrashLogs as NSString).appendingPathComponent(e)) {
                    removed += 1
                }
            }
        }
        return removed
    }

    private static func remove(_ fm: FileManager, _ path: String) -> Bool {
        guard fm.fileExists(atPath: path) else { return false }
        return (try? fm.removeItem(atPath: path)) != nil
    }

    // MARK: khoá telemetry (nguồn: Antiban.swift của bản gốc)

    private func containerRoot() -> String? {
        guard let access, let docs = access.documentsPath(for: game) else { return nil }
        return (docs as NSString).deletingLastPathComponent
    }

    @discardableResult
    public func lockTelemetryDirs() -> Int {
        guard let root = containerRoot() else { return 0 }
        return Self.lockTelemetryDirs(root: root)
    }

    @discardableResult
    public func unlockTelemetryDirs() -> Int {
        guard let root = containerRoot() else { return 0 }
        return Self.unlockTelemetryDirs(root: root)
    }

    /// Bản nonisolated để gọi từ background (không đụng state của actor).
    nonisolated static func lockTelemetryDirs(root: String) -> Int {
        setTelemetryPermissions(root: root, perm: 0o555)
    }

    nonisolated static func unlockTelemetryDirs(root: String) -> Int {
        setTelemetryPermissions(root: root, perm: 0o755)
    }

    nonisolated private static func setTelemetryPermissions(root: String, perm: Int) -> Int {
        let fm = FileManager.default
        let caches = (root as NSString).appendingPathComponent("Library/Caches")
        try? fm.createDirectory(atPath: caches, withIntermediateDirectories: true)
        var n = 0
        for name in AntibanDecoy.telemetryNames {
            let dir = (caches as NSString).appendingPathComponent(name)
            try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
            if (try? fm.setAttributes([.posixPermissions: perm], ofItemAtPath: dir)) != nil {
                n += 1
            }
        }
        return n
    }

    // MARK: decoy flood

    @discardableResult
    public func plantDecoys() -> Int {
        guard let root = containerRoot() else { return 0 }
        let mine = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.path
        return Self.plantDecoys(root: root, manifestDir: mine, gameRaw: game.rawValue)
    }

    nonisolated static func plantDecoys(root: String, manifestDir: String?, gameRaw: String) -> Int {
        let fm = FileManager.default
        let docs = (root as NSString).appendingPathComponent("Documents")
        let caches = (root as NSString).appendingPathComponent("Library/Caches")
        try? fm.createDirectory(atPath: docs, withIntermediateDirectories: true)

        let blob = Data((0..<AntibanDecoy.size).map { _ in UInt8.random(in: 0...255) })
        var names: [String] = []
        var n = 0

        for _ in 0..<AntibanDecoy.count {
            let prefix = AntibanDecoy.prefixes[Int.random(in: 0..<AntibanDecoy.prefixes.count)]
            let name = prefix + randomHex(12) + ".bytes"
            let path = (docs as NSString).appendingPathComponent(name)
            if (try? blob.write(to: URL(fileURLWithPath: path), options: .atomic)) != nil {
                names.append(name)
                n += 1
            }
        }
        for sibling in AntibanDecoy.patchSiblings {
            let path = (docs as NSString).appendingPathComponent(sibling)
            if (try? blob.prefix(4096).write(to: URL(fileURLWithPath: path))) != nil {
                names.append(sibling)
                n += 1
            }
        }
        try? fm.createDirectory(atPath: caches, withIntermediateDirectories: true)
        for _ in 0..<20 {
            let name = AntibanDecoy.cachePrefix + randomHex(10) + ".bin"
            let path = (caches as NSString).appendingPathComponent(name)
            if (try? blob.prefix(2048).write(to: URL(fileURLWithPath: path))) != nil {
                n += 1
            }
        }

        // manifest nằm trong container của app mình, không nằm trong container game
        if let mine = manifestDir {
            let manifest = (mine as NSString).appendingPathComponent("bola_junk_\(gameRaw).txt")
            try? names.joined(separator: "\n").write(toFile: manifest, atomically: true, encoding: .utf8)
        }
        return n
    }

    @discardableResult
    public func removeDecoys() -> Int {
        guard let root = containerRoot() else { return 0 }
        let fm = FileManager.default
        let docs = (root as NSString).appendingPathComponent("Documents")
        let caches = (root as NSString).appendingPathComponent("Library/Caches")
        let library = (root as NSString).appendingPathComponent("Library")
        var n = 0

        if let mine = fm.urls(for: .documentDirectory, in: .userDomainMask).first?.path {
            let manifest = (mine as NSString).appendingPathComponent("bola_junk_\(game.rawValue).txt")
            if let text = try? String(contentsOfFile: manifest, encoding: .utf8) {
                for line in text.split(separator: "\n") {
                    let name = String(line).trimmingCharacters(in: .whitespaces)
                    if name.isEmpty { continue }
                    if (try? fm.removeItem(atPath: (docs as NSString).appendingPathComponent(name))) != nil {
                        n += 1
                    }
                }
                try? fm.removeItem(atPath: manifest)
            }
        }

        for dir in [docs, library] {
            guard let items = try? fm.contentsOfDirectory(atPath: dir) else { continue }
            for f in items {
                let isDecoy = AntibanDecoy.prefixes.contains(where: { f.hasPrefix($0) })
                if !isDecoy && !AntibanDecoy.patchSiblings.contains(f) { continue }
                if (try? fm.removeItem(atPath: (dir as NSString).appendingPathComponent(f))) != nil {
                    n += 1
                }
            }
        }

        for dir in [docs, caches] {
            guard let items = try? fm.contentsOfDirectory(atPath: dir) else { continue }
            for f in items where f.hasPrefix(AntibanDecoy.cachePrefix) || Self.isFloodName(f) {
                if (try? fm.removeItem(atPath: (dir as NSString).appendingPathComponent(f))) != nil {
                    n += 1
                }
            }
        }
        return n
    }

    /// Tên kiểu flood cũ: cache_<14 hex>.bytes / .bin
    nonisolated static func isFloodName(_ name: String) -> Bool {
        guard name.hasPrefix("cache_") else { return false }
        let isBytes = name.hasSuffix(".bytes")
        let isBin = name.hasSuffix(".bin")
        guard isBytes || isBin else { return false }
        let mid = isBytes ? name.dropFirst(6).dropLast(6) : name.dropFirst(6).dropLast(4)
        guard mid.count == 14, mid.allSatisfy({ $0.isHexDigit }) else { return false }
        return isBytes ? name.count == 26 : name.count == 25
    }

    nonisolated private static func randomHex(_ count: Int) -> String {
        let chars = Array("0123456789abcdef")
        return String((0..<count).map { _ in chars[Int.random(in: 0..<chars.count)] })
    }

    private func startLoop() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                let n = self.cleanNow()
                if n > 0 { self.onLog?("anti-ban: đã dọn \(n) mục") }
                self.onTick?()
            }
        }
    }

    private func stopLoop() {
        timer?.invalidate()
        timer = nil
    }
}

