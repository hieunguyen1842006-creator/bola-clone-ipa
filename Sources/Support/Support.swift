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

// MARK: - Antiban (UI + hành vi "tắt = gỡ patch"; phần dọn dấu vết KHÔNG clone)

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
            startLoop()
        } else {
            stopLoop()
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

