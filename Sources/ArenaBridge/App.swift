import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    var onTerminate: (() -> Void)?

    func applicationWillTerminate(_ notification: Notification) {
        onTerminate?()
    }
}

@main
struct ArenaBridgeApp: App {
    @StateObject private var model = AppModel()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup("ArenaBridge") {
            ContentView()
                .environmentObject(model)
                .environmentObject(model.tunnel)
                .environmentObject(model.status)
                .frame(minWidth: 980, minHeight: 660)
                .onAppear {
                    model.onLaunch()
                    appDelegate.onTerminate = { model.tunnel.terminateNow() }
                }
        }
        .defaultSize(width: 1060, height: 700)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
