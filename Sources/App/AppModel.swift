import Foundation
import Combine
#if canImport(UIKit)
import UIKit
#endif

/// AppModel — trái tim của app, giữ ĐÚNG danh sách field như binary gốc:
///
///   @Published: _phase _statusText _game _installedInfo _patchInstalled _logText _busy
///               _restoring _toastText toastToken _cfgFlags _aimBone _silentFov _aimFov
///               _headRate _camFov _espThick _language _antiban _mhaActive _writeOK
///               _keyMaskedName _keyHoursLeft
///   nội bộ   : cancelRequested lastActionTime antibanTimer keyCardTimer settleWindow
///               didBootstrap kernelInFlight kernelDone kernelWaiters
///
/// (`kernelInFlight/Done/Waiters` giữ lại như trạng thái "primitive sẵn sàng chưa" —
///  xem ContainerAccess: clone không kèm kernel exploit, cờ này bật khi đường ghi container
///  hợp lệ đã sẵn sàng.)
@MainActor
public final class AppModel: ObservableObject {

    // MARK: trạng thái (đúng thứ tự __swift5_reflstr)

    @Published public var phase: Phase = .idle
    @Published public var statusText: String = "Đang chuẩn bị…"
    @Published public var game: GameTarget = .freefireMAX {
        didSet {
            guard game != oldValue else { return }
            if access.isAvailable(for: game) {
                patchInstalled = isPatchPresent()
                syncConfigFromDisk()
            } else {
                patchInstalled = Self.persistedInjected(for: game)
            }
        }
    }
    @Published public var installedInfo: [GameTarget: Bool] = [:]
    @Published public var patchInstalled: Bool = false
    @Published public var logText: String = ""
    @Published public var busy: Bool = false
    @Published public var restoring: Bool = false
    @Published public var toastText: String = ""
    @Published public var toastToken: Int = 0
    /// Key đúng như bản gốc. Mặc định: ESP bật, aim/silent/misc tắt.
    @Published public var cfgFlags: Set<String> = [
        "box", "line", "bone", "hp", "name", "dist", "bot", "count", "team", "autolaunch",
    ]
    @Published public var aimBone: BolaConfig.Bone = .head
    @Published public var silentFov: Double = 30       // 5...100 (%)
    @Published public var aimFov: Double = 30          // 5...100 (%)
    @Published public var headRate: Double = 100       // 10...100 (%)
    @Published public var camFov: Double = 88          // 50...130
    @Published public var espThick: Double = 100       // 50...200
    @Published public var language: Language = .vi
    @Published public var antiban: Bool = false
    @Published public var mhaActive: Bool = false
    @Published public var writeOK: Bool = false
    @Published public var keyMaskedName: String = ""
    @Published public var keyHoursLeft: Int = 0
    @Published public var exploitStage: String = "idle"      // mirror ExploitCoordinator.stage

    /// màu từng tính năng (CustomColorPickerPanel ghi vào đây; pack565 khi lưu)
    @Published public var featureRGB: [String: UInt16] = AppModel.defaultColors

    // MARK: nội bộ

    public private(set) var cancelRequested = false
    public private(set) var lastActionTime = Date.distantPast
    public private(set) var didBootstrap = false
    public var kernelInFlight = false
    public var kernelDone = false
    public var kernelWaiters = 0
    public var settleWindow: TimeInterval = 1.2   // chống bấm nhầm: "ui: bỏ qua thao tác quá nhanh"
    private var didLogGameVersion = false

    // MARK: phụ thuộc

    public let brand: AppBrand
    public let device: DeviceInfo
    public let server: ServerConfig
    public let library: PatchLibrary
    public let access: ContainerAccess
    public let coordinator: ExploitCoordinator
    public private(set) var installer: Installer
    public let gate: LicenseGate
    public let antibanEngine = Antiban()

    // MARK: khởi tạo

