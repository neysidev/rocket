import AppKit
import QuickLookThumbnailing
import RocketCore
import RocketDesign
import SwiftUI

/// List row: file tile, name, size line, then a progress bar while transferring or a status line otherwise.
/// Actions stay hidden until the row is hovered or selected; the more menu carries everything else.
struct DownloadRow: View {
    let item: DownloadItem
    let model: DownloadsModel
    var queuePosition: Int?
    var isSelected = false
    @State private var hovering = false

    private var download: Download { item.download }

    var body: some View {
        HStack(spacing: RocketSpace.s4) {
            FileTile(symbol: item.category.symbol, size: RocketSize.fileTileRow)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: RocketSpace.s3) {
                    Text(download.fileName)
                        .font(.rocketHeadline)
                        .foregroundStyle(RocketColor.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: RocketSpace.s3)
                    if download.state.isTransferring { LiveMetrics(item: item) }
                }
                Text(Format.size(item))
                    .font(.rocketLabel)
                    .foregroundStyle(RocketColor.textSecondary)
                    .monospacedDigit()
                    .lineLimit(1)
                if download.state.isTransferring {
                    RocketProgressBar(fraction: item.fraction, tint: RocketColor.accent)
                        .padding(.top, RocketSpace.s2)
                } else {
                    StatusLabel(item: item, queuePosition: queuePosition)
                }
            }
            RowActions(item: item, model: model)
                .opacity(hovering || isSelected ? 1 : 0)
                .allowsHitTesting(hovering || isSelected)
                .animation(RocketMotion.fast, value: hovering)
        }
        .frame(minHeight: RocketSize.row)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.accessibilityLabel)
        .accessibilityActions {
            ForEach(RowAction.available(for: download), id: \.self) { action in
                Button(action.title) { action.perform(on: download, model: model) }
            }
        }
    }
}

/// Grid card: larger tile, name, size, status or progress, actions on hover or selection.
struct DownloadCard: View {
    let item: DownloadItem
    let model: DownloadsModel
    var queuePosition: Int?
    var isSelected = false
    @State private var hovering = false

    private var download: Download { item.download }

    var body: some View {
        VStack(alignment: .leading, spacing: RocketSpace.s3) {
            HStack(alignment: .top) {
                FileThumbnail(item: item, size: RocketSize.fileTileCard)
                Spacer(minLength: 0)
                RowActions(item: item, model: model, compact: true)
                    .opacity(hovering || isSelected ? 1 : 0)
                    .allowsHitTesting(hovering || isSelected)
            }
            VStack(alignment: .leading, spacing: RocketSpace.s1) {
                Text(download.fileName)
                    .font(.rocketHeadline)
                    .foregroundStyle(RocketColor.textPrimary)
                    .lineLimit(1)
                    .help(download.fileName)
                    .truncationMode(.middle)
                Text(Format.size(item))
                    .font(.rocketLabel)
                    .foregroundStyle(RocketColor.textSecondary)
                    .monospacedDigit()
                    .lineLimit(1)
            }
            if download.state.isTransferring {
                VStack(alignment: .leading, spacing: RocketSpace.s2) {
                    LiveMetrics(item: item)
                    RocketProgressBar(fraction: item.fraction, tint: RocketColor.accent)
                }
            } else {
                StatusLabel(item: item, queuePosition: queuePosition)
            }
        }
        .padding(RocketSpace.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            isSelected ? RocketColor.fillSelected : hovering ? RocketColor.fillSubtle : .clear,
            in: RoundedRectangle(cornerRadius: RocketRadius.card)
        )
        .overlay {
            RoundedRectangle(cornerRadius: RocketRadius.card)
                .strokeBorder(isSelected ? RocketColor.accent.opacity(0.7) : RocketColor.hairline, lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: RocketRadius.card))
        .onHover { hovering = $0 }
        .animation(RocketMotion.fast, value: hovering)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.accessibilityLabel)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityActions {
            ForEach(RowAction.available(for: download), id: \.self) { action in
                Button(action.title) { action.perform(on: download, model: model) }
            }
        }
    }
}

