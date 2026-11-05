import RocketCore
import RocketDesign
import SwiftUI

/// The reference surface of the design system: what is downloading, how fast, how long, at a glance.
public struct MenuBarPanel: View {
    @Bindable var model: DownloadsModel
    let openMainWindow: () -> Void
    let openCommandPalette: () -> Void
    @State private var filter = ""
    @FocusState private var filterFocused: Bool

    public init(model: DownloadsModel, openMainWindow: @escaping () -> Void, openCommandPalette: @escaping () -> Void) {
        self.model = model
        self.openMainWindow = openMainWindow
        self.openCommandPalette = openCommandPalette
    }

    public var body: some View {
        VStack(spacing: RocketSpace.s3) {
            header
            HStack(spacing: RocketSpace.s3) {
                StatCard(label: "Active", value: "\(model.transferringCount)", status: model.isDownloading ? "Live" : nil)
                speedCard
                StatCard(label: "Queued", value: "\(model.queuedCount)")
            }
            ThroughputCard(buckets: model.hourlyThroughput())
            ForEach(liveGroups, id: \.queue.id) { group in
                LiveList(queue: group.queue, items: group.items, model: model, openMainWindow: openMainWindow)
            }
            filterField
        }
        .padding(RocketSpace.s3)
        .frame(width: RocketSize.menuBarPanelWidth)
        .background(RocketColor.canvas)
        // The menu bar window closes when it loses key, so menus here open without taking it.
        .environment(\.rocketPopoverTakesKey, false)
    }

    private var header: some View {
        HStack(spacing: RocketSpace.s3) {
            RocketMark(size: 20)
            Text("Rocket")
                .font(.rocketTitle)
                .foregroundStyle(RocketColor.textPrimary)
            Text(model.isDownloading ? Format.speed(model.totalSpeed) : String(localized: "Idle"))
                .font(.rocketTitle.weight(.regular))
                .foregroundStyle(model.isDownloading ? RocketColor.accentText : RocketColor.textSecondary)
                .monospacedDigit()
                .contentTransition(.numericText())
            Spacer()
            if model.hasRunning {
                Button("Pause All", systemImage: "pause") { Task { await model.pauseAll() } }
                    .buttonStyle(.rocketIcon)
                    .rocketTooltip(String(localized: "Pause all downloads"))
            } else {
                Button("Resume All", systemImage: "play") { Task { await model.resumeAll() } }
                    .buttonStyle(.rocketIcon)
                    .disabled(!model.hasPaused)
                    .rocketTooltip(String(localized: "Resume all downloads"))
            }
            SettingsLink {
                Label("Settings", systemImage: "gearshape")
            }
            .buttonStyle(.rocketIcon)
            .rocketTooltip(String(localized: "Settings"), shortcut: "⌘,")
        }
        .padding(.horizontal, RocketSpace.s2)
    }

    private var speedCard: some View {
        let (value, unit) = Format.compactSpeed(model.totalSpeed)
        let limit = model.settings.globalSpeedLimit
        return StatCard(label: "Speed", value: value, unit: unit) {
            // FR-SPD-01: the global limit, changeable live from the menu bar.
            RocketMenuButton(alignment: .trailing) {
                [RocketMenuSection(String(localized: "Limit all downloads"),
                                   items: SpeedLimitOptions.menuItems(current: limit) { rate in Task { await model.setGlobalLimit(rate) } })]
            } label: {
                if let limit {
                    Text("≤ \(Format.speed(Double(limit)))").font(.rocketLabel).foregroundStyle(RocketColor.textSecondary)
                } else {
                    Sparkline(values: model.speedHistory)
                }
            }
            .buttonStyle(.plain)
            .fixedSize()
            .rocketTooltip(String(localized: "Speed limit"))
        }
    }

    /// Active, paused and queued downloads; the 3 most recent finished ones when nothing is running.
    private var liveItems: [DownloadItem] {
        var items = model.items.filter { $0.download.state.isActive || $0.download.state == .paused }
        if items.isEmpty { items = Array(model.items.filter { $0.download.state == .completed }.prefix(3)) }
        guard !filter.isEmpty else { return items }
        return items.filter { $0.download.fileName.localizedCaseInsensitiveContains(filter) }
    }

    /// Live items grouped by queue (queues with nothing live are hidden; the default queue always shows).
    private var liveGroups: [(queue: DownloadQueue, items: [DownloadItem])] {
        let items = liveItems
        let queues = model.queues.isEmpty ? [DownloadQueue(id: DownloadQueue.defaultID, name: String(localized: "Default"))] : model.queues
        return queues.compactMap { queue in
            let members = items.filter { $0.download.queueID == queue.id }
            return members.isEmpty && !queue.isDefault ? nil : (queue, members)
        }
    }

    private var filterField: some View {
        HStack(spacing: RocketSpace.s3) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(RocketColor.textTertiary)
            TextField("Filter downloads", text: $filter)
                .textFieldStyle(.plain)
                .font(.rocketBody)
                .focused($filterFocused)
                .onExitCommand { filter = "" }
            Button {
                openCommandPalette()
            } label: {
                Keycap("⌘K")
            }
            .buttonStyle(.plain)
            .help(String(localized: "Open command palette in the main window"))
        }
        .padding(.horizontal, RocketSpace.s4)
        .frame(height: 36)
        .background(RocketColor.raised, in: RoundedRectangle(cornerRadius: RocketRadius.control, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: RocketRadius.control, style: .continuous)
            .strokeBorder(filterFocused ? RocketColor.accent : RocketColor.border))
    }
}

// MARK: Cards

