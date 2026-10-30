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
                        Image(systemName: g.symbol)
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

            if model.game.isLienQuan { LQModCard(model: model) }

            Button {
                if model.patchInstalled { model.removePatch() } else { model.inject() }
            } label: {
                HStack(spacing: 10) {
                    if model.busy {
                        ProgressView().tint(model.patchInstalled ? .white : .black)
                    }
                    Text(model.busy
                         ? "Đang xử lý…"
                         : (model.patchInstalled ? "UN INJECT" : "INJECT"))
                }
            }
            .buttonStyle(InjectButtonStyle(enabled: !model.busy && gate.isAuthorized,
                                           danger: model.patchInstalled))
            .disabled(model.busy)

            Text(model.patchInstalled
                 ? (model.game.isLienQuan
                    ? "Đang inject — đổi toggle ở thẻ trên rồi mở lại game"
                    : "Đang inject — bấm UN INJECT để gỡ patch")
                 : (model.game.isLienQuan
                    ? "Chỉnh Full Mod ở thẻ trên → bấm INJECT"
                    : "Chọn game → chỉnh chức năng → bấm INJECT"))
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
        NavigationLink {
            AntibanView(model: model)
        } label: {
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
                     ? "🛡️ Đã bật Anti-ban — tự dọn dấu vết + DNS shield (tắt sẽ tự gỡ patch)"
                     : "Mặc định tắt mỗi lần mở app — bật lại khi cần")
                    .font(.system(size: 11)).foregroundStyle(Theme.dim)
                if !gate.isAuthorized {
                    Text("🔑 Activate your key before enabling Anti-ban!")
                        .font(.system(size: 11)).foregroundStyle(Theme.warn)
                }
                HStack(spacing: 6) {
                    Image(systemName: "network.badge.shield.half.filled")
                        .font(.system(size: 10))
                    Text("DNS shield — preset, blocklist & chi tiết")
                        .font(.system(size: 10))
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold))
                }
                .foregroundStyle(Theme.dim)
            }
            .padding(14)
        }
        .buttonStyle(CardButtonStyle())
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

// MARK: - Full Mod AOV card (thay list gói Liên Quân)

/// Thẻ cấu hình Full Mod AOV — bật/tắt tính năng ngay trong app; giá trị ghi vào
/// PlayerPrefs của game (key iFix.*), payload đọc khi mở game.
struct LQModCard: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("FULL MOD (AOV)").font(Theme.monoFont).foregroundStyle(Theme.dim)
                Spacer()
                Button { model.syncAOVFromGame() } label: {
                    Text("Đọc từ game").font(Theme.monoFont).foregroundStyle(Theme.accent)
                }
            }

            LQToggleRow(title: "ESP xuyên tường",
                        isOn: Binding(get: { model.aovEsp }, set: { model.setAOVEsp($0) }))
            LQToggleRow(title: "Tự động BP",
                        isOn: Binding(get: { model.aovBocpha }, set: { model.setAOVBocpha($0) }))
            LQToggleRow(title: "Aim assist",
                        isOn: Binding(get: { model.aovAim }, set: { model.setAOVAim($0) }))

            if model.aovAim {
                LQSegRow(title: "AIM TARGET", options: ["HP", "PCT", "NEAR", "RAY"],
                         index: model.aovTargetMode) { model.setAOVTargetMode($0) }
                LQStepperRow(title: "AIM LINES", value: "\(model.aovLines)",
                             dec: { model.setAOVLines(model.aovLines - 1) },
                             inc: { model.setAOVLines(model.aovLines + 1) })
                LQSegRow(title: "VẼ LINE", options: ["TẮT", "LUÔN", "SKILL"],
                         index: model.aovDrawMode) { model.setAOVDrawMode($0) }
            }

            LQSegRow(title: "TRUNG TRÍ (SMITE)", options: ["TẮT", "BOSS", "BUFF", "ALL"],
                     index: model.aovSmiteMode) { model.setAOVSmiteMode($0) }
            LQStepperRow(title: "ZOOM CAMERA",
                         value: String(format: "%.1fx", model.aovZoom),
                         dec: { model.setAOVZoom(model.aovZoom - 0.1) },
                         inc: { model.setAOVZoom(model.aovZoom + 0.1) })
            LQStepperRow(title: "SKIN • HERO", value: "\(model.aovHero)",
                         dec: { model.setAOVHero(model.aovHero - 1) },
                         inc: { model.setAOVHero(model.aovHero + 1) })
            LQStepperRow(title: "SKIN • MODEL", value: "\(model.aovModel)",
                         dec: { model.setAOVModel(model.aovModel - 1) },
                         inc: { model.setAOVModel(model.aovModel + 1) })

            Text("TẮT HẲN GAME trước khi đổi — cấu hình ghi vào game, mở lại để nhận")
                .font(.system(size: 10)).foregroundStyle(Theme.warn)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.card)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.border, lineWidth: 1)))
    }
}

private struct LQToggleRow: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        HStack {
            Text(title).font(Theme.bodyFont).foregroundStyle(Theme.text)
            Spacer()
            Toggle("", isOn: $isOn).labelsHidden().tint(Theme.accent)
        }
    }
}

private struct LQSegRow: View {
    let title: String
    let options: [String]
    let index: Int
    let onPick: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.dim)
            HStack(spacing: 6) {
                ForEach(options.indices, id: \.self) { i in
                    Button { onPick(i) } label: {
                        Text(options[i])
                            .font(.system(size: 11, weight: .semibold))
                            .padding(.vertical, 5)
                            .frame(maxWidth: .infinity)
                            .background(RoundedRectangle(cornerRadius: 8)
                                .fill(i == index ? Theme.cardHi : Color.clear))
                            .overlay(RoundedRectangle(cornerRadius: 8)
                                .stroke(i == index ? Theme.accent : Theme.border, lineWidth: 1))
                            .foregroundStyle(i == index ? Theme.accent : Theme.dim)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
    }
}

private struct LQStepperRow: View {
    let title: String
    let value: String
    let dec: () -> Void
    let inc: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text(title).font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.dim)
            Spacer()
            Button { dec() } label: {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(Theme.dim)
            }
            .buttonStyle(PlainButtonStyle())
            Text(value).font(Theme.bodyFont).foregroundStyle(Theme.text)
                .frame(minWidth: 46).multilineTextAlignment(.center)
            Button { inc() } label: {
                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(Theme.accent)
            }
            .buttonStyle(PlainButtonStyle())
        }
    }
}