/// Quick Look thumbnail for finished images, videos and documents; the type tile otherwise or until it loads.
struct FileThumbnail: View {
    let item: DownloadItem
    let size: CGFloat
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: RocketRadius.control))
                    .overlay(RoundedRectangle(cornerRadius: RocketRadius.control).strokeBorder(RocketColor.hairline))
                    .accessibilityHidden(true)
            } else {
                FileTile(symbol: item.category.symbol, size: size)
            }
        }
        .task(id: url) { image = await Self.thumbnail(for: url, size: size) }
    }

    private var url: URL? {
        let thumbnailable: Set<FileCategory> = [.image, .video, .document]
        return item.download.state == .completed && thumbnailable.contains(item.category) ? item.download.fileURL : nil
    }

    /// ponytail: unbounded-by-count NSCache (the system evicts under pressure); add a cost limit if grids get huge.
    @MainActor private static let cache = NSCache<NSURL, NSImage>()

    @MainActor
    static func thumbnail(for url: URL?, size: CGFloat) async -> NSImage? {
        guard let url else { return nil }
        if let hit = cache.object(forKey: url as NSURL) { return hit }
        let request = QLThumbnailGenerator.Request(
            fileAt: url, size: CGSize(width: size, height: size), scale: 2, representationTypes: .thumbnail
        )
        guard let image = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request).nsImage else { return nil }
        cache.setObject(image, forKey: url as NSURL)
        return image
    }
}

/// "68% · 24 MB/s" while transferring.
private struct LiveMetrics: View {
    let item: DownloadItem

    var body: some View {
        Text(text)
            .font(.rocketLabel)
            .monospacedDigit()
            .foregroundStyle(RocketColor.accent)
            .lineLimit(1)
            .fixedSize()
    }

    private var text: String {
        switch item.download.state {
        case .probing: return String(localized: "Starting…")
        case .verifying: return String(localized: "Verifying…")
        default:
            var parts: [String] = []
            if let fraction = item.fraction { parts.append(fraction.formatted(.percent.precision(.fractionLength(0)))) }
            if item.speed > 0 { parts.append(Format.speed(item.speed)) }
            return parts.isEmpty ? item.download.state.title : parts.joined(separator: " · ")
        }
    }
}

/// Symbol + word in the state's color, plus context (queue position, error, percent).
struct StatusLabel: View {
    let item: DownloadItem
    var queuePosition: Int?

    private var download: Download { item.download }

