import AppKit
import RocketCore
import RocketDesign
import SwiftUI

/// The detail column: a native table, toolbar, search field and inspector.
/// Selection, ⌘A, arrows and type-select come from the table; double-click opens a finished file or its details,
/// Space pauses or resumes, ⌫ removes.
public struct DownloadListView: View {
    @Bindable var model: DownloadsModel
    @SceneStorage("downloadColumns") private var columns = TableColumnCustomization<DownloadItem>()

    public init(model: DownloadsModel) {
        self.model = model
    }

    public var body: some View {
        let items = model.visibleItems
        content(items)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle(model.title(for: model.filter))
            .navigationSubtitle(subtitle(count: items.count))
            .searchable(text: $model.search, isPresented: $model.isSearching, placement: .toolbar, prompt: Text("Search"))
            .toolbar { DownloadToolbar(model: model) }
            .inspector(isPresented: Binding(get: { model.detailsID != nil }, set: { if !$0 { model.detailsID = nil } })) {
                Group {
                    if let id = model.detailsID { DownloadDetailView(model: model, id: id) }
                }
                .inspectorColumnWidth(min: 280, ideal: 320, max: 440)
            }
            .onChange(of: model.selection) { _, selection in
                // The open inspector follows the selected row.
                if model.detailsID != nil, selection.count == 1 { model.detailsID = selection.first }
            }
            .onDeleteCommand {
                let ids = model.selection
                guard !ids.isEmpty else { return }
                Task { await model.remove(ids) }
            }
            .onPasteCommand(of: [.plainText, .url]) { _ in model.beginAdding() }
    }

    private func subtitle(count: Int) -> String {
        if case .queue(let id) = model.filter, let schedule = model.queues.first(where: { $0.id == id })?.schedule {
            return schedule.summary
        }
        return count == 1 ? String(localized: "1 download") : String(localized: "\(count) downloads")
    }

    @ViewBuilder
    private func content(_ items: [DownloadItem]) -> some View {
        if !model.hasLoaded, model.items.isEmpty {
            ProgressView("Loading Downloads…")
        } else if items.isEmpty {
            EmptyStateView(model: model)
        } else {
            table(items)
        }
    }

    private func table(_ items: [DownloadItem]) -> some View {
        let positions = model.queuePositions
        return Table(of: DownloadItem.self, selection: $model.selection, columnCustomization: $columns) {
            TableColumn("Name") { item in
                HStack(spacing: 6) {
                    StatusGlyph(item.download.state.glyph(item.fraction), size: 12)
                        .help(Self.statusHelp(item, position: positions[item.id]))
                    FileThumbnail(item: item, size: 16)
                    Text(item.download.fileName).lineLimit(1).truncationMode(.middle)
                        .help(item.download.fileName)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(item.accessibilityLabel)
            }
            .width(min: 180, ideal: 340)
            .customizationID("name")
            .disabledCustomizationBehavior(.visibility)
            TableColumn("Progress") { item in ProgressCell(item: item) }
                .width(min: 90, ideal: 150)
                .customizationID("progress")
            TableColumn("Size") { item in
                Text(Self.shortSize(item.download))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 56, ideal: 80, max: 110)
            .customizationID("size")
            TableColumn("Speed") { item in
                Text(Self.speedText(item))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 64, ideal: 84, max: 120)
            .customizationID("speed")
            TableColumn("Date Added") { item in
                Text(item.download.createdAt, format: .dateTime.month(.abbreviated).day().hour().minute())
                    .foregroundStyle(.secondary)
            }
            .width(min: 80, ideal: 120)
            .customizationID("date")
        } rows: {
            ForEach(items) { item in
                TableRow(item)
                    .draggable(item.id.uuidString)
                    // Drag to reorder inside a queue (FR-QUE-03): drops land in front of this row.
                    .dropDestination(for: String.self) { ids in reorder(ids, before: item.id) }
            }
        }
        .contextMenu(forSelectionType: UUID.self) { ids in
            if !ids.isEmpty { RocketNativeMenuItems(sections: DownloadMenu.sections(ids: ids, model: model)) }
        } primaryAction: { ids in
            guard ids.count == 1, let id = ids.first, let download = model.download(id) else { return }
            if download.state == .completed { model.open(id) } else { model.showDetails(id) }
        }
        .onKeyPress(.space) {
            guard !model.selection.isEmpty else { return .ignored }
            Task { await model.toggle(model.selection) }
            return .handled
        }
    }

    private func reorder(_ strings: [String], before: UUID?) {
        guard case .queue(let queueID) = model.filter else { return }
        let ids = strings.compactMap(UUID.init(uuidString:)).filter { $0 != before }
        guard !ids.isEmpty else { return }
        Task { await model.move(ids, toQueue: queueID, before: before) }
    }

    /// Total size when known. Progress already shows how much has arrived.
    static func shortSize(_ download: Download) -> String {
        if let total = download.totalBytes { return Format.bytes(total) }
        if download.receivedBytes > 0 { return Format.bytes(download.receivedBytes) }
        return "—"
    }

    /// "Paused", "#2 in queue", or the failure message.
    static func statusHelp(_ item: DownloadItem, position: Int?) -> String {
        let download = item.download
        if let failure = download.failure, download.state == .failed { return "\(download.state.title): \(failure.userMessage)" }
        if download.state == .queued, let position { return String(localized: "Queued, #\(position) in queue") }
        return download.state.title
    }

    static func speedText(_ item: DownloadItem) -> String {
        item.download.state.isTransferring && item.speed > 0 ? Format.speed(item.speed) : "—"
    }
}

/// New Download first and prominent, then filter, sort and queue controls. Search is the system field.
private struct DownloadToolbar: ToolbarContent {
    @Bindable var model: DownloadsModel

