import AppKit
import RocketCore
import RocketDesign
import SwiftUI

/// The menu bar panel, built like the system's own (Wi-Fi, Bluetooth): a summary header, a list of
/// downloads, and menu-style rows at the bottom. System material, fonts and controls throughout.
public struct MenuBarPanel: View {
    @Bindable var model: DownloadsModel
    let openMainWindow: () -> Void

    public init(model: DownloadsModel, openMainWindow: @escaping () -> Void) {
        self.model = model
        self.openMainWindow = openMainWindow
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            separator
            if liveGroups.isEmpty {
                Text("No downloads")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
            }
            ForEach(liveGroups, id: \.title) { group in
                SectionHeader(title: group.title)
                rows(group.items)
            }
            separator
            speedLimitMenu
            MenuRow(action: openMainWindow) { Text("Open Rocket") }
            SettingsLink {
                MenuRowLabel { Text("Settings…") }
            }
            .buttonStyle(MenuRowStyle())
            separator
            MenuRow(action: { NSApp.terminate(nil) }) { Text("Quit Rocket") }
        }
        .padding(6)
        .frame(width: RocketSize.menuBarPanelWidth)
        // Report the full content height so the menu bar window grows with it instead of squeezing rows.
        .fixedSize(horizontal: false, vertical: true)
    }

    private var separator: some View {
        Divider().padding(.vertical, 5).padding(.horizontal, 8)
    }

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Rocket").font(.headline)
                Text(summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            Spacer()
            Button {
                Task { model.hasRunning ? await model.pauseAll() : await model.resumeAll() }
            } label: {
                Image(systemName: model.hasRunning ? "pause.circle.fill" : "play.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .disabled(!model.hasRunning && !model.hasPaused)
            .help(pauseResumeTitle)
            .accessibilityLabel(pauseResumeTitle)
        }
        .padding(.horizontal, 8)
        .padding(.top, 4)
    }

    private var pauseResumeTitle: String {
        model.hasRunning ? String(localized: "Pause All") : String(localized: "Resume All")
    }

    /// "2 downloading · 4.2 MB/s", "3 queued", or "Idle · 1.4 GB in the last 24 hours".
    private var summary: String {
        if model.isDownloading {
            var parts = [String(localized: "\(model.transferringCount) downloading"), Format.speed(model.totalSpeed)]
            if model.queuedCount > 0 { parts.append(String(localized: "\(model.queuedCount) queued")) }
            return parts.joined(separator: " · ")
        }
        if model.queuedCount > 0 { return String(localized: "\(model.queuedCount) queued") }
        let today = model.hourlyThroughput().reduce(0, +)
        return today > 0 ? String(localized: "Idle · \(Format.bytes(today)) in the last 24 hours") : String(localized: "Idle")
    }

    @ViewBuilder
    private func rows(_ items: [DownloadItem]) -> some View {
        let list = VStack(spacing: 0) {
            ForEach(items) { item in
                DownloadMenuRow(item: item, model: model, openMainWindow: openMainWindow)
            }
        }
        .animation(.default, value: items.map(\.id))
        // The panel grows with its content up to ~6 rows, then the list scrolls.
        if items.count > 6 {
            ScrollView { list }.frame(height: 6 * 52)
        } else {
            list
        }
    }

    /// FR-SPD-01: the global limit, changeable live from the menu bar.
    private var speedLimitMenu: some View {
        let limit = model.settings.globalSpeedLimit
        return Menu {
            Picker("Speed Limit", selection: Binding(get: { limit }, set: { rate in Task { await model.setGlobalLimit(rate) } })) {
                Text("Unlimited").tag(Int64?.none)
                Divider()
                ForEach(SpeedLimitOptions.rates(including: limit), id: \.self) { rate in
                    Text(Format.speed(Double(rate))).tag(Int64?.some(rate))
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            MenuRowLabel {
                Text("Speed Limit")
                Spacer()
                Text(limit.map { Format.speed(Double($0)) } ?? String(localized: "Unlimited")).foregroundStyle(.secondary)
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(MenuRowStyle())
    }

    /// Active, paused, queued and failed downloads by queue; the 3 most recent finished ones when nothing needs attention.
    private var liveGroups: [(title: String, items: [DownloadItem])] {
        let live = model.items.filter { [.paused, .failed].contains($0.download.state) || $0.download.state.isActive }
        guard !live.isEmpty else {
            let recent = Array(model.items.filter { $0.download.state == .completed }.prefix(3))
            return recent.isEmpty ? [] : [(String(localized: "Recent"), recent)]
        }
        let queues = model.queues.isEmpty ? [DownloadQueue(id: DownloadQueue.defaultID, name: String(localized: "Downloads"))] : model.queues
        return queues.compactMap { queue in
            let members = live.filter { $0.download.queueID == queue.id }
            return members.isEmpty ? nil : (queues.count == 1 ? String(localized: "Downloads") : queue.name, members)
        }
    }
}

// MARK: Rows

/// File icon, name, a native progress bar while it moves, and one status line; the one action it needs on the right.
struct DownloadMenuRow: View {
    let item: DownloadItem
    let model: DownloadsModel
    let openMainWindow: () -> Void

    private var download: Download { item.download }

    var body: some View {
        MenuRow(action: {
            model.filter = .all
            model.selection = [download.id]
            openMainWindow()
        }) {
            FileThumbnail(item: item, size: 32)
            VStack(alignment: .leading, spacing: 3) {
                Text(download.fileName)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if download.state.isTransferring || download.state == .paused {
                    ProgressView(value: min(1, max(0, item.fraction ?? 0)))
                        .progressViewStyle(.linear)
                        .controlSize(.small)
                        .tint(download.state == .paused ? .secondary : .accentColor)
                }
                Text(status)
                    .font(.subheadline)
                    .foregroundStyle(download.state == .failed ? .red : .secondary)
                    .monospacedDigit()
                    .lineLimit(1)
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            if let action {
                Button {
                    action.perform(on: download, model: model)
                    // Refresh Link's sheet lives in the main window.
                    if action == .refreshLink { openMainWindow() }
                } label: {
                    Image(systemName: icon(for: action))
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help(action.title)
                .accessibilityLabel(action.title)
            }
        }
        .help(download.state == .failed ? download.failure?.userMessage ?? "" : "")
        .accessibilityLabel(item.accessibilityLabel)
    }

    private var action: RowAction? {
        switch download.state {
        case .probing, .downloading, .verifying: .pause
        case .paused, .failed: RowAction.available(for: download).first { [.resume, .retry, .refreshLink].contains($0) }
        case .completed: .reveal
        case .queued, .cancelled: nil
        }
    }

    private func icon(for action: RowAction) -> String {
        switch action {
        case .reveal: "magnifyingglass.circle.fill"
        case .resume: "play.circle.fill"
        default: action.symbol + ".circle.fill"
        }
    }

    private var percent: String? {
        item.fraction.map { $0.formatted(.percent.precision(.fractionLength(0))) }
    }

    /// Same wording as the main table's Status column: "62% · 4.2 MB/s", "Paused · 35%", a short error.
    private var status: String {
        switch download.state {
        case .downloading:
            var parts = [percent].compactMap { $0 }
            if item.speed > 0 { parts.append(Format.speed(item.speed)) }
            return parts.isEmpty ? download.state.title : parts.joined(separator: " · ")
        case .paused: return [download.state.title, percent].compactMap { $0 }.joined(separator: " · ")
        case .failed: return download.failure?.shortMessage ?? download.state.title
        case .completed: return Format.bytes(download.totalBytes ?? download.receivedBytes)
        case .probing, .verifying, .queued, .cancelled: return download.state.title
        }
    }
}

// MARK: Menu-style building blocks

/// Small bold secondary title, like "Known Networks" in the Wi-Fi menu.
private struct SectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.top, 4)
            .padding(.bottom, 2)
    }
}

/// A full-width row that highlights on hover like a menu item.
private struct MenuRow<Content: View>: View {
    let action: () -> Void
    @ViewBuilder var content: Content

    var body: some View {
        Button(action: action) { MenuRowLabel { content } }
            .buttonStyle(MenuRowStyle())
    }
}

private struct MenuRowLabel<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 8) { content }
            .frame(maxWidth: .infinity, minHeight: 22, alignment: .leading)
    }
}

private struct MenuRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Highlighted(pressed: configuration.isPressed) { configuration.label }
    }

    private struct Highlighted<Label: View>: View {
        let pressed: Bool
        @ViewBuilder var label: Label
        @State private var hovering = false

        var body: some View {
            label
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color.primary.opacity(pressed ? 0.15 : hovering ? 0.08 : 0))
                )
                .onHover { hovering = $0 }
        }
    }
}
