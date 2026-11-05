import AppKit
import Foundation
import RocketCore

/// Logical groups shown in the palette list.
enum CommandPaletteGroup: String, CaseIterable, Sendable {
    case recent
    case downloads
    case selection
    case navigation
    case actions
    case view

    var title: String {
        switch self {
        case .recent: String(localized: "Recent")
        case .downloads: String(localized: "Downloads")
        case .selection: String(localized: "Selection")
        case .navigation: String(localized: "Go to")
        case .actions: String(localized: "Actions")
        case .view: String(localized: "View")
        }
    }

    var sortOrder: Int {
        switch self {
        case .recent: 0
        case .downloads: 1
        case .selection: 2
        case .navigation: 3
        case .actions: 4
        case .view: 5
        }
    }
}

/// One row in the command palette.
@MainActor
struct CommandPaletteItem: Identifiable {
    let id: String
    let title: String
    let subtitle: String?
    let symbol: String
    let group: CommandPaletteGroup
    let shortcut: String?
    /// Extra ranking when query is empty (recents, context).
    let priority: Int
    let enabled: Bool
    /// Indices to highlight in `title` when showing download matches.
    let highlightIndices: [Int]
    let perform: () -> Void

    init(
        id: String, title: String, subtitle: String? = nil, symbol: String, group: CommandPaletteGroup,
        shortcut: String? = nil, priority: Int = 0, enabled: Bool = true, highlightIndices: [Int] = [],
        perform: @escaping () -> Void
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
        self.group = group
        self.shortcut = shortcut
        self.priority = priority
        self.enabled = enabled
        self.highlightIndices = highlightIndices
        self.perform = perform
    }
}

/// Builds palette items from application state.
@MainActor
enum CommandRegistry {
    static let downloadResultLimit = 30

    static func build(model: DownloadsModel, query: String) -> [CommandPaletteItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        var items: [CommandPaletteItem] = []

        if trimmed.isEmpty {
            items += recentItems(model: model)
        }

        items += downloadItems(model: model, query: trimmed)
        items += navigationItems(model: model, query: trimmed)
        items += selectionItems(model: model, query: trimmed)
        items += actionItems(model: model, query: trimmed)
        items += viewItems(model: model, query: trimmed)

        if trimmed.isEmpty {
            return dedupe(items).sorted {
                if $0.group.sortOrder != $1.group.sortOrder { return $0.group.sortOrder < $1.group.sortOrder }
                return $0.priority > $1.priority
            }
        }

        return dedupe(items)
            .compactMap { item -> (CommandPaletteItem, Int)? in
                if item.id.hasPrefix("download:") { return (item, item.priority) }
                guard let match = FuzzyMatcher.match(text: item.title, query: trimmed)
                    ?? item.subtitle.flatMap({ FuzzyMatcher.match(text: $0, query: trimmed) })
                else { return nil }
                return (item, match.score + item.priority)
            }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
    }

    private static func dedupe(_ items: [CommandPaletteItem]) -> [CommandPaletteItem] {
        var seen = Set<String>()
        return items.filter { seen.insert($0.id).inserted }
    }

    private static func recentItems(model: DownloadsModel) -> [CommandPaletteItem] {
        var result: [CommandPaletteItem] = []

        for id in CommandRecents.recentCommandIDs() {
            if let item = staticCommand(id: id, model: model, group: .recent, priority: 100) {
                result.append(item)
            }
        }
        for downloadID in CommandRecents.recentDownloadIDs() {
            guard let item = model.items.first(where: { $0.id == downloadID }) else { continue }
            result.append(openDownloadItem(item, model: model, group: .recent, priority: 90))
        }
        return result
    }

    private static func downloadItems(model: DownloadsModel, query: String) -> [CommandPaletteItem] {
        guard !query.isEmpty else { return [] }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)

        struct Scored {
            let item: DownloadItem
            let score: Int
            let indices: [Int]
        }

        var scored: [Scored] = []
        for item in model.items {
            let download = item.download
            let ext = (download.fileName as NSString).pathExtension
            let fields: [(String, Int)] = [
                (download.fileName, 10),
                (download.url.absoluteString, 4),
                (ext, 6),
                (download.state.title, 5),
                (item.category.title, 3),
                (DownloadSource.host(for: download.url), 2),
            ]
            guard let best = FuzzyMatcher.bestMatch(in: fields, query: trimmed) else { continue }
            scored.append(Scored(item: item, score: best.score, indices: best.field == download.fileName ? best.indices : []))
        }