    public init(brand: AppBrand = .fromBundle(),
                server: ServerConfig = AppModel.defaultServer,
                access: ContainerAccess = AppModel.defaultAccess) {
        self.brand = brand
        self.server = server
        self.access = access
        self.library = PatchLibrary(config: server)
        self.installer = Installer(access: access, library: library)
        self.coordinator = ExploitCoordinator(directProviders: [access],
                                              primitive: AppModel.pluggedPrimitive)
        self.device = AppModel.readDevice()
        self.gate = LicenseGate(client: LicenseClient(config: server),
                               offlineMaxDays: server.offlineMaxDays,
                               packageToken: server.packageToken,
                               productId: brand.product)

        library.onLog = { [weak self] in self?.log($0) }
        installer.onLog = { [weak self] in self?.log($0) }
        installer.onProgress = { [weak self] in self?.phase = $0 }
        coordinator.onLog = { [weak self] in self?.log($0) }
        coordinator.onChange = { [weak self] in
            guard let self else { return }
            self.exploitStage = self.coordinator.stage.rawValue
        }
        gate.onLog = { [weak self] in self?.log($0) }
        gate.onAuthorized = { [weak self] in self?.selfHealToken() }
        antibanEngine.onLog = { [weak self] in self?.log($0) }
        antibanEngine.onForceOff = { [weak self] _ in self?.markInjected(false) }

        Logger.shared.onChange = { [weak self] lines in
            self?.logText = lines.suffix(120).map { "\($0.stamp)  \($0.text)" }.joined(separator: "\n")
        }
    }

    public static let defaultServer: ServerConfig = {
        // đọc cấu hình build từ Info.plist (NVHOfflineMaxDays, TserverPkgToken)
        let info = Bundle.main.infoDictionary ?? [:]
        let offlineDays = (info["NVHOfflineMaxDays"] as? Int) ?? 3
        let pkgToken = (info["TserverPkgToken"] as? String) ?? ""
        return ServerConfig(
            baseURL: URL(string: "https://example.invalid")!,     // ← đổi thành backend của bạn
            offlineMaxDays: offlineDays,
            packageToken: pkgToken,
            telegramURL: (info["NVHTelegram"] as? String).flatMap(URL.init(string:)),
            otaPatchURL: nil)
    }()

    public static let defaultAccess: ContainerAccess = {
        var providers: [ContainerAccess] = [
            DirectContainerAccess(),
        ]
        #if canImport(ObjectiveC) && canImport(UIKit)
        // Đường MHA: bundle id phải là com.apple.mobile.MobileHouseArrest
        // (xem Vendor3105/ — port từ 3105, GPL-3.0).
        providers.append(MHA3105ContainerAccess())
        #endif
        return ContainerAccessChain(providers)
    }()

    /// Primitive cắm ngoài. Mặc định trên iOS là chuỗi 3105 (kexploit + sandbox_escape);
    /// `nil` trên nền tảng khác. Có thể ghi đè trước khi tạo AppModel.
    public static var pluggedPrimitive: KernelPrimitive? = {
        #if canImport(ObjectiveC) && canImport(UIKit)
        return Kernel3105Primitive()
        #else
        return nil
        #endif
    }()


    public static let defaultColors: [String: UInt16] = [
        "box": Pack565.pack(r: 255, g: 38, b: 38),
        "line": Pack565.pack(r: 255, g: 38, b: 38),
        "bone": Pack565.pack(r: 255, g: 38, b: 38),
    ]

    // MARK: vòng đời

    public func bootstrap() {
        guard !didBootstrap else { return }
        didBootstrap = true
        log("Đang chuẩn bị…")
        log("Phiên bản • thiết bị: \(VersionGate.appVersion) • \(device.summary)")
        gate.start()
        refreshDetected()
        statusText = "Đã sẵn sàng — không cần chuẩn bị lại"
        selectFirstAvailableGame()
        phase = .idle
    }

    /// "Đã phát hiện" — dò game đã cài (dùng canOpenURL với LSApplicationQueriesSchemes)
    public func refreshDetected() {
        var found: [GameTarget: Bool] = [:]
        for g in GameTarget.allCases {
            found[g] = Self.canOpen(scheme: g.scheme) || access.isAvailable(for: g)
        }
        installedInfo = found
        // Màu nút = file thật trong Documents của game: có patch + config = đỏ.
        // Chỉ khi chưa đọc được container mới dùng trạng thái lưu từ lần trước.
        if access.isAvailable(for: game) {
            let present = isPatchPresent()
            patchInstalled = present
            UserDefaults.standard.set(present, forKey: Self.injectedPrefix + game.bundleID)
        } else {
            patchInstalled = Self.persistedInjected(for: game)
        }
        syncConfigFromDisk()
        if !found.values.contains(true) {
            log("Không thấy game. Kiểm tra game đã cài chưa nhé.")
        }
        if found[game] == true {
            log("Đã phát hiện \(game.name)")
            #if canImport(UIKit)
            if !didLogGameVersion, let v = BolaInstalledAppVersion(game.bundleID) {
                didLogGameVersion = true
                log("game: \(game.name) phiên bản \(v)")
            }
            #endif
        }
        writeOK = access.isAvailable(for: game)
    }

