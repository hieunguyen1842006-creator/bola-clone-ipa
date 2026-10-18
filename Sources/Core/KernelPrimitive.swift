import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// ┌───────────────────────────────────────────────────────────────────────────────┐
/// │  KERNEL PRIMITIVE — chỗ cắm, KHÔNG phải bản thân exploit                       │
/// │                                                                               │
/// │  Bản gốc BolaMinhDuc đi vào container game bằng 2 tầng:                        │
/// │    1. `kexploit_opa334` — kernel read/write qua IOSurface (pe_v2 / PCB page)   │
/// │    2. sandbox escape "3105" — lấy sandbox extension token của container app    │
/// │       khác rồi `sandbox_extension_consume` để ghi/xoá file trong đó            │
/// │                                                                               │
/// │  Mình KHÔNG viết lại 2 tầng đó — đây là primitive chiếm quyền tầng kernel      │
/// │  (không phải UI/logic nữa) và mình không kiểm chứng được nó ở đây.             │
/// │  Phần mình làm: đúng hợp đồng để cắm primitive, đúng thứ tự probe, đúng        │
/// │  state machine, đúng log — cộng test để chứng minh đường ống chạy đúng khi     │
/// │  có primitive.                                                                │
/// └───────────────────────────────────────────────────────────────────────────────┘

/// Kết quả tầng 2: quyền truy cập container của app khác.
public struct SandboxGrant: Equatable {
    /// Đường dẫn container (Documents của game) mà primitive đã mở được; nil = tự dò sau khi consume.
    public var containerDocuments: String?
    /// Sandbox extension token (opaque bytes) nếu primitive lấy được; rỗng = primitive tự mở đường.
    public var token: Data

    public init(containerDocuments: String?, token: Data = Data()) {
        self.containerDocuments = containerDocuments
        self.token = token
    }

    /// Hợp lệ khi có ít nhất một trong hai: đường dẫn trực tiếp, hoặc token để consume.
    public var isUsable: Bool {
        (containerDocuments?.isEmpty == false) || !token.isEmpty
    }

    /// Consume token qua libSystem (API công khai: `sandbox_extension_consume`).
    /// Token PHẢI đến từ nguồn hợp lệ (entitlement của bạn, hoặc primitive của bạn tự
    /// chịu trách nhiệm) — hàm này chỉ tiêu thụ kết quả, không tạo quyền.
    @discardableResult
    public func consume() -> Bool {
        guard !token.isEmpty else { return true }
        #if canImport(Darwin)
        typealias ConsumeFn = @convention(c) (UnsafePointer<CChar>) -> Int64
        guard let handle = dlopen("/usr/lib/system/libsystem_sandbox.dylib", RTLD_NOW),
              let sym = dlsym(handle, "sandbox_extension_consume")
        else { return false }
        let fn = unsafeBitCast(sym, to: ConsumeFn.self)
        let ok = token.withUnsafeBytes { buf -> Bool in
            guard let base = buf.bindMemory(to: CChar.self).baseAddress else { return false }
            return fn(base) >= 0
        }
        dlclose(handle)
        return ok
        #else
        return false
        #endif
    }
}

/// Hợp đồng cho một primitive (do bạn cung cấp).
///
/// Điều kiện tối thiểu để CẢ app còn lại chạy đúng: sau `prepareContainer(for:)`,
/// hoặc `grant.containerDocuments` phải là đường dẫn THẬT SỰ ghi được,
/// hoặc `grant.token` phải consume được và mở khoá đường dẫn đó.
public protocol KernelPrimitive: AnyObject {
    /// Tên hiển thị trong log (vd "kexploit_opa334" / "jailbreak-platform" / "dev-mock")
    var label: String { get }
    /// Tầng 1 — dựng read/write kernel. Ném lỗi nếu không sẵn sàng.
    func prepareKernelRW() throws
    /// Tầng 2 — mở đường tới container của game.
    /// Trả `SandboxGrant`: hoặc có `containerDocuments` (đường dẫn ghi được → app dùng
    /// `PathContainerAccess`), hoặc chỉ có `token` (→ app dùng API ghi bên dưới).
    func prepareContainer(for game: GameTarget) throws -> SandboxGrant

    // -- API ghi, CHỈ cần khi `prepareContainer` không trả về đường dẫn --------------

