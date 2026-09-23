import SwiftUI

@main
struct ArenaBridgeApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup("ArenaBridge") {
            ContentView()
                .environmentObject(model)
                .environmentObject(model.tunnel)
                .environmentObject(model.status)
                .frame(minWidth: 980, minHeight: 660)
                .onAppear { model.onLaunch() }
        }
        .defaultSize(width: 1060, height: 700)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
