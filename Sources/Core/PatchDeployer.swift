import Foundation

/// PatchDeployer — ghi patch + config + token vào container game, đúng thứ tự và đúng
/// tên file của bản gốc:
///
///   1. Assembly-CSharp-patch.bytes   ← patch IFix (bundle / server / OTA)
///   2. bolacfg.bin                   ← config menu (BolaConfig.encode)
///   3. .bola_tok                     ← token key (do backend cấp — xem README)
///   4. patch_verify.dat + verify_cache.dat
///
/// Gỡ patch = xoá 1..4 (bản gốc: "Anti-ban off → patch removed").
public final class PatchDeployer {

    public enum Step: String {
        case patch = "Assembly-CSharp-patch.bytes"
        case config = "bolacfg.bin"
        case token = ".bola_tok"
        case verify = "patch_verify.dat"
    }

    private let access: ContainerAccess
    private let library: PatchLibrary
    public var onLog: ((String) -> Void)?

    public init(access: ContainerAccess, library: PatchLibrary) {
        self.access = access
        self.library = library
    }

    /// Ghi đủ bộ. Trả về InstallOutcome để UI quyết định phase.
    ///
    /// Patch được gắn trailer 64 byte (`PatchTrailer`) trước khi ghi — thiếu trailer thì
    /// menu trong game rơi vào nhánh "⚠ CHƯA KÍCH HOẠT". `.bola_tok` phải ghi TRƯỚC để
    /// trailer băm đúng nội dung file sẽ có trên đĩa.
    public func install(patchData: Data,
                        config: BolaConfig,
                        token: BolaToken?,
                        game: GameTarget) -> InstallOutcome {
        guard access.isAvailable(for: game) else {
            return .bad("Không tìm thấy thư mục game.\nKhông ghi được — mở game 1 lần "
                        + "(để tạo container) rồi thử lại")
        }

        // 0. token (phải có trước khi ký trailer)
        var license: String?
        var tokenWritten = false
        if let token {
            license = token.encodedString()
            do {
                try access.write(Data(token.encoded()), to: ".bola_tok", in: game)
                tokenWritten = true
                onLog?("token: đã ghi .bola_tok (hết hạn \(token.expiryUnix))")
            } catch {
                license = nil
                onLog?("token: không ghi được .bola_tok — bỏ qua trailer")
            }
        } else {
            license = nil
            onLog?("token: chưa có lease — patch sẽ hiện '⚠ CHƯA KÍCH HOẠT' trong game")
        }

        // 1. patch (+ trailer nếu có license)
        let finalPatch: Data
        if let license, tokenWritten {
            do {
                finalPatch = try PatchTrailer.attach(to: patchData,
                                                     license: license,
                                                     expiryUnix: token?.expiryUnix ?? 0)
                onLog?("patch: đã gắn trailer |BOLATK1| (\(patchData.count) → \(finalPatch.count) B)")
            } catch {
                onLog?("patch: không gắn được trailer (\(error)) — ghi nguyên bản")
                finalPatch = patchData
            }
        } else {
            finalPatch = patchData
        }

        do {
            try access.write(finalPatch, to: PatchLibrary.patchFileName, in: game)
            onLog?("inject: kernel sẵn sàng → cài \(PatchLibrary.patchFileName) (\(finalPatch.count) B)")
        } catch {
            return .bad("Lỗi ghi file: \(PatchLibrary.patchFileName)")
        }

        // 2. config
        do {
            try access.write(Data(config.encoded()), to: "bolacfg.bin", in: game)
            onLog?("cfg: đã ghi bolacfg.bin (\(BolaConfig.size) B, CRC ok)")
        } catch {
            onLog?("cfg: không ghi được bolacfg.bin")
        }

        // 4. dấu xác nhận
        library.writeVerifyMarkers(patchSHA: SHA256.hex([UInt8](finalPatch)), into: access, game: game)

        return .good("Đã cài xong cho \(game.name)")
    }

