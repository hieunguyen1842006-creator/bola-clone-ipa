import Foundation

/// PatchGuard — kiểm tra toàn vẹn patch sau khi ghi + neutral seed.
///
/// Ý tưởng port từ hướng của Sophia/FFXC: patch đầy đủ chỉ nằm trên đĩa khi thật sự
/// có license hợp lệ; nếu không, ghi một IFix seed "neutral" (không chứa chức năng)
/// để container không mang theo payload cheat. Hash của bản đã ghi được lưu trong
/// UserDefaults của app mình (không tạo thêm file lạ trong container game).
public enum PatchGuard {

    public static let neutralResource = "NeutralPatch"
    private static let defaultsPrefix = "nvh.patch.sha."

    public enum State: String {
        case missing      // chưa cài
        case ok           // khớp hash đã ghi nhận
        case neutral      // đang là seed neutral (không có chức năng)
        case modified     // bị sửa/ghi đè bởi thứ khác
    }

    public static func digest(_ data: Data) -> String {
        SHA256.hex([UInt8](data))
    }

    public static func neutralData(bundle: Bundle = .main) -> Data? {
        guard let url = bundle.url(forResource: neutralResource, withExtension: "bytes") else {
            return nil
        }
        return try? Data(contentsOf: url)
    }

    public static func isNeutral(_ data: Data, bundle: Bundle = .main) -> Bool {
        guard let neutral = neutralData(bundle: bundle) else { return false }
        return data == neutral
    }

    public static func record(_ digest: String, for game: GameTarget) {
        UserDefaults.standard.set(digest, forKey: defaultsPrefix + game.bundleID)
    }

    public static func expected(for game: GameTarget) -> String? {
        UserDefaults.standard.string(forKey: defaultsPrefix + game.bundleID)
    }

    public static func clear(for game: GameTarget) {
        UserDefaults.standard.removeObject(forKey: defaultsPrefix + game.bundleID)
    }

    public static func state(of installed: Data?, for game: GameTarget,
                             bundle: Bundle = .main) -> State {
        guard let installed, !installed.isEmpty else { return .missing }
        if isNeutral(installed, bundle: bundle) { return .neutral }
        guard let expected = expected(for: game) else { return .modified }
        return digest(installed) == expected ? .ok : .modified
    }
}
