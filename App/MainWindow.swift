import RocketCore
import RocketDesign
import RocketUI
import SwiftUI

/// Standard source-list window: sidebar, download table with toolbar and search, and an inspector.
struct MainWindow: View {
    @Bindable var downloads: DownloadsModel
    @Environment(\.soundEffects) private var soundEffects
    @AppStorage("sidebarCollapsed") private var sidebarCollapsed = false

    var body: some View {
        NavigationSplitView(columnVisibility: Binding(
            get: { sidebarCollapsed ? .detailOnly : .all },
            set: { sidebarCollapsed = $0 == .detailOnly }
        )) {
            DownloadSidebar(model: downloads) { AgentStatusView() }
                .navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 300)
        } detail: {
            DownloadListView(model: downloads)
        }
        .dropDestination(for: URL.self) { urls, _ in
            let links = LinkExtractor.urls(fromDropped: urls)
            guard !links.isEmpty else { return false }
            downloads.beginAdding(links)
            return true
        }
        .rocketModal(item: $downloads.refreshing) { download in
            RefreshLinkSheet(download: download) { url in await downloads.refreshLink(download.id, to: url) }
        }
        .rocketModal(item: $downloads.editingQueue) { queue in
            QueueEditor(queue: queue) { saved in Task { await downloads.saveQueue(saved) } }
        }
        .rocketModal(item: $downloads.adding) { adding in
            AddDownloadsSheet(model: adding) { ids in
                Task {
                    await downloads.finishAdding(ids)
                    if !ids.isEmpty { soundEffects?.playAdded() }
                }
            }
        }
        .rocketModal(isPresented: $downloads.showInsights) {
            DownloadInsightsView(model: downloads)
        }
        .rocketAlert($downloads.alert)
        .onChange(of: downloads.alert) { _, message in
            if message != nil { soundEffects?.playWarning() }
        }
        .rocketCommandPalette(downloads: downloads)
    }
}
