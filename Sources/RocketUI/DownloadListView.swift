import AppKit
import RocketCore
import RocketDesign
import SwiftUI

/// The main window's content column: header, filter bar, then the list or grid.
/// Click selects (⌘ toggles, ⇧ extends), ↑↓ move, Space pauses/resumes, ⌫ removes, double-click or Return shows details.
public struct DownloadListView: View {
    @Bindable var model: DownloadsModel
    /// Row or card a dragged download would land in front of (queue views).
    @State private var dropTarget: UUID?
    /// Where ⇧-click and ⇧-arrow selections extend from.
    @State private var anchor: UUID?
    @FocusState private var focused: Bool

    public init(model: DownloadsModel) {
        self.model = model
    }

    public var body: some View {
        let items = model.visibleItems
        let positions = model.queuePositions
        VStack(spacing: 0) {
            ContentHeader(model: model, count: items.count)
            if showsFilterBar { FilterBar(model: model) }
            Group {
                if !model.hasLoaded, model.items.isEmpty {
                    VStack(spacing: RocketSpace.s4) {
                        RocketSpinner(size: 18)
                        Text("Loading downloads…")
                            .font(.rocketBody)
                            .foregroundStyle(RocketColor.textSecondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .rocketTransition(RocketTransition.content)
                } else if items.isEmpty {
                    EmptyStateView(model: model)
                        .rocketTransition(RocketTransition.content)
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            if model.viewMode == .grid { grid(items, positions: positions) } else { list(items, positions: positions) }
                        }
                        // Dropped on empty space: move to the end of the queue.
                        .dropDestination(for: String.self) { ids, _ in reorder(ids, before: nil) }
                        .focusable()
                        .focusEffectDisabled()
                        .focused($focused)
                        .modifier(DownloadKeys(model: model, items: items, anchor: $anchor, columns: model.viewMode == .grid) { id in
                            proxy.scrollTo(id, anchor: .center)
                        })
                    }
                    .rocketTransition(RocketTransition.content)
                }
            }
            .id(contentPhase)
            .rocketAnimation(RocketMotion.standard, value: contentPhase)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(RocketColor.canvas)
    }

    private var showsFilterBar: Bool {
        model.hasRefinements || Set(model.items.map(\.category)).count > 1 || model.sourceHosts.count > 1
    }

    private var contentPhase: String {
        if !model.hasLoaded, model.items.isEmpty { return "loading" }
        if model.visibleItems.isEmpty { return "empty-\(String(describing: model.filter))-\(model.search)" }
        return "list-\(model.viewMode)-\(String(describing: model.filter))"
    }

    private func list(_ items: [DownloadItem], positions: [UUID: Int]) -> some View {
        LazyVStack(spacing: 2) {
            ForEach(items) { item in
                DownloadRow(item: item, model: model, queuePosition: positions[item.id], isSelected: model.selection.contains(item.id))
                    .id(item.id)
                    .overlay(alignment: .top) {
                        if dropTarget == item.id {
                            Capsule().fill(RocketColor.accent).frame(height: 2).offset(y: -2).padding(.horizontal, RocketSpace.s3)
                                .transition(.opacity.combined(with: .scale(scale: 0.8, anchor: .center)))
                        }
                    }
                    .rocketTransition(RocketTransition.list)
                    .modifier(ItemInteractions(item: item, items: items, model: model, anchor: $anchor, dropTarget: $dropTarget,
                                               focused: $focused, isQueue: isQueue, reorder: reorder))
            }
        }
        .rocketAnimation(RocketMotion.standard, value: items.map(\.id))
        .padding(.horizontal, RocketSpace.s3)
        .padding(.vertical, RocketSpace.s3)
    }

    private func grid(_ items: [DownloadItem], positions: [UUID: Int]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 210, maximum: 290), spacing: RocketSpace.s4)], spacing: RocketSpace.s4) {
            ForEach(items) { item in
                DownloadCard(item: item, model: model, queuePosition: positions[item.id], isSelected: model.selection.contains(item.id))
                    .id(item.id)
                    .overlay(alignment: .leading) {
                        if dropTarget == item.id {
                            Capsule().fill(RocketColor.accent).frame(width: 2).offset(x: -RocketSpace.s3 + 2)
                                .transition(.opacity.combined(with: .scale(scale: 0.8, anchor: .center)))
                        }
                    }
                    .rocketTransition(RocketTransition.list)
                    .modifier(ItemInteractions(item: item, items: items, model: model, anchor: $anchor, dropTarget: $dropTarget,
                                               focused: $focused, isQueue: isQueue, reorder: reorder))
            }
        }
        .rocketAnimation(RocketMotion.standard, value: items.map(\.id))
        .padding(RocketSpace.s5)
    }

    private func reorder(_ strings: [String], before: UUID?) -> Bool {
        dropTarget = nil
        guard case .queue(let queueID) = model.filter else { return false }
        let ids = strings.compactMap(UUID.init(uuidString:)).filter { $0 != before }
        guard !ids.isEmpty else { return false }
        Task { await model.move(ids, toQueue: queueID, before: before) }
        return true
    }

    private var isQueue: Bool {
        if case .queue = model.filter { return true }
        return false
    }
}

