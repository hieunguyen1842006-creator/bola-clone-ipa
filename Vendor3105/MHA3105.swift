import Foundation

#if canImport(ObjectiveC) && canImport(UIKit)

/// Đường ghi container qua MHA (MobileHouseArrest identity) — port từ 3105.
///
/// Không cần kernel read/write: containermanagerd trả sandbox token cho container
/// của app khác khi tiến trình mang đúng bundle id `com.apple.mobile.MobileHouseArrest`.
/// `MCMActivateContainerPath(2, …)` vừa trả path vừa consume token, sau đó FileManager
/// đọc/ghi được bình thường.
///
/// Điều kiện: app phải được ký bằng cert cho phép bundle id đó (enterprise/wildcard).
final class MHA3105ContainerAccess: ContainerAccess {

    let label = "3105 MHA (container token)"

    private let fm = FileManager.default
    private let lock = NSLock()
    private var resolved: [GameTarget: String] = [:]
    private var lastDetail: String = ""
    private var reportedFailures = Set<GameTarget>()

    /// Log lần dò gần nhất (coordinator hiển thị khi fail).
    var detail: String { lock.lock(); defer { lock.unlock() }; return lastDetail }

    /// Báo lỗi đúng 1 lần cho mỗi game để log không bị spam.
    private func reportFailure(_ game: GameTarget) {
        lock.lock()
        let first = reportedFailures.insert(game).inserted
        let text = lastDetail
        lock.unlock()
        if first { Logger.shared.log("mha: \(text)") }
    }

    private func containerRoot(for game: GameTarget) -> String? {
        lock.lock(); defer { lock.unlock() }

        if let cached = resolved[game], fm.fileExists(atPath: cached) {
            return cached
        }

        var error: NSString?
        guard let raw = MCMActivateContainerPath(2, game.bundleID, false, &error) else {
            lastDetail = (error as String?) ?? "MCMActivateContainerPath trả nil"
            return nil
        }

        let root = (raw as NSString).standardizingPath
        guard root.hasPrefix("/private/var/mobile/Containers/Data/Application/")
                || root.hasPrefix("/var/mobile/Containers/Data/Application/") else {
            lastDetail = "path lạ: \(root)"
            return nil
        }

        lastDetail = root
        resolved[game] = root
        return root
    }

    private func documents(for game: GameTarget) -> String? {
        containerRoot(for: game).map { ($0 as NSString).appendingPathComponent("Documents") }
    }

    func isAvailable(for game: GameTarget) -> Bool {
        guard let docs = documents(for: game) else {
            reportFailure(game)
            return false
        }
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: docs, isDirectory: &isDir), isDir.boolValue else {
            lastDetail = "không thấy Documents: \(docs)"
            reportFailure(game)
            return false
        }
        // kiểm chứng quyền thật: tạo-rồi-xoá 1 file nhỏ
        let probe = (docs as NSString).appendingPathComponent(".bola_probe")
        do {
            try Data([0x01]).write(to: URL(fileURLWithPath: probe))
            try? fm.removeItem(atPath: probe)
            return true
        } catch {
            lastDetail = "không ghi được: \(error.localizedDescription)"
            reportFailure(game)
            return false
        }
    }

    func documentsPath(for game: GameTarget) -> String? { documents(for: game) }

    func write(_ data: Data, to name: String, in game: GameTarget) throws {
        guard let docs = documents(for: game) else {
            throw ContainerAccessError.containerNotFound(game)
        }
        let url = URL(fileURLWithPath: (docs as NSString).appendingPathComponent(name))
        do { try data.write(to: url, options: .atomic) }
        catch { throw ContainerAccessError.ioFailure(name, underlying: error) }
    }

    func read(_ name: String, in game: GameTarget) throws -> Data? {
        guard let docs = documents(for: game) else {
            throw ContainerAccessError.containerNotFound(game)
        }
        return fm.contents(atPath: (docs as NSString).appendingPathComponent(name))
    }

    func remove(_ name: String, in game: GameTarget) throws {
        guard let docs = documents(for: game) else { return }
        try? fm.removeItem(atPath: (docs as NSString).appendingPathComponent(name))
    }
}

#endif
