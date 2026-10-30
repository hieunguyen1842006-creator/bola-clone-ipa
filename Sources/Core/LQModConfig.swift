import Foundation

/// Cấu hình Full Mod AOV cho Liên Quân — ghi vào **PlayerPrefs của game**
/// (`<container>/Library/Preferences/<bundleID>.plist`).
///
/// Payload AOV (LQFull: HeroSkin_1 + HeroSkin_2) đọc các key `iFix.*` này lúc chạy:
///   iFix.ESP.Enabled.v1           Int    0/1
///   iFix.AutoBP.Enabled.v1        Int    0/1
///   iFix.AIM.Enabled.v1           Int    0/1
///   iFix.AIM.TargetMode.v1        Int    0=hp 1=percent 2=near 3=ray
///   iFix.AIM.Lines.v1             Int    1..5
///   iFix.AIM.DrawMode.v1          Int    0=off 1=always 2=skill
///   iFix.AutoSmite.Enabled.v1     Int    0/1
///   iFix.AutoSmite.TargetMode.v1  Int    0=boss 1=buff 2=all
///   iFix.Camera.Zoom.v1           Float  1.0..5.0
///   iFix.SelectedSkin.v1.<heroId> Int    0..99
///
/// LƯU Ý: game đọc prefs qua cfprefsd — phải TẮT HẲN GAME trước khi đổi cấu
/// hình, mở lại game để nhận giá trị mới.
public enum LQModConfig {

    public static let espKey = "iFix.ESP.Enabled.v1"
    public static let bocphaKey = "iFix.AutoBP.Enabled.v1"
    public static let aimKey = "iFix.AIM.Enabled.v1"
    public static let aimTargetKey = "iFix.AIM.TargetMode.v1"
    public static let aimLinesKey = "iFix.AIM.Lines.v1"
    public static let aimDrawKey = "iFix.AIM.DrawMode.v1"
    public static let smiteKey = "iFix.AutoSmite.Enabled.v1"
    public static let smiteTargetKey = "iFix.AutoSmite.TargetMode.v1"
    public static let zoomKey = "iFix.Camera.Zoom.v1"
    public static func skinKey(hero: Int) -> String { "iFix.SelectedSkin.v1.\(hero)" }

    /// Plist prefs nằm ở `<container>/Library/Preferences/<bundle>.plist`.
    /// ContainerAccess anchored ở Documents nên đi ".." ra container root.
    /// Biến thể thật (kgvn / kgvnbig) đọc từ metadata của container.
    static func prefsPath(access: ContainerAccess, game: GameTarget) -> String {
        if let raw = (try? access.read(
            relativePath: "../.com.apple.mobile_container_manager.metadata.plist",
            in: game)) ?? nil,
           let plist = (try? PropertyListSerialization.propertyList(
            from: raw, options: [], format: nil)) as? [String: Any],
           let ident = plist["MCMMetadataIdentifier"] as? String {
            return "../Library/Preferences/\(ident).plist"
        }
        return "../Library/Preferences/\(game.bundleID).plist"
    }

    /// Đọc toàn bộ dict prefs (nil nếu chưa có file / chưa mở được container).
    public static func load(access: ContainerAccess, game: GameTarget) -> [String: Any]? {
        guard let raw = (try? access.read(
            relativePath: prefsPath(access: access, game: game), in: game)) ?? nil,
              !raw.isEmpty else { return nil }
        return (try? PropertyListSerialization.propertyList(
            from: raw, options: [], format: nil)) as? [String: Any]
    }

    public static func int(_ dict: [String: Any]?, _ key: String, _ def: Int) -> Int {
        (dict?[key] as? NSNumber)?.intValue ?? def
    }

    public static func float(_ dict: [String: Any]?, _ key: String, _ def: Float) -> Float {
        (dict?[key] as? NSNumber)?.floatValue ?? def
    }

    /// Ghi nhóm key vào plist prefs của game. Trả true nếu ghi file thành công.
    @discardableResult
    public static func apply(_ values: [String: Any],
                             access: ContainerAccess, game: GameTarget) -> Bool {
        var dict = load(access: access, game: game) ?? [:]
        for (k, v) in values { dict[k] = v }
        guard let data = try? PropertyListSerialization.data(
            fromPropertyList: dict, format: .binary, options: 0) else { return false }
        do {
            try access.write(data, toRelative: prefsPath(access: access, game: game),
                             in: game)
            return true
        } catch {
            return false
        }
    }

    // MARK: kênh LIVE — Documents/nvh_aov.txt

    /// Patch trong game (hook get_frameSynchr) đọc file này mỗi giây và áp vào
    /// PlayerPrefs của chính nó — hoạt động cả khi game ĐANG CHẠY (file thường
    /// không bị cache như cfprefsd). Format khớp parser trong MenuPatch.cs.
    public static let liveFileName = "nvh_aov.txt"

    @discardableResult
    public static func writeLive(_ text: String,
                                 access: ContainerAccess, game: GameTarget) -> Bool {
        do {
            try access.write(Data(text.utf8), to: liveFileName, in: game)
            return true
        } catch {
            return false
        }
    }
}
