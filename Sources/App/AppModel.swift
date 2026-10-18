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
    @Published public var game: GameTarget = .freefireMAX
    @Published public var installedInfo: [GameTarget: Bool] = [:]
    @Published public var patchInstalled: Bool = false
    @Published public var logText: String = ""
    @Published public var busy: Bool = false
    @Published public var restoring: Bool = false
    @Published public var toastText: String = ""
    @Published public var toastToken: Int = 0
    @Published public var cfgFlags: Set<String> = ["autolaunch"]
    @Published public var aimBone: BolaConfig.Bone = .head
    @Published public var silentFov: Double = 0.01
    @Published public var aimFov: Double = 30
    @Published public var headRate: Double = 0.7
    @Published public var camFov: Double = 60
    @Published public var espThick: Double = 1
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
        antibanEngine.onForceOff = { [weak self] _ in self?.patchInstalled = false }

        Logger.shared.onChange = { [weak self] lines in
            self?.logText = lines.suffix(120).map { "\($0.stamp)  \($0.text)" }.joined(separator: "\n")
        }
    }

    public static let defaultServer: ServerConfig = {
        // đọc cấu hình build từ Info.plist (BolaOfflineMaxDays, TserverPkgToken)
        let info = Bundle.main.infoDictionary ?? [:]
        let offlineDays = (info["BolaOfflineMaxDays"] as? Int) ?? 3
        let pkgToken = (info["TserverPkgToken"] as? String) ?? ""
        return ServerConfig(
            baseURL: URL(string: "https://example.invalid")!,     // ← đổi thành backend của bạn
            offlineMaxDays: offlineDays,
            packageToken: pkgToken,
            telegramURL: (info["BolaTelegram"] as? String).flatMap(URL.init(string:)),
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
        "esp_box": Pack565.pack(r: 0, g: 255, b: 128),
        "esp_skeleton": Pack565.pack(r: 255, g: 64, b: 64),
        "esp_hp": Pack565.pack(r: 64, g: 220, b: 64),
        "esp_name": Pack565.pack(r: 255, g: 255, b: 255),
        "fov_circle": Pack565.pack(r: 255, g: 210, b: 80),
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
        patchInstalled = access.isAvailable(for: game) && isPatchPresent()
        if !found.values.contains(true) {
            log("Không thấy game. Kiểm tra game đã cài chưa nhé.")
        }
        if found[game] == true {
            log("Đã phát hiện \(game.name)")
        }
        writeOK = access.isAvailable(for: game)
    }

    private func selectFirstAvailableGame() {
        if let g = GameTarget.allCases.first(where: { installedInfo[$0] == true }) {
            game = g
        }
    }

    private func isPatchPresent() -> Bool {
        ((try? access.read(PatchLibrary.patchFileName, in: game)) ?? nil) != nil
    }

    // MARK: hành động

    public var config: BolaConfig {
        var flags: BolaConfig.Flags = []
        if cfgFlags.contains("esp") { flags.insert(.esp) }
        if cfgFlags.contains("aim") { flags.insert(.aim) }
        if cfgFlags.contains("teammates") || cfgFlags.contains("bots") { flags.insert(.extra) }
        return BolaConfig(flags: flags,
                          bone: aimBone,
                          aimFov: UInt8(max(5, min(100, aimFov))),
                          field19: UInt8(max(5, min(100, headRate * 100))),
                          field20: UInt8(max(10, min(100, camFov))))
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
            inst.currentLease = lease
            let req = Installer.Request(game: game, config: config, lease: lease)
            let outcome = await inst.run(req)
            await MainActor.run {
                self.busy = false
                self.patchInstalled = outcome.ok
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
            patchInstalled = false
            phase = .idle
            toast("Đã huỷ — đã gỡ xong")
        }
    }

    public func removePatch() {
        guard throttle() else { return }
        let n = installer.deployerUninstall(game: game)
        patchInstalled = false
        phase = .idle
        log("Đã gỡ xong. Mở lại game để áp dụng nhé. (\(n) file)")
        toast("Đã gỡ xong. Mở lại game để áp dụng nhé.")
    }

    // MARK: - tương thích bản gốc (AppModel.writeConfig / selfHealToken / attemptMHA)

    /// Chỉ ghi lại `bolacfg.bin` (không tải lại patch), dùng khi đổi toggle/slider.
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
            patchInstalled = true
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
        patchInstalled = false
        phase = .idle
        statusText = outcome.message
        toast(outcome.message)
        log("restore: \(outcome.message)")
    }

    /// Xuất 3 file cài patch ra Documents/BolaExport để copy thủ công (Filza).
    /// Dùng khi app không có quyền ghi container game (chưa jailbreak/entitlement).
    public func exportPatchFiles() {
        guard gate.isAuthorized, let lease = gate.lease else {
            toast("🔑 Nhập key trước")
            return
        }
        guard let url = Bundle.main.url(forResource: "BolaminhducMenu", withExtension: "bytes"),
              let raw = try? Data(contentsOf: url) else {
            toast("Không thấy patch trong app")
            return
        }
        let token = BolaToken(key: lease.key, expiryUnix: lease.expiryUnix, sig: lease.sig)
        let license = token.encodedString()
        let body = PatchTrailer.strip(from: raw)
        guard let signed = try? PatchTrailer.attach(to: body, license: license,
                                                     expiryUnix: lease.expiryUnix) else {
            toast("Không ký được trailer")
            return
        }

        let fm = FileManager.default
        guard let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let dir = docs.appendingPathComponent("BolaExport", isDirectory: true)
        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            try signed.write(to: dir.appendingPathComponent(PatchLibrary.patchFileName))
            try Data(config.encoded()).write(to: dir.appendingPathComponent("bolacfg.bin"))
            try Data(token.encoded()).write(to: dir.appendingPathComponent(".bola_tok"))
            let readme = """
            Copy 3 file sau vào Documents của game (dùng Filza):
              - Assembly-CSharp-patch.bytes
              - bolacfg.bin
              - .bola_tok

            Đường dẫn game:
              /var/mobile/Containers/Data/Application/<UUID>/Documents/

            Sau đó mở game.
            """
            try readme.write(to: dir.appendingPathComponent("README.txt"),
                             atomically: true, encoding: .utf8)
            log("export: đã xuất patch + cfg + token vào Documents/BolaExport")
            toast("Đã xuất file — mở Files > Bola Clone > BolaExport")
        } catch {
            log("export: lỗi \(error.localizedDescription)")
            toast("Xuất file lỗi — thử lại")
        }
    }

    // MARK: setter tương thích bản gốc

    public func setEspThick(_ value: Double) { espThick = value; writeConfig() }
    public func setHeadRate(_ value: Double) { headRate = value; writeConfig() }
    public func setSilentFov(_ value: Double) { silentFov = value; writeConfig() }
    public func setCamFov(_ value: Double) { camFov = value; writeConfig() }

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
        antibanEngine.configure(deployer: installer.deployer, game: game)
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
