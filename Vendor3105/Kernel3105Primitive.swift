import Foundation

#if canImport(ObjectiveC) && canImport(UIKit)

/// Primitive 2 tầng port từ 3105:
///   1. `kexploit_opa334()` — kernel read/write qua IOSurface race (pe_v1/pe_v2).
///   2. `sandbox_escape(proc_self())` — patch ucred/cr_label/ext_set để thoát sandbox.
///
/// Sau tầng 2, container của app khác đọc/ghi được bằng đường dẫn thường
/// (`DirectContainerAccess`), nên primitive chỉ cần trả `SandboxGrant` chứa path.
///
/// Lưu ý: `offsets_init()` trong bản public chỉ nhận iOS 17.0 – 26.0.x; trên build
/// mới hơn nó abort an toàn (longjmp) và primitive ném lỗi thay vì crash app.
final class Kernel3105Primitive: KernelPrimitive {

    let label = "kexploit_opa334/3105"

    private var kernelReady = false
    private var escaped = false

    func prepareKernelRW() throws {
        guard !kernelReady else { return }

        let ret = kexploit_opa334()
        guard ret == 0 else {
            throw PrimitiveError.kernelStageFailed("kexploit_opa334 -> \(ret)")
        }
        kernelReady = true
    }

    func prepareContainer(for game: GameTarget) throws -> SandboxGrant {
        guard kernelReady else {
            throw PrimitiveError.kernelStageFailed("chưa có kernel r/w")
        }
        if !escaped {
            let proc = proc_self()
            guard proc != 0 else {
                throw PrimitiveError.sandboxStageFailed("proc_self() == 0")
            }
            let ret = sandbox_escape(proc)
            guard ret == 0, sandbox_access_is_active() == 1 else {
                throw PrimitiveError.sandboxStageFailed("sandbox_escape -> \(ret)")
            }
            escaped = true
        }

        let direct = DirectContainerAccess()
        guard let docs = direct.documentsPath(for: game), direct.isAvailable(for: game) else {
            throw PrimitiveError.sandboxStageFailed(
                "đã thoát sandbox nhưng không thấy container \(game.bundleID)")
        }
        return SandboxGrant(containerDocuments: docs)
    }

    func teardown() {
        // Không hoàn tác patch kernel — chỉ hạ cờ để lần sau không chạy lại.
        kernelReady = false
    }
}

#endif