    private func selectFirstAvailableGame() {
        if let g = GameTarget.allCases.first(where: { installedInfo[$0] == true }) {
            game = g
        }
    }

    /// Đã inject = có ĐỦ `Assembly-CSharp-patch.bytes` + `nvhcfg.bin` trong Documents game.
    private func isPatchPresent() -> Bool {
        let patch = ((try? access.read(PatchLibrary.patchFileName, in: game)) ?? nil) != nil
        let cfg = ((try? access.read(PatchLibrary.configFileName, in: game)) ?? nil) != nil
        return patch && cfg
    }

    // MARK: đồng bộ UI ← nvhcfg.bin trong container game

    /// Đọc cfg thật trong Documents game và áp lên UI — app và game phải cùng một cấu hình.
    public func syncConfigFromDisk(using provider: ContainerAccess? = nil) {
        let box = provider ?? access
        guard box.isAvailable(for: game) else { return }
        guard let raw = ((try? box.read(PatchLibrary.configFileName, in: game)) ?? nil) else {
            return
        }
        guard let cfg = try? BolaConfig.decode([UInt8](raw)) else {
            log("cfg: không đọc được nvhcfg.bin — giữ cấu hình đang hiển thị")
            return
        }
        applyConfig(cfg)
    }

    private func applyConfig(_ cfg: BolaConfig) {
        var flags: Set<String> = []
        if cfg.flags.contains(.box) { flags.insert("box") }
        if cfg.flags.contains(.line) { flags.insert("line") }
        if cfg.flags.contains(.hp) { flags.insert("hp") }
        if cfg.flags.contains(.name) { flags.insert("name") }
        if cfg.flags.contains(.dist) { flags.insert("dist") }
        if cfg.flags.contains(.bot) { flags.insert("bot") }
        if cfg.flags.contains(.count) { flags.insert("count") }
        if cfg.extra.contains(.aim) { flags.insert("aim") }
        if cfg.extra.contains(.bones) { flags.insert("bone") }
        if cfg.extra.contains(.silent) { flags.insert("silent") }
        if cfg.extra.contains(.skipknock) { flags.insert("skipknock") }
        if cfg.extra.contains(.showfov) { flags.insert("showfov") }
        if cfg.extra.contains(.team) { flags.insert("team") }
        if cfg.extra.contains(.straight) { flags.insert("straight") }
        if cfg.misc1.contains(.fastfire) { flags.insert("fastfire") }
        if cfg.misc1.contains(.fastswap) { flags.insert("fastswap") }
        if cfg.misc1.contains(.emote) { flags.insert("emote") }
        if cfg.misc1.contains(.highjump) { flags.insert("highjump") }
        if cfg.misc1.contains(.fps144) { flags.insert("fps144") }
        if cfg.misc2.contains(.camwide) { flags.insert("camwide") }
        if cfg.misc2.contains(.backjump) { flags.insert("backjump") }
        if cfg.misc2.contains(.speedrun) { flags.insert("speedrun") }
        // autolaunch là tuỳ chọn phía app, không nằm trong cfg — giữ nguyên.
        if cfgFlags.contains("autolaunch") { flags.insert("autolaunch") }

        let changed = flags != cfgFlags
            || aimBone != cfg.bone
            || espThick != Double(cfg.espThick)
            || silentFov != Double(cfg.silentFov)
            || aimFov != Double(cfg.aimFov)
            || camFov != Double(cfg.camFov)
            || headRate != Double(cfg.headRate)
            || featureRGB["box"] != cfg.boxColor
            || featureRGB["line"] != cfg.lineColor
            || featureRGB["bone"] != cfg.boneColor

        cfgFlags = flags
        aimBone = cfg.bone
        espThick = Double(cfg.espThick)
        silentFov = Double(cfg.silentFov)
        aimFov = Double(cfg.aimFov)
        camFov = Double(cfg.camFov)
        headRate = Double(cfg.headRate)
        featureRGB["box"] = cfg.boxColor
        featureRGB["line"] = cfg.lineColor
        featureRGB["bone"] = cfg.boneColor

        if changed {
            log("cfg: đã đồng bộ cấu hình từ nvhcfg.bin trong game")
        }
    }