/// Label top-left, status word or sparkline top-right, metric + unit bottom-left.
struct StatCard<Accessory: View>: View {
    let label: LocalizedStringKey
    let value: String
    var unit: String?
    @ViewBuilder var accessory: Accessory

    var body: some View {
        VStack(alignment: .leading, spacing: RocketSpace.s3) {
            HStack(alignment: .firstTextBaseline) {
                Text(label).font(.rocketLabel).foregroundStyle(RocketColor.textSecondary)
                Spacer(minLength: RocketSpace.s2)
                accessory
            }
            .frame(height: 16)
            HStack(alignment: .lastTextBaseline, spacing: RocketSpace.s2) {
                Text(value)
                    .font(.rocketMetricLarge)
                    .tracking(-0.4)
                    .foregroundStyle(RocketColor.textPrimary)
                    .lineLimit(1)
                // Units never wrap away from their value.
                if let unit { Text(unit).font(.rocketLabel).foregroundStyle(RocketColor.textSecondary).fixedSize() }
            }
        }
        .padding(RocketSpace.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .rocketCard()
        .accessibilityElement(children: .combine)
    }
}

extension StatCard where Accessory == Text? {
    init(label: LocalizedStringKey, value: String, unit: String? = nil, status: LocalizedStringKey? = nil) {
        self.init(label: label, value: value, unit: unit) {
            status.map { Text($0).font(.rocketLabel).foregroundStyle(RocketColor.accentText) }
        }
    }
}

// MARK: Live list

/// Downloads grouped under their queue (only the default queue exists until v0.2), with compact rows.
struct LiveList: View {
    let queue: DownloadQueue
    let items: [DownloadItem]
    let model: DownloadsModel
    let openMainWindow: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: RocketSpace.s3) {
                FileTile(symbol: queue.schedule == nil ? "tray" : "clock")
                Text(queue.name).font(.rocketHeadline).foregroundStyle(RocketColor.textPrimary)
                Text(queue.schedule?.summary ?? model.settings.folder.path(percentEncoded: false).replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                    .font(.rocketMono)
                    .foregroundStyle(RocketColor.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Text("\(items.count)").font(.rocketLabel).foregroundStyle(RocketColor.textSecondary).monospacedDigit()
            }
            .padding(.bottom, RocketSpace.s2)
            if items.isEmpty {
                Text("Nothing is downloading")
                    .font(.rocketBody)
                    .foregroundStyle(RocketColor.textSecondary)
                    .padding(.leading, RocketSize.fileTile + RocketSpace.s3)
                    .padding(.vertical, RocketSpace.s3)
            } else {
                rows
            }
        }
        .padding(RocketSpace.s4)
        .rocketCard()
    }

    @ViewBuilder
    private var rows: some View {
        let list = VStack(spacing: 0) {
            ForEach(items) { item in
                CompactRow(item: item, model: model, openMainWindow: openMainWindow)
                    .rocketTransition(RocketTransition.list)
            }
        }
        .rocketAnimation(RocketMotion.standard, value: items.map(\.id))
        // Panel grows with content up to ~640 pt, then the list scrolls.
        if items.count > 6 {
            ScrollView { list }.frame(height: 6 * RocketSize.row)
        } else {
            list
        }
    }
}

struct CompactRow: View {
    let item: DownloadItem
    let model: DownloadsModel
    let openMainWindow: () -> Void
    @State private var hovering = false

    private var download: Download { item.download }

    var body: some View {
        HStack(spacing: RocketSpace.s3) {
            // Connector from the group header, in the tertiary color.
            Rectangle()
                .fill(RocketColor.borderStrong)
                .frame(width: 1)
                .padding(.leading, RocketSize.fileTile / 2)
                .padding(.trailing, RocketSize.fileTile / 2 - 1)
            VStack(alignment: .leading, spacing: RocketSpace.s1) {
                HStack {
                    Text(download.fileName)
                        .font(.rocketHeadline)
                        .foregroundStyle(RocketColor.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: RocketSpace.s2)
                    Text(trailingText)
                        .font(.rocketLabel)
                        .foregroundStyle(download.state == .downloading ? RocketColor.accentText : RocketColor.textSecondary)
                        .monospacedDigit()
                }
                if download.state != .completed {
                    RocketProgressBar(
                        fraction: item.fraction,
                        tint: download.state == .downloading ? RocketColor.accent : RocketColor.textTertiary
                    )
                }
            }
            button
        }
        .frame(height: RocketSize.row - RocketSpace.s3)
        .background(hovering ? RocketColor.hover : .clear, in: RoundedRectangle(cornerRadius: RocketRadius.small + 1, style: .continuous))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .rocketAnimation(RocketMotion.fast, value: hovering)
        .onTapGesture {
            model.filter = .all
            model.selection = [download.id]
            openMainWindow()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(item.accessibilityLabel)
    }

    private var trailingText: String {
        switch download.state {
        case .downloading: item.speed > 0 ? Format.speed(item.speed) : download.state.title
        case .completed: Format.bytes(download.totalBytes ?? download.receivedBytes)
        default: download.state.title
        }
    }

    @ViewBuilder
    private var button: some View {
        switch download.state {
        case .paused, .failed:
            Button("Resume", systemImage: "play") { Task { await model.resume([download.id]) } }
                .buttonStyle(.rocketIcon)
        case .completed:
            Button("Show in Finder", systemImage: "folder") { model.reveal([download.id]) }
                .buttonStyle(.rocketIcon)
        default:
            Button("Pause", systemImage: "pause") { Task { await model.pause([download.id]) } }
                .buttonStyle(.rocketIcon)
        }
    }
}
