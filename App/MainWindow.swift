import RocketCore
import RocketDesign
import RocketUI
import SwiftUI

/// Sidebar (status filters and queues) → download list or grid; details open in a sheet.
struct MainWindow: View {
    @Bindable var downloads: DownloadsModel

    var body: some View {
        NavigationSplitView {
            DownloadSidebar(model: downloads) { AgentStatusView() }
                .navigationSplitViewColumnWidth(RocketSize.sidebarWidth)
        } detail: {
            DownloadListView(model: downloads)
        }
        .toolbar {
            ToolbarItem {
                Menu {
                    Picker("Category", selection: $downloads.category) {
                        Text("Any Type").tag(FileCategory?.none)
                        ForEach(FileCategory.allCases, id: \.self) { Text($0.title).tag(Optional($0)) }
                    }
                    Picker("Size", selection: $downloads.sizeFilter) {
                        ForEach(SizeFilter.allCases) { Text($0.title).tag($0) }
                    }
                    Picker("Date Added", selection: $downloads.dateFilter) {
                        ForEach(DateFilter.allCases) { Text($0.title).tag($0) }
                    }
                    Divider()
                    Button("Clear Filters") { downloads.clearRefinements() }
                        .disabled(!downloads.hasRefinements)
                } label: {
                    Label("Filter", systemImage: downloads.hasRefinements
                        ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                }
                .help("Filter by type, size and date")
            }
            ToolbarItem {
                Picker("View", selection: $downloads.viewMode) {
                    ForEach(DownloadViewMode.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
                }
                .pickerStyle(.segmented)
                .help("List or grid (⌘1, ⌘2)")
            }
            ToolbarItem {
                ToolbarSearchField(model: downloads)
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    downloads.beginAdding()
                } label: {
                    Label("Add Download", systemImage: "plus")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.borderedProminent)
                .help("Add downloads (⌘N)")
            }
        }
        .sheet(isPresented: Binding(get: { downloads.detailsID != nil }, set: { if !$0 { downloads.detailsID = nil } })) {
            if let id = downloads.detailsID {
                VStack(spacing: 0) {
                    DownloadDetailView(model: downloads, id: id)
                    Divider()
                    HStack {
                        Spacer()
                        Button("Done") { downloads.detailsID = nil }
                            .keyboardShortcut(.cancelAction)
                    }
                    .padding(RocketSpace.s4)
                }
                .frame(width: 460, height: 560)
            }
        }
        .tint(RocketColor.accent)
        .sheet(item: $downloads.refreshing) { download in
            RefreshLinkSheet(download: download) { url in await downloads.refreshLink(download.id, to: url) }
        }
        .sheet(item: $downloads.editingQueue) { queue in
            QueueEditor(queue: queue) { saved in Task { await downloads.saveQueue(saved) } }
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
