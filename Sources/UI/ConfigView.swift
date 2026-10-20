import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// ConfigView — màn chỉnh chức năng (bản gốc: ConfigView với header, tabContent, segment,
/// aimCard, miscCard, bonePill, boneSection, toggleRowInline, toggleRowBadge, warningCard,
/// colorFeatureCard, colorPickerOverlay, colorTitle, statusColor, injectArea)
public struct ConfigView: View {

    @ObservedObject var model: AppModel
    @ObservedObject var gate: LicenseGate

    @State private var tab: FeatureTab = .esp
    @State private var colorPickKey: String?
    @State private var hue: Double = 0.35
    @State private var sat: Double = 1
    @State private var val: Double = 1

    public init(model: AppModel, gate: LicenseGate) {
        self.model = model
        self.gate = gate
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                header
                if model.game.isLienQuan {
                    lqContent
                } else {
                    segment
                    tabContent
                    warningCard
                }
                injectArea
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 30)
        }
        .background(BolaBackground())
        .overlay { colorPickerOverlay }
    }

    // MARK: header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Chỉnh chức năng & INJECT")
                .font(Theme.titleFont).foregroundStyle(Theme.text)
            HStack(spacing: 8) {
                StatusDot(tone: model.installedInfo[model.game] == true ? .ok : .bad)
                Text(model.game.name).font(Theme.bodyFont).foregroundStyle(Theme.dim)
                Text("•").foregroundStyle(Theme.border)
                Text(gate.isAuthorized ? "Key hợp lệ" : "Chưa kích hoạt")
                    .font(Theme.bodyFont)
                    .foregroundStyle(gate.isAuthorized ? Theme.accent : Theme.danger)
            }
            Text(model.patchInstalled ? "Đã inject cho \(model.game.name)"
                                      : "Chưa inject cho \(model.game.name)")
                .font(Theme.monoFont)
                .foregroundStyle(model.patchInstalled ? Theme.accent : Theme.dim)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
    }

    private var segment: some View {
        HStack(spacing: 6) {
            ForEach(FeatureTab.allCases) { t in
                Button { tab = t } label: {
                    HStack(spacing: 6) {
                        Image(systemName: t.symbol).font(.system(size: 12, weight: .bold))
                        Text(t.vi)
                    }
                }
                .buttonStyle(SegmentButtonStyle(selected: tab == t))
            }
        }
        .padding(5)
        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.card)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.border, lineWidth: 1)))
    }

    @ViewBuilder
    private var tabContent: some View {
        switch tab {
        case .esp: espTab
        case .aim: aimTab
        case .misc: miscTab
        }
    }

    // MARK: ESP

    private var espTab: some View {
        VStack(spacing: 12) {
            card("Khung & thông tin") {
                colorFeatureRow("box", "Khung quanh người & bot")
                colorFeatureRow("line", "Đường kẻ từ tâm ngắm")
                colorFeatureRow("bone", "Khung xương người (skeleton)")
            }
            card("Hiển thị") {
                toggleRowInline("hp", "Máu", "Thanh HP cho người & bot")
                toggleRowInline("name", "Tên", "Tên người chơi / bot")
                toggleRowInline("dist", "Khoảng cách", "Khoảng cách tới mục tiêu")
                toggleRowInline("bot", "Bot", "Hiện cả bot (AI)")
                toggleRowInline("count", "Đếm địch", "Số địch + bot ở trên màn hình")
                toggleRowInline("team", "ESP đội", "Hiện đồng đội (màu xanh)")
                sliderRow("Độ dày ESP",
                          value: Binding(get: { model.espThick },
                                         set: { model.setEspThick($0) }),
                          range: 50...200, unit: "%")
            }
        }
    }

    // MARK: AIM

    private var aimTab: some View {
        VStack(spacing: 12) {
            card("Aim") {
                toggleRowInline("aim", "Aimbot", "Khoá địch gần tâm ngắm nhất")
                toggleRowInline("silent", "Aim Silent", "Bắn lệch vẫn bay vào bone đã chọn")

                if model.cfgFlags.contains("aim") || model.cfgFlags.contains("silent") {
                    toggleRowInline("wallcheck", "Check tường",
                                    "Bỏ qua địch sau tường — chỉ khoá khi thấy rõ")
                    boneSection

                    if model.aimBone == .head {
                        sliderRow("Tỉ lệ vào đầu",
                                  value: Binding(get: { model.headRate },
                                                 set: { model.setHeadRate($0) }),
                                  range: 10...100, unit: "%")
                        toggleRowInline("draghead", "Drag Head",
                                        "Bấm bắn = bắn thân, kéo tâm = auto khoá đầu")
                    }

                    // Một thanh FOV + một nút vòng FOV dùng chung cho cả 2 chế độ.
                    sliderRow("FOV",
                              value: Binding(get: { model.activeFov },
                                             set: { model.setFov($0) }),
                              range: 5...100, unit: "%")
                    toggleRowInline("showfov", "Hiện vòng FOV",
                                    "Vẽ vòng FOV của chế độ đang bật lên màn hình")

                    if model.cfgFlags.contains("silent") {
                        toggleRowInline("skipknock", "Bỏ qua gục",
                                        "Không bắn vào địch đã bị hạ gục")
                    }
                }
            }
        }
    }

    private var boneSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Vị trí khoá").font(Theme.bodyFont).foregroundStyle(Theme.text)
            HStack(spacing: 8) {
                ForEach(BolaConfig.Bone.allCases, id: \.rawValue) { b in
                    Button { model.setBone(b) } label: {
                        Text(b.vi).font(Theme.bodyFont)
                            .foregroundStyle(model.aimBone == b ? Color.black : Theme.dim)
                            .frame(maxWidth: .infinity).padding(.vertical, 8)
                            .background(RoundedRectangle(cornerRadius: 10)
                                .fill(model.aimBone == b ? Theme.accent : Theme.cardHi))
                    }
                    .buttonStyle(RowButtonStyle())
                }
            }
        }
    }

    // MARK: MISC

    private var miscTab: some View {
        VStack(spacing: 12) {
            card("Vũ khí") {
                toggleRowInline("straight", "Đạn thẳng (No Recoil 0%)",
                                "Triệt tiêu độ tỏa đạn — đạn bay thẳng tắp")
                toggleRowInline("fastfire", "Bắn Siêu Tốc (Fast Fire)",
                                "Tăng tốc độ nhả đạn của súng liên thanh")
                toggleRowInline("fastswap", "Đổi Súng Nhanh",
                                "Triệt tiêu delay đổi súng, bắn liền tục")
                toggleRowInline("fps144", "Mở Khóa 144 FPS",
                                "Mở khoá tần số quét, hình ảnh siêu mượt")
            }
            card("Di chuyển") {
                toggleRowInline("speedrun", "Chạy Nhanh x3 (Speed Run)",
                                "Di chuyển thần tốc, né đạn & lướt nhanh")
                toggleRowInline("highjump", "Nhảy Cao (High Jump)",
                                "Nhảy cao 1.2x vượt tường kẹo, leo nóc nhà")
                toggleRowInline("backjump", "BACKJUMP",
                                "Khử gia tốc rơi, nhảy giật lùi né đạn")
                toggleRowInline("emote", "Điệu Nhảy Booyah",
                                "Kích hoạt nhảy Booyah & Carnival liên tục")
            }
            card("Hiển thị") {
                toggleRowInline("camwide", "Góc Nhìn Rộng (Cam Xa)",
                                "Mở rộng góc quan sát toàn cảnh chiến trường")
                if model.cfgFlags.contains("camwide") {
                    sliderRow("Khoảng Cách Cam (FOV)",
                              value: Binding(get: { model.camFov },
                                             set: { model.setCamFov($0) }),
                              range: 50...130, unit: "°")
                }
                toggleRowInline("autolaunch", "Tự mở game sau khi inject",
                                "Đã inject — đang mở game")
            }
        }
    }

    // MARK: widgets

    private func card<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(Theme.headFont).foregroundStyle(Theme.text)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16).fill(Theme.card)
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.border, lineWidth: 1)))
    }

    /// toggleRowInline — tên + mô tả + switch (setFlag để ghi config ngay)
    private func toggleRowInline(_ key: String, _ title: String, _ subtitle: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(Theme.bodyFont).foregroundStyle(Theme.text)
                Text(subtitle).font(.system(size: 10)).foregroundStyle(Theme.dim)
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { model.cfgFlags.contains(key) },
                set: { on in model.setFlag(key, on) }))
            .labelsHidden()
            .tint(Theme.accent)
        }
    }

    private func sliderRow(_ title: String, value: Binding<Double>,
                           range: ClosedRange<Double>, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(Theme.bodyFont).foregroundStyle(Theme.text)
                Spacer()
                // Không dùng "%s" với String của Swift — đó là crash EXC_BAD_ACCESS.
                let fmt = range.upperBound <= 1 ? "%.3f" : "%.0f"
                Text(String(format: fmt, value.wrappedValue) + unit)
                    .font(Theme.monoFont).foregroundStyle(Theme.accent)
            }
            Slider(value: value, in: range).tint(Theme.accent)
        }
    }

    /// Một dòng feature có màu: toggle + nút chọn màu (chỉ hiện khi bật).
    private func colorFeatureRow(_ key: String, _ title: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Text(title).font(Theme.bodyFont).foregroundStyle(Theme.text)
                Spacer()
                Toggle("", isOn: Binding(
                    get: { model.cfgFlags.contains(key) },
                    set: { on in model.setFlag(key, on) }))
                .labelsHidden()
                .tint(Theme.accent)
            }
            if model.cfgFlags.contains(key) {
                Button {
                    colorPickKey = key
                    let ui = UIColor(color565(model.featureRGB[key] ?? 0))
                    var h: CGFloat = 0, s: CGFloat = 0, v: CGFloat = 0, a: CGFloat = 0
                    ui.getHue(&h, saturation: &s, brightness: &v, alpha: &a)
                    hue = Double(h); sat = Double(s); val = Double(v)
                } label: {
                    HStack(spacing: 8) {
                        Text("Màu hiển thị").font(.system(size: 12)).foregroundStyle(Theme.dim)
                        Spacer()
                        Circle()
                            .fill(color565(model.featureRGB[key] ?? 0))
                            .frame(width: 16, height: 16)
                            .overlay(Circle().stroke(Theme.border, lineWidth: 1))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.dim)
                    }
                }
                .buttonStyle(RowButtonStyle())
            }
        }
    }

    private func color565(_ v: UInt16) -> Color {
        let (r, g, b) = Pack565.unpack(v)
        return Color(.sRGB, red: Double(r) / 255, green: Double(g) / 255,
                     blue: Double(b) / 255, opacity: 1)
    }

    private func colorTitle(_ key: String) -> String {
        switch key {
        case "box": return "Màu Box"
        case "line": return "Màu Line"
        case "bone": return "Màu Bone"
        default: return key
        }
    }

    // MARK: LQ

    /// Liên Quân dùng hotfix payload đóng sẵn — chọn gói thay vì bật/tắt từng tính năng.
    private var lqContent: some View {
        VStack(spacing: 12) {
            card("Gói hotfix") {
                ForEach(LQPack.allCases) { p in
                    Button { model.setLQPack(p) } label: {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: p.symbol)
                                .foregroundStyle(model.lqPack == p ? Theme.accent : Theme.dim)
                                .frame(width: 22)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(p.title).font(Theme.bodyFont).foregroundStyle(Theme.text)
                                Text(p.subtitle).font(.system(size: 10))
                                    .foregroundStyle(Theme.dim)
                            }
                            Spacer()
                            Image(systemName: model.lqPack == p
                                  ? "largecircle.fill.circle" : "circle")
                                .foregroundStyle(model.lqPack == p ? Theme.accent : Theme.border)
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(RowButtonStyle())
                }
            }
            card("Đích ghi") {
                Text("Documents/Resources/<ver>/Thanos/HeroSkin_2.bytes")
                    .font(Theme.monoFont).foregroundStyle(Theme.dim)
                Text("Gói đôi ghi thêm HeroSkin_1.bytes cùng thư mục.")
                    .font(.system(size: 11)).foregroundStyle(Theme.dim)
                Text("UN INJECT sẽ khôi phục bản gốc đã backup trong app.")
                    .font(.system(size: 11)).foregroundStyle(Theme.dim)
            }
            card("Tuỳ chọn") {
                toggleRowInline("autolaunch", "Tự mở game sau khi inject",
                                "Inject xong tự tắt game cũ và mở lại")
            }
            card("Lưu ý") {
                Text("Payload LQ là gói đóng sẵn (HUD/skin), không có file cfg runtime như Free Fire. "
                     + "App chọn gói rồi ghi — muốn thêm toggle từng tính năng thì phải build payload mới.")
                    .font(.system(size: 11)).foregroundStyle(Theme.dim)
            }
        }
    }

    // MARK: warning + inject

    private var warningCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("CẢNH BÁO NGUY HIỂM:").font(Theme.headFont).foregroundStyle(Theme.warn)
            Text("Bật Đạn Thẳng can thiệp triệt tiêu độ tỏa đạn. Máy chủ có thể từ chối tính sát thương "
                 + "khi xả đạn liên tục dẫn tới SÁT THƯƠNG ẢO / LỖI DAME (bắn trúng địch nhưng không mất máu). "
                 + "Khuyên dùng cẩn trọng!")
                .font(.system(size: 11)).foregroundStyle(Theme.dim)
            Text("Tốc độ quá cao gây lệch tọa độ giữa máy bạn và server (Desync). Khi vừa chạy vừa xả đạn, "
                 + "server có thể TỪ CHỐI TÍNH SÁT THƯƠNG — đạn trúng địch nhưng không mất máu. Dùng cẩn trọng!")
                .font(.system(size: 11)).foregroundStyle(Theme.dim)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.warn.opacity(0.08))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.warn.opacity(0.4), lineWidth: 1)))
    }

    private var injectArea: some View {
        VStack(spacing: 8) {
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

            if !model.game.isLienQuan {
                Button { model.writeConfig() } label: {
                    Text("Lưu cấu hình (không cần inject lại)")
                        .font(Theme.bodyFont)
                }
                .foregroundStyle(model.patchInstalled ? Theme.accent : Theme.dim)
                .disabled(!model.patchInstalled)
            }

            Text(model.game.isLienQuan
                 ? "Gói LQ đã đóng sẵn — bấm INJECT để ghi vào game"
                 : "Mặc định tắt mỗi lần mở app — bật lại khi cần")
                .font(Theme.monoFont).foregroundStyle(Theme.dim)
        }
    }

    // MARK: color picker overlay

    @ViewBuilder
    private var colorPickerOverlay: some View {
        if let key = colorPickKey {
            CustomColorPickerPanel(
                title: colorTitle(key),
                hue: $hue, sat: $sat, val: $val,
                onChange: { color in
                    model.featureRGB[key] = color.rgb565
                },
                onClose: { colorPickKey = nil })
        }
    }
}

