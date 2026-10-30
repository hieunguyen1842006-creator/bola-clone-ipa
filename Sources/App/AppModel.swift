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
    /// Gói hotfix đang chọn cho Liên Quân (Patch máy / Full HUD / NVH Beta / Unlock skin).
    @Published public var lqPack: LQPack =
        LQPack(rawValue: UserDefaults.standard.string(forKey: "nvh.lq.pack") ?? "") ?? .runtime
    /// Cấu hình cho payload NVH Beta (đọc từ Documents/lqcfg.txt).
    @Published public var lqEsp: Bool = UserDefaults.standard.bool(forKey: "nvh.lq.esp")
    @Published public var lqHud: Bool =
        (UserDefaults.standard.object(forKey: "nvh.lq.hud") as? Bool) ?? true
    @Published public var lqFov: Double =
        (UserDefaults.standard.object(forKey: "nvh.lq.fov") as? Double) ?? 88

    // MARK: cấu hình Full Mod AOV — ghi PlayerPrefs của game (iFix.*)
    /// ESP xuyên tường.
    @Published public var aovEsp: Bool =
        (UserDefaults.standard.object(forKey: "nvh.aov.esp") as? Bool) ?? true
    /// Tự động banned/pick.
    @Published public var aovBocpha: Bool = UserDefaults.standard.bool(forKey: "nvh.aov.bocpha")
    /// Aim assist.
    @Published public var aovAim: Bool = UserDefaults.standard.bool(forKey: "nvh.aov.aim")
    /// 0=hp 1=percent 2=near 3=ray.
    @Published public var aovTargetMode: Int =
        (UserDefaults.standard.object(forKey: "nvh.aov.tmode") as? Int) ?? 0
    /// Số đường aim 1..5.
    @Published public var aovLines: Int =
        (UserDefaults.standard.object(forKey: "nvh.aov.lines") as? Int) ?? 1
    /// 0=off 1=always 2=skill.
    @Published public var aovDrawMode: Int =
        (UserDefaults.standard.object(forKey: "nvh.aov.draw") as? Int) ?? 0
    /// 0=off 1=boss 2=buff 3=all.
    @Published public var aovSmiteMode: Int =
        (UserDefaults.standard.object(forKey: "nvh.aov.smite") as? Int) ?? 0
    /// Zoom camera 1.0..5.0.
    @Published public var aovZoom: Float =
        (UserDefaults.standard.object(forKey: "nvh.aov.zoom") as? Float) ?? 1.6
    /// Hero + index skin (ghi key iFix.SelectedSkin.v1.<hero>).
    @Published public var aovHero: Int =
        (UserDefaults.standard.object(forKey: "nvh.aov.hero") as? Int) ?? 111
    @Published public var aovModel: Int =
        (UserDefaults.standard.object(forKey: "nvh.aov.model") as? Int) ?? 0

    // MARK: gói "Patch máy" (runtime) — sửa trực tiếp file trong game
    /// Hệ số zoom camera. 0 = không đụng (giữ nguyên game).
    @Published public var lqZoom: Float =
        (UserDefaults.standard.object(forKey: "nvh.lq.zoom") as? Float) ?? 2.0
    @Published public var lqPrivacyOff: Bool =
        UserDefaults.standard.bool(forKey: "nvh.lq.privacy")
    @Published public var lqFakeHost: Bool =
        UserDefaults.standard.bool(forKey: "nvh.lq.host")
    /// Tag hiển thị thay "[skin v4]" (phải cùng độ dài UTF-8 = 9 byte).
    @Published public var lqTagText: String =
        UserDefaults.standard.string(forKey: "nvh.lq.tag") ?? ""
    /// Kết quả lần patch runtime gần nhất (UI hiện danh sách file + điểm đã sửa).
    @Published public var lqLastReport: [LienQuanDeployer.RuntimeResult] = []
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
    @Published public var textScale: Double = 100      // 50...200 (%)
    @Published public var drawDist: Double = 200       // 100...400 (m)
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
    public let dns = DNSManager()

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

        // Setting sống trong app, không phụ thuộc nvhcfg.bin của game.
        loadSavedSettings()
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
            var installed = Self.canOpen(scheme: g.scheme) || access.isAvailable(for: g)
            #if canImport(UIKit)
            if !installed, g.isLienQuan {
                installed = g.bundleIDs.contains { BolaInstalledAppVersion($0) != nil }
            }
            #endif
            found[g] = installed
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
    /// Với Liên Quân: `Resources/<ver>/Thanos/HeroSkin_2.bytes` khớp payload mình đã ghi.
    private func isPatchPresent() -> Bool {
        if game.isLienQuan {
            return LienQuanDeployer(access: access, game: game).isInstalled()
        }
        let patch = ((try? access.read(PatchLibrary.patchFileName, in: game)) ?? nil) != nil
        let cfg = ((try? access.read(PatchLibrary.configFileName, in: game)) ?? nil) != nil
        return patch && cfg
    }

    // MARK: đồng bộ UI ← nvhcfg.bin trong container game

    /// Đọc cfg thật trong Documents game và áp lên UI.
    ///
    /// Chỉ dùng file game làm nguồn khi app CHƯA có setting riêng (lần đầu cài app mà
    /// game đã có patch). Còn lại app là nguồn chân lý — `nvhcfg.bin` chỉ là bản app
    /// ghi ra để patch đọc, và nó bị xoá mỗi lần uninject.
    public func syncConfigFromDisk(using provider: ContainerAccess? = nil) {
        guard !game.isLienQuan else { return }   // LQ không có file cfg runtime
        guard !hasSavedSettings else { return }
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
        if cfg.dragHead { flags.insert("draghead") }
        if cfg.wallCheck { flags.insert("wallcheck") }
        // autolaunch là tuỳ chọn phía app, không nằm trong cfg — giữ nguyên.
        if cfgFlags.contains("autolaunch") { flags.insert("autolaunch") }

        let changed = flags != cfgFlags
            || aimBone != cfg.bone
            || espThick != Double(cfg.espThick)
            || textScale != Double(cfg.textScale)
            || drawDist != Double(cfg.drawDist) * 2
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
        textScale = Double(cfg.textScale)
        drawDist = Double(cfg.drawDist) * 2
        silentFov = Double(cfg.silentFov)
        aimFov = Double(cfg.aimFov)
        // một thanh FOV chung — giữ 2 byte luôn bằng nhau
        let fov = cfgFlags.contains("silent") ? silentFov : aimFov
        silentFov = fov
        aimFov = fov
        camFov = Double(cfg.camFov)
        headRate = Double(cfg.headRate)
        featureRGB["box"] = cfg.boxColor
        featureRGB["line"] = cfg.lineColor
        featureRGB["bone"] = cfg.boneColor

        if changed {
            log("cfg: đã đồng bộ cấu hình từ nvhcfg.bin trong game")
        }
        saveSettings()
    }

    // MARK: setting sống trong app (UserDefaults) — không mất khi uninject

    private static let store = UserDefaults.standard

    private enum StoreKey {
        static let flags = "nvh.cfg.flags"
        static let bone = "nvh.cfg.bone"
        static let espThick = "nvh.cfg.espThick"
        static let textScale = "nvh.cfg.textScale"
        static let drawDist = "nvh.cfg.drawDist"
        static let fov = "nvh.cfg.fov"
        static let headRate = "nvh.cfg.headRate"
        static let camFov = "nvh.cfg.camFov"
        static let color = "nvh.cfg.color."
    }

    /// App đã có setting lưu riêng chưa (khác hẳn `nvhcfg.bin` trong container game).
    private var hasSavedSettings: Bool {
        Self.store.object(forKey: StoreKey.flags) != nil
    }

    /// Nạp setting đã lưu trong app; field nào chưa từng lưu thì giữ mặc định.
    private func loadSavedSettings() {
        let d = Self.store
        if let v = d.array(forKey: StoreKey.flags) as? [String] { cfgFlags = Set(v) }
        if let v = d.object(forKey: StoreKey.bone) as? Int,
           let b = BolaConfig.Bone(rawValue: UInt8(clamping: v)) { aimBone = b }
        if let v = d.object(forKey: StoreKey.espThick) as? Double {
            espThick = min(max(v, 50), 200)
        }
        if let v = d.object(forKey: StoreKey.textScale) as? Double {
            textScale = min(max(v, 50), 200)
        }
        if let v = d.object(forKey: StoreKey.drawDist) as? Double {
            drawDist = min(max(v, 100), 400)
        }
        if let v = d.object(forKey: StoreKey.fov) as? Double {
            let f = min(max(v, 5), 100)
            silentFov = f
            aimFov = f
        }
        if let v = d.object(forKey: StoreKey.headRate) as? Double {
            headRate = min(max(v, 10), 100)
        }
        if let v = d.object(forKey: StoreKey.camFov) as? Double {
            camFov = min(max(v, 50), 130)
        }
        for key in AppModel.defaultColors.keys {
            if let v = d.object(forKey: StoreKey.color + key) as? Int {
                featureRGB[key] = UInt16(clamping: v)
            }
        }
    }

    /// Ghi setting vào chính app — gọi ở mọi setter nên uninject cũng không mất.
    private func saveSettings() {
        let d = Self.store
        d.set(Array(cfgFlags).sorted(), forKey: StoreKey.flags)
        d.set(Int(aimBone.rawValue), forKey: StoreKey.bone)
        d.set(espThick, forKey: StoreKey.espThick)
        d.set(textScale, forKey: StoreKey.textScale)
        d.set(drawDist, forKey: StoreKey.drawDist)
        d.set(activeFov, forKey: StoreKey.fov)
        d.set(headRate, forKey: StoreKey.headRate)
        d.set(camFov, forKey: StoreKey.camFov)
        for (key, value) in featureRGB { d.set(Int(value), forKey: StoreKey.color + key) }
    }

    /// Màu từng tính năng (bảng chọn màu gọi cái này để lưu lại trong app).
    public func setFeatureColor(_ key: String, _ value: UInt16) {
        featureRGB[key] = value
        saveSettings()
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
            dragHead: cfgFlags.contains("draghead"),
            wallCheck: cfgFlags.contains("wallcheck"),
            textScale: u8(textScale, 50, 200),
            drawDist: u8(drawDist / 2, 25, 200),
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
        // Liên Quân: ghi hotfix payload (không dùng IFix patch + cfg của FF).
        if game.isLienQuan {
            injectLQ()
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

    /// Nút INJECT cho Liên Quân — luôn deploy Full Mod AOV (LQFull),
    /// cấu hình tính năng do thẻ trong app điều khiển (PlayerPrefs của game).
    private func injectLQ() {
        let pack = LQPack.fullMod
        // Gói runtime: không cần payload trong app, tự đọc file gốc của game.
        if !pack.usesBundledPayload {
            injectLQRuntime()
            return
        }
        guard let resource = pack.vaultResource,
              let payload = PatchVault.load(resource: resource) else {
            toast("Không thấy gói LQ trong app")
            log("lq: thiếu \(pack.vaultResource ?? "?").vault")
            return
        }
        busy = true
        cancelRequested = false
        log("lq: chuẩn bị container…")
        Task {
            let ready = await coordinator.ensureReady(for: game)
            switch ready {
            case .success(let live):
                mhaActive = coordinator.lastMessage == "mha"
                let dep = LienQuanDeployer(access: live, game: game)
                dep.onLog = { [weak self] in self?.log($0) }
                let outcome = dep.install(payload, pack: pack, config: nil)
                await MainActor.run {
                    self.busy = false
                    self.markInjected(outcome.ok)
                    self.statusText = outcome.message
                    self.toast(outcome.message)
                    self.writeOK = outcome.ok
                    if outcome.ok {
                        // cấu hình toggle hiện tại → PlayerPrefs của game luôn
                        self.pushAOVConfig(via: live)
                    }
                    if outcome.ok, self.cfgFlags.contains("autolaunch") {
                        self.launchGame()
                    }
                }
            case .failure(let err):
                await MainActor.run {
                    self.busy = false
                    self.phase = .failed
                    self.statusText = "\(err)"
                    self.toast("Không mở được thư mục Liên Quân.")
                    self.log("lq: \(err)")
                }
            }
        }
    }

    /// Gói runtime: đọc `.bytes` gốc trong máy → ResD decrypt → sửa IL → encrypt → ghi.
    private func injectLQRuntime() {
        let cfg = LqConfig(zoom: lqZoom,
                           privacyOff: lqPrivacyOff ? true : nil,
                           fakeHost: lqFakeHost ? true : nil,
                           tagText: lqTagText.isEmpty ? nil : lqTagText)
        guard !cfg.isEmpty else {
            toast("Chưa chọn gì để patch — bật ít nhất 1 tuỳ chọn")
            log("lq: runtime config rỗng, không làm gì")
            return
        }
        busy = true
        cancelRequested = false
        log("lq: chuẩn bị container cho patch runtime…")
        Task {
            let ready = await coordinator.ensureReady(for: game)
            switch ready {
            case .success(let live):
                mhaActive = coordinator.lastMessage == "mha"
                let dep = LienQuanDeployer(access: live, game: game)
                dep.onLog = { [weak self] in self?.log($0) }
                let outcome = dep.installSmart(config: cfg)
                await MainActor.run {
                    self.busy = false
                    self.markInjected(outcome.ok)
                    self.statusText = outcome.message
                    self.toast(outcome.message)
                    self.writeOK = outcome.ok
                    self.lqLastReport = outcome.ok ? dep.inspectRuntime() : self.lqLastReport
                    if outcome.ok, self.cfgFlags.contains("autolaunch") {
                        self.launchGame()
                    }
                }
            case .failure(let err):
                await MainActor.run {
                    self.busy = false
                    self.phase = .failed
                    self.statusText = "\(err)"
                    self.toast("Không mở được thư mục Liên Quân.")
                    self.log("lq: \(err)")
                }
            }
        }
    }

    /// Gỡ hotfix LQ + khôi phục bản gốc đã backup.
    private func removeLQ() {
        busy = true
        log("lq: đang gỡ…")
        Task {
            let ready = await coordinator.ensureReady(for: game)
            switch ready {
            case .success(let live):
                let dep = LienQuanDeployer(access: live, game: game)
                dep.onLog = { [weak self] in self?.log($0) }
                let outcome = dep.uninstall()
                await MainActor.run {
                    self.busy = false
                    if outcome.ok { self.markInjected(false); self.phase = .idle }
                    self.statusText = outcome.message
                    self.toast(outcome.message)
                    if !outcome.ok { self.log("lq: \(outcome.message)") }
                }
            case .failure(let err):
                await MainActor.run {
                    self.busy = false
                    self.phase = .failed
                    self.toast("Không mở được thư mục Liên Quân.")
                    self.log("lq: \(err)")
                }
            }
        }
    }

    /// Chọn gói LQ (Full HUD / NVH Beta / Unlock skin).
    public func setLQPack(_ pack: LQPack) {
        guard pack != lqPack else { return }
        lqPack = pack
        UserDefaults.standard.set(pack.rawValue, forKey: "nvh.lq.pack")
        toast("Đã chọn gói \(pack.title) — bấm INJECT để áp dụng")
    }

    // MARK: setter Full Mod AOV — lưu trong app + ghi plist của game

    private func saveAOV() {
        let d = UserDefaults.standard
        d.set(aovEsp, forKey: "nvh.aov.esp")
        d.set(aovBocpha, forKey: "nvh.aov.bocpha")
        d.set(aovAim, forKey: "nvh.aov.aim")
        d.set(aovTargetMode, forKey: "nvh.aov.tmode")
        d.set(aovLines, forKey: "nvh.aov.lines")
        d.set(aovDrawMode, forKey: "nvh.aov.draw")
        d.set(aovSmiteMode, forKey: "nvh.aov.smite")
        d.set(aovZoom, forKey: "nvh.aov.zoom")
        d.set(aovHero, forKey: "nvh.aov.hero")
        d.set(aovModel, forKey: "nvh.aov.model")
    }

    /// Bộ key iFix.* tương ứng UI đang hiển thị.
    private func aovValues() -> [String: Any] {
        [
            LQModConfig.espKey: aovEsp ? 1 : 0,
            LQModConfig.bocphaKey: aovBocpha ? 1 : 0,
            LQModConfig.aimKey: aovAim ? 1 : 0,
            LQModConfig.aimTargetKey: aovTargetMode,
            LQModConfig.aimLinesKey: aovLines,
            LQModConfig.aimDrawKey: aovDrawMode,
            LQModConfig.smiteKey: aovSmiteMode == 0 ? 0 : 1,
            LQModConfig.smiteTargetKey: max(aovSmiteMode - 1, 0),
            LQModConfig.zoomKey: Double(aovZoom),
            LQModConfig.skinKey(hero: aovHero): aovModel,
        ]
    }

    /// Ghi cấu hình vào PlayerPrefs của game (game phải TẮT để cfprefsd không
    /// giữ giá trị cũ trong cache).
    public func pushAOVConfig(via provider: ContainerAccess? = nil) {
        guard game.isLienQuan else { return }
        let box = provider ?? access
        guard box.isAvailable(for: game) else {
            log("aov: chưa mở được container — cấu hình chỉ lưu trong app")
            return
        }
        if LQModConfig.apply(aovValues(), access: box, game: game) {
            log("aov: đã ghi cấu hình vào game — mở lại game để nhận")
        } else {
            log("aov: không ghi được plist prefs của game")
        }
    }

    /// Đọc cấu hình hiện có trong game lên UI.
    public func syncAOVFromGame() {
        guard game.isLienQuan else { return }
        guard access.isAvailable(for: game) else {
            toast("Chưa mở được thư mục game")
            return
        }
        guard let dict = LQModConfig.load(access: access, game: game) else {
            toast("Game chưa có cấu hình — đang dùng mặc định")
            return
        }
        aovEsp = LQModConfig.int(dict, LQModConfig.espKey, aovEsp ? 1 : 0) == 1
        aovBocpha = LQModConfig.int(dict, LQModConfig.bocphaKey, aovBocpha ? 1 : 0) == 1
        aovAim = LQModConfig.int(dict, LQModConfig.aimKey, aovAim ? 1 : 0) == 1
        aovTargetMode = min(max(LQModConfig.int(dict, LQModConfig.aimTargetKey, aovTargetMode), 0), 3)
        aovLines = min(max(LQModConfig.int(dict, LQModConfig.aimLinesKey, aovLines), 1), 5)
        aovDrawMode = min(max(LQModConfig.int(dict, LQModConfig.aimDrawKey, aovDrawMode), 0), 2)
        let smEn = LQModConfig.int(dict, LQModConfig.smiteKey, 0)
        let smTm = min(max(LQModConfig.int(dict, LQModConfig.smiteTargetKey, 0), 0), 2)
        aovSmiteMode = smEn == 1 ? smTm + 1 : 0
        aovZoom = min(max(LQModConfig.float(dict, LQModConfig.zoomKey, aovZoom), 1.0), 5.0)
        aovModel = min(max(LQModConfig.int(dict, LQModConfig.skinKey(hero: aovHero), aovModel), 0), 99)
        saveAOV()
        toast("Đã đọc cấu hình từ game")
    }

    public func setAOVEsp(_ v: Bool) { aovEsp = v; saveAOV(); pushAOVConfig() }
    public func setAOVBocpha(_ v: Bool) { aovBocpha = v; saveAOV(); pushAOVConfig() }
    public func setAOVAim(_ v: Bool) { aovAim = v; saveAOV(); pushAOVConfig() }
    public func setAOVTargetMode(_ v: Int) { aovTargetMode = min(max(v, 0), 3); saveAOV(); pushAOVConfig() }
    public func setAOVLines(_ v: Int) { aovLines = min(max(v, 1), 5); saveAOV(); pushAOVConfig() }
    public func setAOVDrawMode(_ v: Int) { aovDrawMode = min(max(v, 0), 2); saveAOV(); pushAOVConfig() }
    public func setAOVSmiteMode(_ v: Int) { aovSmiteMode = min(max(v, 0), 3); saveAOV(); pushAOVConfig() }
    public func setAOVZoom(_ v: Float) {
        aovZoom = min(max((v * 10).rounded() / 10, 1.0), 5.0)
        saveAOV(); pushAOVConfig()
    }
    public func setAOVHero(_ v: Int) { aovHero = max(v, 1); saveAOV(); pushAOVConfig() }
    public func setAOVModel(_ v: Int) { aovModel = min(max(v, 0), 99); saveAOV(); pushAOVConfig() }

    public func setLQEsp(_ on: Bool) {
        lqEsp = on
        UserDefaults.standard.set(on, forKey: "nvh.lq.esp")
        pushLQConfig()
    }

    public func setLQHud(_ on: Bool) {
        lqHud = on
        UserDefaults.standard.set(on, forKey: "nvh.lq.hud")
        pushLQConfig()
    }

    public func setLQFov(_ value: Double) {
        lqFov = min(max(value, 50), 130)
        UserDefaults.standard.set(lqFov, forKey: "nvh.lq.fov")
        pushLQConfig()
    }

    // MARK: setter cho gói "Patch máy" (runtime)

    /// 0 = tắt patch zoom (trả về bản gốc của game).
    public func setLQZoom(_ value: Float) {
        lqZoom = value <= 0 ? 0 : min(max(value, 1.0), 5.0)
        UserDefaults.standard.set(lqZoom, forKey: "nvh.lq.zoom")
    }

    public func setLQPrivacyOff(_ on: Bool) {
        lqPrivacyOff = on
        UserDefaults.standard.set(on, forKey: "nvh.lq.privacy")
    }

    public func setLQFakeHost(_ on: Bool) {
        lqFakeHost = on
        UserDefaults.standard.set(on, forKey: "nvh.lq.host")
    }

    public func setLQTagText(_ text: String) {
        lqTagText = text
        UserDefaults.standard.set(text, forKey: "nvh.lq.tag")
    }

    private func lqConfigText() -> String {
        "esp=\(lqEsp ? 1 : 0)\nhud=\(lqHud ? 1 : 0)\nfov=\(Int(lqFov))\n"
    }

    /// Ghi lqcfg.txt ngay nếu đang mở được container (payload đọc mỗi ~16 frame).
    private func pushLQConfig() {
        guard game.isLienQuan, patchInstalled, access.isAvailable(for: game) else { return }
        _ = LienQuanDeployer(access: access, game: game).writeConfig(lqConfigText())
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
        if game.isLienQuan {
            removeLQ()
            return
        }
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
        if game.isLienQuan {
            removeLQ()
            return
        }
        let n = installer.deployerUninstall(game: game)
        markInjected(false)
        phase = .idle
        log("Đã gỡ xong. Mở lại game để áp dụng nhé. (\(n) file)")
        toast("Đã gỡ xong. Mở lại game để áp dụng nhé.")
    }

    // MARK: - tương thích bản gốc (AppModel.writeConfig / selfHealToken / attemptMHA)

    /// Chỉ ghi lại `nvhcfg.bin` (không tải lại patch), dùng khi đổi toggle/slider.
    public func writeConfig() {
        // Setting đã được setter lưu trong app; gọi thẳng hàm này cũng lưu cho chắc.
        saveSettings()
        guard throttle() else { return }
        if game.isLienQuan {
            toast("LQ dùng gói cố định — không có cấu hình riêng")
            return
        }
        guard gate.isAuthorized, let lease = gate.lease else {
            toast("Đã lưu trong app — nhập key để áp vào game")
            return
        }
        guard let patch = ((try? access.read(PatchLibrary.patchFileName, in: game)) ?? nil) else {
            toast("Đã lưu trong app — bấm INJECT để áp vào game")
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
        guard !game.isLienQuan else { return }
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
        if game.isLienQuan {
            removeLQ()
            return
        }
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
        saveSettings()
        // autolaunch là tuỳ chọn phía app — LQ không có cfg để ghi.
        if !game.isLienQuan { writeConfig() }
    }

    public func setBone(_ bone: BolaConfig.Bone) {
        aimBone = bone
        saveSettings()
        writeConfig()
    }

    public func setEspThick(_ value: Double) {
        espThick = min(max(value, 50), 200)
        saveSettings()
        writeConfig()
    }

    public func setTextScale(_ value: Double) {
        textScale = min(max(value.rounded(), 50), 200)
        saveSettings()
        writeConfig()
    }

    public func setDrawDist(_ value: Double) {
        drawDist = min(max((value / 10).rounded() * 10, 100), 400)
        saveSettings()
        writeConfig()
    }

    public func setHeadRate(_ value: Double) {
        headRate = min(max(value, 10), 100)
        saveSettings()
        writeConfig()
    }

    /// Một thanh FOV dùng chung cho cả Aimbot và Silent.
    /// Patch đọc byte 19 khi Aimbot, byte 15 khi Silent — nên ghi cả hai cùng giá trị.
    public var activeFov: Double { cfgFlags.contains("silent") ? silentFov : aimFov }
    public func setFov(_ value: Double) {
        let v = min(max(value, 5), 100)
        silentFov = v
        aimFov = v
        saveSettings()
        writeConfig()
    }

    public func setCamFov(_ value: Double) {
        camFov = min(max(value, 50), 130)
        saveSettings()
        writeConfig()
    }

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
            return
        }
        // DNS làm antiban: bật = cài DoH blocklist, tắt = gỡ về DNS hệ thống
        Task { await dns.applyAntiban(on) }
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
