import AppKit
import RocketCore
import RocketDesign
import SwiftUI

/// The main window's content column: filter bar, then the list or grid. Space pauses/resumes, ⌫ removes,
/// double-click or Return shows details.
public struct DownloadListView: View {
    @Bindable var model: DownloadsModel
    /// Card a dragged download would land in front of (grid queue view).
    @State private var dropTarget: UUID?

    public init(model: DownloadsModel) {
        self.model = model
    }

    public var body: some View {
        let items = model.visibleItems
        let positions = model.queuePositions
        Group {
            if !model.hasLoaded, model.items.isEmpty {
                VStack(spacing: RocketSpace.s3) {
                    ProgressView().controlSize(.small)
                    Text("Loading downloads…")
                        .font(.rocketBody)
                        .foregroundStyle(RocketColor.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if items.isEmpty {
                EmptyStateView(model: model)
            } else if model.viewMode == .grid {
                grid(items, positions: positions)
            } else {
                list(items, positions: positions)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .safeAreaInset(edge: .top, spacing: 0) { FilterBar(model: model) }
        .background(RocketColor.canvas)
        .navigationTitle(model.title(for: model.filter))
    }

    private func list(_ items: [DownloadItem], positions: [UUID: Int]) -> some View {
        List(selection: $model.selection) {
            ForEach(items) { item in
                DownloadRow(item: item, model: model, queuePosition: positions[item.id], isSelected: model.selection.contains(item.id))
                    .listRowInsets(EdgeInsets(top: RocketSpace.s3, leading: RocketSpace.s4, bottom: RocketSpace.s3, trailing: RocketSpace.s3))
                    .listRowSeparator(.visible)
                    .listRowSeparatorTint(RocketColor.hairline)
                    .draggable(item.id.uuidString)
            }
            // Drag to reorder inside a queue (FR-QUE-03).
            .onMove(perform: isQueue ? { source, destination in
                Task { await model.moveInCurrentQueue(from: source, to: destination) }
            } : nil)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .contextMenu(forSelectionType: UUID.self) { ids in
            DownloadMenuItems(ids: ids, model: model)
        } primaryAction: { ids in
            // Double-click or Return opens the details sheet.
            if ids.count == 1, let id = ids.first { model.showDetails(id) }
        }
        .modifier(DownloadKeys(model: model))
    }

    private func grid(_ items: [DownloadItem], positions: [UUID: Int]) -> some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 200, maximum: 280), spacing: RocketSpace.s4)], spacing: RocketSpace.s4) {
                ForEach(items) { item in
                    DownloadCard(item: item, model: model, queuePosition: positions[item.id], isSelected: model.selection.contains(item.id))
                        .draggable(item.id.uuidString)
                        .overlay(alignment: .leading) {
                            if dropTarget == item.id {
                                Capsule().fill(RocketColor.accent).frame(width: 3).offset(x: -RocketSpace.s3)
                            }
                        }
                        // Drag to reorder inside a queue (FR-QUE-03): drops land in front of this card.
                        .dropDestination(for: String.self) { ids, _ in
                            reorder(ids, before: item.id)
                        } isTargeted: { targeted in
                            guard isQueue else { return }
                            if targeted { dropTarget = item.id } else if dropTarget == item.id { dropTarget = nil }
                        }
                        .onTapGesture(count: 2) { model.showDetails(item.id) }
                        .onTapGesture { select(item.id) }
                        .contextMenu {
                            DownloadMenuItems(ids: model.selection.contains(item.id) ? model.selection : [item.id], model: model)
                        }
                }
            }
            .padding(RocketSpace.s5)
        }
        // Dropped on empty space: move to the end of the queue.
        .dropDestination(for: String.self) { ids, _ in reorder(ids, before: nil) }
        .focusable()
        .focusEffectDisabled()
        .modifier(DownloadKeys(model: model))
    }

    private func reorder(_ strings: [String], before: UUID?) -> Bool {
        dropTarget = nil
        guard case .queue(let queueID) = model.filter else { return false }
        let ids = strings.compactMap(UUID.init(uuidString:)).filter { $0 != before }
        guard !ids.isEmpty else { return false }
        Task { await model.move(ids, toQueue: queueID, before: before) }
        return true
    }