        return scored
            .sorted { $0.score > $1.score }
            .prefix(downloadResultLimit)
            .map { openDownloadItem($0.item, model: model, group: .downloads, priority: $0.score, highlightIndices: $0.indices) }
    }

    private static func openDownloadItem(
        _ item: DownloadItem, model: DownloadsModel, group: CommandPaletteGroup, priority: Int, highlightIndices: [Int] = []
    ) -> CommandPaletteItem {
        let download = item.download
        return CommandPaletteItem(
            id: "download:\(download.id.uuidString)",
            title: download.fileName,
            subtitle: "\(download.state.title) · \(DownloadSource.host(for: download.url))",
            symbol: item.category.symbol,
            group: group,
            priority: priority,
            highlightIndices: highlightIndices
        ) {
            CommandRecents.recordDownload(download.id)
            model.filter = .all
            model.showInsights = false
            model.search = ""
            model.selection = [download.id]
            model.isCommandPaletteOpen = false
        }
    }

    private static func navigationItems(model: DownloadsModel, query: String) -> [CommandPaletteItem] {
        var items: [CommandPaletteItem] = []
        for filter in SidebarFilter.statuses {
            items.append(CommandPaletteItem(
                id: "nav:\(filter.id)",
                title: filter.title,
                subtitle: String(localized: "Show \(filter.title.lowercased())"),
                symbol: filter.symbol,
                group: .navigation,
                priority: model.filter == filter ? 2 : 0
            ) {
                record("nav:\(filter.id)")
                model.filter = filter
                model.showInsights = false
                model.clearRefinements()
                model.isCommandPaletteOpen = false
            })
        }
        let presentCategories = Set(model.items.map(\.category))
        for category in FileCategory.allCases where presentCategories.contains(category) {
            items.append(CommandPaletteItem(
                id: "nav:category:\(category.rawValue)",
                title: category.title,
                subtitle: String(localized: "Filter by file type"),
                symbol: category.symbol,
                group: .navigation,
                priority: model.category == category ? 2 : 0
            ) {
                record("nav:category:\(category.rawValue)")
                model.category = category
                model.showInsights = false
                model.isCommandPaletteOpen = false
            })
        }
        items.append(CommandPaletteItem(
            id: "nav:insights",
            title: String(localized: "Download Insights"),
            subtitle: String(localized: "Statistics and throughput"),
            symbol: "chart.bar",
            group: .navigation,
            priority: model.showInsights ? 2 : 0
        ) {
            record("nav:insights")
            model.showInsights = true
            model.isCommandPaletteOpen = false
        })
        for queue in model.queues {
            items.append(CommandPaletteItem(
                id: "nav:queue:\(queue.id)",
                title: queue.name,
                subtitle: String(localized: "Queue"),
                symbol: queue.schedule == nil ? "tray" : "calendar.badge.clock",
                group: .navigation,
                priority: model.filter == .queue(queue.id) ? 2 : 0
            ) {
                record("nav:queue:\(queue.id)")
                model.filter = .queue(queue.id)
                model.showInsights = false
                model.isCommandPaletteOpen = false
            })
        }
        items.append(CommandPaletteItem(
            id: "nav:settings",
            title: String(localized: "Settings"),
            subtitle: String(localized: "Preferences"),
            symbol: "gearshape",
            group: .navigation,
            shortcut: "⌘,"
        ) {
            record("nav:settings")
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            model.isCommandPaletteOpen = false
        })
        _ = query
        return items
    }

    private static func selectionItems(model: DownloadsModel, query: String) -> [CommandPaletteItem] {
        guard !model.selection.isEmpty else { return [] }
        let ids = model.selection
        let count = ids.count
        let label = count == 1 ? model.download(ids.first!)?.fileName ?? String(localized: "Download") : String(localized: "\(count) downloads")

        var items: [CommandPaletteItem] = []

        if ids.count == 1, let id = ids.first {
            items.append(CommandPaletteItem(
                id: "sel:details",
                title: String(localized: "Show Details"),
                subtitle: label,
                symbol: "info.circle",
                group: .selection,
                shortcut: "⌘I"
            ) {
                record("sel:details")
                model.showDetails(id)
                model.isCommandPaletteOpen = false
            })
        }

        items.append(CommandPaletteItem(
            id: "sel:finder",
            title: String(localized: "Reveal in Finder"),
            subtitle: label,
            symbol: "folder",
            group: .selection,
            shortcut: "⌘O"
        ) {
            record("sel:finder")
            model.reveal(ids)
            model.isCommandPaletteOpen = false
        })

        items.append(CommandPaletteItem(
            id: "sel:toggle",
            title: String(localized: "Pause or Resume"),
            subtitle: label,
            symbol: "play.circle",
            group: .selection,
            shortcut: "Space"
        ) {
            record("sel:toggle")
            Task { await model.toggle(ids) }
            model.isCommandPaletteOpen = false
        })

        if ids.contains(where: { [.paused, .failed].contains(model.download($0)?.state) }) {
            items.append(CommandPaletteItem(
                id: "sel:resume",
                title: String(localized: "Resume"),
                subtitle: label,
                symbol: "play",
                group: .selection
            ) {
                record("sel:resume")
                Task { await model.resume(ids) }
                model.isCommandPaletteOpen = false
            })
        }
        if ids.contains(where: { model.download($0)?.state.isActive == true }) {
            items.append(CommandPaletteItem(
                id: "sel:pause",
                title: String(localized: "Pause"),
                subtitle: label,
                symbol: "pause",
                group: .selection
            ) {
                record("sel:pause")
                Task { await model.pause(ids) }
                model.isCommandPaletteOpen = false
            })
        }
        if ids.contains(where: { model.download($0)?.state == .failed }) {
            items.append(CommandPaletteItem(
                id: "sel:retry",
                title: String(localized: "Retry Failed"),
                subtitle: label,
                symbol: "arrow.clockwise",
                group: .selection
            ) {
                record("sel:retry")
                Task { await model.resume(ids) }
                model.isCommandPaletteOpen = false
            })
        }

        items.append(CommandPaletteItem(
            id: "sel:remove",
            title: String(localized: "Remove from List"),
            subtitle: label,
            symbol: "minus.circle",
            group: .selection,
            shortcut: "⌫"
        ) {
            record("sel:remove")
            Task { await model.remove(ids) }
            model.isCommandPaletteOpen = false
        })

        _ = query
        return items
    }

    private static func actionItems(model: DownloadsModel, query: String) -> [CommandPaletteItem] {
        [
            CommandPaletteItem(
                id: "act:new",
                title: String(localized: "New Download…"),
                subtitle: String(localized: "Add URLs from clipboard"),
                symbol: "plus",
                group: .actions,
                shortcut: "⌘N"
            ) {
                record("act:new")
                model.beginAdding()
                model.isCommandPaletteOpen = false
            },
            CommandPaletteItem(
                id: "act:pauseAll",
                title: String(localized: "Pause All"),
                subtitle: nil,
                symbol: "pause",
                group: .actions,
                enabled: model.hasRunning
            ) {
                record("act:pauseAll")
                Task { await model.pauseAll() }
                model.isCommandPaletteOpen = false
            },
            CommandPaletteItem(
                id: "act:resumeAll",
                title: String(localized: "Resume All"),
                subtitle: nil,
                symbol: "play",
                group: .actions,
                enabled: model.hasPaused
            ) {
                record("act:resumeAll")
                Task { await model.resumeAll() }
                model.isCommandPaletteOpen = false
            },
            CommandPaletteItem(
                id: "act:clearCompleted",
                title: String(localized: "Clear Completed"),
                subtitle: String(localized: "Remove finished downloads from the list"),
                symbol: "checkmark.circle",
                group: .actions,
                shortcut: "⇧⌘K",
                enabled: model.hasFinished
            ) {
                record("act:clearCompleted")
                Task { await model.clearCompleted() }
                model.isCommandPaletteOpen = false
            },
            CommandPaletteItem(
                id: "act:searchToolbar",
                title: String(localized: "Filter List…"),
                subtitle: String(localized: "Search in the current view"),
                symbol: "magnifyingglass",
                group: .actions,
                shortcut: "⌘F"
            ) {
                record("act:searchToolbar")
                model.isSearching = true
                model.isCommandPaletteOpen = false
            },
            CommandPaletteItem(
                id: "act:newQueue",
                title: String(localized: "New Queue…"),
                subtitle: nil,
                symbol: "tray.2",
                group: .actions
            ) {
                record("act:newQueue")
                model.newQueue()
                model.isCommandPaletteOpen = false
            },
        ]
    }

    private static func viewItems(model: DownloadsModel, query: String) -> [CommandPaletteItem] {
        [
            CommandPaletteItem(
                id: "view:list",
                title: String(localized: "View as List"),
                symbol: "list.bullet",
                group: .view,
                shortcut: "⌘1",
                priority: model.viewMode == .list ? 1 : 0
            ) {
                record("view:list")
                model.viewMode = .list
                model.isCommandPaletteOpen = false
            },
            CommandPaletteItem(
                id: "view:grid",
                title: String(localized: "View as Grid"),
                symbol: "square.grid.2x2",
                group: .view,
                shortcut: "⌘2",
                priority: model.viewMode == .grid ? 1 : 0
            ) {
                record("view:grid")
                model.viewMode = .grid
                model.isCommandPaletteOpen = false
            },
        ]
    }

    private static func staticCommand(id: String, model: DownloadsModel, group: CommandPaletteGroup, priority: Int) -> CommandPaletteItem? {
        let all = navigationItems(model: model, query: "") + actionItems(model: model, query: "") + viewItems(model: model, query: "")
            + selectionItems(model: model, query: "")
        guard let item = all.first(where: { $0.id == id }) else { return nil }
        return CommandPaletteItem(
            id: item.id, title: item.title, subtitle: item.subtitle, symbol: item.symbol, group: group,
            shortcut: item.shortcut, priority: priority, enabled: item.enabled, highlightIndices: item.highlightIndices,
            perform: item.perform
        )
    }

    private static func record(_ id: String) {
        CommandRecents.recordCommand(id)
    }
}