    /// Gỡ patch (đúng danh sách file bản gốc xoá).
    @discardableResult
    public func uninstall(game: GameTarget) -> Int {
        var n = 0
        for f in [PatchLibrary.patchFileName, "bolacfg.bin", ".bola_tok",
                  "patch_verify.dat", "verify_cache.dat"] {
            if (try? access.read(f, in: game)) ?? nil != nil {
                try? access.remove(f, in: game)
                n += 1
            }
        }
        onLog?("patch removed (\(n) file) — Anti-ban off → patch removed (\(n))")
        return n
    }

    public func isInstalled(game: GameTarget) -> Bool {
        ((try? access.read(PatchLibrary.patchFileName, in: game)) ?? nil) != nil
    }

    /// Alias đúng tên bản gốc `Installer.patchExists(for:)`.
    public func patchExists(for game: GameTarget) -> Bool {
        isInstalled(game: game)
    }

    /// Info ngắn của patch đang cài (bản gốc: `Installer.installedPatchInfo(for:)`).
    /// Trả nil nếu chưa cài; chuỗi mô tả trailer nếu có.
    public func installedPatchInfo(for game: GameTarget) -> String? {
        guard let data = (try? access.read(PatchLibrary.patchFileName, in: game)) ?? nil else {
            return nil
        }
        if let trailer = PatchTrailer.decode(from: data) {
            return "\(data.count) B · trailer exp=\(trailer.expiryUnix) · sig=\(trailer.bodySig)"
        }
        return "\(data.count) B · không có trailer (chưa kích hoạt)"
    }

    /// Bản gốc: `Installer.resyncTokenIfNeeded(for:)` — key/token đổi hoặc trailer hết hạn
    /// thì cập nhật lại `.bola_tok` + trailer mà không cần bơm lại cả patch từ server.
    @discardableResult
    public func resyncTokenIfNeeded(for game: GameTarget, token: BolaToken,
                                    now: Date = Date()) -> Bool {
        guard let current = (try? access.read(PatchLibrary.patchFileName, in: game)) ?? nil,
              !current.isEmpty
        else { return false }

        let license = token.encodedString()
        if PatchTrailer.isValid(patch: current, license: license, now: now) {
            // trailer còn hạn và khớp key hiện tại → chỉ cần đồng bộ .bola_tok
            try? access.write(Data(token.encoded()), to: ".bola_tok", in: game)
            return false
        }

        let body = PatchTrailer.strip(from: current)
        guard let resigned = try? PatchTrailer.attach(to: body, license: license,
                                                      expiryUnix: token.expiryUnix) else {
            return false
        }
        try? access.write(Data(token.encoded()), to: ".bola_tok", in: game)
        try? access.write(resigned, to: PatchLibrary.patchFileName, in: game)
        onLog?("token: resync → đã ký lại trailer \(resigned.count) B")
        return true
    }

    /// "reset guest": đặt cờ localConfig.json {"testCodePatch":true,"resetGuest":true} vào container
    /// (đúng payload bản gốc dùng để buộc game tạo guest mới).
    public func setResetGuestFlag(game: GameTarget) throws {
        let payload = #"{"testCodePatch":true,"resetGuest":true}"#
        try access.write(Data(payload.utf8), to: "localConfig.json", in: game)
        onLog?("reset guest: đã đặt cờ localConfig.json vào \(game.name)")
    }
}

// MARK: - Installer (orchestrate: dò game → cfg → patch → token → mở game)

@MainActor
public final class Installer {

    private let library: PatchLibrary
    private let access: ContainerAccess
    public let deployer: PatchDeployer
    public var onLog: ((String) -> Void)?
    public var onProgress: ((Phase) -> Void)?

    public init(access: ContainerAccess, library: PatchLibrary) {
        self.library = library
        self.access = access
        self.deployer = PatchDeployer(access: access, library: library)
        self.deployer.onLog = { [weak self] in self?.onLog?($0) }
    }

    // MARK: - API tương thích bản gốc (Installer.*)