/// Click, double-click, drag (to reorder or onto a sidebar queue) and right-click for one row or card.
private struct ItemInteractions: ViewModifier {
    let item: DownloadItem
    let items: [DownloadItem]
    let model: DownloadsModel
    @Binding var anchor: UUID?
    @Binding var dropTarget: UUID?
    var focused: FocusState<Bool>.Binding
    let isQueue: Bool
    let reorder: ([String], UUID?) -> Bool

    func body(content: Content) -> some View {
        content
            .draggable(item.id.uuidString)
            // Drag to reorder inside a queue (FR-QUE-03): drops land in front of this item.
            .dropDestination(for: String.self) { ids, _ in
                reorder(ids, item.id)
            } isTargeted: { targeted in
                guard isQueue else { return }
                withAnimation(RocketMotion.fast) {
                    if targeted { dropTarget = item.id } else if dropTarget == item.id { dropTarget = nil }
                }
            }
            .onTapGesture { click() }
            .rocketContextMenu(onOpen: {
                if !model.selection.contains(item.id) { model.selection = [item.id] }
            }, sections: {
                DownloadMenu.sections(ids: model.selection.contains(item.id) ? model.selection : [item.id], model: model)
            })
    }

    private func click() {
        focused.wrappedValue = true
        if (NSApp.currentEvent?.clickCount ?? 1) >= 2 {
            model.showDetails(item.id)
            return
        }
        let flags = NSEvent.modifierFlags
        if flags.contains(.command) {
            if model.selection.contains(item.id) { model.selection.remove(item.id) } else { model.selection.insert(item.id) }
        } else if flags.contains(.shift), let anchor, let from = items.firstIndex(where: { $0.id == anchor }),
                  let to = items.firstIndex(where: { $0.id == item.id }) {
            model.selection = Set(items[min(from, to)...max(from, to)].map(\.id))
            return
        } else {
            model.selection = [item.id]
        }
        anchor = item.id
    }
}

/// ↑↓ (←→ in the grid) move the selection, ⇧ extends it, Return shows details, Space toggles, ⌫ removes,
/// ⌘A selects all, ⌘V adds, Esc clears the selection. Keyboard moves never animate.
private struct DownloadKeys: ViewModifier {
    let model: DownloadsModel
    let items: [DownloadItem]
    @Binding var anchor: UUID?
    let columns: Bool
    let reveal: (UUID) -> Void

