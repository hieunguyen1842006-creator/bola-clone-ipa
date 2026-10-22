import Foundation
import NetworkExtension

/// DNSManager — port từ FFDNSManager (Fl0rkFF clone) sang Swift cho BolaClone.
///
/// Quản lý DNS-over-HTTPS của thiết bị qua NetworkExtension (NEDNSSettingsManager):
/// - Cài/cập nhật "secure DNS settings" (chính xác bản gốc Fl0rkFF làm).
/// - Preset có sẵn + custom DoH template.
/// - Fallback: khi thiếu entitlement `dns-settings` (free cert / sideload thường),
///   sinh file `.mobileconfig` để user cài profile tay trong Settings.
///
/// Mục đích trong tool: kiểm soát traffic tầng DNS — chặn domain anti-cheat/telemetry
/// của game, route domain auth, tránh ISP DNS hijack khi app gọi license server.
@MainActor
public final class DNSManager: ObservableObject {

    public struct Preset: Identifiable, Equatable {
        public var id: String { name }
        public let name: String
        public let template: String
        public let note: String
    }

    public static let presets: [Preset] = [
        Preset(name: "Cloudflare", template: "https://cloudflare-dns.com/dns-query",
               note: "Nhanh, không log — chọn mặc định"),
        Preset(name: "Google", template: "https://dns.google/dns-query",
               note: "Ổn định, phổ biến"),
        Preset(name: "AdGuard (unfiltered)", template: "https://dns.adguard-dns.com/dns-query",
               note: "Không chặn quảng cáo, chỉ mã hoá"),
        Preset(name: "AdGuard (ads block)", template: "https://dns.adguard-dns.com/dns-query{ads}",
               note: "Kèm blocklist quảng cáo"),
        Preset(name: "NextDNS", template: "https://dns.nextdns.io/",
               note: "Nhập ID config của bạn vào ô custom"),
    ]

    // MARK: - Published state (mirrors FFDNSSnapshot)

    /// Kết quả lần thao tác gần nhất (install/remove) — cho UI hiện banner.
    @Published public private(set) var lastResult: (ok: Bool, message: String)? = nil
    @Published public private(set) var enabled: Bool = false
    @Published public private(set) var busy: Bool = false
    @Published public private(set) var currentTemplate: String = ""
    @Published public private(set) var statusMessage: String = "DNS-over-HTTPS profile management."
    @Published public private(set) var lastError: String?

    // MARK: - Antiban blocklist (antiban-nvh.json)

    @Published public private(set) var antibanRules: [DNSBlocklistRule] = []
    @Published public var antibanOn: Bool {
        didSet { UserDefaults.standard.set(antibanOn, forKey: "antiban.on") }
    }

    /// Denylist domain gốc hiện hành (apex, sorted) — rỗng khi tắt.
    public var antibanDomains: [String] {
        guard antibanOn else { return [] }
        return Set(antibanRules.filter { $0.enabled }.flatMap { DNSBlocklist.domains(fromPattern: $0.url) }).sorted()
    }

    /// Nhập file antiban JSON khác (fileImporter). true = parse được.
    @discardableResult
    public func loadAntiban(from url: URL) -> Bool {
        do {
            let rules = DNSBlocklist.load(try Data(contentsOf: url))
            guard !rules.isEmpty else { return false }
            antibanRules = rules
            if let d = try? JSONEncoder().encode(rules) {
                UserDefaults.standard.set(d, forKey: "antiban.rules")
            }
            Logger.shared.log("[DNS] antiban loaded: \(rules.count) rule(s)")
            return true
        } catch {
            return false
        }
    }

    public init() {
        if let d = UserDefaults.standard.data(forKey: "antiban.rules"),
           let rules = try? JSONDecoder().decode([DNSBlocklistRule].self, from: d), !rules.isEmpty {
            antibanRules = rules
        } else {
            antibanRules = DNSBlocklist.load(Data(DNSBlocklist.defaultJSON.utf8))
        }
        antibanOn = UserDefaults.standard.bool(forKey: "antiban.on")
    }

