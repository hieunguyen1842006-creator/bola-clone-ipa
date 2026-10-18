import SwiftUI

/// HomeView — màn chính (bản gốc: HomeView với hero, heroStat, gameList, detectPill,
/// keyBar, antibanCard, resetGuestCard, telegramCard, hint, refreshDetected)
public struct HomeView: View {

    @ObservedObject var model: AppModel
    @ObservedObject var gate: LicenseGate
    @Binding var showSettings: Bool
    @Binding var showLanguage: Bool
    @State private var appeared = false

    public init(model: AppModel, gate: LicenseGate,
                showSettings: Binding<Bool>, showLanguage: Binding<Bool>) {
        self.model = model
        self.gate = gate
        self._showSettings = showSettings
        self._showLanguage = showLanguage
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                hero
                detectPill
                gameList
                injectArea
                keyBar
                antibanCard
                resetGuestCard
                telegramCard
                hint
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 28)
        }
        .background(BolaBackground())
        .navigationTitle("")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { showSettings = true } label: {
                    Image(systemName: "gearshape.fill").foregroundStyle(Theme.dim)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showLanguage = true } label: {
                    Text(model.language.flag).font(.system(size: 17))
                }
            }
        }
        .sheet(isPresented: $showLanguage) { LanguageOverlay(model: model) }
        .onAppear {
            model.bootstrap()
            withAnimation(.easeOut(duration: 0.35)) { appeared = true }
        }
    }

    // MARK: hero

    private var hero: some View {
        VStack(spacing: 8) {
            Text("TRỢ LÝ TRONG GAME")
                .font(Theme.monoFont).foregroundStyle(Theme.dim)
            Text(AppBrand.fromBundle().displayName)
                .font(.system(size: 26, weight: .black, design: .rounded))
                .foregroundStyle(Theme.text)
            HStack(spacing: 10) {
                heroStat(title: "PHIÊN BẢN", value: VersionGate.appVersion)
                heroStat(title: "HỆ ĐIỀU HÀNH", value: model.device.systemName + " " + model.device.systemVersion)
                heroStat(title: "KEY", value: model.keyMaskedName.isEmpty ? "—" : model.keyMaskedName)
            }
            statusRow
        }
        .padding(.vertical, 18)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(LinearGradient(colors: [Theme.cardHi, Theme.card],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Theme.border, lineWidth: 1))
        )
        .padding(.top, 6)
    }

    private func heroStat(title: String, value: String) -> some View {
        VStack(spacing: 3) {
            Text(title).font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.dim)
            Text(value).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.text)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }

    private var statusRow: some View {
        HStack(spacing: 8) {
            StatusDot(tone: model.phase.dotColor)
            Text(model.statusText).font(Theme.bodyFont).foregroundStyle(Theme.dim)
        }
    }

    // MARK: detect

    private var detectPill: some View {
        HStack(spacing: 8) {
            StatusDot(tone: model.installedInfo[model.game] == true ? .ok : .bad)
            Text(model.installedInfo[model.game] == true ? "Đã phát hiện \(model.game.name)"
                 : "Không thấy \(model.game.name)")
                .font(Theme.bodyFont).foregroundStyle(Theme.text)
            Spacer()
            Button("Làm mới") { model.refreshDetected() }
                .font(Theme.monoFont).foregroundStyle(Theme.accent)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.card)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.border, lineWidth: 1)))
    }

    // MARK: game list

    private var gameList: some View {
        VStack(spacing: 10) {
            ForEach(GameTarget.allCases) { g in
                Button { model.game = g } label: {
                    HStack(spacing: 12) {
                        Image(systemName: g == .freefireMAX ? "flame.fill" : "flame")
                            .font(.system(size: 20))
                            .foregroundStyle(model.game == g ? Theme.accent : Theme.dim)
                            .frame(width: 34)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(g.name).font(Theme.headFont).foregroundStyle(Theme.text)
                            Text(g.bundleID).font(Theme.monoFont).foregroundStyle(Theme.dim)
                        }
                        Spacer()
                        if model.installedInfo[g] == true {
                            Text("Đã cài").font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Theme.accent)
                        } else {
                            Text("Chưa cài đặt").font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Theme.dim)
                        }
                        Image(systemName: model.game == g ? "largecircle.fill.circle" : "circle")
                            .foregroundStyle(model.game == g ? Theme.accent : Theme.border)
                    }
                    .padding(14)
                }
                .buttonStyle(CardButtonStyle())
            }
        }
    }

    // MARK: inject

    private var injectArea: some View {
        VStack(spacing: 10) {
            NavigationLink {
                ConfigView(model: model, gate: gate)
            } label: {
                HStack {
                    Image(systemName: "slider.horizontal.3")
                    Text("Chỉnh chức năng").font(Theme.headFont)
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold))
                }
                .foregroundStyle(Theme.text)
                .padding(14)
            }
            .buttonStyle(CardButtonStyle())

            Button { model.inject() } label: {
                HStack(spacing: 10) {
                    if model.busy { ProgressView().tint(.black) }
                    Text(model.busy ? "Đang inject…" : "INJECT")
                }
            }
            .buttonStyle(InjectButtonStyle(enabled: !model.busy && gate.isAuthorized))
            .disabled(model.busy)

            if model.patchInstalled {
                Button("Gỡ patch khỏi game") { model.removePatch() }
                    .font(Theme.bodyFont).foregroundStyle(Theme.danger)
            }
            Text("Chọn game → chỉnh chức năng → bấm INJECT")
                .font(Theme.monoFont).foregroundStyle(Theme.dim)
        }
    }

    // MARK: key bar

    private var keyBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "key.fill").foregroundStyle(Theme.gold)
            VStack(alignment: .leading, spacing: 2) {
                Text(model.keyMaskedName.isEmpty ? "Chưa kích hoạt" : model.keyMaskedName)
                    .font(Theme.bodyFont).foregroundStyle(Theme.text)
                Text(model.keyHoursLeft > 0 ? "Còn \(model.keyHoursLeft)h" : gate.remainingText)
                    .font(Theme.monoFont).foregroundStyle(Theme.dim)
            }
            Spacer()
            Button("Đổi key") { model.gate.deactivate() }
                .font(Theme.monoFont).foregroundStyle(Theme.accent)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.card)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.border, lineWidth: 1)))
    }

    // MARK: anti-ban

    private var antibanCard: some View {
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
                 ? "🛡️ Đã bật Anti-ban — tự dọn dấu vết liên tục (tắt sẽ tự gỡ patch)"
                 : "Mặc định tắt mỗi lần mở app — bật lại khi cần")
                .font(.system(size: 11)).foregroundStyle(Theme.dim)
            if !gate.isAuthorized {
                Text("🔑 Activate your key before enabling Anti-ban!")
                    .font(.system(size: 11)).foregroundStyle(Theme.warn)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.card)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.border, lineWidth: 1)))
    }

    // MARK: reset guest

    private var resetGuestCard: some View {
        Button { model.resetGuest() } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text("🧹 Xoá định danh khách").font(Theme.headFont).foregroundStyle(Theme.text)
                Text("Xoá định danh khách — mở game tạo guest mới (tắt hẳn game trước!)")
                    .font(.system(size: 11)).foregroundStyle(Theme.dim)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
        }
        .buttonStyle(CardButtonStyle())
    }

    // MARK: telegram

    private var telegramCard: some View {
        Group {
            if let url = AppBrand.fromBundle().telegram {
                Link(destination: url) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Hỗ trợ • thông báo • cập nhật mới")
                            .font(Theme.headFont).foregroundStyle(Theme.text)
                        Text(url.absoluteString).font(Theme.monoFont).foregroundStyle(Theme.accent)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                }
                .buttonStyle(CardButtonStyle())
            }
        }
    }

    private var hint: some View {
        Text("Phiên bản • thiết bị\n\(VersionGate.appVersion) • \(model.device.summary)")
            .font(Theme.monoFont)
            .foregroundStyle(Theme.dim)
            .multilineTextAlignment(.center)
            .padding(.top, 6)
    }
}