    func body(content: Content) -> some View {
        content
            .onKeyPress(keys: columns ? [.upArrow, .downArrow, .leftArrow, .rightArrow] : [.upArrow, .downArrow]) { press in
                let step = press.key == .upArrow || press.key == .leftArrow ? -1 : 1
                return move(step, extend: press.modifiers.contains(.shift))
            }
            .onKeyPress(.return) {
                guard model.selection.count == 1, let id = model.selection.first else { return .ignored }
                model.showDetails(id)
                return .handled
            }
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
            .onCommand(#selector(NSResponder.selectAll(_:))) { model.selection = Set(items.map(\.id)) }
            .onPasteCommand(of: [.plainText, .url]) { _ in model.beginAdding() }
            .onDeleteCommand {
                let ids = model.selection
                Task { await model.remove(ids) }
            }
    }

    private func move(_ step: Int, extend: Bool) -> KeyPress.Result {
        guard !items.isEmpty else { return .ignored }
        let ids = items.map(\.id)
        let cursor = anchor.flatMap { ids.firstIndex(of: $0) } ?? ids.lastIndex { model.selection.contains($0) }
        let index = cursor.map { min(max(0, $0 + step), ids.count - 1) } ?? (step > 0 ? 0 : ids.count - 1)
        if extend { model.selection.insert(ids[index]) } else { model.selection = [ids[index]] }
        anchor = ids[index]
        reveal(ids[index])
        return .handled
    }
}

/// Title and count, queue controls, search, filter, sort and the list/grid switch. Empty space drags the window.
private struct ContentHeader: View {
    @Bindable var model: DownloadsModel
    let count: Int

    var body: some View {
        HStack(spacing: RocketSpace.s3) {
            Text(model.title(for: model.filter))
                .font(.rocketTitle)
                .foregroundStyle(RocketColor.textPrimary)
                .lineLimit(1)
            Text("\(count)")
                .font(.rocketLabel)
                .monospacedDigit()
                .foregroundStyle(RocketColor.textTertiary)
                .contentTransition(.numericText(value: Double(count)))
            if case .queue(let id) = model.filter { queueControls(id) }
            Spacer(minLength: RocketSpace.s4)
            HeaderSearchField(model: model)
            filterMenu
            if !isQueue { sortMenu }
            RocketSegmented(selection: $model.viewMode, segments: DownloadViewMode.allCases.map {
                RocketSegment($0, title: $0 == .list ? String(localized: "List (⌘1)") : String(localized: "Grid (⌘2)"), symbol: $0.symbol)
            }, iconOnly: true)
        }
        .padding(.leading, RocketSpace.s6)
        .padding(.trailing, RocketSpace.s4)
        .frame(height: RocketSize.headerHeight)
        .rocketWindowDragArea()
        .overlay(alignment: .bottom) { Rectangle().fill(RocketColor.border).frame(height: 1) }
    }

    private var isQueue: Bool {
        if case .queue = model.filter { return true }
        return false
    }

    private var filterMenu: some View {
        RocketMenuButton(alignment: .trailing) {
            [
                RocketMenuSection(items: [
                    .submenu(String(localized: "Type"), symbol: "doc", children:
                        [RocketMenuItem(String(localized: "Any Type"), checked: model.category == nil) { model.category = nil }]
                            + FileCategory.allCases.map { category in
                                RocketMenuItem(category.title, checked: model.category == category) { model.category = category }
                            }),
                    .submenu(String(localized: "Size"), symbol: "externaldrive", children: SizeFilter.allCases.map { size in
                        RocketMenuItem(size.title, checked: model.sizeFilter == size) { model.sizeFilter = size }
                    }),
                    .submenu(String(localized: "Date Added"), symbol: "calendar", children: DateFilter.allCases.map { date in
                        RocketMenuItem(date.title, checked: model.dateFilter == date) { model.dateFilter = date }
                    }),
                    .submenu(String(localized: "Source"), symbol: "globe", children:
                        [RocketMenuItem(String(localized: "Any Source"), checked: model.sourceHost == nil) { model.sourceHost = nil }]
                            + model.sourceHosts.map { host in
                                RocketMenuItem(host, checked: model.sourceHost == host) { model.sourceHost = host }
                            }),
                ]),
                RocketMenuSection(items: [
                    RocketMenuItem(String(localized: "Clear Filters"), symbol: "xmark", enabled: model.hasRefinements) { model.clearRefinements() },
                ]),
            ]
        } label: {
            Label("Filter", systemImage: "line.3.horizontal.decrease")
                .overlay(alignment: .topTrailing) {
                    if model.hasRefinements {
                        Circle().fill(RocketColor.accent).frame(width: 6, height: 6).offset(x: 3, y: -2)
                    }
                }
        }
        .buttonStyle(IconButtonStyle(isActive: model.hasRefinements))
        .rocketTooltip(String(localized: "Filter by type, source, size and date"))
    }

