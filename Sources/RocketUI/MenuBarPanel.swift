import Charts
import RocketCore
import RocketDesign
import SwiftUI

/// The reference surface of the design system: what is downloading, how fast, how long, at a glance.
public struct MenuBarPanel: View {
    @Bindable var model: DownloadsModel
    let openMainWindow: () -> Void
    @State private var filter = ""
    @FocusState private var filterFocused: Bool

    public init(model: DownloadsModel, openMainWindow: @escaping () -> Void) {
        self.model = model
        self.openMainWindow = openMainWindow
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
    }

    private var header: some View {
        HStack(spacing: RocketSpace.s2) {
            Text("Rocket")
                .font(.rocketTitle)
                .foregroundStyle(RocketColor.textPrimary)
            Text(model.isDownloading ? Format.speed(model.totalSpeed) : String(localized: "Idle"))
                .font(.rocketTitle.weight(.regular))
                .foregroundStyle(RocketColor.textSecondary)
                .monospacedDigit()
            Spacer()
            if model.hasRunning {
                Button("Pause All", systemImage: "pause") { Task { await model.pauseAll() } }
                    .buttonStyle(.rocketIcon)
                    .help("Pause all downloads")
            } else {
                Button("Resume All", systemImage: "play") { Task { await model.resumeAll() } }
                    .buttonStyle(.rocketIcon)
                    .disabled(!model.hasPaused)
                    .help("Resume all downloads")
            }
            SettingsLink {
                Label("Settings", systemImage: "gearshape")
            }
            .buttonStyle(.rocketIcon)
            .help("Settings")
        }
        .padding(.horizontal, RocketSpace.s2)
    }

    private var speedCard: some View {
        let (value, unit) = Format.compactSpeed(model.totalSpeed)
        let limit = model.settings.globalSpeedLimit
        return StatCard(label: "Speed", value: value, unit: unit) {
            // FR-SPD-01: the global limit, changeable live from the menu bar.
            Menu {
                SpeedLimitPicker("Limit All Downloads", current: limit) { rate in Task { await model.setGlobalLimit(rate) } }
            } label: {
                if let limit {
                    Text("≤ \(Format.speed(Double(limit)))").font(.rocketLabel).foregroundStyle(RocketColor.textSecondary)
                } else {
                    Sparkline(values: model.speedHistory)
                }
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Speed limit")
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
        HStack(spacing: RocketSpace.s2) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(RocketColor.textSecondary)
            TextField("Filter downloads", text: $filter)
                .textFieldStyle(.plain)
                .font(.rocketBody)
                .focused($filterFocused)
                .onExitCommand { filter = "" }
            Text("⌘K")
                .font(.rocketCaption.weight(.medium))
                .foregroundStyle(RocketColor.textSecondary)
                .padding(.horizontal, 6)
                .frame(height: RocketSize.keycapHeight)
                .background(RocketColor.control, in: RoundedRectangle(cornerRadius: RocketRadius.small))
                .overlay(RoundedRectangle(cornerRadius: RocketRadius.small).stroke(RocketColor.hairline))
                .accessibilityHidden(true)
        }
        .padding(.horizontal, RocketSpace.s4)
        .frame(height: 36)
        .background(RocketColor.control, in: RoundedRectangle(cornerRadius: RocketRadius.control))
        .background {
            Button("Focus filter") { filterFocused = true }
                .keyboardShortcut("k")
                .hidden()
        }
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
        .background(RocketColor.card, in: RoundedRectangle(cornerRadius: RocketRadius.card))
        .accessibilityElement(children: .combine)
    }
}

extension StatCard where Accessory == Text? {
    init(label: LocalizedStringKey, value: String, unit: String? = nil, status: LocalizedStringKey? = nil) {
        self.init(label: label, value: value, unit: unit) {
            status.map { Text($0).font(.rocketLabel).foregroundStyle(RocketColor.success) }
        }
    }
}

/// 16 bars, 2 pt wide, 14 pt tall; the latest in Flame.
struct Sparkline: View {
    let values: [Double]