    // MARK: - Load

    /// Đọc cấu hình hiện có trên thiết bị (gọi lúc mở màn DNS).
    public func refresh() async {
        busy = true
        defer { busy = false }
        lastResult = nil
        let manager = NEDNSSettingsManager.shared()
        do {
            try await manager.loadFromPreferences()
            if let settings = manager.dnsSettings {
                enabled = true
                // DoH template (nếu có) — đọc qua KVC để khỏi phụ thuộc
                // compile-time symbol NEDoHResolverSettings.
                if settings.responds(to: Selector(("doHServerTemplates"))),
                   let templates = settings.value(forKey: "doHServerTemplates") as? [String],
                   let first = templates.first {
                    currentTemplate = first
                    statusMessage = "DoH active: \(first)"
                } else {
                    currentTemplate = "(plain DNS settings)"
                    statusMessage = "DNS settings present (plain servers)."
                }
                lastError = nil
            } else {
                enabled = false
                currentTemplate = ""
                statusMessage = "No DNS profile installed."
                lastError = nil
            }
        } catch {
            // Thiếu entitlement dns-settings → rơi xuống fallback profile tay.
            enabled = false
            lastError = error.localizedDescription
            statusMessage = "NE unavailable (thiếu entitlement?) — dùng profile tay bên dưới."
        }
    }

    // MARK: - Install / remove (NEDNSSettingsManager path)

    /// Bật DoH với preset + optional custom template (NextDNS ID, server riêng).
    public func install(preset: Preset, customTemplate: String?) async {
        var template = customTemplate?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if template.isEmpty { template = preset.template }
        if !template.hasPrefix("https://") {
            statusMessage = "Template phải là URL https://…"
            lastResult = (ok: false,
                          message: "❌ Ô Custom không phải URL DoH. Denylist ||domain^ dán vào dashboard NextDNS/AdGuard — không dán vào ô này.")
            return
        }
        busy = true
        defer { busy = false }

        let manager = NEDNSSettingsManager.shared()
        do { try await manager.loadFromPreferences() } catch { }

        // NEDoHResolverSettings qua runtime lookup (NSClassFromString) — iPadOS 26
        // không expose class này lúc runtime → không thể tạo DoH qua NE từ app.
        var settings: NEDNSSettings? = nil
        if let dohClass = NSClassFromString("NEDoHResolverSettings") as? NEDNSSettings.Type {
            let doh = dohClass.init(servers: [])
            doh.setValue([template], forKey: "doHServerTemplates")
            settings = doh
            Logger.shared.log("[DNS] NEDoHResolverSettings OK → \(template)")
        } else {
            // Cài plain DNS là vô ích (không blocklist) và NE còn báo
            // "configuration is unchanged" nếu profile thường đã có sẵn.
            // Dẫn user sang profile tay .mobileconfig — đường đó luôn chạy được.
            Logger.shared.log("[DNS] NEDoHResolverSettings không có trên máy này → hướng profile tay")
            statusMessage = "⚠️ iPadOS 26 không cho app tạo DoH qua NE. Dùng nút 'Tạo file profile (.mobileconfig)' bên dưới (dùng đúng URL anh nhập) — hoặc chọn profile NextDNS trong Settings → DNS."
            lastResult = (ok: false, message: statusMessage)
            return
        }
        manager.dnsSettings = settings

        do {
            try await manager.saveToPreferences()
            enabled = true
            currentTemplate = template
            statusMessage = "✅ Đã cài DoH: \(template)"
            lastError = nil
            lastResult = (ok: true, message: statusMessage)
            UserDefaults.standard.set(template, forKey: "antiban.doh.template")
            Logger.shared.log("[DNS] save OK (DoH)")
        } catch {
            let msg = error.localizedDescription
            if msg.localizedCaseInsensitiveContains("unchanged") {
                // NE coi cấu hình trùng khớp là lỗi — thực chất DoH đã chạy sẵn.
                enabled = true
                currentTemplate = template
                statusMessage = "✅ DoH đã cài sẵn (configuration unchanged)."
                lastError = nil
                lastResult = (ok: true, message: statusMessage)
                Logger.shared.log("[DNS] save unchanged → coi như đã cài")
            } else {
                lastError = msg
                statusMessage = "❌ Lưu profile thất bại: \(msg) — dùng 'Tạo file profile (.mobileconfig)' bên dưới."
                lastResult = (ok: false, message: statusMessage)
                Logger.shared.log("[DNS] NE save failed: \(msg)")
            }
        }
    }

