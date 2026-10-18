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
        PatchVault.neutralPatch(bundle: bundle)
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

/// PatchJournal — nhớ `localConfig.json` gốc trước khi ghi đè để un-inject khôi phục.
/// Giống Sophia: uninject trả cấu hình về như trước, không để lại cờ testCodePatch.
public enum PatchJournal {

    private static let configKey = "nvh.cfg.orig."
    private static let recordKey = "nvh.cfg.record."

    public static func rememberConfig(_ data: Data?, for game: GameTarget) {
        let defaults = UserDefaults.standard
        defaults.set(true, forKey: recordKey + game.bundleID)
        if let data {
            defaults.set(data, forKey: configKey + game.bundleID)
        } else {
            defaults.removeObject(forKey: configKey + game.bundleID)
        }
    }

    public static func hasConfigRecord(for game: GameTarget) -> Bool {
        UserDefaults.standard.bool(forKey: recordKey + game.bundleID)
    }

    public static func originalConfig(for game: GameTarget) -> Data? {
        UserDefaults.standard.data(forKey: configKey + game.bundleID)
    }

    public static func clearConfig(for game: GameTarget) {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: configKey + game.bundleID)
        defaults.removeObject(forKey: recordKey + game.bundleID)
    }
}

/// PatchRandomizer — chèn padding ngẫu nhiên vào cuối phần thân patch (trước trailer
/// license) để MD5 file cài đổi mỗi lần inject. IFix loader bỏ qua byte thừa sau cấu
/// trúc patch, nên padding không ảnh hưởng chức năng.
public enum PatchRandomizer {
    public static func pad(_ data: Data, range: ClosedRange<Int> = 16...48) -> Data {
        let count = Int.random(in: range)
        var out = data
        var rng = SystemRandomNumberGenerator()
        for _ in 0..<count {
            out.append(UInt8.random(in: 0...255, using: &rng))
        }
        return out
    }
}
