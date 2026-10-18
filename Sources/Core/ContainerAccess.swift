import Foundation

/// Nơi ghi patch/config/token vào container của game.
///
/// ┌───────────────────────────────────────────────────────────────────────────┐
/// │ RANH GIỚI CỦA BẢN CLONE NÀY                                               │
/// │                                                                           │
/// │ Bản gốc (BolaMinhDuc) đi vào container của Free Fire bằng 2 tầng:         │
/// │   1. `kexploit_opa334` — kernel read/write qua IOSurface (pe_v2 / PCB)     │
/// │   2. sandbox escape "3105" — `container_copy_sandbox_token` để lấy        │
/// │      extension token của container app khác                                │
/// │                                                                           │
/// │ Mình KHÔNG viết lại 2 tầng đó. Đó là primitive chiếm quyền ở tầng kernel   │
/// │ — không phải "UI/logic copy" nữa mà là vũ khí post-exploitation.           │
/// │                                                                           │
/// │ Bản clone giữ ĐÚNG chỗ cắm (`ContainerAccess`) và cung cấp các đường      │
/// │ hợp pháp: máy đã jailbreak, app group, file sharing, hoặc chính app gốc    │
/// │ cấp token qua URL scheme. Muốn cắm primitive khác thì implement protocol.  │
/// └───────────────────────────────────────────────────────────────────────────┘
public protocol ContainerAccess {
    /// Tên hiển thị trong log (UI hiện "exploit: …" của bản gốc).
    var label: String { get }
    /// Có dùng được ngay không (kiểm tra trước khi INJECT).
    func isAvailable(for game: GameTarget) -> Bool
    /// Ghi 1 file vào thư mục Documents của game.
    func write(_ data: Data, to name: String, in game: GameTarget) throws
    /// Đọc file (nil nếu không tồn tại).
    func read(_ name: String, in game: GameTarget) throws -> Data?
    /// Xoá file (gỡ patch).
    func remove(_ name: String, in game: GameTarget) throws
    /// Dọn cache phía đường ghi (mặc định: không có gì để dọn).
    func clearCaches()
    /// Đường dẫn Documents của game nếu đường ghi này biết (mặc định: nil).
    func documentsPath(for game: GameTarget) -> String?
}

public extension ContainerAccess {
    func clearCaches() {}
    func documentsPath(for game: GameTarget) -> String? { nil }

    // MARK: đường dẫn tương đối (LQ: Resources/<ver>/Thanos/HeroSkin_2.bytes)

