import RocketCore
import RocketDesign
import SwiftUI

/// The main window's content column. Space pauses/resumes, ⌫ removes, double-click opens.
public struct DownloadListView: View {
    @Bindable var model: DownloadsModel

    public init(model: DownloadsModel) {
        self.model = model
    }

    public var body: some View {
        Group {
            if model.visibleItems.isEmpty {
                EmptyStateView(filter: model.filter, searching: !model.search.isEmpty)
            } else {
                List(selection: $model.selection) {
                    ForEach(model.visibleItems) { item in
                        DownloadRow(item: item, model: model)
                            .listRowInsets(EdgeInsets(top: RocketSpace.s3, leading: RocketSpace.s4, bottom: RocketSpace.s3, trailing: RocketSpace.s4))
                            .draggable(item.id.uuidString)
                    }
                    // Drag to reorder inside a queue (FR-QUE-03).
                    .onMove(perform: isQueue ? { source, destination in
                        Task { await model.moveInCurrentQueue(from: source, to: destination) }
                    } : nil)
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
                .contextMenu(forSelectionType: UUID.self) { ids in
                    contextMenu(for: ids)
                } primaryAction: { ids in
                    ids.forEach(model.open)
                }
                .onKeyPress(.space) {
                    let ids = model.selection
                    Task { await model.toggle(ids) }
                    return .handled
                }
                .onPasteCommand(of: [.plainText, .url]) { _ in model.beginAdding() }
                .onDeleteCommand {
                    let ids = model.selection
                    Task { await model.remove(ids) }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RocketColor.canvas)
        .navigationTitle(model.title(for: model.filter))
    }

    private var isQueue: Bool {
        if case .queue = model.filter { return true }
        return false
    }

    @ViewBuilder
    private func contextMenu(for ids: Set<UUID>) -> some View {
        let states = ids.compactMap { model.download($0)?.state }
        if states.contains(where: \.isActive) {
            Button("Pause") { Task { await model.pause(ids) } }
        }
        if states.contains(where: { $0 == .paused || $0 == .failed }) {
            Button("Resume") { Task { await model.resume(ids) } }
        }
        if states.contains(.completed) {
            Button("Open") { ids.forEach(model.open) }
        }
        if ids.count == 1, let download = ids.first.flatMap(model.download), download.state != .completed {
            Button("Refresh Link…") { model.refreshing = download }
        }
        Button("Show in Finder") { model.reveal(ids) }
        Menu("Move to Queue") {
            ForEach(model.queues) { queue in
                Button(queue.name) { Task { await model.move(Array(ids), toQueue: queue.id) } }
            }
        }
        Menu("Speed Limit") {
            SpeedLimitPicker(current: ids.count == 1 ? ids.first.flatMap(model.download)?.speedLimit : nil) { rate in
                Task { await model.setLimit(ids, bytesPerSecond: rate) }
            }
        }
        Divider()
        if states.contains(where: { $0.isActive || $0 == .paused }) {
            Button("Cancel Download") { Task { await model.cancel(ids) } }
        }
        Button("Remove from List") { Task { await model.remove(ids) } }
        if states.contains(.completed) {
            Button("Remove and Move File to Trash") { Task { await model.remove(ids, deleteFiles: true) } }
        }
    }
}

/// One symbol, one sentence, one hint. No illustrations.
struct EmptyStateView: View {
    let filter: SidebarFilter
    let searching: Bool

    var body: some View {
        VStack(spacing: RocketSpace.s3) {
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 28))
                .foregroundStyle(RocketColor.textTertiary)
            Text(title)
                .font(.rocketHeadline)
                .foregroundStyle(RocketColor.textPrimary)
            if filter == .all, !searching {
                Text("Copy a link and press ⌘V, or use rocket add in Terminal.")
                    .font(.rocketBody)
                    .foregroundStyle(RocketColor.textSecondary)
            }
        }
        .multilineTextAlignment(.center)
        .padding(RocketSpace.s6)
    }

    private var title: String {
        if searching { return String(localized: "No matching downloads") }
        switch filter {
        case .all: return String(localized: "No downloads yet")
        case .active: return String(localized: "Nothing is downloading")
        case .completed: return String(localized: "No completed downloads")
        case .failed: return String(localized: "No failed downloads")
        case .queue: return String(localized: "This queue is empty")
        }
    }
}

/// Status filters and queues with live counts. Downloads can be dropped on a queue to move them there.
public struct DownloadSidebar<Footer: View>: View {
    @Bindable var model: DownloadsModel
    let footer: Footer

    public init(model: DownloadsModel, @ViewBuilder footer: () -> Footer) {
        self.model = model
        self.footer = footer()
    }

    public var body: some View {
        List(selection: Binding(get: { model.filter }, set: { model.filter = $0 ?? .all })) {
            Section("Status") {
                ForEach(SidebarFilter.statuses) { filter in
                    Label(filter.title, systemImage: filter.symbol)
                        .badge(model.count(filter))
                        .tag(filter)
                }
            }
            Section {
                ForEach(model.queues) { queue in
                    Label(queue.name, systemImage: queue.schedule == nil ? "list.bullet" : "clock")
                        .badge(model.count(.queue(queue.id)))
                        .help(queue.schedule?.summary ?? "")
                        .tag(SidebarFilter.queue(queue.id))
                        .dropDestination(for: String.self) { ids, _ in
                            let ids = ids.compactMap(UUID.init(uuidString:))
                            Task { await model.move(ids, toQueue: queue.id) }
                            return !ids.isEmpty
                        }
                        .contextMenu {
                            Button("Edit Queue…") { model.editingQueue = queue }
                            if !queue.isDefault {
                                Button("Delete Queue") { Task { await model.deleteQueue(queue.id) } }
                            }
                        }
                }
            } header: {
                HStack {
                    Text("Queues")
                    Spacer()
                    Button("New Queue", systemImage: "plus") { model.newQueue() }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .help("New queue")
                }
            }
        }
        .safeAreaInset(edge: .bottom) { footer.padding(RocketSpace.s4) }
    }
}
