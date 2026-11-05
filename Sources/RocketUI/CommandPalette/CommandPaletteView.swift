import RocketDesign
import SwiftUI

/// Raycast-style command palette overlay: fuzzy search, grouped commands, keyboard-first navigation.
struct CommandPaletteView: View {
    @Bindable var downloads: DownloadsModel
    @State private var palette = CommandPaletteModel()
    @FocusState private var focused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let rows = palette.rows(for: downloads)
        VStack(spacing: 0) {
            searchField
            Divider().overlay(RocketColor.border)
            content(rows: rows)
            footer
        }
        .frame(width: 580)
        .background(RocketColor.overlay, in: RoundedRectangle(cornerRadius: RocketRadius.modal, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: RocketRadius.modal, style: .continuous).strokeBorder(RocketColor.border))
        .shadow(color: .black.opacity(0.35), radius: 32, y: 12)
        .onAppear {
            palette.reset()
            focused = true
        }
        .onChange(of: palette.query) { _, _ in
            palette.selectedIndex = 0
        }
        .onChange(of: rows.count) { _, count in
            palette.clampSelection(rowCount: count)
        }
        .onKeyPress(keys: [.upArrow, .downArrow]) { press in
            palette.moveSelection(by: press.key == .upArrow ? -1 : 1, rowCount: rows.count)
            return .handled
        }
        .onKeyPress(.return) {
            execute(rows: rows)
            return .handled
        }
        .onExitCommand {
            close()
        }
    }

    private var searchField: some View {
        HStack(spacing: RocketSpace.s3) {
            RocketIcon(.search, size: 15)
                .foregroundStyle(RocketColor.textTertiary)
            TextField("Search downloads and commands…", text: $palette.query)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .focused($focused)
            if !palette.query.isEmpty {
                Button { palette.query = "" } label: { RocketIcon(.circleX, size: 14) }
                    .buttonStyle(.plain)
                    .foregroundStyle(RocketColor.textTertiary)
                    .accessibilityLabel(String(localized: "Clear"))
            }
            Keycap("⌘K")
        }
        .padding(.horizontal, RocketSpace.s5)
        .padding(.vertical, RocketSpace.s4)
    }

    @ViewBuilder
    private func content(rows: [CommandPaletteRow]) -> some View {
        if !downloads.hasLoaded, downloads.items.isEmpty {
            loadingState
        } else if rows.isEmpty {
            emptyState
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                            if row.showsGroup, palette.query.isEmpty {
                                Text(row.item.group.title)
                                    .rocketEyebrow()
                                    .padding(.horizontal, RocketSpace.s5)
                                    .padding(.top, index == 0 ? RocketSpace.s3 : RocketSpace.s5)
                                    .padding(.bottom, RocketSpace.s2)
                            }
                            CommandPaletteRowView(
                                row: row.item,
                                isSelected: index == palette.selectedIndex,
                                query: palette.query
                            )
                            .id(row.id)
                            .onTapGesture { palette.selectedIndex = index; execute(rows: rows) }
                        }
                    }
                    .padding(.bottom, RocketSpace.s3)
                }
                .frame(maxHeight: 360)
                .onChange(of: palette.selectedIndex) { _, index in
                    if rows.indices.contains(index) {
                        withAnimation(reduceMotion ? nil : RocketMotion.fast) {
                            proxy.scrollTo(rows[index].id, anchor: .center)
                        }
                    }
                }
            }
        }
    }

    private var loadingState: some View {
        HStack(spacing: RocketSpace.s3) {
            RocketSpinner(size: 16)
            Text("Loading downloads…")
                .font(.rocketBody)
                .foregroundStyle(RocketColor.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, RocketSpace.s7)
    }

    private var emptyState: some View {
        VStack(spacing: RocketSpace.s3) {
            RocketIcon(.search, size: 28)
                .foregroundStyle(RocketColor.textTertiary)
            Text("No results")
                .font(.rocketHeadline)
                .foregroundStyle(RocketColor.textPrimary)
            Text("Try a different search, or browse commands with an empty search.")
                .font(.rocketBody)
                .foregroundStyle(RocketColor.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, RocketSpace.s7)
        .padding(.horizontal, RocketSpace.s5)
    }

    private var footer: some View {
        HStack(spacing: RocketSpace.s4) {
            footerHint("↑↓", String(localized: "Navigate"))
            footerHint("↩", String(localized: "Run"))
            footerHint("esc", String(localized: "Close"))
            Spacer()
        }
        .padding(.horizontal, RocketSpace.s5)
        .padding(.vertical, RocketSpace.s3)
        .background(RocketColor.control.opacity(0.5))
    }

    private func footerHint(_ key: String, _ label: String) -> some View {
        HStack(spacing: RocketSpace.s2) {
            Keycap(key)
            Text(label).font(.rocketCaption).foregroundStyle(RocketColor.textTertiary)
        }
    }

    private func execute(rows: [CommandPaletteRow]) {
        guard rows.indices.contains(palette.selectedIndex) else { return }
        let item = rows[palette.selectedIndex].item
        CommandRecents.recordCommand(item.id)
        item.perform()
    }

    private func close() {
        downloads.isCommandPaletteOpen = false
    }
}

private struct CommandPaletteRowView: View {
    let row: CommandPaletteItem
    let isSelected: Bool
    let query: String

    var body: some View {
        HStack(spacing: RocketSpace.s3) {
            RocketIcon(symbol: row.symbol, size: 15)
                .foregroundStyle(isSelected ? RocketColor.accentText : RocketColor.textSecondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                HighlightedText(row.title, indices: row.highlightIndices.isEmpty ? titleMatchIndices : row.highlightIndices)
                    .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                    .foregroundStyle(RocketColor.textPrimary)
                    .lineLimit(1)
                if let subtitle = row.subtitle {
                    Text(subtitle)
                        .font(.rocketCaption)
                        .foregroundStyle(RocketColor.textTertiary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: RocketSpace.s3)
            if let shortcut = row.shortcut {
                Keycap(shortcut)
            }
        }
        .padding(.horizontal, RocketSpace.s5)
        .padding(.vertical, RocketSpace.s3)
        .background(isSelected ? RocketColor.selected : .clear, in: RoundedRectangle(cornerRadius: RocketRadius.control, style: .continuous))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var titleMatchIndices: [Int] {
        FuzzyMatcher.match(text: row.title, query: query)?.indices ?? []
    }
}

/// Renders `text` with matched character indices in the accent color.
struct HighlightedText: View {
    let text: String
    let indices: Set<Int>

    init(_ text: String, indices: [Int]) {
        self.text = text
        self.indices = Set(indices)
    }

    var body: some View {
        if indices.isEmpty {
            Text(text)
        } else {
            Text(attributed)
        }
    }

    private var attributed: AttributedString {
        var result = AttributedString(text)
        for index in indices where index < text.count {
            let start = result.index(result.startIndex, offsetByCharacters: index)
            let end = result.index(afterCharacter: start)
            result[start..<end].foregroundColor = RocketColor.accentText
            result[start..<end].font = .system(size: 13, weight: .semibold)
        }
        return result
    }
}

/// Full-window host: scrim, centered palette, blocks interaction with content beneath.
struct CommandPaletteHost: ViewModifier {
    @Bindable var downloads: DownloadsModel

    func body(content: Content) -> some View {
        content
            .disabled(downloads.isCommandPaletteOpen)
            .overlay {
                if downloads.isCommandPaletteOpen {
                    ZStack {
                        RocketColor.scrim
                            .ignoresSafeArea()
                            .contentShape(Rectangle())
                            .onTapGesture { downloads.isCommandPaletteOpen = false }
                            .transition(.opacity)
                        CommandPaletteView(downloads: downloads)
                            .padding(.top, 72)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                            .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
                            .accessibilityAddTraits(.isModal)
                    }
                    .rocketAnimation(downloads.isCommandPaletteOpen ? RocketMotion.enter : RocketMotion.exit, value: downloads.isCommandPaletteOpen)
                }
            }
    }
}

public extension View {
    func rocketCommandPalette(downloads: DownloadsModel) -> some View {
        modifier(CommandPaletteHost(downloads: downloads))
    }
}
