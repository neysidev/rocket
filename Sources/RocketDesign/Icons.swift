import AppKit
import SwiftUI

/// Stroke icons drawn on one 24 pt grid: 1.6 pt round stroke, no fills except dots.
/// Pass an SF Symbol name to `init(symbol:)` and it maps onto this set.
public struct RocketIcon: View {
    public var name: Name
    public var size: CGFloat

    public init(_ name: Name, size: CGFloat = 15) {
        self.name = name
        self.size = size
    }

    /// Maps a legacy SF Symbol name onto the stroke set. Unknown names draw a plain file.
    public init(symbol: String, size: CGFloat = 15) {
        self.name = Name(symbol: symbol) ?? .file
        self.size = size
    }

    public var body: some View {
        Canvas { context, canvas in
            let scale = canvas.width / 24
            var pen = Pen()
            name.draw(&pen)
            context.scaleBy(x: scale, y: scale)
            let style = StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round)
            context.stroke(pen.stroke, with: .foreground, style: style)
            context.fill(pen.fill, with: .foreground)
        }
        .frame(width: size, height: size)
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

        init?(symbol: String) {
            switch symbol {
            case "plus": self = .plus
            case "minus": self = .minus
            case "xmark", "xmark.circle.fill": self = symbol.contains("circle") ? .circleX : .close
            case "checkmark": self = .check
            case "chevron.right": self = .chevronRight
            case "chevron.up.chevron.down": self = .chevronUpDown
            case "magnifyingglass", "doc.text.magnifyingglass": self = .search
            case "line.3.horizontal.decrease": self = .filter
            case "arrow.up.arrow.down": self = .sort
            case "ellipsis": self = .ellipsis
            case "slider.horizontal.3": self = .sliders
            case "line.3.horizontal": self = .grip
            case "pause": self = .pause
            case "play", "play.circle", "play.rectangle": self = symbol == "play.rectangle" ? .video : .play
            case "arrow.clockwise": self = .refresh
            case "arrow.down", "arrow.down.circle", "arrow.down.circle.fill": self = .arrowDown
            case "tray.and.arrow.down": self = .download
            case "gearshape": self = .gear
            case "clock": self = .clock
            case "calendar", "calendar.badge.clock": self = .calendar
            case "tray": self = .tray
            case "tray.2", "list.bullet": self = symbol == "list.bullet" ? .list : .queue
            case "square.grid.2x2": self = .grid
            case "chart.bar": self = .chart
            case "sparkles": self = .spark
            case "gauge.with.dots.needle.33percent": self = .gauge
            case "folder": self = .folder
            case "trash": self = .trash
            case "doc.on.doc": self = .copy
            case "link": self = .link
            case "arrow.up.forward.square": self = .open
            case "info.circle": self = .info
            case "pencil": self = .pencil
            case "arrow.left.arrow.right": self = .swap
            case "doc", "doc.text": self = symbol == "doc.text" ? .document : .file
            case "doc.zipper", "externaldrive", "shippingbox": self = symbol == "shippingbox" ? .app : .archive
            case "photo": self = .image
            case "waveform": self = .audio
            case "globe": self = .globe
            case "network": self = .network
            case "xmark.circle": self = .circleX
            case "minus.circle": self = .circleMinus
            case "checkmark.circle": self = .checkCircle
            case "exclamationmark.triangle", "exclamationmark.bubble": self = .alert
            case "exclamationmark.circle": self = .alertCircle
            default: return nil
            }
        }

