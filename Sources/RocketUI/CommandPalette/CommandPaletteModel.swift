import Foundation
import Observation

/// Palette query, selection index, and flattened results for keyboard navigation.
@MainActor
@Observable
final class CommandPaletteModel {
    var query = ""
    var selectedIndex = 0

    func rows(for model: DownloadsModel) -> [CommandPaletteRow] {
        let items = CommandRegistry.build(model: model, query: query).filter(\.enabled)
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return grouped(items)
        }
        return items.map { CommandPaletteRow(item: $0, showsGroup: false) }
    }

    func clampSelection(rowCount: Int) {
        guard rowCount > 0 else { selectedIndex = 0; return }
        selectedIndex = min(max(0, selectedIndex), rowCount - 1)
    }

    func moveSelection(by delta: Int, rowCount: Int) {
        guard rowCount > 0 else { return }
        selectedIndex = (selectedIndex + delta + rowCount) % rowCount
    }

    func reset() {
        query = ""
        selectedIndex = 0
    }

    private func grouped(_ items: [CommandPaletteItem]) -> [CommandPaletteRow] {
        var rows: [CommandPaletteRow] = []
        var lastGroup: CommandPaletteGroup?
        for item in items {
            let shows = item.group != lastGroup
            rows.append(CommandPaletteRow(item: item, showsGroup: shows))
            lastGroup = item.group
        }
        return rows
    }
}

struct CommandPaletteRow: Identifiable {
    var id: String { item.id }
    let item: CommandPaletteItem
    let showsGroup: Bool
}
