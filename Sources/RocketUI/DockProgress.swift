import AppKit
import RocketDesign

/// Dock badge (active count) and a progress bar on the app icon (FR-APP-06). Can be turned off in Settings.
@MainActor
public final class DockProgress {
    private let tile = NSApp.dockTile
    private let view = DockTileView()
    private var last: (count: Int, fraction: Double?)?

    public init() {}

    public func update(count: Int, fraction: Double?, enabled: Bool) {
        let state = enabled ? (count, fraction.map { ($0 * 50).rounded() / 50 }) : (0, nil) // 2 % steps: few redraws
        guard last.map({ $0.count != state.0 || $0.fraction != state.1 }) ?? true else { return }
        last = state
        tile.badgeLabel = state.0 > 0 ? "\(state.0)" : nil
        view.fraction = state.1
        tile.contentView = state.1 == nil ? nil : view
        tile.display()
    }
}

private final class DockTileView: NSView {
    var fraction: Double?

    override func draw(_ dirtyRect: NSRect) {
        NSApp.applicationIconImage.draw(in: bounds)
        guard let fraction else { return }
        let bar = NSRect(x: bounds.width * 0.12, y: bounds.height * 0.08, width: bounds.width * 0.76, height: bounds.height * 0.09)
        NSColor.black.withAlphaComponent(0.55).setFill()
        NSBezierPath(roundedRect: bar, xRadius: bar.height / 2, yRadius: bar.height / 2).fill()
        let fill = bar.insetBy(dx: 2, dy: 2)
        NSColor(RocketColor.accent).setFill()
        NSBezierPath(roundedRect: NSRect(x: fill.minX, y: fill.minY, width: max(fill.height, fill.width * min(1, fraction)), height: fill.height),
                     xRadius: fill.height / 2, yRadius: fill.height / 2).fill()
    }
}
