import SwiftUI

/// ContentView — vỏ app: NavigationStack + chuyển màn theo gate/phase, sheet Settings,
/// overlay chọn ngôn ngữ (đúng field: _model _gate _scenePhase _path _showSettings _showLanguage)
public struct ContentView: View {

    @EnvironmentObject private var model: AppModel
    @ObservedObject private var gate: LicenseGate
    @Environment(\.scenePhase) private var scenePhase

    @State private var path = NavigationPath()
    @State private var showSettings = false
    @State private var showLanguage = false

    public init(gate: LicenseGate) {
        self._gate = ObservedObject(wrappedValue: gate)
    }

    public var body: some View {
        ZStack {
            BolaBackground()
            ContentRoot(model: model, gate: gate, path: $path,
                        showSettings: $showSettings, showLanguage: $showLanguage)
        }
        .preferredColorScheme(.dark)
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .active {
                model.refreshDetected()
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(model: model).environmentObject(model)
        }
        .overlay(alignment: .top) {
            if !model.toastText.isEmpty {
                ToastView(text: model.toastText)
                    .padding(.top, 8)
                    .id(model.toastToken)
                    .task(id: model.toastToken) {
                        try? await Task.sleep(nanoseconds: 2_600_000_000)
                        withAnimation { model.toastText = "" }
                    }
            }
        }
    }
}

private struct ContentRoot: View {
    @ObservedObject var model: AppModel
    @ObservedObject var gate: LicenseGate
    @Binding var path: NavigationPath
    @Binding var showSettings: Bool
    @Binding var showLanguage: Bool

    var body: some View {
        Group {
            if !gate.isAuthorized {
                KeyScreenView(gate: gate)
            } else {
                NavigationStack(path: $path) {
                    HomeView(model: model, gate: gate,
                             showSettings: $showSettings, showLanguage: $showLanguage)
                }
            }
        }
    }
}

/// Chọn ngôn ngữ — overlay nhỏ (bản gốc: langOption / languageCard / languageOverlay)
public struct LanguageOverlay: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    public init(model: AppModel) { self.model = model }

    public var body: some View {
        VStack(spacing: 12) {
            Text("Chọn ngôn ngữ")
                .font(Theme.headFont).foregroundStyle(Theme.text)
            ForEach(Language.allCases) { lang in
                Button {
                    model.setLanguage(lang)
                    dismiss()
                } label: {
                    HStack {
                        Text(lang.flag)
                        Text(lang.display).font(Theme.bodyFont).foregroundStyle(Theme.text)
                        Spacer()
                        if model.language == lang {
                            Image(systemName: "checkmark").foregroundStyle(Theme.accent)
                        }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 12)
                }
                .buttonStyle(CardButtonStyle())
            }
        }
        .padding(20)
        .background(Theme.bg.ignoresSafeArea())
    }
}