    /// `Installer.containerPath(for:)` — Documents của game, nil nếu chưa thấy container.
    public func containerPath(for game: GameTarget) -> String? {
        access.documentsPath(for: game)
    }

    /// `Installer.hasAccess(to:)` — có quyền ghi container chưa.
    public func hasAccess(to game: GameTarget) -> Bool {
        access.isAvailable(for: game)
    }

    /// `Installer.canWriteIntoGame` — alias rõ nghĩa của `hasAccess`.
    public func canWriteIntoGame(_ game: GameTarget) -> Bool {
        access.isAvailable(for: game)
    }

    /// `Installer.patchExists(for:)` — patch đã nằm trong container chưa.
    public func patchExists(for game: GameTarget) -> Bool {
        deployer.isInstalled(game: game)
    }

    /// `Installer.installedPatchInfo(for:)` — mô tả patch đang cài.
    public func installedPatchInfo(for game: GameTarget) -> String? {
        deployer.installedPatchInfo(for: game)
    }

    /// `Installer.resyncTokenIfNeeded(for:)` — ký lại trailer khi token đổi/hết hạn.
    @discardableResult
    public func resyncTokenIfNeeded(for game: GameTarget) -> Bool {
        guard let lease = currentLease else { return false }
        let token = BolaToken(key: lease.key, expiryUnix: lease.expiryUnix, sig: lease.sig)
        return deployer.resyncTokenIfNeeded(for: game, token: token)
    }

    /// Lease hiện tại do AppModel gắn vào trước mỗi lần inject (nil = chưa có key).
    public var currentLease: Lease?

    /// `Installer.restore(game:)` — gỡ toàn bộ dấu vết đã cài, trả outcome cho UI.
    public func restore(game: GameTarget) -> InstallOutcome {
        let n = deployer.uninstall(game: game)
        onLog?("restore: đã gỡ \(n) file khỏi \(game.name)")
        return .good(n > 0 ? "Đã gỡ xong. Mở lại game để áp dụng nhé."
                           : "Chưa có gì để gỡ.")
    }

    /// Gỡ patch (AppModel.removePatch / cancel).
    @discardableResult
    public func deployerUninstall(game: GameTarget) -> Int {
        deployer.uninstall(game: game)
    }

    /// "reset guest" — đặt cờ localConfig.json.
    public func deployerSetResetGuest(game: GameTarget) throws {
        try deployer.setResetGuestFlag(game: game)
    }

    public func isInstalled(game: GameTarget) -> Bool {
        deployer.isInstalled(game: game)
    }

    public struct Request {
        public var game: GameTarget
        public var config: BolaConfig
        public var lease: Lease?
        public init(game: GameTarget, config: BolaConfig, lease: Lease?) {
            self.game = game
            self.config = config
            self.lease = lease
        }
    }

    /// Chạy toàn bộ quy trình. Trả về outcome để HomeView hiện toast.
    public func run(_ req: Request, bundle: Bundle = .main) async -> InstallOutcome {
        onProgress?(.running)
        onLog?("Đang chuẩn bị…")
        currentLease = req.lease
        onLog?("container: \(containerPath(for: req.game) ?? "không thấy path (primitive tự ghi)")")

        let (data, file) = await library.fetchPatch(key: req.lease?.key, bundle: bundle)
        guard !data.isEmpty else {
            onProgress?(.failed)
            return .bad("Patch chưa sẵn sàng — kiểm tra mạng + key rồi mở lại app.")
        }
        onLog?("patch: \(file.name) • \(file.sizeText)\(file.bundled ? " (bundled)" : "")")

        let token: BolaToken?
        if let lease = req.lease, lease.expiryUnix > 0 {
            token = BolaToken(key: lease.key, expiryUnix: lease.expiryUnix, sig: lease.sig)
        } else {
            token = nil
        }

        let outcome = deployer.install(patchData: data, config: req.config,
                                       token: token, game: req.game)
        onProgress?(outcome.ok ? .active : .failed)
        return outcome
    }
}