    var body: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button { model.beginAdding() } label: {
                Label("New Download", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .labelStyle(.iconOnly)
            .help("New Download (⌘N)")
        }
        ToolbarItemGroup(placement: .primaryAction) {
            filterMenu
            if !isQueue { sortMenu }
            if case .queue(let id) = model.filter, let queue = model.queues.first(where: { $0.id == id }) {
                if model.queueIsRunning(id) {
                    Button { Task { await model.pauseQueue(id) } } label: { Label("Pause Queue", systemImage: "pause") }
                        .help("Pause every download in this queue")
                } else {
                    Button { Task { await model.resumeQueue(id) } } label: { Label("Resume Queue", systemImage: "play") }
                        .help("Resume this queue’s paused downloads")
                }
                Button { model.editingQueue = queue } label: { Label("Edit Queue", systemImage: "slider.horizontal.3") }
                    .help("Edit Queue")
            }
        }
    }

    private var isQueue: Bool {
        if case .queue = model.filter { return true }
        return false
    }

    private var filterMenu: some View {
        Menu {
            Picker("Type", selection: $model.category) {
                Text("Any Type").tag(FileCategory?.none)
                Divider()
                ForEach(FileCategory.allCases, id: \.self) { Label($0.title, systemImage: $0.symbol).tag(FileCategory?.some($0)) }
            }
            Picker("Size", selection: $model.sizeFilter) {
                ForEach(SizeFilter.allCases) { Text($0.title).tag($0) }
            }
            Picker("Date Added", selection: $model.dateFilter) {
                ForEach(DateFilter.allCases) { Text($0.title).tag($0) }
            }
            Picker("Source", selection: $model.sourceHost) {
                Text("Any Source").tag(String?.none)
                Divider()
                ForEach(model.sourceHosts, id: \.self) { Text($0).tag(String?.some($0)) }
            }
            Divider()
            Button("Clear Filters") { model.clearRefinements() }
                .disabled(!model.hasRefinements)
        } label: {
            Label("Filter", systemImage: model.hasRefinements
                ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
        }
        .help("Filter by type, size, date and source")
    }

    private var sortMenu: some View {
        Menu {
            Picker("Sort By", selection: $model.sort) {
                ForEach(DownloadSort.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.inline)
        } label: {
            Label("Sort", systemImage: "arrow.up.arrow.down")
        }
        .help("Sort by \(model.sort.title)")
    }
}

/// System empty state: one sentence and one way forward.
struct EmptyStateView: View {
    let model: DownloadsModel

    var body: some View {
        if filtered {
            ContentUnavailableView {
                Label("No Matching Downloads", systemImage: "line.3.horizontal.decrease.circle")
            } description: {
                Text("Try a different search or clear the filters.")
            } actions: {
                Button("Clear Filters") {
                    model.clearRefinements()
                    model.search = ""
                }
            }
        } else if model.filter == .all {
            ContentUnavailableView {
                Label("No Downloads", systemImage: "arrow.down.circle")
            } description: {
                Text("Copy a link and press ⌘V, or use rocket add in Terminal.")
            } actions: {
                Button("New Download") { model.beginAdding() }
            }
        } else {
            ContentUnavailableView(title, systemImage: model.filter.symbol)
        }
    }

    private var filtered: Bool { model.hasRefinements || !model.search.isEmpty }

    private var title: String {
        switch model.filter {
        case .all: String(localized: "No Downloads")
        case .active: String(localized: "Nothing Is Downloading")
        case .queued: String(localized: "Nothing Is Waiting")
        case .completed: String(localized: "No Completed Downloads")
        case .failed: String(localized: "No Failed Downloads")
        case .queue: String(localized: "This Queue Is Empty")
        }
    }
}

/// Source list: status filters and queues with live counts. Downloads can be dropped on a queue to move them there.
public struct DownloadSidebar<Footer: View>: View {
    @Bindable var model: DownloadsModel
    let footer: Footer
    @State private var dropQueue: String?

    public init(model: DownloadsModel, @ViewBuilder footer: () -> Footer) {
        self.model = model
        self.footer = footer()
    }

    public var body: some View {
        List(selection: Binding<SidebarFilter?>(get: { model.filter }, set: { if let filter = $0 { model.filter = filter } })) {
            Section {
                ForEach(SidebarFilter.statuses) { filter in
                    Label { Text(filter.title) } icon: { SidebarIcon(filter.tile) }
                        .badge(model.count(filter))
                        .tag(filter)
                }
            }
            Section {
                ForEach(model.queues) { queue in queueRow(queue) }
            } header: {
                HStack {
                    Text("Queues")
                    Spacer()
                    Button { model.newQueue() } label: { Image(systemName: "plus") }
                        .buttonStyle(.borderless)
                        .help("New Queue")
                        .accessibilityLabel("New Queue")
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom, spacing: 0) { footer.padding(8) }
    }

    private func queueRow(_ queue: DownloadQueue) -> some View {
        Label { Text(queue.name) } icon: { SidebarIcon(Self.tile(for: queue)) }
            .badge(model.count(.queue(queue.id)))
            .tag(SidebarFilter.queue(queue.id))
            .help(queue.schedule?.summary ?? "")
            .listRowBackground(dropQueue == queue.id ? RoundedRectangle(cornerRadius: 5).fill(Color.accentColor.opacity(0.25)) : nil)
            .dropDestination(for: String.self) { ids, _ in
                dropQueue = nil
                let ids = ids.compactMap(UUID.init(uuidString:))
                Task { await model.move(ids, toQueue: queue.id) }
                return !ids.isEmpty
            } isTargeted: { targeted in
                if targeted { dropQueue = queue.id } else if dropQueue == queue.id { dropQueue = nil }
            }
            .contextMenu {
                if model.queueIsRunning(queue.id) {
                    Button("Pause Queue") { Task { await model.pauseQueue(queue.id) } }
                } else {
                    Button("Resume Queue") { Task { await model.resumeQueue(queue.id) } }
                }
                Button("Edit Queue…") { model.editingQueue = queue }
                if !queue.isDefault {
                    Divider()
                    Button("Delete Queue", role: .destructive) { Task { await model.deleteQueue(queue.id) } }
                }
            }
    }

    /// Default queue is neutral; scheduled queues read as time (indigo), other queues as lists (purple).
    static func tile(for queue: DownloadQueue) -> SidebarIcon.Tile {
        if queue.isDefault { return .init(symbol: "tray.fill", color: .gray) }
        if queue.schedule != nil { return .init(symbol: "calendar.badge.clock", color: .indigo) }
        return .init(symbol: "list.bullet", color: .purple)
    }
}

/// System Settings–style icon: a white symbol on a rounded, softly graded color tile.
struct SidebarIcon: View {
    struct Tile {
        let symbol: String
        let color: Color
    }

    let tile: Tile

    init(_ tile: Tile) {
        self.tile = tile
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(tile.color.gradient)
            .overlay {
                RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(.white.opacity(0.12), lineWidth: 0.5)
            }
            .frame(width: 20, height: 20)
            .overlay {
                Image(systemName: tile.symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .symbolRenderingMode(.monochrome)
            }
            .shadow(color: .black.opacity(0.15), radius: 0.5, y: 0.5)
            .accessibilityHidden(true)
    }
}

/// One hue per meaning: blue for everything, cyan for in flight, orange for waiting, green for done, red for trouble.
extension SidebarFilter {
    var tile: SidebarIcon.Tile {
        switch self {
        case .all: .init(symbol: "tray.full.fill", color: .blue)
        case .active: .init(symbol: "arrow.down", color: .cyan)
        case .queued: .init(symbol: "clock.fill", color: .orange)
        case .completed: .init(symbol: "checkmark", color: .green)
        case .failed: .init(symbol: "exclamationmark.triangle.fill", color: .red)
        case .queue: .init(symbol: "list.bullet", color: .purple)
        }
    }
}
