import RocketCore
import RocketDesign
import RocketUI
import SwiftUI

/// Sidebar (brand, status filters, queues, activity) → header and download list or grid; dialogs are Rocket modals.
struct MainWindow: View {
    @Bindable var downloads: DownloadsModel
    @Environment(\.soundEffects) private var soundEffects

    var body: some View {
        HStack(spacing: 0) {
            DownloadSidebar(model: downloads) { AgentStatusView() }
                .frame(width: RocketSize.sidebarWidth)
            DownloadListView(model: downloads)
        }
        .ignoresSafeArea(.container, edges: .top)
        .background(RocketColor.canvas)
        .rocketWindowChrome(color: RocketColor.sidebar)
        .tint(RocketColor.accent)
        .dropDestination(for: URL.self) { urls, _ in
            let links = LinkExtractor.urls(fromDropped: urls)
            guard !links.isEmpty else { return false }
            downloads.beginAdding(links)
            return true
        }
        .rocketModal(isPresented: Binding(get: { downloads.detailsID != nil }, set: { if !$0 { downloads.detailsID = nil } })) {
            if let id = downloads.detailsID {
                DownloadDetailView(model: downloads, id: id)
                    .frame(width: 540)
            }
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
        .rocketModal(isPresented: Binding(get: { downloads.showInsights }, set: { downloads.showInsights = $0 })) {
            DownloadInsightsView(model: downloads)
        }
        .rocketAlert($downloads.alert)
        .onChange(of: downloads.alert) { _, message in
            if message != nil { soundEffects?.playWarning() }
        }
    }
}
