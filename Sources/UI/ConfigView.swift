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
                segment
                tabContent
                warningCard
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
            Text("Đã cài xong cho \(model.game.name)").font(Theme.monoFont)
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
                toggleRowInline("esp", "Khung quanh người & bot", "Khung quanh người & bot")
                toggleRowInline("skeleton", "Khung xương người (skeleton)", "Khung xương người (skeleton)")
                toggleRowInline("hp", "Thanh HP cho người & bot", "Thanh HP cho người & bot")
                toggleRowInline("name", "Tên người chơi / bot", "Tên người chơi / bot")
                toggleRowInline("distance", "Khoảng cách tới mục tiêu", "Khoảng cách tới mục tiêu")
            }
            card("Bộ lọc") {
                toggleRowInline("teammates", "Hiện đồng đội (màu xanh)", "Hiện đồng đội (màu xanh)")
                toggleRowInline("bots", "Hiện cả bot (AI)", "Hiện cả bot (AI)")
                toggleRowInline("counter", "Số địch + bot ở trên màn hình", "Số địch + bot ở trên màn hình")
            }
            colorFeatureCard("Màu hiển thị")
        }
    }

    // MARK: AIM

    private var aimTab: some View {
        VStack(spacing: 12) {
            card("Mục tiêu") {
                toggleRowInline("aim", "Khoá địch gần tâm ngắm nhất", "Khoá địch gần tâm ngắm nhất")
                toggleRowInline("aimline", "Đường kẻ từ tâm ngắm", "Đường kẻ từ tâm ngắm")
                toggleRowInline("fovcircle", "Hiện vòng FOV", "Ẩn/hiện vòng tròn FOV trên màn hình")
                toggleRowInline("skipdown", "Không bắn vào địch đã bị hạ gục", "Không bắn vào địch đã bị hạ gục")
            }
            card("Bone & thông số") {
                boneSection
                sliderRow("Khoảng Cách Cam (FOV)", value: $model.aimFov, range: 5...100, unit: "°")
                sliderRow("Tỉ lệ vào đầu", value: $model.headRate, range: 0.1...1, unit: "")
                sliderRow("Silent FOV", value: $model.silentFov, range: 0.001...0.2, unit: "")
                Text("Bắn lệch vẫn bay vào bone đã chọn").font(.system(size: 11)).foregroundStyle(Theme.dim)
            }
        }
    }

    private var boneSection: some View {
        HStack(spacing: 8) {
            ForEach(BolaConfig.Bone.allCases, id: \.rawValue) { b in
                Button { model.aimBone = b } label: {
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

    // MARK: MISC

    private var miscTab: some View {
        VStack(spacing: 12) {
            card("Vũ khí") {
                toggleRowInline("fastfire", "Bắn Siêu Tốc (Fast Fire)", "Tăng tốc độ nhả đạn của súng liên thanh")
                toggleRowInline("norecoil", "Đạn thẳng (No Recoil 0%)", "Triệt tiêu độ tỏa đạn — đạn bay thẳng tắp")
                toggleRowInline("fastswap", "Đổi Súng Nhanh", "Triệt tiêu delay đổi súng, bắn liền tục")
            }
            card("Di chuyển") {
                toggleRowInline("speedrun", "Chạy Nhanh x3 (Speed Run)", "Di chuyển thần tốc, né đạn & lướt nhanh")
                toggleRowInline("highjump", "Nhảy Cao (High Jump)", "Nhảy cao 1.2x vượt tường kẹo, leo nóc nhà")
                toggleRowInline("lowfall", "Khử gia tốc rơi", "Khử gia tốc rơi, nhảy giật lùi né đạn")
                toggleRowInline("booyah", "Điệu Nhảy Booyah", "Kích hoạt nhảy Booyah & Carnival liên tục")
            }
            card("Hiển thị") {
                toggleRowInline("camfar", "Góc Nhìn Rộng (Cam Xa)", "Mở rộng góc quan sát toàn cảnh chiến trường")
                toggleRowInline("fps144", "Mở Khóa 144 FPS", "Mở khoá tần số quét, hình ảnh siêu mượt")
                toggleRowInline("autolaunch", "Tự mở game sau khi inject", "Đã inject — đang mở game")
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

    /// toggleRowInline — tên + mô tả + switch
    private func toggleRowInline(_ key: String, _ title: String, _ subtitle: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(Theme.bodyFont).foregroundStyle(Theme.text)
                Text(subtitle).font(.system(size: 10)).foregroundStyle(Theme.dim)
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { model.cfgFlags.contains(key) },
                set: { on in
                    if on { model.cfgFlags.insert(key) } else { model.cfgFlags.remove(key) }
                }))
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
                Text(String(format: range.upperBound <= 1 ? "%.3f%s" : "%.0f%s", value.wrappedValue, unit))
                    .font(Theme.monoFont).foregroundStyle(Theme.accent)
            }
            Slider(value: value, in: range).tint(Theme.accent)
        }
    }

    private func colorFeatureCard(_ title: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(Theme.headFont).foregroundStyle(Theme.text)
            ForEach(model.featureRGB.keys.sorted(), id: \.self) { key in
                Button {
                    colorPickKey = key
                    let ui = UIColor(Color(hex: UInt32(model.featureRGB[key] ?? 0)))
                    var h: CGFloat = 0, s: CGFloat = 0, v: CGFloat = 0, a: CGFloat = 0
                    ui.getHue(&h, saturation: &s, brightness: &v, alpha: &a)
                    hue = Double(h); sat = Double(s); val = Double(v)
                } label: {
                    HStack {
                        Circle()
                            .fill(Color(hex: UInt32(model.featureRGB[key] ?? 0)))
                            .frame(width: 16, height: 16)
                            .overlay(Circle().stroke(Theme.border, lineWidth: 1))
                        Text(colorTitle(key)).font(Theme.bodyFont).foregroundStyle(Theme.text)
                        Spacer()
                        Text(String(format: "#%04X", model.featureRGB[key] ?? 0))
                            .font(Theme.monoFont).foregroundStyle(Theme.dim)
                    }
                }
                .buttonStyle(RowButtonStyle())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16).fill(Theme.card)
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.border, lineWidth: 1)))
    }

    private func colorTitle(_ key: String) -> String {
        switch key {
        case "esp_box": return "Khung"
        case "esp_skeleton": return "Xương"
        case "esp_hp": return "Thanh HP"
        case "esp_name": return "Tên"
        case "fov_circle": return "Vòng FOV"
        default: return key
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
            Button { model.inject() } label: {
                Text(model.busy ? "Đang inject…" : "INJECT")
            }
            .buttonStyle(InjectButtonStyle(enabled: !model.busy && gate.isAuthorized))
            .disabled(model.busy)

            Button { model.writeConfig() } label: {
                Text("Lưu cấu hình (không cần inject lại)")
                    .font(Theme.bodyFont)
            }
            .foregroundStyle(model.patchInstalled ? Theme.accent : Theme.dim)
            .disabled(!model.patchInstalled)

            Text("Mặc định tắt mỗi lần mở app — bật lại khi cần")
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
