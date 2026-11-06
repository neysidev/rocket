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
            .searchable(text: $model.search, isPresented: $model.isSearching, placement: .toolbar, prompt: Text("Search names and links"))
            .toolbar { DownloadToolbar(model: model, visibleIDs: items.map(\.id)) }
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
            .onChange(of: items.map(\.id)) { _, ids in
                // Bulk actions only ever touch rows you can see: drop selected rows that a filter or search hid.
                let visible = model.selection.intersection(ids)
                if visible != model.selection { model.selection = visible }
            }
            .onExitCommand { model.selection = [] }
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
                NameCell(item: item, queuePosition: positions[item.id])
                    .help(Self.statusHelp(item, position: positions[item.id]))
            }
            .width(min: 220, ideal: 420)
            .customizationID("name")
            .disabledCustomizationBehavior(.visibility)
            TableColumn("Progress") { item in StatusCell(item: item, model: model) }
                .width(min: 130, ideal: 190, max: 280)
                .customizationID("progress")
            TableColumn("Size") { item in
                Text(Self.shortSize(item))
                    .font(.rocketLabel)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.trailing, RocketSpace.s3)
            }
            .width(min: 80, ideal: 130, max: 180)
            .customizationID("size")
            TableColumn("Date") { item in
                Text(item.download.completedAt ?? item.download.createdAt,
                     format: .dateTime.month(.abbreviated).day().hour().minute())
                    .font(.rocketLabel)
                    .foregroundStyle(item.download.state == .completed ? .secondary : .tertiary)
                    .lineLimit(1)
                    .help(item.download.completedAt == nil ? "Added" : "Completed")
            }
            .width(min: 90, ideal: 120)
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

    /// "12 MB of 40 MB" while bytes are arriving, the total otherwise.
    static func shortSize(_ item: DownloadItem) -> String {
        let download = item.download
        let total = download.totalBytes.map(Format.bytes)
        switch download.state {
        case .downloading, .verifying, .paused:
            return total.map { "\(Format.bytes(download.receivedBytes)) of \($0)" } ?? Format.bytes(download.receivedBytes)
        default:
            if let total { return total }
            return download.receivedBytes > 0 ? Format.bytes(download.receivedBytes) : "—"
        }
    }

    /// "Paused", "#2 in queue", or the failure message.
    static func statusHelp(_ item: DownloadItem, position: Int?) -> String {
        let download = item.download
        if let failure = download.failure, download.state == .failed { return "\(download.state.title): \(failure.userMessage)" }
        if download.state == .queued, let position { return String(localized: "Queued, #\(position) in queue") }
        return download.state.title
    }
}

/// Default bar: New Download (prominent), Filter, Sort, search (system field), More.
/// With rows selected it becomes a contextual bar: count, then only the bulk actions the selection allows.
private struct DownloadToolbar: ToolbarContent {
    @Bindable var model: DownloadsModel
    let visibleIDs: [UUID]

