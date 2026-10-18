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

    private var timer: Timer?
    private var deployer: PatchDeployer?
    private var game: GameTarget = .freefireMAX
    public var onLog: ((String) -> Void)?
    public var onForceOff: ((Int) -> Void)?     // số file đã gỡ
    public var onTick: (() -> Void)?

    /// ⚠️ Bản gốc dùng vòng này để "keeps wiping traces" — tức dọn dấu vết của tool khỏi máy
    /// để né anti-cheat của game. Clone KHÔNG làm việc đó (đó là che giấu can thiệp vào game).
    /// Ở đây timer chỉ giữ app thức và cập nhật UI.
    public static let traceWipingImplemented = false

    public init() {}

    public func configure(deployer: PatchDeployer, game: GameTarget) {
        self.deployer = deployer
        self.game = game
    }

    public func setEnabled(_ on: Bool, hasKey: Bool) {
        if on && !hasKey {
            onLog?("🔑 Nhập key xong rồi mới bật được Anti-ban nhé!")
            enabled = false
            return
        }
        enabled = on
        if on {
            onLog?("🛡️ Đã bật Anti-ban — (clone: chỉ giữ phiên, không dọn dấu vết)")
            startKeepalive()
        } else {
            stopKeepalive()
            let n = deployer?.uninstall(game: game) ?? 0
            onLog?("Đã tắt Anti-ban → tự gỡ patch (\(n))")
            onForceOff?(n)
        }
    }

    private func startKeepalive() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 90, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.onTick?() }
        }
    }

    private func stopKeepalive() {
        timer?.invalidate()
        timer = nil
    }
}