    /// Click selects one; ⌘-click toggles; ⇧-click adds.
    private func select(_ id: UUID) {
        let flags = NSEvent.modifierFlags
        if flags.contains(.command) {
            if model.selection.contains(id) { model.selection.remove(id) } else { model.selection.insert(id) }
        } else if flags.contains(.shift) {
            model.selection.insert(id)
        } else {
            model.selection = [id]
        }
    }

    private var isQueue: Bool {
        if case .queue = model.filter { return true }
        return false
    }
}

/// Space toggles, ⌫ removes, ⌘V adds, Esc clears the selection.
private struct DownloadKeys: ViewModifier {
    let model: DownloadsModel

    func body(content: Content) -> some View {
        content
            .onKeyPress(.space) {
                let ids = model.selection
                Task { await model.toggle(ids) }
                return .handled
            }
            .onKeyPress(.escape) {
                guard !model.selection.isEmpty else { return .ignored }
                model.selection = []
                return .handled
            }
            .onPasteCommand(of: [.plainText, .url]) { _ in model.beginAdding() }
            .onDeleteCommand {
                let ids = model.selection
                Task { await model.remove(ids) }
            }
    }
}

/// Category pills, removable refinement chips, queue controls and sort.
private struct FilterBar: View {
    @Bindable var model: DownloadsModel

    var body: some View {
        HStack(spacing: RocketSpace.s3) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: RocketSpace.s2) {
                    Button("All") { model.category = nil }
                        .buttonStyle(PillButtonStyle(selected: model.category == nil))
                    ForEach(categories, id: \.self) { category in
                        Button {
                            model.category = model.category == category ? nil : category
                        } label: {
                            Label(category.title, systemImage: category.symbol)
                        }
                        .buttonStyle(PillButtonStyle(selected: model.category == category))
                    }
                    if model.sizeFilter != .any || model.dateFilter != .any {
                        Divider().frame(height: 16).padding(.horizontal, RocketSpace.s2)
                    }
                    if model.sizeFilter != .any {
                        Chip(title: model.sizeFilter.title) { model.sizeFilter = .any }
                    }
                    if model.dateFilter != .any {
                        Chip(title: model.dateFilter.title) { model.dateFilter = .any }
                    }
                }
            }
            if case .queue(let id) = model.filter {
                queueControls(id)
            } else {
                Menu {
                    Picker("Sort By", selection: $model.sort) {
                        ForEach(DownloadSort.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.inline)
                } label: {
                    Text("Sort by: \(model.sort.title)")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .font(.rocketLabel)
                .foregroundStyle(RocketColor.textSecondary)
            }
        }
        .padding(.horizontal, RocketSpace.s5)
        .padding(.vertical, RocketSpace.s3)
        .background(RocketColor.canvas)
        .overlay(alignment: .bottom) { Rectangle().fill(RocketColor.hairline).frame(height: 1) }
    }

    /// Only categories that exist in the list, plus the selected one, so the bar stays short.
    private var categories: [FileCategory] {
        let present = Set(model.items.map(\.category))
        return FileCategory.allCases.filter { present.contains($0) || $0 == model.category }
    }

    @ViewBuilder
    private func queueControls(_ id: String) -> some View {
        Text("Run order")
            .font(.rocketLabel)
            .foregroundStyle(RocketColor.textTertiary)
        if model.queueIsRunning(id) {
            Button("Pause Queue", systemImage: "pause.circle") { Task { await model.pauseQueue(id) } }
                .buttonStyle(.rocketIcon)
                .help("Pause every download in this queue")
        } else {
            Button("Resume Queue", systemImage: "play.circle") { Task { await model.resumeQueue(id) } }
                .buttonStyle(.rocketIcon)
                .help("Resume this queue's paused downloads")
        }
        if let queue = model.queues.first(where: { $0.id == id }) {
            Button("Edit Queue", systemImage: "slider.horizontal.3") { model.editingQueue = queue }
                .buttonStyle(.rocketIcon)
                .help("Edit queue")
        }
    }
}

/// Active refinement with a remove button.
private struct Chip: View {
    let title: String
    let remove: () -> Void

    var body: some View {
        Button(action: remove) {
            HStack(spacing: RocketSpace.s2) {
                Text(title)
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
            }
        }
        .buttonStyle(PillButtonStyle(selected: true))
        .help("Remove filter")
    }
}

/// One symbol, one sentence, one hint. No illustrations.
struct EmptyStateView: View {
    let model: DownloadsModel

