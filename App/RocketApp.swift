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
        .commands {
            DownloadCommands(downloads: app.downloads)
            UpdateCommands(updater: app.updater)
        }
        Settings {
            SettingsView(model: app.downloads) { UpdateSettings(updater: app.updater.updater) }
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
    let updater = Updater()
    private var notifier: Notifier?
    private let dock = DockProgress()
    private var polling: Task<Void, Never>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let settings = downloads.settings
        let notifier = Notifier(downloads: downloads, isEnabled: { settings.notificationsEnabled })
        self.notifier = notifier
        downloads.onEvent = { notifier.post($0) }
        downloads.onUpdate = { [dock, downloads] in
            dock.update(count: downloads.transferringCount + downloads.queuedCount, fraction: downloads.overallFraction,
                        enabled: settings.showDockProgress)
        }
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
            Divider()
            Button("Clear Completed") { Task { await downloads.clearCompleted() } }
                .keyboardShortcut("k", modifiers: [.command, .shift])
                .disabled(!downloads.hasFinished)
        }
        CommandGroup(after: .toolbar) {
            Picker("Sort By", selection: Binding(get: { downloads.sort }, set: { downloads.sort = $0 })) {
                ForEach(DownloadSort.allCases) { Text($0.title).tag($0) }
            }
        }
    }
}