    // MARK: trạng thái inject bền (sống qua lần kill app)

    private static let injectedPrefix = "nvh.injected."

    public static func persistedInjected(for game: GameTarget) -> Bool {
        UserDefaults.standard.bool(forKey: injectedPrefix + game.bundleID)
    }

    /// Cập nhật nút INJECT / UN INJECT và ghi nhớ trạng thái cho lần mở sau.
    private func markInjected(_ on: Bool) {
        patchInstalled = on
        UserDefaults.standard.set(on, forKey: Self.injectedPrefix + game.bundleID)
    }

    // MARK: hành động

    public var config: BolaConfig {
        var flags: BolaConfig.Flags = []
        if cfgFlags.contains("box") { flags.insert(.box) }
        if cfgFlags.contains("line") { flags.insert(.line) }
        if cfgFlags.contains("hp") { flags.insert(.hp) }
        if cfgFlags.contains("name") { flags.insert(.name) }
        if cfgFlags.contains("dist") { flags.insert(.dist) }
        if cfgFlags.contains("bot") { flags.insert(.bot) }
        if cfgFlags.contains("count") { flags.insert(.count) }

        var extra: BolaConfig.Extra = []
        if cfgFlags.contains("aim") { extra.insert(.aim) }
        if cfgFlags.contains("bone") { extra.insert(.bones) }
        if cfgFlags.contains("silent") { extra.insert(.silent) }
        if cfgFlags.contains("skipknock") { extra.insert(.skipknock) }
        if cfgFlags.contains("showfov") { extra.insert(.showfov) }
        if cfgFlags.contains("team") { extra.insert(.team) }
        if cfgFlags.contains("straight") { extra.insert(.straight) }

        var misc1: BolaConfig.Misc1 = []
        if cfgFlags.contains("fastfire") { misc1.insert(.fastfire) }
        if cfgFlags.contains("fastswap") { misc1.insert(.fastswap) }
        if cfgFlags.contains("emote") { misc1.insert(.emote) }
        if cfgFlags.contains("highjump") { misc1.insert(.highjump) }
        if cfgFlags.contains("fps144") { misc1.insert(.fps144) }

        var misc2: BolaConfig.Misc2 = []
        if cfgFlags.contains("camwide") { misc2.insert(.camwide) }
        if cfgFlags.contains("backjump") { misc2.insert(.backjump) }
        if cfgFlags.contains("speedrun") { misc2.insert(.speedrun) }

        func u8(_ v: Double, _ lo: UInt8, _ hi: UInt8) -> UInt8 {
            UInt8(min(max(v, Double(lo)), Double(hi)))
        }

        return BolaConfig(
            flags: flags,
            extra: extra,
            misc1: misc1,
            misc2: misc2,
            bone: aimBone,
            espThick: u8(espThick, 50, 200),
            silentFov: u8(silentFov, 5, 100),
            aimFov: u8(aimFov, 5, 100),
            camFov: u8(camFov, 50, 130),
            headRate: u8(headRate, 10, 100),
            boxColor: featureRGB["box"] ?? 0xF925,
            lineColor: featureRGB["line"] ?? 0xF925,
            boneColor: featureRGB["bone"] ?? 0xF925)
    }

