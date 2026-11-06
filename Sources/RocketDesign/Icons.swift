import AppKit
import SwiftUI

/// SF Symbol by Rocket name, or any SF Symbol name via `init(symbol:)`.
public struct RocketIcon: View {
    let symbol: String
    let size: CGFloat

    public init(_ name: Name, size: CGFloat = 15) {
        symbol = name.symbol
        self.size = size
    }

    public init(symbol: String, size: CGFloat = 15) {
        self.symbol = symbol
        self.size = size
    }

    public var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.9))
            .accessibilityHidden(true)
    }

    public enum Name: Sendable {
        case plus, minus, close, check, chevronRight, chevronUpDown
        case search, filter, sort, ellipsis, sliders, grip
        case pause, play, refresh, arrowDown, download
        case gear, clock, calendar, tray, queue, list, grid, chart, spark, gauge
        case folder, trash, copy, link, open, info, pencil, swap
        case file, document, archive, image, video, audio, app
        case globe, network, sidebar
        case circleX, circleMinus, checkCircle, alert, alertCircle

        public var symbol: String {
            switch self {
            case .plus: "plus"
            case .minus: "minus"
            case .close: "xmark"
            case .check: "checkmark"
            case .chevronRight: "chevron.right"
            case .chevronUpDown: "chevron.up.chevron.down"
            case .search: "magnifyingglass"
            case .filter: "line.3.horizontal.decrease.circle"
            case .sort: "arrow.up.arrow.down"
            case .ellipsis: "ellipsis.circle"
            case .sliders: "slider.horizontal.3"
            case .grip: "line.3.horizontal"
            case .pause: "pause.fill"
            case .play: "play.fill"
            case .refresh: "arrow.clockwise"
            case .arrowDown: "arrow.down"
            case .download: "arrow.down.circle"
            case .gear: "gearshape"
            case .clock: "clock"
            case .calendar: "calendar"
            case .tray: "tray"
            case .queue: "tray.2"
            case .list: "list.bullet"
            case .grid: "square.grid.2x2"
            case .chart: "chart.bar"
            case .spark: "sparkles"
            case .gauge: "gauge.with.dots.needle.33percent"
            case .folder: "folder"
            case .trash: "trash"
            case .copy: "doc.on.doc"
            case .link: "link"
            case .open: "arrow.up.forward.app"
            case .info: "info.circle"
            case .pencil: "pencil"
            case .swap: "arrow.left.arrow.right"
            case .file: "doc"
            case .document: "doc.text"
            case .archive: "doc.zipper"
            case .image: "photo"
            case .video: "film"
            case .audio: "waveform"
            case .app: "app"
            case .globe: "globe"
            case .network: "network"
            case .sidebar: "sidebar.left"
            case .circleX: "xmark.circle"
            case .circleMinus: "minus.circle"
            case .checkCircle: "checkmark.circle"
            case .alert: "exclamationmark.triangle"
            case .alertCircle: "exclamationmark.circle"
            }
        }
    }
}

/// Borderless icon button with a help tag. The title is the accessibility label.
public struct RocketIconButton: View {
    let title: String
    let icon: RocketIcon.Name
    var role: ButtonRole?
    var shortcut: String?
    let action: () -> Void

    public init(_ title: String, icon: RocketIcon.Name, role: ButtonRole? = nil, isActive: Bool = false,
                size: CGFloat = 0, shortcut: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.role = role
        self.shortcut = shortcut
        self.action = action
    }

    public var body: some View {
        Button(role: role, action: action) {
            Label(title, systemImage: icon.symbol)
        }
        .buttonStyle(.borderless)
        .labelStyle(.iconOnly)
        .rocketTooltip(title, shortcut: shortcut)
    }
}

/// Native checkbox, including the mixed state for "some rows selected".
public struct MacCheckbox: NSViewRepresentable {
    public var state: NSControl.StateValue
    public var allowsMixed: Bool
    public var label: String
    public var onToggle: () -> Void

    public init(state: NSControl.StateValue, allowsMixed: Bool = false, label: String, onToggle: @escaping () -> Void) {
        self.state = state
        self.allowsMixed = allowsMixed
        self.label = label
        self.onToggle = onToggle
    }

    public func makeCoordinator() -> Coordinator { Coordinator() }

    public func makeNSView(context: Context) -> NSButton {
        let button = NSButton(checkboxWithTitle: "", target: context.coordinator, action: #selector(Coordinator.toggle(_:)))
        button.controlSize = .small
        return button
    }

    public func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.onToggle = onToggle
        button.allowsMixedState = allowsMixed
        if button.state != state { button.state = state }
        button.setAccessibilityLabel(label)
    }

    public final class Coordinator: NSObject {
        var onToggle: () -> Void = {}
        @objc func toggle(_ sender: NSButton) { onToggle() }
    }
}