    private var sortMenu: some View {
        RocketMenuButton(alignment: .trailing) {
            [RocketMenuSection(String(localized: "Sort by"), items: DownloadSort.allCases.map { sort in
                RocketMenuItem(sort.title, checked: model.sort == sort) { model.sort = sort }
            })]
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "arrow.up.arrow.down").font(.system(size: 10.5, weight: .semibold))
                Text(model.sort.title)
            }
        }
        .buttonStyle(RocketButtonStyle(.ghost, size: .small))
        .accessibilityLabel("Sort by \(model.sort.title)")
    }

    @ViewBuilder
    private func queueControls(_ id: String) -> some View {
        if let queue = model.queues.first(where: { $0.id == id }), let schedule = queue.schedule {
            Label(schedule.summary, systemImage: "clock")
                .font(.rocketCaption)
                .foregroundStyle(RocketColor.textSecondary)
                .padding(.horizontal, RocketSpace.s3)
                .frame(height: 20)
                .background(RocketColor.control, in: Capsule())
                .lineLimit(1)
        }
        if model.queueIsRunning(id) {
            Button("Pause Queue", systemImage: "pause") { Task { await model.pauseQueue(id) } }
                .buttonStyle(.rocketIcon)
                .rocketTooltip(String(localized: "Pause every download in this queue"))
        } else {
            Button("Resume Queue", systemImage: "play") { Task { await model.resumeQueue(id) } }
                .buttonStyle(.rocketIcon)
                .rocketTooltip(String(localized: "Resume this queue's paused downloads"))
        }
        if let queue = model.queues.first(where: { $0.id == id }) {
            Button("Edit Queue", systemImage: "slider.horizontal.3") { model.editingQueue = queue }
                .buttonStyle(.rocketIcon)
                .rocketTooltip(String(localized: "Edit queue"))
        }
    }
}

/// Category pills and removable refinement chips.
private struct FilterBar: View {
    @Bindable var model: DownloadsModel

    var body: some View {
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
                if model.sourceHost != nil || model.sizeFilter != .any || model.dateFilter != .any {
                    Rectangle().fill(RocketColor.border).frame(width: 1, height: 14).padding(.horizontal, RocketSpace.s2)
                }
                if let host = model.sourceHost {
                    Chip(title: host) { model.sourceHost = nil }
                        .rocketTransition(RocketTransition.reveal)
                }
                if model.sizeFilter != .any {
                    Chip(title: model.sizeFilter.title) { model.sizeFilter = .any }
                        .rocketTransition(RocketTransition.reveal)
                }
                if model.dateFilter != .any {
                    Chip(title: model.dateFilter.title) { model.dateFilter = .any }
                        .rocketTransition(RocketTransition.reveal)
                }
            }
            .padding(.horizontal, RocketSpace.s5)
        }
        .frame(height: 40)
        .overlay(alignment: .bottom) { Rectangle().fill(RocketColor.border).frame(height: 1) }
        .rocketAnimation(RocketMotion.standard, value: categories.map(\.self))
        .rocketAnimation(RocketMotion.fast, value: model.category)
        .rocketAnimation(RocketMotion.fast, value: model.sizeFilter)
        .rocketAnimation(RocketMotion.fast, value: model.dateFilter)
        .rocketAnimation(RocketMotion.fast, value: model.sourceHost)
    }

    /// Only categories that exist in the list, plus the selected one, so the bar stays short.
    private var categories: [FileCategory] {
        let present = Set(model.items.map(\.category))
        return FileCategory.allCases.filter { present.contains($0) || $0 == model.category }
    }
}

/// Active refinement with a remove button.
private struct Chip: View {
    let title: String
    let remove: () -> Void