    /// Nút INJECT — kiểm tra → ghi patch/cfg/token → mở game.
    public func inject() {
        guard throttle() else {
            log("ui: bỏ qua thao tác quá nhanh (chống bấm nhầm)")
            return
        }
        guard gate.isAuthorized, let lease = gate.lease else {
            log("inject: chưa có patch cá nhân hoá hợp lệ")
            toast("🔑 Nhập key trước để bật")
            return
        }
        busy = true
        cancelRequested = false
        log("Chờ một chút rồi inject…")
        Task {
            // tầng container: direct → MHA → primitive 2 tầng (kernel r/w + sandbox escape)
            let ready = await coordinator.ensureReady(for: game)
            let liveAccess: ContainerAccess
            switch ready {
            case .success(let a):
                liveAccess = a
                mhaActive = coordinator.lastMessage == "mha"
            case .failure(let err):
                busy = false
                phase = .failed
                statusText = "\(err)"
                toast("Không tìm thấy thư mục game.")
                log("Không ghi được — mở game 1 lần (để tạo container) rồi thử lại")
                return
            }
            let inst = makeInstaller(access: liveAccess)
            // Có cfg sẵn trong game → lấy cfg làm chuẩn trước khi ghi đè.
            syncConfigFromDisk(using: liveAccess)
            inst.currentLease = lease
            let req = Installer.Request(game: game, config: config, lease: lease)
            let outcome = await inst.run(req)
            await MainActor.run {
                self.busy = false
                self.markInjected(outcome.ok)
                self.statusText = outcome.message
                self.toast(outcome.message)
                self.keyMaskedName = KeyMask.mask(lease.key)
                self.keyHoursLeft = BolaToken(key: lease.key,
                                              expiryUnix: lease.expiryUnix,
                                              sig: lease.sig).hoursLeft()
                self.writeOK = outcome.ok
                if outcome.ok, self.cfgFlags.contains("autolaunch") {
                    self.launchGame()
                }
            }
        }
    }

    /// Tạo Installer cho một đường ghi cụ thể (coordinator có thể trả đường khác nhau
    /// giữa các lần chạy: direct / MHA / primitive).
    private func makeInstaller(access: ContainerAccess) -> Installer {
        let inst = Installer(access: access, library: library)
        inst.onLog = { [weak self] in self?.log($0) }
        inst.onProgress = { [weak self] in self?.phase = $0 }
        installer = inst
        return inst
    }

    public func cancelInject() {
        cancelRequested = true
        log("inject: người dùng bấm huỷ")
        Task { @MainActor in
            let n = (installer as Installer).deployerUninstall(game: game)
            log("inject: huỷ muộn → gỡ patch vừa cài (\(n))")
            markInjected(false)
            phase = .idle
            toast("Đã huỷ — đã gỡ xong")
        }
    }

    public func removePatch() {
        guard throttle() else { return }
        let n = installer.deployerUninstall(game: game)
        markInjected(false)
        phase = .idle
        log("Đã gỡ xong. Mở lại game để áp dụng nhé. (\(n) file)")
        toast("Đã gỡ xong. Mở lại game để áp dụng nhé.")
    }

    // MARK: - tương thích bản gốc (AppModel.writeConfig / selfHealToken / attemptMHA)

    /// Chỉ ghi lại `nvhcfg.bin` (không tải lại patch), dùng khi đổi toggle/slider.
    public func writeConfig() {
        guard throttle() else { return }
        guard gate.isAuthorized, let lease = gate.lease else {
            toast("🔑 Nhập key trước để lưu cấu hình")
            return
        }
        guard let patch = ((try? access.read(PatchLibrary.patchFileName, in: game)) ?? nil) else {
            toast("Chưa có patch — bấm INJECT trước")
            return
        }
        let token = BolaToken(key: lease.key, expiryUnix: lease.expiryUnix, sig: lease.sig)
        let outcome = installer.deployer.install(patchData: patch, config: config,
                                                 token: token, game: game)
        log("cfg: writeConfig → \(outcome.message)")
        toast(outcome.ok ? "Đã lưu cấu hình" : outcome.message)
    }

    /// Token/trailer cũ hết hạn hoặc key đổi → ký lại tại chỗ, không cần bơm patch mới.
    public func selfHealToken() {
        guard gate.isAuthorized, let lease = gate.lease else { return }
        keyMaskedName = KeyMask.mask(lease.key)
        keyHoursLeft = BolaToken(key: lease.key, expiryUnix: lease.expiryUnix,
                                 sig: lease.sig).hoursLeft()
        let inst = makeInstaller(access: access)
        inst.currentLease = lease
        if inst.resyncTokenIfNeeded(for: game) {
            markInjected(true)
            log("token: self-heal → đã ký lại trailer cho \(game.name)")
        }
    }