        fileprivate func draw(_ pen: inout Pen) {
            switch self {
            case .plus:
                pen.line(12, 5, 12, 19)
                pen.line(5, 12, 19, 12)
            case .minus:
                pen.line(5, 12, 19, 12)
            case .close:
                pen.line(7, 7, 17, 17)
                pen.line(17, 7, 7, 17)
            case .check:
                pen.line(6, 12.5, 10, 16.5, 18, 7.5)
            case .chevronRight:
                pen.line(9, 6, 15, 12, 9, 18)
            case .chevronUpDown:
                pen.line(8, 10, 12, 6, 16, 10)
                pen.line(8, 14, 12, 18, 16, 14)
            case .search:
                pen.circle(10.5, 10.5, 5.2)
                pen.line(14.4, 14.4, 19, 19)
            case .filter:
                pen.line(4, 6, 20, 6)
                pen.line(7, 12, 17, 12)
                pen.line(10, 18, 14, 18)
            case .sort:
                pen.line(7, 6, 7, 18)
                pen.line(4.5, 9, 7, 6, 9.5, 9)
                pen.line(17, 6, 17, 18)
                pen.line(14.5, 15, 17, 18, 19.5, 15)
            case .ellipsis:
                pen.dot(6.5, 12, 1.15)
                pen.dot(12, 12, 1.15)
                pen.dot(17.5, 12, 1.15)
            case .sliders:
                pen.line(4, 7, 20, 7)
                pen.line(4, 12, 20, 12)
                pen.line(4, 17, 20, 17)
                pen.circle(9, 7, 2)
                pen.circle(15, 12, 2)
                pen.circle(11, 17, 2)
            case .grip:
                pen.line(5, 7, 19, 7)
                pen.line(5, 12, 19, 12)
                pen.line(5, 17, 19, 17)
            case .pause:
                pen.line(9, 6, 9, 18)
                pen.line(15, 6, 15, 18)
            case .play:
                pen.line(8, 6, 17, 12, 8, 18, 8, 6)
            case .refresh:
                pen.arc(12, 12, 6.2, start: 40, end: 320)
                pen.line(16.2, 5.2, 16.8, 9.4, 12.8, 8.6)
            case .arrowDown:
                pen.line(12, 4, 12, 16)
                pen.line(6.5, 11, 12, 17, 17.5, 11)
            case .download:
                pen.line(12, 4, 12, 13)
                pen.line(8, 9.5, 12, 14, 16, 9.5)
                pen.line(5, 17, 5, 20, 19, 20, 19, 17)
            case .gear:
                pen.circle(12, 12, 3)
                pen.circle(12, 12, 7.4)
                for step in stride(from: 0, to: 360, by: 45) {
                    let rad = Double(step) * .pi / 180
                    let inner = (CGFloat(cos(rad)) * 7.2, CGFloat(sin(rad)) * 7.2)
                    let outer = (CGFloat(cos(rad)) * 9.4, CGFloat(sin(rad)) * 9.4)
                    pen.line(12 + inner.0, 12 + inner.1, 12 + outer.0, 12 + outer.1)
                }
            case .clock:
                pen.circle(12, 12, 7.5)
                pen.line(12, 12, 12, 8)
                pen.line(12, 12, 15.2, 13.4)
            case .calendar:
                pen.round(5, 6, 14, 14, 2)
                pen.line(5, 10, 19, 10)
                pen.line(9, 4, 9, 8)
                pen.line(15, 4, 15, 8)
            case .tray:
                pen.line(4, 10, 4, 18, 20, 18, 20, 10)
                pen.line(4, 10, 9, 10, 10.5, 13, 13.5, 13, 15, 10, 20, 10)
            case .queue:
                pen.round(4, 5, 16, 5, 1.5)
                pen.round(4, 12, 16, 5, 1.5)
            case .list:
                pen.line(8, 7, 19, 7)
                pen.line(8, 12, 19, 12)
                pen.line(8, 17, 19, 17)
                pen.dot(5, 7, 1)
                pen.dot(5, 12, 1)
                pen.dot(5, 17, 1)
            case .grid:
                pen.round(4, 4, 6.5, 6.5, 1.4)
                pen.round(13.5, 4, 6.5, 6.5, 1.4)
                pen.round(4, 13.5, 6.5, 6.5, 1.4)
                pen.round(13.5, 13.5, 6.5, 6.5, 1.4)
            case .chart:
                pen.line(5, 19, 19, 19)
                pen.line(7, 19, 7, 12)
                pen.line(12, 19, 12, 7)
                pen.line(17, 19, 17, 10)
            case .spark:
                pen.line(12, 3, 12, 21)
                pen.line(3, 12, 21, 12)
                pen.line(6.2, 6.2, 17.8, 17.8)
                pen.line(17.8, 6.2, 6.2, 17.8)
            case .gauge:
                pen.arc(12, 14, 7, start: 200, end: 340)
                pen.line(12, 14, 16.2, 10)
                pen.dot(12, 14, 1.1)
            case .folder:
                pen.line(4, 8, 4, 18, 20, 18, 20, 8, 12, 8, 10.5, 6, 4, 6, 4, 8)
            case .trash:
                pen.line(5, 7, 19, 7)
                pen.line(9, 7, 9.5, 19, 14.5, 19, 15, 7)
                pen.line(10, 4.5, 14, 4.5)
                pen.line(8, 7, 8, 5.5, 16, 5.5, 16, 7)
            case .copy:
                pen.round(8, 8, 11, 11, 1.6)
                pen.line(6, 16, 6, 6, 16, 6)
            case .link:
                pen.round(4, 9, 8, 6, 3)
                pen.round(12, 9, 8, 6, 3)
            case .open:
                pen.line(6, 8, 6, 18, 16, 18, 16, 14)
                pen.line(11, 5, 19, 5, 19, 13)
                pen.line(19, 5, 11, 13)
            case .info:
                pen.circle(12, 12, 7.5)
                pen.dot(12, 8.2, 0.9)
                pen.line(12, 11, 12, 16.5)
            case .pencil:
                pen.line(14, 5, 19, 10, 9, 20, 4, 20, 4, 15, 14, 5)
                pen.line(13, 8, 16, 11)
            case .swap:
                pen.line(4, 8, 16, 8)
                pen.line(13, 5, 16, 8, 13, 11)
                pen.line(20, 16, 8, 16)
                pen.line(11, 13, 8, 16, 11, 19)
            case .file:
                pen.line(7, 3, 14, 3, 19, 8, 19, 21, 7, 21, 7, 3)
                pen.line(14, 3, 14, 8, 19, 8)
            case .document:
                pen.line(7, 3, 14, 3, 19, 8, 19, 21, 7, 21, 7, 3)
                pen.line(14, 3, 14, 8, 19, 8)
                pen.line(10, 13, 16, 13)
                pen.line(10, 16.5, 16, 16.5)
            case .archive:
                pen.round(4, 4, 16, 16, 2)
                pen.line(4, 9, 20, 9)
                pen.line(10, 13, 14, 13)
            case .image:
                pen.round(3.5, 4, 17, 16, 2)
                pen.circle(8.5, 9, 1.6)
                pen.line(4, 17, 9, 12, 13, 16, 16, 13, 20, 16)
            case .video:
                pen.round(3, 6, 13, 12, 2)
                pen.line(16, 9, 21, 6.5, 21, 17.5, 16, 15)
            case .audio:
                pen.line(5, 10, 5, 14)
                pen.line(9, 7, 9, 17)
                pen.line(13, 4.5, 13, 19.5)
                pen.line(17, 8, 17, 16)
                pen.line(21, 10.5, 21, 13.5)
            case .app:
                pen.round(4, 4, 16, 16, 3.5)
                pen.line(12, 8, 12, 13)
                pen.line(9.5, 10.5, 12, 13, 14.5, 10.5)
            case .globe:
                pen.circle(12, 12, 7.5)
                pen.ellipse(12, 12, 3.4, 7.5)
                pen.line(4.5, 12, 19.5, 12)
            case .network:
                pen.circle(6, 8, 2.2)
                pen.circle(18, 8, 2.2)
                pen.circle(12, 17, 2.2)
                pen.line(8, 9, 16, 9)
                pen.line(7.2, 9.6, 10.6, 15.2)
                pen.line(16.8, 9.6, 13.4, 15.2)
            case .sidebar:
                pen.round(3, 4, 18, 16, 2)
                pen.line(9, 4, 9, 20)
            case .circleX:
                pen.circle(12, 12, 7.5)
                pen.line(9, 9, 15, 15)
                pen.line(15, 9, 9, 15)
            case .circleMinus:
                pen.circle(12, 12, 7.5)
                pen.line(8, 12, 16, 12)
            case .checkCircle:
                pen.circle(12, 12, 7.5)
                pen.line(8.5, 12.2, 11, 14.8, 15.8, 9.2)
            case .alert:
                pen.line(12, 4, 21, 19, 3, 19, 12, 4)
                pen.line(12, 10, 12, 14.5)
                pen.dot(12, 16.8, 0.8)
            case .alertCircle:
                pen.circle(12, 12, 7.5)
                pen.line(12, 8, 12, 13)
                pen.dot(12, 16, 0.85)
            }
        }
    }
}