    /// Ghi vào thư mục con của Documents. Đường không lộ path thì ném lỗi.
    func write(_ data: Data, toRelative path: String, in game: GameTarget) throws {
        if !path.contains("/") { try write(data, to: path, in: game); return }
        guard let docs = documentsPath(for: game) else {
            throw ContainerAccessError.notWritable("đường ghi này không hỗ trợ thư mục con")
        }
        let fm = FileManager.default
        let url = URL(fileURLWithPath: docs).appendingPathComponent(path)
        do {
            try fm.createDirectory(at: url.deletingLastPathComponent(),
                                   withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        } catch {
            throw ContainerAccessError.ioFailure(path, underlying: error)
        }
    }

    func read(relativePath path: String, in game: GameTarget) throws -> Data? {
        if !path.contains("/") { return try read(path, in: game) }
        guard let docs = documentsPath(for: game) else { return nil }
        return FileManager.default.contents(
            atPath: URL(fileURLWithPath: docs).appendingPathComponent(path).path)
    }

    func remove(relativePath path: String, in game: GameTarget) throws {
        if !path.contains("/") { try remove(path, in: game); return }
        guard let docs = documentsPath(for: game) else { return }
        try? FileManager.default.removeItem(
            atPath: URL(fileURLWithPath: docs).appendingPathComponent(path).path)
    }

    /// Liệt kê tên file/thư mục con (rỗng nếu không đọc được).
    func list(_ relativePath: String, in game: GameTarget) throws -> [String] {
        guard let docs = documentsPath(for: game) else { return [] }
        let dir = relativePath.isEmpty
            ? URL(fileURLWithPath: docs)
            : URL(fileURLWithPath: docs).appendingPathComponent(relativePath)
        return (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
    }
}

public enum ContainerAccessError: Error, CustomStringConvertible {
    case containerNotFound(GameTarget)
    case notWritable(String)
    case ioFailure(String, underlying: Error?)

    public var description: String {
        switch self {
        case .containerNotFound(let g):
            return "Không tìm thấy thư mục game (\(g.bundleID)). Mở game 1 lần để tạo container rồi thử lại"
        case .notWritable(let p):
            return "Không ghi được — \(p)"
        case .ioFailure(let what, let e):
            return "Lỗi ghi file: \(what)" + (e.map { " (\($0.localizedDescription))" } ?? "")
        }
    }
}

/// Đường 1: máy jailbreak / có quyền đọc-ghi container (rootless: /var/mobile/Containers/…).
/// Đây là đường "tự nhiên" nhất — không cần exploit nào.
public final class DirectContainerAccess: ContainerAccess {
    public let label = "direct container (jailbreak / có quyền)"

    private let roots: [String]
    private let fm = FileManager.default

    public init(extraRoots: [String] = []) {
        self.roots = [
            "/var/mobile/Containers/Data/Application",
            "/private/var/mobile/Containers/Data/Application",
        ] + extraRoots
    }

    /// Tìm container của game bằng cách quét `.../Data/Application/*/.com.apple.mobile_container_manager.metadata.plist`
    /// và so `MCMMetadataIdentifier`. Trên máy có quyền thì đây là cách duy nhất cần dùng.
    public func containerURL(for game: GameTarget) -> URL? {
        for root in roots {
            guard let entries = try? fm.contentsOfDirectory(atPath: root) else { continue }
            for entry in entries {
                let dir = (root as NSString).appendingPathComponent(entry)
                let meta = (dir as NSString).appendingPathComponent(
                    ".com.apple.mobile_container_manager.metadata.plist")
                guard let data = fm.contents(atPath: meta),
                      let plist = try? PropertyListSerialization.propertyList(
                        from: data, options: [], format: nil) as? [String: Any],
                      let ident = plist["MCMMetadataIdentifier"] as? String,
                      game.bundleIDs.contains(ident)
                else { continue }
                return URL(fileURLWithPath: (dir as NSString).appendingPathComponent("Documents"))
            }
        }
        return nil
    }

    public func isAvailable(for game: GameTarget) -> Bool {
        containerURL(for: game) != nil
    }

    public func documentsPath(for game: GameTarget) -> String? {
        containerURL(for: game)?.path
    }

    public func write(_ data: Data, to name: String, in game: GameTarget) throws {
        guard let dir = containerURL(for: game) else { throw ContainerAccessError.containerNotFound(game) }
        let url = dir.appendingPathComponent(name)
        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        } catch {
            throw ContainerAccessError.ioFailure(name, underlying: error)
        }
    }

    public func read(_ name: String, in game: GameTarget) throws -> Data? {
        guard let dir = containerURL(for: game) else { throw ContainerAccessError.containerNotFound(game) }
        return fm.contents(atPath: dir.appendingPathComponent(name).path)
    }

    public func remove(_ name: String, in game: GameTarget) throws {
        guard let dir = containerURL(for: game) else { throw ContainerAccessError.containerNotFound(game) }
        try? fm.removeItem(at: dir.appendingPathComponent(name))
    }
}

/// Đường 2: app group dùng chung (nếu bản build có entitlement app-group với app game —
/// thực tế chỉ dùng khi tự build cả 2 phía, giữ đây làm mẫu).
#if canImport(Darwin)
public final class AppGroupContainerAccess: ContainerAccess {
    public let label: String
    private let groupID: String
    private let fm = FileManager.default

    public init(groupID: String) {
        self.groupID = groupID
        self.label = "app group \(groupID)"
    }