    /// Thử mở container qua MobileHouseArrest rồi báo kết quả (bản gốc: attemptMHA).
    public func attemptMHA() {
        guard throttle() else { return }
        log("mha: thử mở container qua MobileHouseArrest…")
        Task {
            let result = await coordinator.ensureReady(for: game)
            await MainActor.run {
                switch result {
                case .success:
                    self.mhaActive = self.coordinator.skippedKernel
                    self.writeOK = true
                    self.log(self.mhaActive
                             ? "mha: đã mở container — bỏ qua kernel"
                             : "auto: đã có đường ghi container")
                case .failure(let err):
                    self.log("mha: không khả dụng (\(err))")
                }
            }
        }
    }

    /// Cập nhật thẻ key (bản gốc: refreshKeyCard).
    public func refreshKeyCard() {
        guard let lease = gate.lease else {
            keyMaskedName = ""
            keyHoursLeft = 0
            return
        }
        keyMaskedName = KeyMask.mask(lease.key)
        keyHoursLeft = BolaToken(key: lease.key, expiryUnix: lease.expiryUnix,
                                 sig: lease.sig).hoursLeft()
    }

    /// Tải lại patch từ server/OTA (bản gốc: refreshPatchRemote).
    public func refreshPatchRemote() {
        log("patch: đang làm mới từ server/OTA…")
        Task {
            let (data, file) = await library.fetchPatch(key: gate.lease?.key)
            await MainActor.run {
                if data.isEmpty {
                    self.log("patch: refreshRemote thất bại — giữ bản hiện tại")
                } else {
                    self.log("patch: refreshRemote → \(file.name) • \(file.sizeText)")
                }
            }
        }
    }

    /// Gỡ toàn bộ và trả về trạng thái nghỉ (bản gốc: AppModel.restore).
    public func restore() {
        let outcome = installer.restore(game: game)
        markInjected(false)
        phase = .idle
        statusText = outcome.message
        toast(outcome.message)
        log("restore: \(outcome.message)")
    }

