import SwiftUI

/// Entry point — @main
@main
struct BolaCloneApp: App {

    @StateObject private var model: AppModel
    @ObservedObject private var version = VersionGate.shared

    init() {
        let brand = AppBrand.fromBundle()
        let server = AppModel.defaultServer
        let m = AppModel(brand: brand, server: server)
        _model = StateObject(wrappedValue: m)
        VersionGate.shared.configure(server)
        #if canImport(AVFoundation)
        BackgroundAudio.shared.start()
        #endif
        Logger.shared.log("Đang kết nối hệ thống key…")
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                ContentView(gate: model.gate)
                    .environmentObject(model)
                if version.killed || version.blocked {
                    VersionGateView(gate: version)
                }
            }
            .onAppear {
                VersionGate.shared.check()
            }
        }
    }
}