/// Square icon button with a tooltip. The title is the accessibility label.
public struct RocketIconButton: View {
    let title: String
    let icon: RocketIcon.Name
    var role: ButtonRole?
    var isActive = false
    var size: CGFloat = RocketSize.iconButton
    var shortcut: String?
    let action: () -> Void

    public init(_ title: String, icon: RocketIcon.Name, role: ButtonRole? = nil, isActive: Bool = false,
                size: CGFloat = RocketSize.iconButton, shortcut: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.role = role
        self.isActive = isActive
        self.size = size
        self.shortcut = shortcut
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            RocketIcon(icon, size: min(15, size * 0.54))
        }
        .buttonStyle(IconButtonStyle(role: role, isActive: isActive, size: size))
        .accessibilityLabel(title)
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
        button.setContentHuggingPriority(.defaultLow, for: .horizontal)
        button.setContentHuggingPriority(.defaultLow, for: .vertical)
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

private struct Pen {
    var stroke = Path()
    var fill = Path()

    mutating func line(_ xs: CGFloat...) {
        var points: [CGPoint] = []
        var index = xs.startIndex
        while index < xs.endIndex {
            let x = xs[index]
            index = xs.index(after: index)
            guard index < xs.endIndex else { break }
            points.append(CGPoint(x: x, y: xs[index]))
            index = xs.index(after: index)
        }
        guard let first = points.first else { return }
        stroke.move(to: first)
        for point in points.dropFirst() { stroke.addLine(to: point) }
    }