    var body: some View {
        Button(action: remove) {
            HStack(spacing: 5) {
                Text(title)
                Image(systemName: "xmark").font(.system(size: 8, weight: .bold)).foregroundStyle(RocketColor.textTertiary)
            }
        }
        .buttonStyle(PillButtonStyle(selected: true))
        .accessibilityLabel("Remove filter \(title)")
    }
}

/// One tile, one sentence, one way forward. No illustrations.
struct EmptyStateView: View {
    let model: DownloadsModel

    var body: some View {
        VStack(spacing: RocketSpace.s4) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(RocketColor.textSecondary)
                .frame(width: 44, height: 44)
                .rocketCard(radius: 12)
            VStack(spacing: RocketSpace.s2) {
                Text(title)
                    .font(.rocketHeadline)
                    .foregroundStyle(RocketColor.textPrimary)
                if filtered {
                    Text("Try a different search or clear the filters.")
                        .font(.rocketBody)
                        .foregroundStyle(RocketColor.textSecondary)
                } else if model.filter == .all {
                    Text("Copy a link and press ⌘V, or use rocket add in Terminal.")
                        .font(.rocketBody)
                        .foregroundStyle(RocketColor.textSecondary)
                }
            }
            if filtered {
                Button("Clear Filters") {
                    model.clearRefinements()
                    model.search = ""
                }
                .buttonStyle(RocketButtonStyle(.secondary, size: .small))
            } else if model.filter == .all {
                Button {
                    model.beginAdding()
                } label: {
                    HStack(spacing: RocketSpace.s3) {
                        Text("New Download")
                        Text("⌘N").foregroundStyle(RocketColor.textInverse.opacity(0.6))
                    }
                }
                .buttonStyle(.rocketPrimary)
                .padding(.top, RocketSpace.s2)
            }
        }
        .multilineTextAlignment(.center)
        .padding(RocketSpace.s6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var filtered: Bool { model.hasRefinements || !model.search.isEmpty }

    private var symbol: String {
        filtered ? "line.3.horizontal.decrease" : model.filter == .all ? "arrow.down" : model.filter.symbol
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

/// Brand, New Download, status filters and queues with live counts, then live activity.
/// Downloads can be dropped on a queue to move them there.
public struct DownloadSidebar<Footer: View>: View {
    @Bindable var model: DownloadsModel
    let footer: Footer
    @State private var dropQueue: String?

    public init(model: DownloadsModel, @ViewBuilder footer: () -> Footer) {
        self.model = model
        self.footer = footer()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Room for the traffic lights; drags the window like a title bar.
            Color.clear.frame(height: 36).rocketWindowDragArea()
            HStack(spacing: RocketSpace.s3) {
                RocketMark(size: 20)
                Text("Rocket").font(.system(size: 13, weight: .semibold)).foregroundStyle(RocketColor.textPrimary)
                Spacer()
                SettingsLink {
                    Label("Settings", systemImage: "gearshape")
                }
                .buttonStyle(.rocketIcon)
                .rocketTooltip(String(localized: "Settings"), shortcut: "⌘,")
            }
            .padding(.leading, RocketSpace.s4)
            .padding(.trailing, RocketSpace.s3)
            .padding(.bottom, RocketSpace.s4)
            Button {
                model.beginAdding()
            } label: {
                HStack(spacing: RocketSpace.s3) {
                    Image(systemName: "plus").font(.system(size: 11.5, weight: .semibold)).foregroundStyle(RocketColor.textSecondary)
                    Text("New Download")
                    Spacer(minLength: 0)
                    Keycap("⌘N")
                }
            }
            .buttonStyle(RocketButtonStyle(.secondary, fullWidth: true))
            .padding(.horizontal, RocketSpace.s3)

            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(SidebarFilter.statuses) { filter in
                        SidebarRow(title: filter.title, symbol: filter.symbol, count: model.count(filter),
                                   isSelected: model.filter == filter && !model.showInsights, live: filter == .active && model.isDownloading) {
                            withAnimation(RocketMotion.standard) { model.filter = filter; model.showInsights = false }
                        }
                    }
                    SidebarRow(title: String(localized: "Insights"), symbol: "chart.bar", count: 0,
                               isSelected: model.showInsights) {
                        withAnimation(RocketMotion.standard) { model.showInsights = true }
                    }
                    .padding(.top, RocketSpace.s2)
                    HStack {
                        Text("Queues").rocketEyebrow()
                        Spacer()
                        Button("New Queue", systemImage: "plus") { model.newQueue() }
                            .buttonStyle(IconButtonStyle(size: 20))
                            .rocketTooltip(String(localized: "New queue"))
                    }
                    .padding(.leading, RocketSpace.s3)
                    .padding(.top, RocketSpace.s5)
                    .padding(.bottom, RocketSpace.s2)
                    ForEach(model.queues) { queue in
                        queueRow(queue)
                    }
                }
                .padding(.horizontal, RocketSpace.s3)
                .padding(.vertical, RocketSpace.s4)
            }
            .scrollIndicators(.never)

            VStack(alignment: .leading, spacing: RocketSpace.s3) {
                footer
                ActivityFooter(model: model)
            }
            .padding(RocketSpace.s3)
        }
        .frame(maxHeight: .infinity)
        .background(RocketColor.sidebar)
        .overlay(alignment: .trailing) { Rectangle().fill(RocketColor.border).frame(width: 1) }
    }