    var body: some View {
        let peak = max(values.max() ?? 0, 1)
        HStack(alignment: .bottom, spacing: 1) {
            ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                Capsule()
                    .fill(index == values.count - 1 ? RocketColor.flame : RocketColor.chartNeutral)
                    .frame(width: 2, height: max(2, 14 * value / peak))
            }
        }
        .frame(height: 14, alignment: .bottom)
        .accessibilityHidden(true)
    }
}

/// 24 hourly bars of completed bytes; the current hour in Flame. No gridlines, two captions.
struct ThroughputCard: View {
    let buckets: [Int64]

    var body: some View {
        VStack(alignment: .leading, spacing: RocketSpace.s3) {
            HStack {
                Text("Last 24 hours").font(.rocketHeadline).foregroundStyle(RocketColor.textPrimary)
                Spacer()
                Text(Format.bytes(buckets.reduce(0, +)))
                    .font(.rocketLabel)
                    .foregroundStyle(RocketColor.textSecondary)
                    .monospacedDigit()
            }
            if buckets.allSatisfy({ $0 == 0 }) {
                Capsule().fill(RocketColor.chartTrack).frame(height: 2).padding(.top, 40)
                Text("No downloads in the last 24 hours")
                    .font(.rocketCaption)
                    .foregroundStyle(RocketColor.textTertiary)
            } else {
                Chart(Array(buckets.enumerated()), id: \.offset) { hour, bytes in
                    BarMark(x: .value("Hour", hour), y: .value("Bytes", bytes), width: .fixed(10))
                        .foregroundStyle(hour == buckets.count - 1 ? RocketColor.flame : RocketColor.chartNeutral)
                        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 2, topTrailingRadius: 2))
                }
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .frame(height: 56)
                .accessibilityLabel(summary)
                HStack {
                    Text(Date.now.addingTimeInterval(-23 * 3600), format: .dateTime.hour())
                    Spacer()
                    Text("Now")
                }
                .font(.rocketCaption)
                .foregroundStyle(RocketColor.textTertiary)
            }
        }
        .padding(RocketSpace.s4)
        .background(RocketColor.card, in: RoundedRectangle(cornerRadius: RocketRadius.card))
    }

    private var summary: String {
        guard let peak = buckets.indices.max(by: { buckets[$0] < buckets[$1] }) else { return "" }
        let hour = Date.now.addingTimeInterval(Double(peak - 23) * 3600).formatted(.dateTime.hour())
        return String(localized: "Peak \(Format.bytes(buckets[peak])) at \(hour)")
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
                Image(systemName: queue.schedule == nil ? "list.bullet" : "clock")
                    .frame(width: RocketSize.fileTile, height: RocketSize.fileTile)
                    .background(RocketColor.control, in: RoundedRectangle(cornerRadius: RocketRadius.small))
                    .foregroundStyle(RocketColor.textSecondary)
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
        .background(RocketColor.card, in: RoundedRectangle(cornerRadius: RocketRadius.card))
    }

    @ViewBuilder
    private var rows: some View {
        let list = VStack(spacing: 0) {
            ForEach(items) { item in
                CompactRow(item: item, model: model, openMainWindow: openMainWindow)
            }
        }
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

    private var download: Download { item.download }

    var body: some View {
        HStack(spacing: RocketSpace.s3) {
            // Connector from the group header, in the tertiary color.
            Rectangle()
                .fill(RocketColor.textTertiary.opacity(0.5))
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
                        .foregroundStyle(download.state == .downloading ? RocketColor.flameText : RocketColor.textSecondary)
                        .monospacedDigit()
                }
                if download.state != .completed {
                    RocketProgressBar(
                        fraction: item.fraction,
                        tint: download.state == .downloading ? RocketColor.flame : RocketColor.textTertiary
                    )
                }
            }
            button
        }
        .frame(height: RocketSize.row - RocketSpace.s3)
        .contentShape(Rectangle())
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
