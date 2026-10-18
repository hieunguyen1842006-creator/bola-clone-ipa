import Foundation

// MARK: - Phase (AppModel.Phase — 4 case đúng như binary: idle/running/active/failed)

public enum Phase: String, Equatable {
    case idle
    case running
    case active
    case failed

    public var vi: String {
        switch self {
        case .idle: return "Sẵn sàng — bấm INJECT"
        case .running: return "Đang chạy…"
        case .active: return "Đã cài đặt"
        case .failed: return "Có lỗi — thử lại nhé"
        }
    }

    public var dotColor: DotTone {
        switch self {
        case .idle: return .idle
        case .running: return .busy
        case .active: return .ok
        case .failed: return .bad
        }
    }
}

public enum DotTone { case idle, ok, bad, busy }

// MARK: - FeatureTab (esp / aim / misc — đúng thứ tự trong __swift5_reflstr)

public enum FeatureTab: String, CaseIterable, Identifiable {
    case esp, aim, misc

    public var id: String { rawValue }

    public var vi: String {
        switch self {
        case .esp: return "ESP"
        case .aim: return "AIM"
        case .misc: return "KHÁC"
        }
    }

    public var symbol: String {
        switch self {
        case .esp: return "eye"
        case .aim: return "scope"
        case .misc: return "wrench.and.screwdriver"
        }
    }
}

// MARK: - GameTarget (freefireTH / freefireMAX / lienquan)

public enum GameTarget: String, CaseIterable, Identifiable {
    case freefireTH
    case freefireMAX
    case lienquan

    public var id: String { rawValue }

    /// Bundle chính + biến thể. LQ iOS có cả `kgvn` và `kgvnbig`.
    public var bundleIDs: [String] {
        switch self {
        case .freefireTH: return ["com.dts.freefireth"]
        case .freefireMAX: return ["com.dts.freefiremax"]
        case .lienquan: return ["com.garena.game.kgvn", "com.garena.game.kgvnbig"]
        }
    }

    public var bundleID: String { bundleIDs[0] }

    public var scheme: String {
        switch self {
        case .freefireTH: return "freefire"
        case .freefireMAX: return "freefiremax"
        case .lienquan: return "lienquan"
        }
    }

    public var name: String {
        switch self {
        case .freefireTH: return "Free Fire"
        case .freefireMAX: return "Free Fire MAX"
        case .lienquan: return "Liên Quân Mobile"
        }
    }

    /// Icon hiển thị trong danh sách game.
    public var symbol: String {
        switch self {
        case .freefireTH: return "flame"
        case .freefireMAX: return "flame.fill"
        case .lienquan: return "shield.lefthalf.filled"
        }
    }

    /// LQ dùng hotfix payload (`HeroSkin_2.bytes`) thay vì IFix patch + cfg của FF.
    public var isLienQuan: Bool { self == .lienquan }

    /// Info.plist của bản gốc khai báo LSApplicationQueriesSchemes = [freefire];
    /// bản clone khai báo cả 3 scheme để dò được cả MAX.
    public static let querySchemes = ["freefire", "freefireth", "freefiremax"]
}

// MARK: - InstallOutcome (ok / message)

public struct InstallOutcome: Equatable {
    public var ok: Bool
    public var message: String

    public init(ok: Bool, message: String) {
        self.ok = ok
        self.message = message
    }

    public static func good(_ m: String) -> InstallOutcome { .init(ok: true, message: m) }
    public static func bad(_ m: String) -> InstallOutcome { .init(ok: false, message: m) }
}

// MARK: - DeviceInfo

public struct DeviceInfo: Equatable {
    public var model: String
    public var systemName: String
    public var systemVersion: String
    public var identifier: String

    public init(model: String, systemName: String, systemVersion: String, identifier: String) {
        self.model = model
        self.systemName = systemName
        self.systemVersion = systemVersion
        self.identifier = identifier
    }

    /// "iPhone17,3 · iOS 26.0"
    public var summary: String {
        "\(identifier) · \(systemName) \(systemVersion)"
    }
}

// MARK: - PatchFile (url / name / size / bundled — đúng field của PatchFile)

public struct PatchFile: Equatable {
    public var url: URL?
    public var name: String
    public var size: Int
    public var bundled: Bool

    public init(url: URL?, name: String, size: Int, bundled: Bool) {
        self.url = url
        self.name = name
        self.size = size
        self.bundled = bundled
    }

    public var sizeText: String {
        ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }
}

// MARK: - ServerConfig (Base URL + endpoint — gốc: ds.tphat.store)

public struct ServerConfig: Equatable {
    public var baseURL: URL
    public var activatePath: String
    public var checkPath: String
    public var secretPath: String
    public var patchPath: String
    public var downloadPath: String
    public var offlineMaxDays: Int
    public var packageToken: String
    public var telegramURL: URL?
    public var otaPatchURL: URL?

    public init(baseURL: URL,
                activatePath: String = "/api/client/activate",
                checkPath: String = "/api/client/check",
                secretPath: String = "/api/client/secret",
                patchPath: String = "/api/client/patch",
                downloadPath: String = "/download/latest",
                offlineMaxDays: Int = 3,
                packageToken: String = "",
                telegramURL: URL? = nil,
                otaPatchURL: URL? = nil) {
        self.baseURL = baseURL
        self.activatePath = activatePath
        self.checkPath = checkPath
        self.secretPath = secretPath
        self.patchPath = patchPath
        self.downloadPath = downloadPath
        self.offlineMaxDays = offlineMaxDays
        self.packageToken = packageToken
        self.telegramURL = telegramURL
        self.otaPatchURL = otaPatchURL
    }

    public func endpoint(_ path: String) -> URL {
        URL(string: path, relativeTo: baseURL)?.absoluteURL ?? baseURL
    }
}

// MARK: - AppBrand (NVHProduct / NVHTelegram trong Info.plist)

public struct AppBrand: Equatable {
    public var product: String
    public var displayName: String
    public var author: String
    public var telegram: URL?

    public init(product: String, displayName: String, author: String = "", telegram: URL?) {
        self.product = product
        self.displayName = displayName
        self.author = author
        self.telegram = telegram
    }

    public static func fromBundle(_ bundle: Bundle = .main) -> AppBrand {
        let info = bundle.infoDictionary ?? [:]
        let telegram = (info["NVHTelegram"] as? String).flatMap(URL.init(string:))
        return AppBrand(product: info["NVHProduct"] as? String ?? "NVH MOD",
                        displayName: info["CFBundleDisplayName"] as? String ?? "NVH MOD",
                        author: info["NVHAuthor"] as? String ?? "Nguyễn Việt Hiếu",
                        telegram: telegram)
    }
}

// MARK: - Version (Foundation-only — VersionGate trên Apple dùng lại)

public enum Version {
    /// So sánh "1.0.0" kiểu từng thành phần: -1 / 0 / 1
    public static func compare(_ a: String, _ b: String) -> Int {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x != y { return x < y ? -1 : 1 }
        }
        return 0
    }

    public static var appVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.0.0"
    }
}