    var body: some View {
        HStack(spacing: RocketSpace.s2) {
            Image(systemName: download.state.statusSymbol)
                .imageScale(.small)
            Text(download.state.title)
            if let extra {
                Text("· " + extra)
                    .foregroundStyle(RocketColor.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .font(.rocketLabel)
        .foregroundStyle(download.state.statusColor)
        .help(download.failure?.userMessage ?? "")
    }

    private var extra: String? {
        switch download.state {
        case .queued: queuePosition.map { String(localized: "#\($0) in queue") }
        case .paused: item.fraction.map { $0.formatted(.percent.precision(.fractionLength(0))) }
        case .failed: download.failure?.userMessage
        default: nil
        }
    }
}

/// Hover buttons for the row's state, then a more menu with the full command set.
private struct RowActions: View {
    let item: DownloadItem
    let model: DownloadsModel
    var compact = false

    private var download: Download { item.download }

    var body: some View {
        HStack(spacing: RocketSpace.s1) {
            if download.state == .queued, model.queues.count > 1 {
                Menu {
                    MoveToQueueItems(ids: [download.id], model: model)
                } label: {
                    Image(systemName: "arrow.left.arrow.right")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .frame(width: RocketSize.iconButton, height: RocketSize.iconButton)
                .help("Move to Queue")
            }
            if !compact {
                ForEach(RowAction.available(for: download).filter { $0 != .remove }, id: \.self) { action in
                    Button(action.title, systemImage: action.symbol) { action.perform(on: download, model: model) }
                        .buttonStyle(IconButtonStyle(role: action == .cancel ? .destructive : nil))
                        .help(action.title)
                }
            }
            Menu {
                DownloadMenuItems(ids: menuIDs, model: model)
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: RocketSize.iconButton, height: RocketSize.iconButton)
            .help("More")
        }
        .foregroundStyle(RocketColor.textSecondary)
    }

    /// The menu acts on the whole selection when this item is part of it.
    private var menuIDs: Set<UUID> {
        model.selection.contains(download.id) ? model.selection : [download.id]
    }
}

/// The full command set for one or more downloads; used by the context menu and the more menu.
struct DownloadMenuItems: View {
    let ids: Set<UUID>
    let model: DownloadsModel

    var body: some View {
        let downloads = ids.compactMap(model.download)
        let states = downloads.map(\.state)
        if states.contains(where: { $0 == .paused || $0 == .failed }) {
            Button("Resume") { Task { await model.resume(ids) } }
        }
        if states.contains(where: \.isActive) {
            Button("Pause") { Task { await model.pause(ids) } }
        }
        if states.contains(.completed) {
            Button("Open") { ids.forEach(model.open) }
        }
        Button("Show in Finder") { model.reveal(ids) }
        if downloads.count == 1, let download = downloads.first {
            Button("Show Details") { model.showDetails(download.id) }
            if download.state != .completed {
                Button("Refresh Link…") { model.refreshing = download }
            }
            Button("Copy Link") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(download.url.absoluteString, forType: .string)
            }
        }
        Divider()
        Menu("Move to Queue") { MoveToQueueItems(ids: ids, model: model) }
        Menu("Speed Limit") {
            SpeedLimitPicker(current: downloads.count == 1 ? downloads.first?.speedLimit : nil) { rate in
                Task { await model.setLimit(ids, bytesPerSecond: rate) }
            }
        }
        Divider()
        if states.contains(where: { $0.isActive || $0 == .paused }) {
            Button("Cancel Download") { Task { await model.cancel(ids) } }
        }
        Button("Remove from List") { Task { await model.remove(ids) } }
        if states.contains(.completed) {
            Button("Remove and Move File to Trash") { Task { await model.remove(ids, deleteFiles: true) } }
        }
    }
}

private struct MoveToQueueItems: View {
    let ids: Set<UUID>
    let model: DownloadsModel

    var body: some View {
        ForEach(model.queues) { queue in
            Button(queue.name) { Task { await model.move(Array(ids), toQueue: queue.id) } }
        }
    }
}

/// Row actions per state; the same set drives hover buttons and VoiceOver actions.
enum RowAction: Hashable {
    case pause, resume, retry, cancel, open, reveal, remove, refreshLink, viewError, details

    static func available(for download: Download) -> [RowAction] {
        // Expired or forbidden links get Refresh Link instead of a plain retry (FR-ENG-09).
        if download.state == .failed, case .http(let status)? = download.failure, [401, 403, 404, 410].contains(status) {
            return [.refreshLink, .viewError, .remove]
        }
        return available(for: download.state)
    }

    static func available(for state: DownloadState) -> [RowAction] {
        switch state {
        // Failed rows reach details through View Error; every other row gets a Details button.
        case .probing, .downloading, .verifying: [.pause, .cancel, .details]
        case .queued: [.details, .remove] // Move is a menu next to it
        case .paused: [.resume, .cancel, .details]
        case .failed: [.retry, .viewError, .remove]
        case .completed: [.open, .reveal, .details, .remove]
        case .cancelled: [.details, .remove]
        }
    }

    var title: String {
        switch self {
        case .pause: String(localized: "Pause")
        case .resume: String(localized: "Resume")
        case .retry: String(localized: "Retry")
        case .cancel: String(localized: "Cancel")
        case .open: String(localized: "Open")
        case .reveal: String(localized: "Show in Finder")
        case .remove: String(localized: "Remove from List")
        case .refreshLink: String(localized: "Refresh Link…")
        case .viewError: String(localized: "View Error")
        case .details: String(localized: "Show Details")
        }
    }

    var symbol: String {
        switch self {
        case .pause: "pause.circle"
        case .resume: "play.circle"
        case .retry: "arrow.clockwise"
        case .cancel: "xmark"
        case .open: "arrow.up.forward.square"
        case .reveal: "folder"
        case .remove: "minus.circle"
        case .refreshLink: "link"
        case .viewError: "exclamationmark.bubble"
        case .details: "info.circle"
        }
    }

    @MainActor
    func perform(on download: Download, model: DownloadsModel) {
        let ids = [download.id]
        switch self {
        case .open: model.open(download.id)
        case .reveal: model.reveal(ids)
        case .refreshLink: model.refreshing = download
        case .viewError, .details:
            // The details sheet shows the failure and the download's log.
            model.showDetails(download.id)
        case .pause: Task { await model.pause(ids) }
        case .resume, .retry: Task { await model.resume(ids) }
        case .cancel: Task { await model.cancel(ids) }
        case .remove: Task { await model.remove(ids) }
        }
    }
}

extension DownloadState {
    var isTransferring: Bool { [.probing, .downloading, .verifying].contains(self) }

    var statusSymbol: String {
        switch self {
        case .queued: "clock"
        case .probing, .downloading: "arrow.down.circle"
        case .verifying: "checkmark.shield"
        case .paused: "pause.circle"
        case .completed: "checkmark.circle"
        case .failed: "exclamationmark.circle"
        case .cancelled: "xmark.circle"
        }
    }

    var statusColor: Color {
        switch self {
        case .queued: RocketColor.warning
        case .probing, .downloading, .verifying: RocketColor.accent
        case .completed: RocketColor.success
        case .failed: RocketColor.danger
        case .paused: RocketColor.textSecondary
        case .cancelled: RocketColor.textTertiary
        }
    }
}
