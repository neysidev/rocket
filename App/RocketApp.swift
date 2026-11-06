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
                .soundEffects(app.sounds)
                .frame(minWidth: 760, minHeight: 480)
                .onChange(of: app.agent.status) { app.downloads.agent = app.agent.client }
                // External links go to the open window instead of opening another one.
                .handlesExternalEvents(preferring: ["*"], allowing: ["*"])
                .onOpenURL { url in
                    // rocket://add?url=… opens the add sheet for review; nothing starts without the user.
                    guard let request = RocketURLRequest(url) else { return }
                    app.downloads.beginAdding(request.links, folder: request.folder)
                    NSApp.activate()
                }
        }
        .windowToolbarStyle(.unified)
        .commands {
            DownloadCommands(downloads: app.downloads, windows: app.downloadWindows)
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
    lazy var downloadWindows = DownloadWindows(model: downloads)
    private var notifier: Notifier?
    private(set) var sounds: SoundManager?
    private var watcher: ClipboardWatcher?
    private let services = ServicesProvider()
    private let dock = DockProgress()
    private var polling: Task<Void, Never>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.servicesProvider = services
        let settings = downloads.settings
        let sounds = SoundManager(isEnabled: { settings.soundEffectsEnabled })
        self.sounds = sounds
        let notifier = Notifier(downloads: downloads, isEnabled: { settings.notificationsEnabled })
        self.notifier = notifier
        settings.onSoundEffectsChange = { sounds.setEnabled($0) }
        let watcher = ClipboardWatcher(extensions: { settings.clipboardExtensionSet }, offer: { notifier.offer(copied: $0) })
        self.watcher = watcher
        settings.onWatchClipboardChange = { watcher.setEnabled($0) }
        watcher.setEnabled(settings.watchClipboard)
        downloads.onEvent = { event in
            sounds.handle(event)
            notifier.post(event)
        }
        downloads.onStateTransition = { id, previous, next in
            sounds.handleTransition(id: id, from: previous, to: next)
        }
        let windows = downloadWindows
        downloads.onUpdate = { [dock, downloads, sounds] in
            windows.update(enabled: settings.showDownloadWindow)
            sounds.pruneStarted(excluding: Set(downloads.items.map(\.id)))
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
        MenuBarPanel(model: downloads, openMainWindow: {
            openWindow(id: "main")
            NSApp.activate()
        }, openCommandPalette: {
            openWindow(id: "main")
            NSApp.activate()
            downloads.isCommandPaletteOpen = true
        })
    }
}

/// Menu commands for the selected downloads (keyboard: ⌘O reveals in Finder).
struct DownloadCommands: Commands {
    let downloads: DownloadsModel
    let windows: DownloadWindows

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Download…") { downloads.beginAdding() }
                .keyboardShortcut("n")
        }
        CommandGroup(replacing: .textEditing) {
            Button("Command Palette…") { downloads.isCommandPaletteOpen = true }
                .keyboardShortcut("k", modifiers: .command)
            Button("Find") { downloads.isSearching = true }
                .keyboardShortcut("f")
        }
        CommandMenu("Download") {
            Button(downloads.detailsID == nil ? "Show Inspector" : "Hide Inspector") {
                if downloads.detailsID == nil { downloads.selection.first.map(downloads.showDetails) } else { downloads.detailsID = nil }
            }
            .keyboardShortcut("i")
            .disabled(downloads.detailsID == nil && downloads.selection.count != 1)
            Button("Show Progress Window") { downloads.selection.first.map { windows.show($0) } }
                .keyboardShortcut("p", modifiers: [.command, .option])
                .disabled(downloads.selection.count != 1)
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
        CommandGroup(before: .toolbar) {
            Button("Download Insights") { downloads.showInsights = true }
                .keyboardShortcut("i", modifiers: [.command, .option])
            Divider()
            Picker("Sort By", selection: Binding(get: { downloads.sort }, set: { downloads.sort = $0 })) {
                ForEach(DownloadSort.allCases) { Text($0.title).tag($0) }
            }
        }
    }
}