/// CustomColorPickerPanel — picker HSV tự vẽ (bản gốc: gradientSlider, hex, hsvToRGB,
/// rgbToHSV, presets, onChange, onClose)
public struct CustomColorPickerPanel: View {

    public var title: String
    @Binding public var hue: Double
    @Binding public var sat: Double
    @Binding public var val: Double
    public var onChange: (Color) -> Void
    public var onClose: () -> Void

    @State private var hexText: String = ""

    public static let presets: [Color] = [
        Color(hex: 0xFF4040), Color(hex: 0x40FF80), Color(hex: 0x40A0FF),
        Color(hex: 0xFFD24B), Color(hex: 0xFF40FF), Color(hex: 0xFFFFFF),
    ]

    public init(title: String, hue: Binding<Double>, sat: Binding<Double>, val: Binding<Double>,
                onChange: @escaping (Color) -> Void, onClose: @escaping () -> Void) {
        self.title = title
        self._hue = hue
        self._sat = sat
        self._val = val
        self.onChange = onChange
        self.onClose = onClose
    }

    private var currentColor: Color { Color(hue: hue, saturation: sat, brightness: val) }

    public var body: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
                .onTapGesture { onClose() }
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(title).font(Theme.headFont).foregroundStyle(Theme.text)
                    Spacer()
                    Button("Xong") { onChange(currentColor); onClose() }
                        .font(Theme.bodyFont).foregroundStyle(Theme.accent)
                }

                RoundedRectangle(cornerRadius: 12).fill(currentColor)
                    .frame(height: 46)
                    .overlay(RoundedRectangle(cornerRadius: 12)
                        .stroke(Theme.border, lineWidth: 1))

                gradientSlider(hue: $hue, sat: $sat, val: $val)
                slider("H", $hue, 0...1)
                slider("S", $sat, 0...1)
                slider("V", $val, 0...1)

                HStack(spacing: 8) {
                    ForEach(Array(CustomColorPickerPanel.presets.enumerated()), id: \.offset) { _, c in
                        Button { apply(c) } label: {
                            RoundedRectangle(cornerRadius: 8).fill(c)
                                .frame(height: 26)
                                .overlay(RoundedRectangle(cornerRadius: 8)
                                    .stroke(Theme.border, lineWidth: 1))
                        }
                        .buttonStyle(RowButtonStyle())
                    }
                }
            }
            .padding(18)
            .background(RoundedRectangle(cornerRadius: 20).fill(Theme.bgTop)
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(Theme.border, lineWidth: 1)))
            .padding(22)
        }
    }

    /// gradient HSV (bản gốc: gradientSlider)
    private func gradientSlider(hue: Binding<Double>, sat: Binding<Double>,
                                val: Binding<Double>) -> some View {
        GeometryReader { geo in
            let steps = 24
            HStack(spacing: 0) {
                ForEach(0..<steps, id: \.self) { i in
                    Color(hue: Double(i) / Double(steps), saturation: 1, brightness: 1)
                }
            }
            .frame(height: 30)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .gesture(DragGesture(minimumDistance: 0).onChanged { g in
                let f = max(0, min(1, g.location.x / geo.size.width))
                hue.wrappedValue = f
            })
        }
        .frame(height: 30)
    }

    private func slider(_ label: String, _ value: Binding<Double>, _ range: ClosedRange<Double>) -> some View {
        HStack(spacing: 8) {
            Text(label).font(Theme.monoFont).foregroundStyle(Theme.dim).frame(width: 14)
            Slider(value: value, in: range).tint(Theme.accent)
        }
    }

    private func apply(_ c: Color) {
        let ui = UIColor(c)
        var h: CGFloat = 0, s: CGFloat = 0, v: CGFloat = 0, a: CGFloat = 0
        ui.getHue(&h, saturation: &s, brightness: &v, alpha: &a)
        hue = Double(h); sat = Double(s); val = Double(v)
        onChange(c)
    }

    /// hex ⇄ color (bản gốc có field `hex`)
    public static func hex(_ c: Color) -> String {
        let ui = UIColor(c)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
    }

    public static func rgbToHSV(_ c: Color) -> (h: Double, s: Double, v: Double) {
        let ui = UIColor(c)
        var h: CGFloat = 0, s: CGFloat = 0, v: CGFloat = 0, a: CGFloat = 0
        ui.getHue(&h, saturation: &s, brightness: &v, alpha: &a)
        return (Double(h), Double(s), Double(v))
    }

    public static func hsvToRGB(h: Double, s: Double, v: Double) -> (r: Double, g: Double, b: Double) {
        let c = Color(hue: h, saturation: s, brightness: v)
        let ui = UIColor(c)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        return (Double(r), Double(g), Double(b))
    }
}