    /// Xuất 3 file cài patch ra Documents/NVHExport để copy thủ công (Filza).
    /// Dùng khi app không có quyền ghi container game (chưa jailbreak/entitlement).
    public func exportPatchFiles() {
        guard gate.isAuthorized, let lease = gate.lease else {
            toast("🔑 Nhập key trước")
            return
        }
        guard let raw = PatchVault.bundledPatch() else {
            toast("Không thấy patch trong app")
            return
        }
        let token = BolaToken(key: lease.key, expiryUnix: lease.expiryUnix, sig: lease.sig)
        let license = token.encodedString()
        // padding ngẫu nhiên trước trailer → hash file xuất ra cũng khác mỗi lần
        let body = PatchRandomizer.pad(PatchTrailer.strip(from: raw))
        guard let signed = try? PatchTrailer.attach(to: body, license: license,
                                                     expiryUnix: lease.expiryUnix) else {
            toast("Không ký được trailer")
            return
        }

        let fm = FileManager.default
        guard let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let dir = docs.appendingPathComponent("NVHExport", isDirectory: true)
        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            try signed.write(to: dir.appendingPathComponent(PatchLibrary.patchFileName))
            try Data(config.encoded()).write(to: dir.appendingPathComponent(PatchLibrary.configFileName))
            try Data(token.encoded()).write(to: dir.appendingPathComponent(PatchLibrary.tokenFileName))
            let readme = """
            Copy 3 file sau vào Documents của game (dùng Filza):
              - Assembly-CSharp-patch.bytes
              - nvhcfg.bin
              - .nvhtok

            Đường dẫn game:
              /var/mobile/Containers/Data/Application/<UUID>/Documents/

            Sau đó mở game.
            """
            try readme.write(to: dir.appendingPathComponent("README.txt"),
                             atomically: true, encoding: .utf8)
            log("export: đã xuất patch + cfg + token vào Documents/NVHExport")
            toast("Đã xuất file — mở Files > NVH MOD > NVHExport")
        } catch {
            log("export: lỗi \(error.localizedDescription)")
            toast("Xuất file lỗi — thử lại")
        }
    }

    // MARK: setter tương thích bản gốc

    /// Bật/tắt feature đúng key của bản gốc; aim và silent loại trừ nhau.
    public func setFlag(_ key: String, _ on: Bool) {
        if on && key == "aim" { cfgFlags.remove("silent") }
        if on && key == "silent" { cfgFlags.remove("aim") }
        if on { cfgFlags.insert(key) } else { cfgFlags.remove(key) }
        writeConfig()
    }

    public func setBone(_ bone: BolaConfig.Bone) {
        aimBone = bone
        writeConfig()
    }

    public func setEspThick(_ value: Double) { espThick = min(max(value, 50), 200); writeConfig() }
    public func setHeadRate(_ value: Double) { headRate = min(max(value, 10), 100); writeConfig() }
    public func setSilentFov(_ value: Double) { silentFov = min(max(value, 5), 100); writeConfig() }
    public func setAimFov(_ value: Double) { aimFov = min(max(value, 5), 100); writeConfig() }
    public func setCamFov(_ value: Double) { camFov = min(max(value, 50), 130); writeConfig() }

    /// Alias log/showToast đúng tên field bản gốc.
    public func append(_ text: String) { log(text) }
    public func showToast(_ text: String) { toast(text) }

    public func launchGame() {
        log("Đã cài — chuẩn bị mở game…")
        #if canImport(UIKit)
        GameLauncher.launch(game) { [weak self] text in
            Task { @MainActor in
                self?.log(text)
                if text.hasPrefix("KHÔNG") {
                    self?.toast("Mở game bằng tay giúp mình.")
                }
            }
        }
        #endif
    }

    public func setLanguage(_ lang: Language) {
        language = lang
        log("Chọn ngôn ngữ: \(lang.display)")
    }

    public func clearCache() {
        let n = library.clearCache()
        access.clearCaches()
        log("cache: đã xoá (\(n) file tạm trong app)")
        toast("Đã xoá bộ nhớ đệm")
    }

    public func resetGuest() {
        do {
            try installer.deployerSetResetGuest(game: game)
            log("🧹 Đã đặt cờ reset guest — tắt hẳn game rồi MỞ LẠI để reset!")
            toast("Đã đặt cờ reset guest — tắt hẳn game rồi MỞ LẠI để reset!")
        } catch {
            log("reset guest: không ghi được (\(error.localizedDescription))")
            toast("Không ghi được — mở game 1 lần (để tạo container) rồi thử lại")
        }
    }

    public func setAntiban(_ on: Bool) {
        antiban = on
        antibanEngine.configure(deployer: installer.deployer, game: game, access: access)
        antibanEngine.setEnabled(on, hasKey: gate.isAuthorized)
        if !gate.isAuthorized && on {
            antiban = false
            toast("🔑 Nhập key xong rồi mới bật được Anti-ban nhé!")
        }
    }

    // MARK: helpers

    private func throttle() -> Bool {
        let now = Date()
        guard now.timeIntervalSince(lastActionTime) >= settleWindow else { return false }
        lastActionTime = now
        return true
    }

    public func toast(_ text: String) {
        toastText = text
        toastToken &+= 1
    }

    public func log(_ text: String) {
        Logger.shared.log(text)
    }

    private static func canOpen(scheme: String) -> Bool {
        #if canImport(UIKit)
        guard let url = URL(string: "\(scheme)://") else { return false }
        return UIApplication.shared.canOpenURL(url)
        #else
        return false
        #endif
    }

    private static func readDevice() -> DeviceInfo {
        #if canImport(UIKit)
        let d = UIDevice.current
        var sysinfo = utsname()
        uname(&sysinfo)
        let mirror = Mirror(reflecting: sysinfo.machine)
        let identifier = mirror.children.reduce(into: "") { acc, el in
            if let v = el.value as? Int8, v != 0 { acc.append(Character(UnicodeScalar(UInt8(v)))) }
        }
        return DeviceInfo(model: d.model, systemName: d.systemName,
                          systemVersion: d.systemVersion, identifier: identifier)
        #else
        return DeviceInfo(model: "host", systemName: "Linux", systemVersion: "0",
                          identifier: "x86_64")
        #endif
    }
}

// MARK: - Language (ContentView: langOption / languageCard / languageOverlay)

public enum Language: String, CaseIterable, Identifiable {
    case vi, en

    public var id: String { rawValue }
    public var display: String { self == .vi ? "Tiếng Việt" : "English" }
    public var flag: String { self == .vi ? "🇻🇳" : "🇺🇸" }
}
