import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// KeyScreenView — màn nhập key (bản gốc: KeyScreenView + LicenseGate + pulse)
/// Chuỗi lấy đúng từ binary:
///   "Nhập license key để kích hoạt."   "Nhập key để kích hoạt menu"
///   "Chưa có key? Liên hệ admin để mua."   "🔑 …"
public struct KeyScreenView: View {

    @ObservedObject var gate: LicenseGate
    @State private var keyText: String = ""
    @State private var pulse = false

    public init(gate: LicenseGate) { self.gate = gate }

    public var body: some View {
        ZStack {
            BolaBackground()
            VStack(spacing: 18) {
                header
                keyField
                if !gate.errorText.isEmpty {
                    Text(gate.errorText)
                        .font(Theme.bodyFont)
                        .foregroundStyle(Theme.danger)
                        .multilineTextAlignment(.center)
                }
                Button(action: { gate.submit(key: keyText) }) {
                    HStack(spacing: 8) {
                        if gate.busy { ProgressView().tint(.black) }
                        Text(gate.busy ? "Đang kiểm tra key…" : "Kích hoạt key")
                    }
                }
                .buttonStyle(InjectButtonStyle(enabled: !keyText.isEmpty && !gate.busy))
                .disabled(keyText.isEmpty || gate.busy)

                if let telegram = AppBrand.fromBundle().telegram {
                    Link(destination: telegram) {
                        Text("Chưa có key? Liên hệ admin để mua.")
                            .font(Theme.bodyFont)
                            .foregroundStyle(Theme.accent)
                    }
                }
                Text("Key: \(gate.remainingText.isEmpty ? "—" : gate.remainingText)")
                    .font(Theme.monoFont)
                    .foregroundStyle(Theme.dim)
                Spacer()
            }
            .padding(24)
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Theme.card)
                    .frame(width: 92, height: 92)
                    .overlay(Circle().stroke(Theme.borderHi.opacity(pulse ? 0.9 : 0.25), lineWidth: 2))
                    .shadow(color: Theme.accent.opacity(pulse ? 0.35 : 0.08), radius: pulse ? 22 : 6)
                Image(systemName: "key.horizontal.fill")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(Theme.accent)
            }
            .scaleEffect(pulse ? 1.03 : 1)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }

            Text(AppBrand.fromBundle().displayName)
                .font(Theme.titleFont).foregroundStyle(Theme.text)
            Text(gate.statusText)
                .font(Theme.bodyFont).foregroundStyle(Theme.dim)
            Text("Nhập key để kích hoạt menu")
                .font(Theme.bodyFont).foregroundStyle(Theme.dim)
        }
        .padding(.top, 40)
    }

    private var keyField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("License Key").font(Theme.monoFont).foregroundStyle(Theme.dim)
            TextField("", text: $keyText, prompt: Text("Nhap key").foregroundColor(Theme.dim))
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled(true)
                .font(Theme.bodyFont)
                .foregroundStyle(Theme.text)
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Theme.card)
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Theme.border, lineWidth: 1))
                )
        }
    }
}

/// Màn "Bản này đã ngừng hoạt động" — VersionGate killed
public struct VersionGateView: View {
    @ObservedObject var gate: VersionGate
    public init(gate: VersionGate) { self.gate = gate }

    public var body: some View {
        BlockOverlay(title: "NGỪNG HOẠT ĐỘNG",
                     message: gate.message.isEmpty ? "⛔ Bản này đã ngừng hoạt động." : gate.message,
                     buttonTitle: "⬇️  TẢI BẢN MỚI NHẤT") {
            #if canImport(UIKit)
            if let url = gate.downloadURL { UIApplication.shared.open(url) }
            #endif
        }
    }
}