    private func queueRow(_ queue: DownloadQueue) -> some View {
        SidebarRow(title: queue.name, symbol: queue.schedule == nil ? "tray" : "calendar.badge.clock",
                   count: model.count(.queue(queue.id)),                    isSelected: model.filter == .queue(queue.id) && !model.showInsights,
                   isDropTarget: dropQueue == queue.id) {
            withAnimation(RocketMotion.standard) { model.filter = .queue(queue.id); model.showInsights = false }
        }
        .rocketTooltip(queue.schedule?.summary ?? "")
        .dropDestination(for: String.self) { ids, _ in
            dropQueue = nil
            let ids = ids.compactMap(UUID.init(uuidString:))
            Task { await model.move(ids, toQueue: queue.id) }
            return !ids.isEmpty
        } isTargeted: { targeted in
            withAnimation(RocketMotion.fast) {
                if targeted { dropQueue = queue.id } else if dropQueue == queue.id { dropQueue = nil }
            }
        }
        .rocketContextMenu {
            var items = [
                model.queueIsRunning(queue.id)
                    ? RocketMenuItem(String(localized: "Pause Queue"), symbol: "pause") { Task { await model.pauseQueue(queue.id) } }
                    : RocketMenuItem(String(localized: "Resume Queue"), symbol: "play") { Task { await model.resumeQueue(queue.id) } },
                RocketMenuItem(String(localized: "Edit Queue…"), symbol: "slider.horizontal.3") { model.editingQueue = queue },
            ]
            var sections = [RocketMenuSection(items: items)]
            if !queue.isDefault {
                items = [RocketMenuItem(String(localized: "Delete Queue"), symbol: "trash", role: .destructive) {
                    Task { await model.deleteQueue(queue.id) }
                }]
                sections.append(RocketMenuSection(items: items))
            }
            return sections
        }
    }
}

