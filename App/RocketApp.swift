import RocketDesign
import RocketUI
import SwiftUI

@main
struct RocketApp: App {
    @State private var agent = AgentConnection()
    @State private var downloads = DownloadsModel()

    var body: some Scene {
        WindowGroup("Rocket") {
            MainWindow(downloads: downloads)
                .environment(agent)
                .frame(minWidth: 760, minHeight: 480)
                .task {
                    await agent.connect()
                    downloads.agent = agent.client
                    await downloads.poll()
                }
                .onChange(of: agent.status) { downloads.agent = agent.client }
        }
        .commands { DownloadCommands(downloads: downloads) }
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

/// Menu commands for the selected downloads (keyboard: ⌘O reveals in Finder).
struct DownloadCommands: Commands {
    let downloads: DownloadsModel

    var body: some Commands {
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
