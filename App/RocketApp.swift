import RocketDesign
import RocketUI
import SwiftUI

@main
struct RocketApp: App {
    @NSApplicationDelegateAdaptor private var app: AppDelegate

    var body: some Scene {
        WindowGroup("Rocket", id: "main") {
            MainWindow(downloads: app.downloads)
                .environment(app.agent)
                .frame(minWidth: 760, minHeight: 480)
                .onChange(of: app.agent.status) { app.downloads.agent = app.agent.client }
        }
        .commands { DownloadCommands(downloads: app.downloads) }
        Settings {
            SettingsView(model: app.downloads)
        }
        MenuBarExtra {
            MenuBarContent(downloads: app.downloads)
        } label: {
            // Filled while downloading. ponytail: SF Symbol until the custom rocket.down glyph exists.
            Image(systemName: app.downloads.isDownloading ? "arrow.down.circle.fill" : "arrow.down.circle")
        }
        .menuBarExtraStyle(.window)
    }
}

/// Composition root: owns the agent connection and the download state for the app's whole lifetime,
/// so polling and notifications continue while the window is closed (the menu bar extra keeps the app running).
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let agent = AgentConnection()
    let downloads = DownloadsModel()
    private var notifier: Notifier?
    private var polling: Task<Void, Never>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let settings = downloads.settings
        let notifier = Notifier(downloads: downloads, isEnabled: { settings.notificationsEnabled })
        self.notifier = notifier
        downloads.onEvent = { notifier.post($0) }
        polling = Task { [agent, downloads] in
            await agent.connect()
            downloads.agent = agent.client
            await downloads.poll()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        polling?.cancel()
    }
}

struct MenuBarContent: View {
    let downloads: DownloadsModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        MenuBarPanel(model: downloads) {
            openWindow(id: "main")
            NSApp.activate()
        }
    }
}

/// Menu commands for the selected downloads (keyboard: ⌘O reveals in Finder).
struct DownloadCommands: Commands {
    let downloads: DownloadsModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Download…") { downloads.beginAdding() }
                .keyboardShortcut("n")
        }
        CommandMenu("Download") {
            Button("Show in Finder") { downloads.reveal(downloads.selection) }
                .keyboardShortcut("o")
                .disabled(downloads.selection.isEmpty)
            Button("Pause or Resume") { Task { await downloads.toggle(downloads.selection) } }
                .disabled(downloads.selection.isEmpty)
            Divider()
            Button("Pause All") { Task { await downloads.pauseAll() } }
            Button("Resume All") { Task { await downloads.resumeAll() } }
        }
    }
}
