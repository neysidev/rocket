import RocketDesign
import SwiftUI

@main
struct RocketApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate

    var body: some Scene {
        WindowGroup("Rocket") {
            MainWindow()
                .frame(minWidth: 760, minHeight: 480)
        }
        Settings {
            Text("Settings")
                .font(.rocketBody)
                .padding(RocketSpace.s6)
        }
        MenuBarExtra("Rocket", systemImage: "arrow.down.circle") {
            MenuBarPanel()
        }
        .menuBarExtraStyle(.window)
    }
}

/// Needed when launched as a bare SPM executable (no Info.plist) so the window comes to front.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }
}
