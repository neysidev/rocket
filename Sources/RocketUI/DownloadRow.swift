import RocketCore
import RocketDesign
import SwiftUI

/// File tile, name, metadata line, 3 pt progress bar; actions appear on hover (always in the context menu).
struct DownloadRow: View {
    let item: DownloadItem
    let model: DownloadsModel
    @State private var hovering = false

    private var download: Download { item.download }

    var body: some View {
        HStack(spacing: RocketSpace.s4) {
            FileTile(symbol: item.category.symbol)
            VStack(alignment: .leading, spacing: RocketSpace.s1) {
                Text(download.fileName)
                    .font(.rocketHeadline)
                    .foregroundStyle(RocketColor.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: RocketSpace.s2) {
                    Text(download.state.title)
                        .foregroundStyle(statusColor)
                    Text(Format.detail(item))
                        .foregroundStyle(RocketColor.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .font(.rocketLabel)
                .monospacedDigit()
                if showsProgress {
                    RocketProgressBar(fraction: item.fraction, tint: progressTint)
                        .padding(.top, RocketSpace.s1)
                }
            }
            Spacer(minLength: RocketSpace.s3)
            actions
                .opacity(hovering ? 1 : 0)
                .animation(RocketMotion.fast, value: hovering)
        }
        .frame(minHeight: RocketSize.row)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.accessibilityLabel)
        .accessibilityActions {
            ForEach(RowAction.available(for: download.state), id: \.self) { action in
                Button(action.title) { perform(action) }
            }
        }
    }

    private var showsProgress: Bool {
        ![.completed, .cancelled].contains(download.state)
    }

    private var statusColor: Color {
        switch download.state {
        case .downloading, .probing, .verifying: RocketColor.flameText
        case .completed: RocketColor.success
        case .failed: RocketColor.danger
        default: RocketColor.textSecondary
        }
    }

    private var progressTint: Color {
        switch download.state {
        case .downloading, .probing, .verifying: RocketColor.flame
        case .failed: RocketColor.danger
        default: RocketColor.textTertiary
        }
    }

    private var actions: some View {
        HStack(spacing: RocketSpace.s1) {
            ForEach(RowAction.available(for: download.state), id: \.self) { action in
                Button(action.title, systemImage: action.symbol) { perform(action) }
                    .buttonStyle(IconButtonStyle(role: action == .cancel ? .destructive : nil))
                    .help(action.title)
            }
        }
    }

    private func perform(_ action: RowAction) {
        let ids = [download.id]
        Task {
            switch action {
            case .pause: await model.pause(ids)
            case .resume, .retry: await model.resume(ids)
            case .cancel: await model.cancel(ids)
            case .reveal: model.reveal(ids)
            case .remove: await model.remove(ids)
            }
        }
    }
}

/// Row actions per state; the same set drives hover buttons, the context menu and VoiceOver actions.
enum RowAction: Hashable {
    case pause, resume, retry, cancel, reveal, remove

    static func available(for state: DownloadState) -> [RowAction] {
        switch state {
        case .queued, .probing, .downloading, .verifying: [.pause, .cancel]
        case .paused: [.resume, .cancel]
        case .failed: [.retry, .remove]
        case .completed: [.reveal, .remove]
        case .cancelled: [.remove]
        }
    }

    var title: String {
        switch self {
        case .pause: String(localized: "Pause")
        case .resume: String(localized: "Resume")
        case .retry: String(localized: "Retry")
        case .cancel: String(localized: "Cancel")
        case .reveal: String(localized: "Show in Finder")
        case .remove: String(localized: "Remove from List")
        }
    }

    var symbol: String {
        switch self {
        case .pause: "pause"
        case .resume: "play"
        case .retry: "arrow.clockwise"
        case .cancel: "xmark"
        case .reveal: "magnifyingglass.circle"
        case .remove: "minus.circle"
        }
    }
}
