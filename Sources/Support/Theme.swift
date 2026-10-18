import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Theme — bảng màu của bản gốc (field: bg, bgTop, card, cardHi, border, borderHi, dim, …)
public enum Theme {
    public static let bg       = Color(hex: 0x0A0C10)
    public static let bgTop    = Color(hex: 0x121722)
    public static let card     = Color(hex: 0x161C28)
    public static let cardHi   = Color(hex: 0x1E2634)
    public static let border   = Color(hex: 0x232C3B)
    public static let borderHi = Color(hex: 0x37D0A0)
    public static let dim      = Color(hex: 0x8A93A6)

    public static let accent   = Color(hex: 0x37D0A0)   // xanh ngọc
    public static let danger   = Color(hex: 0xFF5D5D)
    public static let warn     = Color(hex: 0xFFC24B)
    public static let gold     = Color(hex: 0xF5C451)
    public static let text     = Color(hex: 0xE8EDF7)

    public static let titleFont = Font.system(size: 20, weight: .heavy, design: .rounded)
    public static let headFont  = Font.system(size: 15, weight: .bold, design: .rounded)
    public static let bodyFont  = Font.system(size: 13, weight: .medium, design: .rounded)
    public static let monoFont  = Font.system(size: 11, weight: .regular, design: .monospaced)
}

public extension Color {
    init(hex: UInt32) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }

    /// AppModel.pack565 / CustomColorPickerPanel dùng RGB565 — giữ ở đây cho tiện
    var rgb565: UInt16 {
        let ui = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        return Pack565.pack(r: UInt8(r * 255), g: UInt8(g * 255), b: UInt8(b * 255))
    }
}

/// Nền chung: gradient tối + viền glow
public struct BolaBackground: View {
    public init() {}
    public var body: some View {
        LinearGradient(colors: [Theme.bgTop, Theme.bg],
                       startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
    }
}

// MARK: - Styles (đúng tên trong binary: CardButtonStyle, InjectButtonStyle,
//          RowButtonStyle, SegmentButtonStyle)

public struct CardButtonStyle: ButtonStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(configuration.isPressed ? Theme.cardHi : Theme.card)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Theme.border, lineWidth: 1)
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

public struct InjectButtonStyle: ButtonStyle {
    public var enabled: Bool = true
    /// Đã inject → nút chuyển đỏ với chữ "UN INJECT"
    public var danger: Bool = false
    public init(enabled: Bool = true, danger: Bool = false) {
        self.enabled = enabled
        self.danger = danger
    }
    public func makeBody(configuration: Configuration) -> some View {
        let labelColor: Color = danger ? .white : (enabled ? .black : Theme.dim)
        let fill: [Color] = danger
            ? [Color(hex: 0xE24848), Color(hex: 0x8E1B1B)]
            : (enabled ? [Theme.accent, Color(hex: 0x1FA97F)] : [Theme.cardHi, Theme.card])
        let stroke: Color = danger
            ? Color(hex: 0xFF8A8A).opacity(0.6)
            : (enabled ? Theme.borderHi.opacity(0.6) : Theme.border)
        let glow: Color = danger ? Theme.danger.opacity(0.3)
            : (enabled ? Theme.accent.opacity(0.25) : .clear)
        configuration.label
            .font(Theme.titleFont)
            .foregroundStyle(labelColor)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(LinearGradient(colors: fill,
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(stroke, lineWidth: 1)
                    )
                    .shadow(color: glow, radius: 14, y: 6)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

public struct RowButtonStyle: ButtonStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Theme.cardHi : .clear)
    }
}

public struct SegmentButtonStyle: ButtonStyle {
    public var selected: Bool
    public init(selected: Bool) { self.selected = selected }
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.headFont)
            .foregroundStyle(selected ? Color.black : Theme.dim)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(selected ? Theme.accent : Color.clear)
            )
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

// MARK: - StatusDot

public struct StatusDot: View {
    public var tone: DotTone
    public var size: CGFloat = 9

    public init(tone: DotTone, size: CGFloat = 9) {
        self.tone = tone
        self.size = size
    }

    private var color: Color {
        switch tone {
        case .ok: return Theme.accent
        case .bad: return Theme.danger
        case .busy: return Theme.warn
        case .idle: return Theme.dim
        }
    }

    public var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .shadow(color: color.opacity(0.8), radius: 5)
    }
}

// MARK: - ToastView

public struct ToastView: View {
    public var text: String
    public init(text: String) { self.text = text }

    public var body: some View {
        Text(text)
            .font(Theme.bodyFont)
            .foregroundStyle(Theme.text)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                Capsule().fill(Theme.cardHi)
                    .overlay(Capsule().stroke(Theme.border, lineWidth: 1))
            )
            .shadow(radius: 12, y: 6)
            .transition(.move(edge: .top).combined(with: .opacity))
    }
}

// MARK: - BlockOverlay (khi VersionGate.killed / blocked)

public struct BlockOverlay: View {
    public var title: String
    public var message: String
    public var buttonTitle: String
    public var onOpen: () -> Void

    public init(title: String, message: String, buttonTitle: String, onOpen: @escaping () -> Void) {
        self.title = title
        self.message = message
        self.buttonTitle = buttonTitle
        self.onOpen = onOpen
    }

    public var body: some View {
        ZStack {
            Theme.bg.opacity(0.96).ignoresSafeArea()
            VStack(spacing: 14) {
                Text("⛔").font(.system(size: 44))
                Text(title).font(Theme.titleFont).foregroundStyle(Theme.danger)
                Text(message)
                    .font(Theme.bodyFont)
                    .foregroundStyle(Theme.dim)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
                Button(buttonTitle, action: onOpen)
                    .buttonStyle(InjectButtonStyle())
                    .padding(.horizontal, 28)
            }
        }
    }
}
