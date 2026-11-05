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
                .inspector(isPresented: $downloads.showsInspector) {
                    Group {
                        if downloads.selection.count == 1, let id = downloads.selection.first {
                            DownloadDetailView(model: downloads, id: id)
                        } else {
                            Text(downloads.selection.isEmpty ? "Select a download" : "\(downloads.selection.count) downloads selected")
                                .font(.rocketBody)
                                .foregroundStyle(RocketColor.textSecondary)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                    .inspectorColumnWidth(min: 260, ideal: RocketSize.inspectorWidth, max: 420)
                }
        }
        .searchable(text: $downloads.search, placement: .toolbar, prompt: "Filter")
        .toolbar {
            ToolbarItem { Button("Add", systemImage: "plus") { downloads.beginAdding() }.help("Add downloads (⌘N)") }
            ToolbarItem(placement: .primaryAction) {
                Button("Inspector", systemImage: "sidebar.right") { downloads.showsInspector.toggle() }
                    .help("Show details (⌥⌘I)")
                    .keyboardShortcut("i", modifiers: [.command, .option])
            }
            ToolbarItem {
                Menu {
                    Picker("Sort By", selection: $downloads.sort) {
                        ForEach(DownloadSort.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.inline)
                    Divider()
                    Button("Clear Completed") { Task { await downloads.clearCompleted() } }
                        .disabled(!downloads.hasFinished)
                } label: {
                    Label("View Options", systemImage: "line.3.horizontal.decrease")
                }
                .help("Sort and clear")
            }
            ToolbarItem {
                Menu {
                    SpeedLimitPicker("Limit All Downloads", current: downloads.settings.globalSpeedLimit) { rate in
                        Task { await downloads.setGlobalLimit(rate) }
                    }
                } label: {
                    Label("Speed Limit", systemImage: "gauge.with.dots.needle.33percent")
                }
                .help(downloads.settings.globalSpeedLimit.map { "Limited to \(Format.speed(Double($0)))" } ?? "No speed limit")
            }
            ToolbarItem {
                if downloads.hasRunning || !downloads.hasPaused {
                    Button("Pause All", systemImage: "pause") { Task { await downloads.pauseAll() } }
                        .disabled(!downloads.hasRunning)
                } else {
                    Button("Resume All", systemImage: "play") { Task { await downloads.resumeAll() } }
                }
            }
        }
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