    var body: some View {
        VStack(spacing: RocketSpace.s3) {
            Image(systemName: symbol)
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(RocketColor.textTertiary)
            Text(title)
                .font(.rocketHeadline)
                .foregroundStyle(RocketColor.textPrimary)
            if filtered {
                Button("Clear Filters") {
                    model.clearRefinements()
                    model.search = ""
                }
                .buttonStyle(.link)
                .font(.rocketBody)
            } else if model.filter == .all {
                Text("Copy a link and press ⌘V, or use rocket add in Terminal.")
                    .font(.rocketBody)
                    .foregroundStyle(RocketColor.textSecondary)
            }
        }
        .multilineTextAlignment(.center)
        .padding(RocketSpace.s6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var filtered: Bool { model.hasRefinements || !model.search.isEmpty }

    private var symbol: String {
        filtered ? "line.3.horizontal.decrease.circle" : model.filter == .all ? "arrow.down.circle" : model.filter.symbol
    }

    private var title: String {
        if filtered { return String(localized: "No matching downloads") }
        switch model.filter {
        case .all: return String(localized: "No downloads yet")
        case .active: return String(localized: "Nothing is downloading")
        case .queued: return String(localized: "Nothing is waiting")
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
            Section {
                ForEach(SidebarFilter.statuses) { filter in
                    SidebarLabel(title: filter.title, symbol: filter.symbol)
                        .badge(model.count(filter))
                        .tag(filter)
                }
            }
            Section {
                ForEach(model.queues) { queue in
                    SidebarLabel(title: queue.name, symbol: queue.schedule == nil ? "list.bullet" : "calendar.badge.clock")
                        .badge(model.count(.queue(queue.id)))
                        .help(queue.schedule?.summary ?? "")
                        .tag(SidebarFilter.queue(queue.id))
                        .dropDestination(for: String.self) { ids, _ in
                            let ids = ids.compactMap(UUID.init(uuidString:))
                            Task { await model.move(ids, toQueue: queue.id) }
                            return !ids.isEmpty
                        }
                        .contextMenu {
                            if model.queueIsRunning(queue.id) {
                                Button("Pause Queue") { Task { await model.pauseQueue(queue.id) } }
                            } else {
                                Button("Resume Queue") { Task { await model.resumeQueue(queue.id) } }
                            }
                            Divider()
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
        // Only agent problems show here; the view is empty while the agent is healthy.
        .safeAreaInset(edge: .bottom, spacing: 0) { footer.padding(.horizontal, RocketSpace.s4).padding(.vertical, RocketSpace.s3) }
    }
}

/// Neutral icon instead of the accent-tinted default, like the reference.
private struct SidebarLabel: View {
    let title: String
    let symbol: String

    var body: some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: symbol).foregroundStyle(RocketColor.textSecondary)
        }
    }
}

/// Magnifying-glass button that expands into a search field (⌘F); collapses when emptied and unfocused.
public struct ToolbarSearchField: View {
    @Bindable var model: DownloadsModel
    @FocusState private var focused: Bool

    public init(model: DownloadsModel) {
        self.model = model
    }

    public var body: some View {
        Group {
            if model.isSearching || !model.search.isEmpty {
                HStack(spacing: RocketSpace.s2) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(RocketColor.textSecondary)
                    TextField("Search downloads", text: $model.search)
                        .textFieldStyle(.plain)
                        .focused($focused)
                        .frame(width: 180)
                        .onKeyPress(.escape) {
                            model.search = ""
                            model.isSearching = false
                            return .handled
                        }
                    if !model.search.isEmpty {
                        Button("Clear Search", systemImage: "xmark.circle.fill") { model.search = "" }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.plain)
                            .foregroundStyle(RocketColor.textTertiary)
                    }
                }
                .font(.rocketBody)
                .padding(.horizontal, RocketSpace.s3)
                .frame(height: 28)
                .background(RocketColor.fillSubtle, in: Capsule())
                .onAppear { focused = true }
            } else {
                Button("Search", systemImage: "magnifyingglass") { model.isSearching = true }
                    .help("Search downloads (⌘F)")
            }
        }
        .onChange(of: model.isSearching) { _, searching in focused = searching }
        .onChange(of: focused) { _, isFocused in
            if !isFocused, model.search.isEmpty { model.isSearching = false }
        }
    }
}
