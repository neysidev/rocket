import RocketCore
import RocketDesign
import RocketUI
import SwiftUI

/// Sidebar, download table, and an inspector when a download is open. Dialogs stay Rocket modals.
struct MainWindow: View {
    @Bindable var downloads: DownloadsModel
    @Environment(\.soundEffects) private var soundEffects

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let compactNav = width < 980
            let inlineInspector = downloads.detailsID != nil && width >= 1120
            HStack(spacing: 0) {
                DownloadSidebar(model: downloads, compact: compactNav) { AgentStatusView() }
                    .frame(width: compactNav ? RocketSize.sidebarRail : RocketSize.sidebarWidth)
                DownloadListView(model: downloads)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if inlineInspector, let id = downloads.detailsID {
                    DownloadDetailView(model: downloads, id: id, layout: .inspector)
                        .frame(width: min(RocketSize.inspectorWidth, max(280, width * 0.32)))
                        .background(RocketColor.canvas)
                        .overlay(alignment: .leading) { Rectangle().fill(RocketColor.border).frame(width: 1) }
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .frame(width: width, height: proxy.size.height)
            .overlay {
                if downloads.detailsID != nil, !inlineInspector, let id = downloads.detailsID {
                    HStack(spacing: 0) {
                        Color.black.opacity(0.28)
                            .contentShape(Rectangle())
                            .onTapGesture { downloads.detailsID = nil }
                        DownloadDetailView(model: downloads, id: id, layout: .inspector)
                            .frame(width: min(RocketSize.inspectorWidth, max(260, width - RocketSize.sidebarRail - 16)))
                            .background(RocketColor.canvas)
                            .overlay(alignment: .leading) { Rectangle().fill(RocketColor.border).frame(width: 1) }
                    }
                    .transition(.opacity)
                }
            }
            .rocketAnimation(RocketMotion.standard, value: downloads.detailsID)
            .rocketAnimation(RocketMotion.standard, value: inlineInspector)
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
        .rocketCommandPalette(downloads: downloads)
        .background { commandPaletteShortcut }
    }

    @ViewBuilder
    private var commandPaletteShortcut: some View {
        if downloads.adding == nil, downloads.detailsID == nil, downloads.refreshing == nil,
           downloads.editingQueue == nil, !downloads.isCommandPaletteOpen {
            Button("Command Palette") { downloads.isCommandPaletteOpen = true }
                .keyboardShortcut("k", modifiers: .command)
                .hidden()
        }
    }
}
