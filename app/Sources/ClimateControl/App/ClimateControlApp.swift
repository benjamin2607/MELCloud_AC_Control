import AppKit
import SwiftUI

@main
struct ClimateControlApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    // The UI lives in a custom status item + panel (see StatusBarController); SwiftUI only needs a scene.
    var body: some Scene {
        Settings { EmptyView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menubar-only app: no Dock icon, no main window.
        NSApp.setActivationPolicy(.accessory)
        let store = ProcessInfo.processInfo.environment["CLIMATE_DEMO"] == "1"
            ? ClimateStore(demo: .demo)
            : ClimateStore(client: BridgeClient())
        controller = StatusBarController(store: store)
        store.start()
    }
}
