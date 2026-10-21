import SwiftUI

/// SettingsView — cài đặt (bản gốc: SettingsView với header, rowsCard, row)
/// Gồm: ngôn ngữ, xoá cache, console log ("tserver terminal"), thông tin app, gỡ patch.
public struct SettingsView: View {

    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    public init(model: AppModel) { self.model = model }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    header
                    rowsCard
                    consoleCard
                    about
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .background(BolaBackground())
            .navigationTitle("Cài đặt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Xong") { dismiss() }.foregroundStyle(Theme.accent)
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Thông Tin Ứng Dụng").font(Theme.titleFont).foregroundStyle(Theme.text)
            Text("Phiên bản • thiết bị: \(VersionGate.appVersion) • \(model.device.summary)")
                .font(Theme.monoFont).foregroundStyle(Theme.dim)
            Text("Hệ điều hành: \(model.device.systemName) \(model.device.systemVersion)")
                .font(Theme.monoFont).foregroundStyle(Theme.dim)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
    }

    private var rowsCard: some View {
        VStack(spacing: 0) {
            row("Ngôn ngữ", value: model.language.display) {
                model.setLanguage(model.language == .vi ? .en : .vi)
            }
            divider
            row("Xoá Bộ Nhớ Đệm", value: "File tạm trong app") {
                model.clearCache()
            }
            divider
            row("Un-inject — gỡ patch khỏi game", value: model.patchInstalled ? "Đã cài đặt" : "Chưa có gì để gỡ.") {
                model.removePatch()
            }
            divider
            row("Xuất file patch (thủ công)", value: "Cho Filza / không cần quyền container") {
                model.exportPatchFiles()
            }
            divider
            row("Đổi key khác", value: model.keyMaskedName.isEmpty ? "Chưa có key" : model.keyMaskedName) {
                model.gate.deactivate()
                dismiss()
            }
            divider
            row("Làm mới thiết bị", value: model.game.name) {
                model.refreshDetected()
            }
        }
        .background(RoundedRectangle(cornerRadius: 16).fill(Theme.card)
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.border, lineWidth: 1)))
    }

    private var divider: some View {
        Rectangle().fill(Theme.border).frame(height: 1).padding(.leading, 14)
    }

    private func row(_ title: String, value: String, action: @escaping () -> Void) -> some View {
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

    /// Console — bản gốc hiện log kiểu "tserver terminal: …"
    private var consoleCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("tserver terminal").font(Theme.monoFont).foregroundStyle(Theme.accent)
                Spacer()
                Button("Xoá") {
                    Logger.shared.clear()
                    model.log("")
                }
                    .font(Theme.monoFont).foregroundStyle(Theme.dim)
            }
            ScrollView {
                Text(model.logText.isEmpty ? "—" : model.logText)
                    .font(Theme.monoFont)
                    .foregroundStyle(Theme.dim)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(height: 190)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.black.opacity(0.55))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.border, lineWidth: 1)))
    }

    private var about: some View {
        VStack(alignment: .leading, spacing: 6) {
            let brand = AppBrand.fromBundle()
            Text("Hỗ trợ • thông báo • cập nhật mới")
                .font(Theme.headFont).foregroundStyle(Theme.text)
            if let url = brand.telegram {
                Link(url.absoluteString, destination: url)
                    .font(Theme.monoFont).foregroundStyle(Theme.accent)
            }
            Text("\(brand.displayName) — menu trong game cho Free Fire iOS.")
                .font(.system(size: 10)).foregroundStyle(Theme.dim)
            Text("Tác giả: \(brand.author)")
                .font(.system(size: 10)).foregroundStyle(Theme.dim)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.card)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.border, lineWidth: 1)))
    }
}