    /// Gỡ DNS profile (quay về DNS hệ thống).
    public func remove() async {
        busy = true
        defer { busy = false }
        let manager = NEDNSSettingsManager.shared()
        do {
            try await manager.loadFromPreferences()
            try await manager.removeFromPreferences()
            enabled = false
            currentTemplate = ""
            statusMessage = "✅ Đã gỡ DNS profile — về DNS hệ thống."
            lastError = nil
            lastResult = (ok: true, message: statusMessage)
            Logger.shared.log("[DNS] profile removed")
        } catch {
            lastError = error.localizedDescription
            statusMessage = "❌ Gỡ thất bại: \(error.localizedDescription)"
            lastResult = (ok: false, message: statusMessage)
        }
    }

    /// DNS làm antiban: bật = cài DoH chặn telemetry (AdGuard ads-block, hoặc
    /// custom template đã lưu từ lần trước); tắt = gỡ profile, về DNS hệ thống.
    public func applyAntiban(_ on: Bool) async {
        if on {
            let saved = UserDefaults.standard.string(forKey: "antiban.doh.template")
            await install(preset: Self.presets[3], customTemplate: saved)
        } else {
            await remove()
        }
    }

    // MARK: - Fallback: mobileconfig profile (không cần entitlement)

    /// Sinh file .mobileconfig DoH để user cài tay (Settings → Profile Downloaded).
    /// Trả về URL file tạm; nil nếu lỗi.
    public func makeManualProfile(preset: Preset, customTemplate: String?) -> URL? {
        var template = customTemplate?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if template.isEmpty { template = preset.template }
        guard template.hasPrefix("https://") else { return nil }

        let uuid = UUID().uuidString
        let payloadUUID = UUID().uuidString
        let safeName = preset.name.replacingOccurrences(of: " ", with: "")

        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
          <key>PayloadContent</key>
          <array>
            <dict>
              <key>DNSSettings</key>
              <dict>
                <key>DNSProtocol</key>
                <string>HTTPS</string>
                <key>ServerURL</key>
                <string>\(template)</string>
                <key>ServerURLFallback</key>
                <string>\(template)</string>
              </dict>
              <key>PayloadDisplayName</key>
              <string>DoH — \(preset.name)</string>
              <key>PayloadIdentifier</key>
              <string>com.bolaclone.doh.\(safeName)</string>
              <key>PayloadOrganization</key>
              <string>BolaClone</string>
              <key>PayloadType</key>
              <string>com.apple.dnsSettings.managed</string>
              <key>PayloadUUID</key>
              <string>\(payloadUUID)</string>
              <key>PayloadVersion</key>
              <integer>1</integer>
            </dict>
          </array>
          <key>PayloadDisplayName</key>
          <string>BolaClone Secure DNS</string>
          <key>PayloadIdentifier</key>
          <string>com.bolaclone.dns.\(safeName)</string>
          <key>PayloadRemovalDisallowed</key>
          <false/>
          <key>PayloadType</key>
          <string>Configuration</string>
          <key>PayloadUUID</key>
          <string>\(uuid)</string>
          <key>PayloadVersion</key>
          <integer>1</integer>
        </dict>
        </plist>
        """

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("BolaClone-\(safeName)-DoH.mobileconfig")
        do {
            try xml.data(using: .utf8)?.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }
}