    /// Ghi 1 file vào Documents của game (mặc định: không hỗ trợ).
    func writeFile(_ data: Data, to name: String, in game: GameTarget) throws
    /// Đọc lại 1 file để XÁC MINH sau khi ghi (mặc định: nil = primitive không đọc được).
    func readFile(_ name: String, in game: GameTarget) throws -> Data?
    /// Xoá 1 file (gỡ patch).
    func removeFile(_ name: String, in game: GameTarget) throws

    /// Thu hồi (giải phóng object kernel, drop token…) — gọi khi huỷ/gỡ patch.
    func teardown()
}

public extension KernelPrimitive {
    func teardown() {}
    func writeFile(_ data: Data, to name: String, in game: GameTarget) throws {
        throw PrimitiveError.writeUnsupported
    }
    func readFile(_ name: String, in game: GameTarget) throws -> Data? { nil }
    func removeFile(_ name: String, in game: GameTarget) throws {
        throw PrimitiveError.writeUnsupported
    }
}

public enum PrimitiveError: Error, CustomStringConvertible {
    case notPlugged
    case kernelStageUnsupported
    case kernelStageFailed(String)
    case sandboxStageFailed(String)
    case deviceUnsupported(String)
    case grantUnusable
    case writeUnsupported
    case writeVerifyFailed(String)

    public var description: String {
        switch self {
        case .notPlugged: return "chưa cắm primitive"
        case .kernelStageUnsupported: return "primitive không hỗ trợ tầng kernel"
        case .kernelStageFailed(let m): return "kernel r/w thất bại: \(m)"
        case .sandboxStageFailed(let m): return "sandbox escape thất bại: \(m)"
        case .deviceUnsupported(let m): return "thiết bị không hỗ trợ: \(m)"
        case .grantUnusable: return "primitive trả về grant không dùng được (thiếu path và token)"
        case .writeUnsupported:
            return "primitive không cung cấp API ghi file — hãy trả containerDocuments trong SandboxGrant"
        case .writeVerifyFailed(let n): return "ghi xong nhưng đọc lại không khớp: \(n)"
        }
    }
}

// MARK: - Mock primitive (CHỈ để test đường ống — không phải exploit)

/// Primitive giả: "escape" bằng cách trỏ vào container thật do bạn truyền vào.
/// Dùng để chạy full pipeline trong self-test / trên simulator / trên máy đã jailbreak
/// khi bạn muốn kiểm tra logic trước khi cắm primitive thật.
public final class MockContainerPrimitive: KernelPrimitive {
    public let label: String
    public private(set) var kernelPrepared = false
    public private(set) var containerPrepared = [GameTarget]()
    public private(set) var tornDown = false

    private let documentsRoot: String
    private let failKernel: Bool
    private let delay: TimeInterval

    public init(label: String = "dev-mock",
                documentsRoot: String,
                failKernel: Bool = false,
                delay: TimeInterval = 0) {
        self.label = label
        self.documentsRoot = documentsRoot
        self.failKernel = failKernel
        self.delay = delay
    }

    public func prepareKernelRW() throws {
        if delay > 0 { Thread.sleep(forTimeInterval: delay) }
        if failKernel { throw PrimitiveError.kernelStageFailed("mock: kernel stage bị tắt") }
        kernelPrepared = true
    }

    public func prepareContainer(for game: GameTarget) throws -> SandboxGrant {
        let path = "\(documentsRoot)/\(game.bundleID)/Documents"
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        containerPrepared.append(game)
        return SandboxGrant(containerDocuments: path)
    }

    public func teardown() { tornDown = true }

    // Mock ghi thật trên đường dẫn đã cấp (để self-test kiểm chứng được toàn bộ đường ống)
    private func path(_ name: String, _ game: GameTarget) -> String {
        "\(documentsRoot)/\(game.bundleID)/Documents/\(name)"
    }

    public func writeFile(_ data: Data, to name: String, in game: GameTarget) throws {
        try data.write(to: URL(fileURLWithPath: path(name, game)), options: .atomic)
    }

    public func readFile(_ name: String, in game: GameTarget) throws -> Data? {
        FileManager.default.contents(atPath: path(name, game))
    }

    public func removeFile(_ name: String, in game: GameTarget) throws {
        try? FileManager.default.removeItem(atPath: path(name, game))
    }
}