    var body: some ToolbarContent {
        if model.selection.isEmpty {
            ToolbarItem(placement: .primaryAction) {
                Button { model.beginAdding() } label: {
                    Label("New Download", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .labelStyle(.titleAndIcon)
                .help("Add a download from a link (⌘N)")
            }
            ToolbarItemGroup(placement: .primaryAction) {
                filterMenu
                if !isQueue { sortMenu }
                moreMenu
            }
        } else {
            selectionItems
        }
    }

    // MARK: Selection bar

    @ToolbarContentBuilder
    private var selectionItems: some ToolbarContent {
        let ids = model.selection
        let states = ids.compactMap(model.download).map(\.state)
        let paused = ids.filter { model.download($0)?.state == .paused }
        let failed = ids.filter { model.download($0)?.state == .failed }
        ToolbarItem(placement: .primaryAction) {
            Text("\(ids.count) selected")
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .accessibilityLabel("\(ids.count) downloads selected")
        }
        ToolbarItemGroup(placement: .primaryAction) {
            if states.contains(where: \.isActive) {
                Button { Task { await model.pause(ids) } } label: { Label("Pause", systemImage: "pause") }
                    .help("Pause the selected downloads that are running (Space)")
            }
            if !paused.isEmpty {
                Button { Task { await model.resume(paused) } } label: { Label("Resume", systemImage: "play") }
                    .help("Resume the selected paused downloads")
            }
            if !failed.isEmpty {
                Button { Task { await model.resume(failed) } } label: { Label("Retry", systemImage: "arrow.clockwise") }
                    .help("Retry the selected failed downloads")
            }
            Button { Task { await model.remove(ids) } } label: { Label("Remove", systemImage: "minus.circle") }
                .help("Remove the selected downloads from the list (⌫)")
        }
        ToolbarItemGroup(placement: .primaryAction) {
            if !Set(visibleIDs).isSubset(of: ids) {
                Button { model.selection = Set(visibleIDs) } label: { Label("Select All", systemImage: "checklist.checked") }
                    .help("Select every download in this view (⌘A)")
            }
            Button { model.selection = [] } label: { Label("Clear Selection", systemImage: "xmark.circle") }
                .help("Clear the selection (Esc)")
        }
    }

    // MARK: Default bar

    private var isQueue: Bool {
        if case .queue = model.filter { return true }
        return false
    }

    private var filterMenu: some View {
        Menu {
            Picker("Status", selection: Binding<SidebarFilter>(get: { isQueue ? .all : model.filter }, set: { model.filter = $0 })) {
                ForEach(SidebarFilter.statuses) { Label($0.title, systemImage: $0.symbol).tag($0) }
            }
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
        .labelStyle(.titleAndIcon)
        .help(model.hasRefinements ? "Filters are on. Filter by status, type, size, date and source" : "Filter by status, type, size, date and source")
    }

    private var sortMenu: some View {
        Menu {
            Picker("Sort By", selection: $model.sort) {
                ForEach(DownloadSort.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.inline)
        } label: {
            Label("Sort: \(model.sort.title)", systemImage: "arrow.up.arrow.down")
        }
        .labelStyle(.titleAndIcon)
        .help("Change the sort order")
    }

    /// Less frequent, list-wide operations. Same actions as the Download menu, so shortcuts stay discoverable.
    private var moreMenu: some View {
        Menu {
            if case .queue(let id) = model.filter, let queue = model.queues.first(where: { $0.id == id }) {
                Section(queue.name) {
                    if model.queueIsRunning(id) {
                        Button("Pause Queue", systemImage: "pause") { Task { await model.pauseQueue(id) } }
                    } else {
                        Button("Resume Queue", systemImage: "play") { Task { await model.resumeQueue(id) } }
                    }
                    Button("Edit Queue…", systemImage: "slider.horizontal.3") { model.editingQueue = queue }
                }
            }
            Section {
                Button("Pause All", systemImage: "pause.circle") { Task { await model.pauseAll() } }
                    .disabled(!model.hasRunning)
                Button("Resume All", systemImage: "play.circle") { Task { await model.resumeAll() } }
                    .disabled(!model.hasPaused)
            }
            Section {
                Button("Clear Completed", systemImage: "checkmark.circle.badge.xmark") { Task { await model.clearCompleted() } }
                    .disabled(!model.hasFinished)
                Button("Download Insights", systemImage: "chart.bar") { model.showInsights = true }
            }
        } label: {
            Label("More", systemImage: "ellipsis.circle")
        }
        .help("More actions")
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

/// Source list: Library status filters and Queues with live counts. Downloads can be dropped on a queue to move them there.
public struct DownloadSidebar<Footer: View>: View {
    @Bindable var model: DownloadsModel
    let footer: Footer
    @State private var dropQueue: String?
    @State private var renaming: String?
    @State private var draftName = ""
    @State private var deleting: DownloadQueue?
    @FocusState private var renameFocused: Bool

    public init(model: DownloadsModel, @ViewBuilder footer: () -> Footer) {
        self.model = model
        self.footer = footer()
    }

    public var body: some View {
        List(selection: Binding<SidebarFilter?>(get: { model.filter }, set: { if let filter = $0 { model.filter = filter } })) {
            Section("Library") {
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
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Divider()
                SettingsLink {
                    Label("Settings", systemImage: "gearshape")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .help("Settings (⌘,)")
                footer.padding(.horizontal, 8)
            }
            .padding(.bottom, 8)
        }
        .confirmationDialog(
            "Delete “\(deleting?.name ?? "")”?",
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            presenting: deleting
        ) { queue in
            Button("Delete Queue", role: .destructive) { Task { await model.deleteQueue(queue.id) } }
        } message: { queue in
            let count = model.count(.queue(queue.id))
            if count == 0 { Text("This queue is empty.") } else { Text("Its \(count) downloads move to the Default queue.") }
        }
    }

    @ViewBuilder private func queueName(_ queue: DownloadQueue) -> some View {
        if renaming == queue.id {
            TextField("Queue name", text: $draftName)
                .textFieldStyle(.plain)
                .focused($renameFocused)
                .onAppear { renameFocused = true }
                .onSubmit { commitRename(queue) }
                .onExitCommand { renaming = nil }
                .onChange(of: renameFocused) { _, focused in if !focused { commitRename(queue) } }
        } else {
            Text(queue.name)
        }
    }

    private func startRename(_ queue: DownloadQueue) {
        draftName = queue.name
        renaming = queue.id
    }

    private func commitRename(_ queue: DownloadQueue) {
        guard renaming == queue.id else { return }
        renaming = nil
        let name = draftName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, name != queue.name else { return }
        var renamed = queue
        renamed.name = name
        Task { await model.saveQueue(renamed) }
    }

    private func queueRow(_ queue: DownloadQueue) -> some View {
        Label { queueName(queue) } icon: { SidebarIcon(Self.tile(for: queue)) }
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
                Divider()
                Button("Rename") { startRename(queue) }
                Button("Edit Queue…") { model.editingQueue = queue }
                if !queue.isDefault {
                    Divider()
                    Button("Delete Queue…", role: .destructive) { deleting = queue }
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