/// Sidebar navigation item: icon, title, count; one fill step when selected.
struct SidebarRow: View {
    let title: String
    let symbol: String
    let count: Int
    let isSelected: Bool
    var isDropTarget = false
    var live = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: RocketSpace.s3 + 1) {
                Image(systemName: symbol)
                    .font(.system(size: 12.5, weight: .regular))
                    .foregroundStyle(isSelected ? RocketColor.textPrimary : RocketColor.textSecondary)
                    .frame(width: 16)
                Text(title)
                    .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                    .foregroundStyle(isSelected || hovering ? RocketColor.textPrimary : RocketColor.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: RocketSpace.s2)
                if live { Circle().fill(RocketColor.accent).frame(width: 6, height: 6) }
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 11.5, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(RocketColor.textTertiary)
                        .contentTransition(.numericText(value: Double(count)))
                }
            }
            .padding(.horizontal, RocketSpace.s3)
            .frame(height: RocketSize.sidebarRow)
            .background(isSelected ? RocketColor.selected : hovering ? RocketColor.hover : .clear,
                        in: RoundedRectangle(cornerRadius: RocketRadius.small + 1, style: .continuous))
            .overlay {
                if isDropTarget {
                    RoundedRectangle(cornerRadius: RocketRadius.small + 1, style: .continuous).strokeBorder(RocketColor.accent, lineWidth: 1.5)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .rocketAnimation(RocketMotion.fast, value: hovering)
        .rocketAnimation(RocketMotion.fast, value: isSelected)
        .rocketAnimation(RocketMotion.fast, value: isDropTarget)
        .accessibilityLabel("\(title), \(count)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Total speed and a sparkline while downloading; pause or resume everything.
private struct ActivityFooter: View {
    let model: DownloadsModel

    var body: some View {
        HStack(spacing: RocketSpace.s3) {
            StatusGlyph(model.isDownloading ? .active(model.overallFraction) : model.hasPaused ? .paused(model.overallFraction) : .done, size: 12)
                .opacity(model.items.isEmpty ? 0.4 : 1)
            VStack(alignment: .leading, spacing: 1) {
                Text(model.isDownloading ? Format.speed(model.totalSpeed) : String(localized: "Idle"))
                    .font(.rocketLabel)
                    .monospacedDigit()
                    .foregroundStyle(model.isDownloading ? RocketColor.textPrimary : RocketColor.textSecondary)
                Text(summary)
                    .font(.rocketCaption)
                    .foregroundStyle(RocketColor.textTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if model.hasRunning {
                Button("Pause All", systemImage: "pause") { Task { await model.pauseAll() } }
                    .buttonStyle(IconButtonStyle(size: 24))
                    .rocketTooltip(String(localized: "Pause all"))
            } else if model.hasPaused {
                Button("Resume All", systemImage: "play") { Task { await model.resumeAll() } }
                    .buttonStyle(IconButtonStyle(size: 24))
                    .rocketTooltip(String(localized: "Resume all"))
            }
        }
        .padding(.horizontal, RocketSpace.s3)
        .frame(height: 44)
        .rocketCard()
        .accessibilityElement(children: .combine)
    }

    private var summary: String {
        let active = model.transferringCount
        let queued = model.queuedCount
        if active == 0, queued == 0 { return String(localized: "Nothing in flight") }
        return String(localized: "\(active) active · \(queued) queued")
    }
}

/// Magnifying-glass button that becomes a search field (⌘F); collapses when emptied and unfocused.
private struct HeaderSearchField: View {
    @Bindable var model: DownloadsModel
    @FocusState private var focused: Bool

    var body: some View {
        Group {
            if model.isSearching || !model.search.isEmpty {
                HStack(spacing: RocketSpace.s2 + 2) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(RocketColor.textTertiary)
                    TextField("Search downloads", text: $model.search)
                        .textFieldStyle(.plain)
                        .font(.rocketBody)
                        .focused($focused)
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
                .padding(.horizontal, RocketSpace.s3)
                .frame(width: 200, height: RocketSize.iconButton)
                .background(RocketColor.control, in: RoundedRectangle(cornerRadius: RocketRadius.small + 1, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: RocketRadius.small + 1, style: .continuous)
                    .strokeBorder(focused ? RocketColor.accent : RocketColor.border))
                .onAppear { focused = true }
                .rocketTransition(RocketTransition.reveal)
            } else {
                Button("Search", systemImage: "magnifyingglass") { model.isSearching = true }
                    .buttonStyle(.rocketIcon)
                    .rocketTooltip(String(localized: "Search"), shortcut: "⌘F")
                    .rocketTransition(RocketTransition.reveal)
            }
        }
        .rocketAnimation(RocketMotion.spring, value: model.isSearching)
        .onChange(of: model.isSearching) { _, searching in focused = searching }
        .onChange(of: focused) { _, isFocused in
            if !isFocused, model.search.isEmpty { model.isSearching = false }
        }
    }
}
