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

    @Published public private(set) var enabled: Bool = false
    @Published public private(set) var busy: Bool = false
    @Published public private(set) var currentTemplate: String = ""
    @Published public private(set) var statusMessage: String = "DNS-over-HTTPS profile management."
    @Published public private(set) var lastError: String?

    public init() {}

    // MARK: - Load

    /// Đọc cấu hình hiện có trên thiết bị (gọi lúc mở màn DNS).
    public func refresh() async {
        busy = true
        defer { busy = false }
        let manager = NEDNSSettingsManager.shared()
        do {
            try await manager.loadFromPreferences()
            if let doh = manager.dnsSettings as? NEDoHResolverSettings,
               let first = doh.doHServerTemplates.first {
                enabled = true
                currentTemplate = first
                statusMessage = "DoH active: \(first)"
                lastError = nil
            } else if manager.dnsSettings != nil {
                enabled = true
                currentTemplate = "(legacy plain DNS settings)"
                statusMessage = "Legacy DNS settings present."
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
            return
        }
        busy = true
        defer { busy = false }

        let manager = NEDNSSettingsManager.shared()
        do { try await manager.loadFromPreferences() } catch { }

        let doh = NEDoHResolverSettings(servers: [])
        doh.doHServerTemplates = [template]
        manager.dnsSettings = doh

        do {
            try await manager.saveToPreferences()
            enabled = true
            currentTemplate = template
            statusMessage = "DoH installed: \(template)"
            lastError = nil
            Logger.shared.log("[DNS] installed DoH template \(template)")
        } catch {
            lastError = error.localizedDescription
            statusMessage = "Lưu profile thất bại: \(error.localizedDescription) — dùng profile tay."
            Logger.shared.log("[DNS] NE save failed: \(error.localizedDescription)")
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
            statusMessage = "DNS profile removed."
            lastError = nil
            Logger.shared.log("[DNS] profile removed")
        } catch {
            lastError = error.localizedDescription
            statusMessage = "Gỡ thất bại: \(error.localizedDescription)"
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
