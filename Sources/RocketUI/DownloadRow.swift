import AppKit
import QuickLookThumbnailing
import RocketCore
import RocketDesign
import SwiftUI
import UniformTypeIdentifiers

/// Percent and a thin bar. Completed rows settle on a full track.
struct ProgressCell: View {
    let item: DownloadItem
    @State private var completionFlash = false

    var body: some View {
        let download = item.download
        let active = download.state.isTransferring || download.state == .paused || completionFlash
        HStack(spacing: 8) {
            RocketProgressBar(
                fraction: completionFlash || download.state == .completed ? 1 : item.fraction,
                tint: completionFlash || download.state == .completed ? RocketColor.success
                    : download.state == .paused ? RocketColor.textTertiary : RocketColor.accent
            )
            Text(percent)
                .font(.rocketCaption)
                .monospacedDigit()
                .foregroundStyle(active ? RocketColor.textSecondary : RocketColor.textTertiary)
                .frame(width: 34, alignment: .trailing)
        }
        .onChange(of: download.state) { previous, state in
            guard state == .completed, previous != .completed else { return }
            completionFlash = true
            Task {
                try? await Task.sleep(for: RocketMotion.completionFlash)
                if !Task.isCancelled { completionFlash = false }
            }
        }
    }

    private var percent: String {
        if item.download.state == .completed || completionFlash { return "100%" }
        guard let fraction = item.fraction else { return "—" }
        return fraction.formatted(.percent.precision(.fractionLength(0)))
    }
}

/// Quick Look thumbnail for finished images, videos and documents; the Finder icon for the file type otherwise.
struct FileThumbnail: View {
    let item: DownloadItem
    let size: CGFloat
    @State private var image: NSImage?

    var body: some View {
        Image(nsImage: image ?? Self.typeIcon(item.download.fileName))
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
            .task(id: url) { image = await Self.thumbnail(for: url, size: size) }
    }

    @MainActor private static var typeIcons: [String: NSImage] = [:]

    /// Finder's icon for the extension, one per extension.
    @MainActor
    static func typeIcon(_ fileName: String) -> NSImage {
        let ext = (fileName as NSString).pathExtension.lowercased()
        if let icon = typeIcons[ext] { return icon }
        let icon = NSWorkspace.shared.icon(for: UTType(filenameExtension: ext) ?? .data)
        typeIcons[ext] = icon
        return icon
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

/// Drawn status glyph + word in the state's color, then context (size, queue position, error).
struct StatusLabel: View {
    let item: DownloadItem
    var queuePosition: Int?
    var showsDetail = true
    /// Table cells show the status word only; the error stays on the tooltip.
    var titleOnly = false

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
        if titleOnly { return nil }
        switch download.state {
        case .queued:
            let position = queuePosition.map { String(localized: "#\($0) in queue") }
            return showsDetail ? [position, Format.size(item)].compactMap { $0 }.joined(separator: " · ") : position
        case .failed: return download.failure?.userMessage
        default: return showsDetail ? Format.size(item) : nil
        }
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
        case .paused: RocketColor.warning
        case .queued: RocketColor.textSecondary
        case .cancelled: RocketColor.textTertiary
        }
    }
}