    public func isAvailable(for game: GameTarget) -> Bool {
        // containerURL chỉ nói group có tồn tại; phải thử GHI thật, vì path
        // group của app khác (hoặc group không có entitlement) sẽ không ghi được.
        guard let base = fm.containerURL(forSecurityApplicationGroupIdentifier: groupID) else {
            return false
        }
        let dir = base.appendingPathComponent("\(game.bundleID)/Documents", isDirectory: true)
        let probe = dir.appendingPathComponent(".nvh_probe")
        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            try Data([0x01]).write(to: probe)
            try? fm.removeItem(at: probe)
            return true
        } catch {
            return false
        }
    }

    private func dir(for game: GameTarget) throws -> URL {
        guard let base = fm.containerURL(forSecurityApplicationGroupIdentifier: groupID) else {
            throw ContainerAccessError.containerNotFound(game)
        }
        return base.appendingPathComponent("\(game.bundleID)/Documents", isDirectory: true)
    }

    public func documentsPath(for game: GameTarget) -> String? {
        (try? dir(for: game))?.path
    }

    public func write(_ data: Data, to name: String, in game: GameTarget) throws {
        let d = try dir(for: game)
        try fm.createDirectory(at: d, withIntermediateDirectories: true)
        try data.write(to: d.appendingPathComponent(name), options: .atomic)
    }

    public func read(_ name: String, in game: GameTarget) throws -> Data? {
        fm.contents(atPath: try dir(for: game).appendingPathComponent(name).path)
    }

    public func remove(_ name: String, in game: GameTarget) throws {
        try? fm.removeItem(at: try dir(for: game).appendingPathComponent(name))
    }
}
#endif

/// Đường 3: cắm primitive của bạn (ví dụ primitive public bạn tự tích hợp).
/// Protocol chỉ quan tâm "ghi được file vào container game hay không".
public final class PluggedContainerAccess: ContainerAccess {
    public typealias Writer = (Data, String, GameTarget) throws -> Void
    public typealias Reader = (String, GameTarget) throws -> Data?
    public typealias Remover = (String, GameTarget) throws -> Void
    public typealias Probe = (GameTarget) -> Bool

    public let label: String
    private let probe: Probe
    private let writer: Writer
    private let reader: Reader
    private let remover: Remover

    public init(label: String,
                probe: @escaping Probe,
                write: @escaping Writer,
                read: @escaping Reader,
                remove: @escaping Remover) {
        self.label = label
        self.probe = probe
        self.writer = write
        self.reader = read
        self.remover = remove
    }

    public func isAvailable(for game: GameTarget) -> Bool { probe(game) }
    public func write(_ data: Data, to name: String, in game: GameTarget) throws { try writer(data, name, game) }
    public func read(_ name: String, in game: GameTarget) throws -> Data? { try reader(name, game) }
    public func remove(_ name: String, in game: GameTarget) throws { try remover(name, game) }
}

/// Bộ chọn: thử lần lượt các đường có sẵn (giống thứ tự "mha → kernel → direct" của bản gốc,
/// chỉ khác là KHÔNG có tầng kernel).
public final class ContainerAccessChain: ContainerAccess {
    public let label = "container access chain"
    private let providers: [ContainerAccess]

    public init(_ providers: [ContainerAccess]) {
        self.providers = providers
    }

    private func pick(_ game: GameTarget) throws -> ContainerAccess {
        for p in providers where p.isAvailable(for: game) { return p }
        throw ContainerAccessError.containerNotFound(game)
    }

    public func isAvailable(for game: GameTarget) -> Bool {
        providers.contains { $0.isAvailable(for: game) }
    }

    public func documentsPath(for game: GameTarget) -> String? {
        active(for: game)?.documentsPath(for: game)
    }

    /// Đường nào đang dùng (để log giống bản gốc: "auto: đã truy cập được thư mục game → bỏ qua kernel").
    public func active(for game: GameTarget) -> ContainerAccess? {
        providers.first { $0.isAvailable(for: game) }
    }

    public func write(_ data: Data, to name: String, in game: GameTarget) throws {
        try pick(game).write(data, to: name, in: game)
    }

    public func read(_ name: String, in game: GameTarget) throws -> Data? {
        try pick(game).read(name, in: game)
    }

    public func remove(_ name: String, in game: GameTarget) throws {
        try pick(game).remove(name, in: game)
    }
}
