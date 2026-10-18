import Foundation

#if canImport(UIKit)
import UIKit

/// Mở game sau khi inject — giống IPA gốc:
/// 1. `LSApplicationWorkspace openApplicationWithBundleID:` (chính xác, không cần scheme).
/// 2. Fallback lần lượt các URL scheme của Free Fire.
enum GameLauncher {

    static func launch(_ game: GameTarget, log: @escaping (String) -> Void) {
        // IFix chỉ nạp patch lúc process khởi động → tắt bản đang chạy trước.
        let killed = BolaTerminateApplication(game.bundleID)
        if killed {
            log("đã tắt game cũ — mở lại để nạp patch")
        }
        let delay: TimeInterval = killed ? 0.8 : 0
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            if BolaOpenApplication(game.bundleID) {
                log("đã gửi lệnh mở game (LSApplicationWorkspace)")
                return
            }
            let schemes: [String] = {
                var seen = Set<String>()
                return [game.scheme, "freefire", "ff", "freefireth", "freefiremax"]
                    .filter { seen.insert($0).inserted }
            }()
            tryScheme(schemes, at: 0, game: game, log: log)
        }
    }

    private static func tryScheme(_ schemes: [String], at index: Int,
                                  game: GameTarget, log: @escaping (String) -> Void) {
        guard index < schemes.count else {
            log("KHÔNG mở được — mở \(game.name) bằng tay giúp mình.")
            return
        }
        guard let url = URL(string: "\(schemes[index])://") else {
            tryScheme(schemes, at: index + 1, game: game, log: log)
            return
        }
        UIApplication.shared.open(url, options: [:]) { ok in
            if ok {
                log("đã gửi lệnh mở game (\(schemes[index])://)")
            } else {
                tryScheme(schemes, at: index + 1, game: game, log: log)
            }
        }
    }
}

#endif