    mutating func circle(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat) {
        stroke.addEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
    }

    mutating func ellipse(_ x: CGFloat, _ y: CGFloat, _ rx: CGFloat, _ ry: CGFloat) {
        stroke.addEllipse(in: CGRect(x: x - rx, y: y - ry, width: rx * 2, height: ry * 2))
    }

    mutating func dot(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat) {
        fill.addEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
    }

    mutating func round(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat) {
        stroke.addRoundedRect(in: CGRect(x: x, y: y, width: w, height: h), cornerSize: CGSize(width: r, height: r))
    }

    mutating func arc(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat, start: CGFloat, end: CGFloat) {
        stroke.addArc(center: CGPoint(x: x, y: y), radius: r,
                      startAngle: .degrees(start), endAngle: .degrees(end), clockwise: false)
    }
}

/// Sidebar material: system blur with a tint, or a solid fill when Reduce Transparency is on.
public extension View {
    func rocketSidebarBackground() -> some View {
        modifier(SidebarBackground())
    }
}

private struct SidebarBackground: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        content.background {
            if reduceTransparency {
                RocketColor.sidebar
            } else {
                ZStack {
                    SidebarVisualEffect()
                    RocketColor.sidebar.opacity(0.72)
                }
            }
        }
    }
}

private struct SidebarVisualEffect: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        view.isEmphasized = true
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}
