import AppKit
import QuickLookThumbnailing
import RocketCore
import RocketDesign
import SwiftUI

/// List row: file tile, name, status line; live progress (or a date) on the right, swapped for actions on hover.
struct DownloadRow: View {
    let item: DownloadItem
    let model: DownloadsModel
    var queuePosition: Int?
    var isSelected = false
    @State private var hovering = false

    private var download: Download { item.download }

    var body: some View {
        HStack(spacing: RocketSpace.s4) {
            FileThumbnail(item: item, size: RocketSize.fileTileRow)
            VStack(alignment: .leading, spacing: 3) {
                Text(download.fileName)
                    .font(.rocketHeadline)
                    .foregroundStyle(RocketColor.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                StatusLabel(item: item, queuePosition: queuePosition)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            ZStack(alignment: .trailing) {
                TrailingInfo(item: item)
                    .opacity(hovering ? 0 : 1)
                    .offset(x: hovering ? 6 : 0)
                RowActions(item: item, model: model)
                    .opacity(hovering ? 1 : 0)
                    .offset(x: hovering ? 0 : 6)
                    .allowsHitTesting(hovering)
            }
            .rocketAnimation(RocketMotion.fast, value: hovering)
        }
        .padding(.horizontal, RocketSpace.s4)
        .frame(height: RocketSize.row)
        .background(
            isSelected ? RocketColor.selected : hovering ? RocketColor.hover : .clear,
            in: RoundedRectangle(cornerRadius: RocketRadius.card - 2, style: .continuous)
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .rocketAnimation(RocketMotion.fast, value: hovering)
        .rocketAnimation(RocketMotion.fast, value: isSelected)
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

/// Right column of a row: percent, speed and a bar while transferring, the paused bar, or when it was added.
private struct TrailingInfo: View {
    let item: DownloadItem
    @State private var completionFlash = false

    var body: some View {
        let download = item.download
        Group {
            if download.state.isTransferring || download.state == .paused || completionFlash {
                VStack(alignment: .trailing, spacing: 6) {
                    LiveMetrics(item: item)
                    RocketProgressBar(
                        fraction: completionFlash ? 1 : item.fraction,
                        tint: progressTint(for: download.state)
                    )
                    .frame(width: 132)
                }
            } else {
                Text(download.completedAt ?? download.createdAt, format: .dateTime.month(.abbreviated).day())
                    .font(.rocketLabel)
                    .foregroundStyle(RocketColor.textTertiary)
                    .monospacedDigit()
            }
        }
        .rocketTransition(.opacity)
        .rocketAnimation(RocketMotion.standard, value: completionFlash)
        .rocketAnimation(RocketMotion.standard, value: download.state)
        .onChange(of: download.state) { previous, state in
            guard state == .completed, previous != .completed else { return }
            completionFlash = true
            Task {
                try? await Task.sleep(for: RocketMotion.completionFlash)
                if !Task.isCancelled { completionFlash = false }
            }
        }
    }

    private func progressTint(for state: DownloadState) -> Color {
        if completionFlash { return RocketColor.success }
        return state == .paused ? RocketColor.textTertiary : RocketColor.accent
    }
}

/// Grid card: larger tile, name, status, progress; actions appear on hover.
struct DownloadCard: View {
    let item: DownloadItem
    let model: DownloadsModel
    var queuePosition: Int?
    var isSelected = false
    @State private var hovering = false

    private var download: Download { item.download }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: RocketRadius.card, style: .continuous)
        VStack(alignment: .leading, spacing: RocketSpace.s4) {
            HStack(alignment: .top) {
                FileThumbnail(item: item, size: RocketSize.fileTileCard)
                Spacer(minLength: 0)
                RowActions(item: item, model: model, compact: true)
                    .opacity(hovering ? 1 : 0)
                    .allowsHitTesting(hovering)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(download.fileName)
                    .font(.rocketHeadline)
                    .foregroundStyle(RocketColor.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .rocketTooltip(download.fileName)
                StatusLabel(item: item, queuePosition: queuePosition, showsDetail: false)
            }
            VStack(alignment: .leading, spacing: 6) {
                RocketProgressBar(
                    fraction: download.state == .completed ? 1 : item.fraction,
                    tint: download.state.isTransferring ? RocketColor.accent
                        : download.state == .completed ? RocketColor.success.opacity(0.5) : RocketColor.textTertiary
                )
                HStack {
                    Text(Format.size(item))
                        .font(.rocketCaption)
                        .foregroundStyle(RocketColor.textSecondary)
                        .monospacedDigit()
                        .lineLimit(1)
                    Spacer(minLength: RocketSpace.s2)
                    if download.state.isTransferring { LiveMetrics(item: item, speedOnly: true) }
                }
            }
        }
        .padding(RocketSpace.s4 + 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isSelected ? RocketColor.selected : RocketColor.raised, in: shape)
        .overlay(shape.strokeBorder(isSelected ? RocketColor.accent.opacity(0.75) : hovering ? RocketColor.borderStrong : RocketColor.border))
        .contentShape(shape)
        .onHover { hovering = $0 }
        .rocketAnimation(RocketMotion.fast, value: hovering)
        .rocketAnimation(RocketMotion.fast, value: isSelected)
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
                let shape = RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .clipShape(shape)
                    .overlay(shape.strokeBorder(RocketColor.border))
                    .accessibilityHidden(true)
                    .transition(.opacity)
            } else {
                FileTile(symbol: item.category.symbol, size: size)
            }
        }
        .animation(RocketMotion.enter, value: image != nil)
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

/// "68% · 24 MB/s" while transferring, "Paused · 31%" when paused.
private struct LiveMetrics: View {
    let item: DownloadItem
    var speedOnly = false

    var body: some View {
        Text(text)
            .font(.rocketLabel)
            .monospacedDigit()
            .foregroundStyle(item.download.state == .paused ? RocketColor.textSecondary : RocketColor.accentText)
            .lineLimit(1)
            .fixedSize()
            .contentTransition(.numericText())
            .animation(RocketMotion.progress, value: text)
    }

    private var text: String {
        switch item.download.state {
        case .probing: return String(localized: "Starting…")
        case .verifying: return String(localized: "Verifying…")
        default:
            var parts: [String] = []
            if !speedOnly, let fraction = item.fraction { parts.append(fraction.formatted(.percent.precision(.fractionLength(0)))) }
            if item.speed > 0 { parts.append(Format.speed(item.speed)) }
            return parts.isEmpty ? item.download.state.title : parts.joined(separator: " · ")
        }
    }
}

/// Drawn status glyph + word in the state's color, then context (size, queue position, error).
struct StatusLabel: View {
    let item: DownloadItem
    var queuePosition: Int?
    var showsDetail = true

    private var download: Download { item.download }

    var body: some View {
        HStack(spacing: 6) {
            StatusGlyph(download.state.glyph(item.fraction), size: 11)
                .rocketAnimation(RocketMotion.fast, value: download.state)
            Text(download.state.title)
                .foregroundStyle(download.state.textColor)
                .fixedSize()
                .rocketAnimation(RocketMotion.fast, value: download.state)
            if let extra {
                Text(extra)
                    .foregroundStyle(download.state == .failed ? RocketColor.danger.opacity(0.85) : RocketColor.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .font(.rocketLabel)
        .monospacedDigit()
        .rocketTooltip(download.failure?.userMessage ?? "")
    }

    private var extra: String? {
        switch download.state {
        case .queued:
            let position = queuePosition.map { String(localized: "#\($0) in queue") }
            return showsDetail ? [position, Format.size(item)].compactMap { $0 }.joined(separator: " · ") : position
        case .failed: return download.failure?.userMessage
        default: return showsDetail ? Format.size(item) : nil
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
                RocketMenuButton(alignment: .trailing) {
                    [RocketMenuSection(String(localized: "Move to queue"), items: DownloadMenu.queueItems(ids: [download.id], model: model))]
                } label: {
                    Label("Move to Queue", systemImage: "arrow.left.arrow.right")
                }
                .buttonStyle(.rocketIcon)
                .rocketTooltip(String(localized: "Move to Queue"))
            }
            if !compact {
                ForEach(RowAction.available(for: download).filter { $0 != .remove }, id: \.self) { action in
                    Button(action.title, systemImage: action.symbol) { action.perform(on: download, model: model) }
                        .buttonStyle(IconButtonStyle(role: action == .cancel ? .destructive : nil))
                        .rocketTooltip(action.title)
                }
            }
            RocketMenuButton(alignment: .trailing) {
                DownloadMenu.sections(ids: menuIDs, model: model)
            } label: {
                Label("More", systemImage: "ellipsis")
            }
            .buttonStyle(.rocketIcon)
            .rocketTooltip(String(localized: "More"))
        }
    }

    /// The menu acts on the whole selection when this item is part of it.
    private var menuIDs: Set<UUID> {
        model.selection.contains(download.id) ? model.selection : [download.id]
    }
}

/// The full command set for one or more downloads; used by the context menu and the more menu.
@MainActor
enum DownloadMenu {
    static func sections(ids: Set<UUID>, model: DownloadsModel) -> [RocketMenuSection] {
        let downloads = ids.compactMap(model.download)
        let states = downloads.map(\.state)
        var primary: [RocketMenuItem] = []
        if states.contains(where: { $0 == .paused || $0 == .failed }) {
            primary.append(RocketMenuItem(String(localized: "Resume"), symbol: "play") { Task { await model.resume(ids) } })
        }
        if states.contains(where: \.isActive) {
            primary.append(RocketMenuItem(String(localized: "Pause"), symbol: "pause") { Task { await model.pause(ids) } })
        }
        if states.contains(.completed) {
            primary.append(RocketMenuItem(String(localized: "Open"), symbol: "arrow.up.forward.square") { ids.forEach(model.open) })
        }
        primary.append(RocketMenuItem(String(localized: "Show in Finder"), symbol: "folder", shortcut: "⌘O") { model.reveal(ids) })
        if downloads.count == 1, let download = downloads.first {
            primary.append(RocketMenuItem(String(localized: "Show Details"), symbol: "info.circle", shortcut: "⌘I") { model.showDetails(download.id) })
            if download.state != .completed {
                primary.append(RocketMenuItem(String(localized: "Refresh Link…"), symbol: "link") { model.refreshing = download })
            }
            primary.append(RocketMenuItem(String(localized: "Copy Link"), symbol: "doc.on.doc") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(download.url.absoluteString, forType: .string)
            })
        }
        let current = downloads.count == 1 ? downloads.first?.speedLimit : nil
        let organize = [
            RocketMenuItem.submenu(String(localized: "Move to Queue"), symbol: "tray.2", children: queueItems(ids: ids, model: model)),
            RocketMenuItem.submenu(String(localized: "Speed Limit"), symbol: "gauge.with.dots.needle.33percent",
                                   children: SpeedLimitOptions.menuItems(current: current) { rate in
                                       Task { await model.setLimit(ids, bytesPerSecond: rate) }
                                   }),
        ]
        var destructive: [RocketMenuItem] = []
        if states.contains(where: { $0.isActive || $0 == .paused }) {
            destructive.append(RocketMenuItem(String(localized: "Cancel Download"), symbol: "xmark.circle") { Task { await model.cancel(ids) } })
        }
        destructive.append(RocketMenuItem(String(localized: "Remove from List"), symbol: "minus.circle", shortcut: "⌫") {
            Task { await model.remove(ids) }
        })
        if states.contains(.completed) {
            destructive.append(RocketMenuItem(String(localized: "Remove and Move File to Trash"), symbol: "trash", role: .destructive) {
                Task { await model.remove(ids, deleteFiles: true) }
            })
        }
        return [RocketMenuSection(items: primary), RocketMenuSection(items: organize), RocketMenuSection(items: destructive)]
    }

    static func queueItems(ids: Set<UUID>, model: DownloadsModel) -> [RocketMenuItem] {
        let current = Set(ids.compactMap { model.download($0)?.queueID })
        return model.queues.map { queue in
            RocketMenuItem(queue.name, checked: current == [queue.id]) { Task { await model.move(Array(ids), toQueue: queue.id) } }
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
        case .pause: "pause"
        case .resume: "play"
        case .retry: "arrow.clockwise"
        case .cancel: "xmark.circle"
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
            // The details view shows the failure and the download's log.
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

    func glyph(_ fraction: Double?) -> StatusGlyph.Kind {
        switch self {
        case .queued: .queued
        case .probing, .downloading: .active(fraction)
        case .verifying: .verifying
        case .paused: .paused(fraction)
        case .completed: .done
        case .failed: .failed
        case .cancelled: .cancelled
        }
    }

    /// The status word's color; Ember text for live states so it stays legible on light surfaces.
    var textColor: Color {
        switch self {
        case .probing, .downloading, .verifying: RocketColor.accentText
        case .completed: RocketColor.success
        case .failed: RocketColor.danger
        case .queued, .paused: RocketColor.textSecondary
        case .cancelled: RocketColor.textTertiary
        }
    }
}
