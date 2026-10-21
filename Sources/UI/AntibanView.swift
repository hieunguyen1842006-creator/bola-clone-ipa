import SwiftUI
import UniformTypeIdentifiers
import UIKit

/// AntibanView — tab Anti-ban: toggle dọn dấu vết (Antiban engine) + DNS shield
/// (DoH blocklist port từ FFDNSViewController, Fl0rkFF clone).
/// Bật Anti-ban = cài DNS blocklist luôn; tắt = gỡ DNS profile.
public struct AntibanView: View {

    @ObservedObject public var model: AppModel
    @StateObject private var dns = DNSManager()
    @State private var selectedPreset: DNSManager.Preset = DNSManager.presets[0]
    @State private var customTemplate: String = ""
    @State private var shareURL: URL?
    @State private var showImporter = false
    @State private var importFailed = false
    @State private var copied = false
    @Environment(\.dismiss) private var dismiss

    public init(model: AppModel) { self.model = model }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    antibanToggleCard
                    statusCard
                    presetsCard
                    customCard
                    controlsCard
                    antibanCard
                    manualCard
                    footer
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .background(BolaBackground())
            .navigationTitle("Anti-ban")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Xong") { dismiss() }.foregroundStyle(Theme.accent)
                }
            }
            .task { await dns.refresh() }
        }
    }

    /// Toggle Anti-ban chính — bật/tắt dọn dấu vết + DNS shield cùng lúc.
    private var antibanToggleCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("🛡️ Anti-ban").font(Theme.headFont).foregroundStyle(Theme.text)
                Spacer()
                Toggle("", isOn: Binding(get: { model.antiban },
                                         set: { model.setAntiban($0) }))
                    .labelsHidden()
                    .tint(Theme.accent)
            }
            Text(model.antiban
                 ? "Đã bật — tự dọn dấu vết + DNS shield chặn telemetry/anti-cheat (tắt sẽ tự gỡ)"
                 : "Bật để tự dọn dấu vết và cài DNS blocklist chặn domain anti-cheat")
                .font(.system(size: 11)).foregroundStyle(Theme.dim)
            if !model.gate.isAuthorized {
                Text("🔑 Activate your key before enabling Anti-ban!")
                    .font(.system(size: 11)).foregroundStyle(Theme.warn)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16).fill(Theme.card)
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.border, lineWidth: 1)))
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: dns.enabled ? "checkmark.shield.fill" : "shield.slash")
                    .foregroundStyle(dns.enabled ? Color.green : Theme.dim)
                Text(dns.enabled ? "Đang bật — \(dns.currentTemplate)" : "Chưa cài DNS profile")
                    .font(Theme.bodyFont).foregroundStyle(Theme.text)
                Spacer()
                if dns.busy { ProgressView() }
            }
            Text(dns.lastError ?? dns.statusMessage)
                .font(Theme.monoFont).foregroundStyle(Theme.dim)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16).fill(Theme.card)
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.border, lineWidth: 1)))
    }

    private var presetsCard: some View {
        VStack(spacing: 0) {
            ForEach(DNSManager.presets) { preset in
                Button {
                    selectedPreset = preset
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(preset.name).font(Theme.bodyFont).foregroundStyle(Theme.text)
                            Text(preset.note).font(Theme.monoFont).foregroundStyle(Theme.dim)
                        }
                        Spacer()
                        Image(systemName: selectedPreset == preset ? "largecircle.fill.circle" : "circle")
                            .foregroundStyle(Theme.accent)
                    }
                    .padding(14)
                }
                .buttonStyle(RowButtonStyle())
                if preset.id != DNSManager.presets.last?.id {
                    Rectangle().fill(Theme.border).frame(height: 1).padding(.leading, 14)
                }
            }
        }
        .background(RoundedRectangle(cornerRadius: 16).fill(Theme.card)
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.border, lineWidth: 1)))
    }

    private var customCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Custom DoH template (tuỳ chọn)")
                .font(Theme.bodyFont).foregroundStyle(Theme.text)
            TextField("https://dns.nextdns.io/xxxxxx", text: $customTemplate)
                .font(Theme.monoFont)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.35))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border, lineWidth: 1)))
            Text("Bỏ trống → dùng template của preset đang chọn.")
                .font(.system(size: 10)).foregroundStyle(Theme.dim)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16).fill(Theme.card)
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.border, lineWidth: 1)))
    }

    private var controlsCard: some View {
        VStack(spacing: 0) {
            rowButton("Cài / cập nhật DoH", value: "NEDNSSettingsManager") {
                Task { await dns.install(preset: selectedPreset, customTemplate: customTemplate) }
            }
            Rectangle().fill(Theme.border).frame(height: 1).padding(.leading, 14)
            rowButton("Gỡ DNS profile", value: "Về DNS hệ thống") {
                Task { await dns.remove() }
            }
        }
        .background(RoundedRectangle(cornerRadius: 16).fill(Theme.card)
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.border, lineWidth: 1)))
    }

    /// Card Antiban: blocklist từ antiban-nvh.json → denylist cho resolver có lọc.
    private var antibanCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Antiban blocklist").font(Theme.bodyFont).foregroundStyle(Theme.text)
                Spacer()
                Toggle("", isOn: $dns.antibanOn).labelsHidden()
            }
            ForEach(dns.antibanRules) { rule in
                VStack(alignment: .leading, spacing: 2) {
                    Text(rule.enabled ? rule.name : "\(rule.name) (off)")
                        .font(Theme.monoFont).foregroundStyle(rule.enabled ? Theme.text : Theme.dim)
                    Text(rule.note).font(.system(size: 9)).foregroundStyle(Theme.dim)
                }
            }
            let domains = dns.antibanDomains
            if !domains.isEmpty {
                Text(domains.joined(separator: "  ·  "))
                    .font(Theme.monoFont).foregroundStyle(Theme.accent)
            }
            Text("Regex trong JSON được biên dịch thành denylist domain gốc. Dán denylist vào NextDNS/AdGuard dashboard rồi trỏ DoH về đó (ô Custom). Telemetry còn bị chặn sẵn khi dùng preset AdGuard (ads block). Phần script rewrite trong JSON là của proxy engine — tầng DNS không chạy JS.")
                .font(.system(size: 10)).foregroundStyle(Theme.dim)
            HStack(spacing: 16) {
                Button {
                    UIPasteboard.general.string = DNSBlocklist.denylistADG(dns.antibanDomains)
                    copied = true
                } label: {
                    Label(copied ? "Đã copy" : "Copy ||domain^", systemImage: "doc.on.doc")
                        .font(Theme.bodyFont).foregroundStyle(Theme.accent)
                }
                .buttonStyle(.plain)
                .disabled(domains.isEmpty)

                Button {
                    importFailed = false
                    showImporter = true
                } label: {
                    Label("Nhập JSON khác", systemImage: "square.and.arrow.down")
                        .font(Theme.bodyFont).foregroundStyle(Theme.accent)
                }
                .buttonStyle(.plain)

                if importFailed {
                    Text("JSON lỗi").font(Theme.monoFont).foregroundStyle(.red)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16).fill(Theme.card)
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.border, lineWidth: 1)))
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json, .data]) { result in
            if case .success(let url) = result {
                let scoped = url.startAccessingSecurityScopedResource()
                importFailed = !dns.loadAntiban(from: url)
                if scoped { url.stopAccessingSecurityScopedResource() }
            }
        }
    }

    /// Fallback khi thiếu entitlement: sinh .mobileconfig, user tự cài.
    private var manualCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Profile tay (khi NE bị chặn)")
                .font(Theme.bodyFont).foregroundStyle(Theme.text)
            Text("Sinh file .mobileconfig → mở trong Safari/Files → Settings cài profile.")
                .font(Theme.monoFont).foregroundStyle(Theme.dim)
            if let url = shareURL {
                ShareLink(item: url) {
                    Label("Chia sẻ profile .mobileconfig", systemImage: "square.and.arrow.up")
                        .font(Theme.bodyFont).foregroundStyle(Theme.accent)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16).fill(Theme.card)
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.border, lineWidth: 1)))
    }

    private var footer: some View {
        Text("Install or update secure DNS settings.")
            .font(.system(size: 10)).foregroundStyle(Theme.dim)
            .frame(maxWidth: .infinity, alignment: .center)
    }

    private func rowButton(_ title: String, value: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(Theme.bodyFont).foregroundStyle(Theme.text)
                    Text(value).font(Theme.monoFont).foregroundStyle(Theme.dim)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.border)
            }
            .padding(14)
        }
        .buttonStyle(RowButtonStyle())
    }
}
