import RocketDesign
import RocketUI
import SwiftUI

/// Sidebar (status filters) → download list. The inspector arrives with FR-APP-02.
struct MainWindow: View {
    @Bindable var downloads: DownloadsModel

    var body: some View {
        NavigationSplitView {
            DownloadSidebar(model: downloads) { AgentStatusView() }
                .navigationSplitViewColumnWidth(RocketSize.sidebarWidth)
        } detail: {
            DownloadListView(model: downloads)
        }
        .searchable(text: $downloads.search, placement: .toolbar, prompt: "Filter")
        .toolbar {
            ToolbarItem { Button("Add", systemImage: "plus") { downloads.beginAdding() }.help("Add downloads (⌘N)") }
            ToolbarItem {
                if downloads.hasRunning || !downloads.hasPaused {
                    Button("Pause All", systemImage: "pause") { Task { await downloads.pauseAll() } }
                        .disabled(!downloads.hasRunning)
                } else {
                    Button("Resume All", systemImage: "play") { Task { await downloads.resumeAll() } }
                }
            }
        }
        .sheet(item: $downloads.adding) { adding in
            AddDownloadsSheet(model: adding) { ids in Task { await downloads.finishAdding(ids) } }
        }
        .dropDestination(for: URL.self) { urls, _ in
            let links = LinkExtractor.urls(fromDropped: urls)
            guard !links.isEmpty else { return false }
            downloads.beginAdding(links)
            return true
        }
        .alert("Rocket", isPresented: Binding(get: { downloads.alert != nil }, set: { if !$0 { downloads.alert = nil } })) {
            Button("OK") { downloads.alert = nil }
        } message: {
            Text(downloads.alert ?? "")
        }
    }
}
