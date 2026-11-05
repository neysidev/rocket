import SwiftUI

// MARK: Buttons

/// Text buttons. Primary is the inverse fill (one per view), secondary is a bordered raised fill,
/// ghost has no fill until hovered, danger is for destructive confirmation only.
public struct RocketButtonStyle: ButtonStyle {
    public enum Variant: Sendable { case primary, secondary, ghost, danger }
    public enum Size: Sendable { case small, regular }

    let variant: Variant
    let size: Size
    let fullWidth: Bool

    public init(_ variant: Variant = .secondary, size: Size = .regular, fullWidth: Bool = false) {
        self.variant = variant
        self.size = size
        self.fullWidth = fullWidth
    }

    public func makeBody(configuration: Configuration) -> some View {
        StyledBody(configuration: configuration, style: self)
    }

    private struct StyledBody: View {
        let configuration: ButtonStyleConfiguration
        let style: RocketButtonStyle
        @State private var hovering = false
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: style.size == .small ? RocketRadius.small + 1 : RocketRadius.control, style: .continuous)
            configuration.label
                .font(style.size == .small ? .rocketLabel : .system(size: 13, weight: .medium))
                .lineLimit(1)
                .foregroundStyle(foreground)
                .padding(.horizontal, style.size == .small ? RocketSpace.s3 + 1 : RocketSpace.s4)
                .frame(maxWidth: style.fullWidth ? .infinity : nil, alignment: style.fullWidth ? .leading : .center)
                .frame(height: style.size == .small ? RocketSize.controlSmall : RocketSize.control)
                .background(fill, in: shape)
                .overlay {
                    if style.variant == .secondary { shape.strokeBorder(hovering ? RocketColor.borderStrong : RocketColor.border) }
                }
                .contentShape(shape)
                .rocketPressScale(configuration.isPressed)
                .opacity(isEnabled ? 1 : 0.4)
                .onHover { hovering = isEnabled && $0 }
                .animation(RocketMotion.fast, value: hovering)
                .animation(RocketMotion.fast, value: configuration.isPressed)
        }

        private var foreground: Color {
            switch style.variant {
            case .primary: RocketColor.textInverse
            case .danger: .white
            case .secondary: RocketColor.textPrimary
            case .ghost: hovering ? RocketColor.textPrimary : RocketColor.textSecondary
            }
        }

        private var fill: AnyShapeStyle {
            switch style.variant {
            case .primary: AnyShapeStyle(RocketColor.inverse.opacity(configuration.isPressed ? 0.8 : hovering ? 0.9 : 1))
            case .danger: AnyShapeStyle(RocketColor.danger.opacity(configuration.isPressed ? 0.8 : hovering ? 0.9 : 1))
            case .secondary: AnyShapeStyle(configuration.isPressed ? RocketColor.control : hovering ? RocketColor.control.opacity(0.7) : RocketColor.raised)
            case .ghost: AnyShapeStyle(configuration.isPressed ? RocketColor.selected : hovering ? RocketColor.hover : .clear)
            }
        }
    }
}

public extension ButtonStyle where Self == RocketButtonStyle {
    static var rocketPrimary: RocketButtonStyle { RocketButtonStyle(.primary) }
    static var rocketSecondary: RocketButtonStyle { RocketButtonStyle(.secondary) }
    static var rocketGhost: RocketButtonStyle { RocketButtonStyle(.ghost) }
}

/// Square icon button: no fill at rest, a hover fill, a deeper step when pressed or toggled on.
public struct IconButtonStyle: ButtonStyle {
    let role: ButtonRole?
    let isActive: Bool
    let size: CGFloat

    public init(role: ButtonRole? = nil, isActive: Bool = false, size: CGFloat = RocketSize.iconButton) {
        self.role = role
        self.isActive = isActive
        self.size = size
    }

    public func makeBody(configuration: Configuration) -> some View {
        StyledBody(configuration: configuration, style: self)
    }

    private struct StyledBody: View {
        let configuration: ButtonStyleConfiguration
        let style: IconButtonStyle
        @State private var hovering = false
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: RocketRadius.small + 1, style: .continuous)
            configuration.label
                .labelStyle(.iconOnly)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(foreground)
                .frame(width: style.size, height: style.size)
                .background(configuration.isPressed || style.isActive ? RocketColor.selected : hovering ? RocketColor.hover : .clear, in: shape)
                .contentShape(shape)
                .rocketPressScale(configuration.isPressed, scale: 0.94)
                .opacity(isEnabled ? 1 : 0.35)
                .onHover { hovering = isEnabled && $0 }
                .animation(RocketMotion.fast, value: hovering)
                .animation(RocketMotion.fast, value: configuration.isPressed)
        }

        private var foreground: Color {
            if style.role == .destructive { return hovering ? RocketColor.danger : RocketColor.textSecondary }
            return hovering || style.isActive ? RocketColor.textPrimary : RocketColor.textSecondary
        }
    }
}

public extension ButtonStyle where Self == IconButtonStyle {
    static var rocketIcon: IconButtonStyle { IconButtonStyle() }
}

/// Filter pill: borderless at rest, a bordered control fill when selected.
public struct PillButtonStyle: ButtonStyle {
    let selected: Bool

    public init(selected: Bool) {
        self.selected = selected
    }

    public func makeBody(configuration: Configuration) -> some View {
        StyledBody(configuration: configuration, selected: selected)
    }

    private struct StyledBody: View {
        let configuration: ButtonStyleConfiguration
        let selected: Bool
        @State private var hovering = false

        var body: some View {
            configuration.label
                .font(.rocketLabel)
                .labelStyle(PillLabelStyle())
                .foregroundStyle(selected || hovering ? RocketColor.textPrimary : RocketColor.textSecondary)
                .padding(.horizontal, RocketSpace.s3 + 2)
                .frame(height: RocketSize.controlSmall)
                .background(selected ? RocketColor.control : hovering ? RocketColor.hover : .clear, in: Capsule())
                .overlay(Capsule().strokeBorder(selected ? RocketColor.borderStrong : .clear))
                .contentShape(Capsule())
                .rocketPressScale(configuration.isPressed)
                .onHover { hovering = $0 }
                .animation(RocketMotion.fast, value: hovering)
                .animation(RocketMotion.fast, value: configuration.isPressed)
        }
    }

    private struct PillLabelStyle: LabelStyle {
        func makeBody(configuration: Configuration) -> some View {
            HStack(spacing: 5) {
                configuration.icon.font(.system(size: 10.5, weight: .medium)).foregroundStyle(RocketColor.textTertiary)
                configuration.title
            }
        }
    }
}

/// Plain text link in the accent color.
public struct RocketLinkStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        StyledBody(configuration: configuration)
    }

    private struct StyledBody: View {
        let configuration: ButtonStyleConfiguration
        @State private var hovering = false

        var body: some View {
            configuration.label
                .foregroundStyle(RocketColor.accentText)
                .underline(hovering)
                .opacity(configuration.isPressed ? 0.7 : 1)
                .contentShape(Rectangle())
                .onHover { hovering = $0 }
                .animation(RocketMotion.fast, value: hovering)
                .animation(RocketMotion.fast, value: configuration.isPressed)
            }
    }
}

public extension ButtonStyle where Self == RocketLinkStyle {
    static var rocketLink: RocketLinkStyle { RocketLinkStyle() }
}

// MARK: Data display

/// Track + fill. A known fraction fills; an unknown one sweeps (static under Reduce Motion).
public struct RocketProgressBar: View {
    let fraction: Double?
    let tint: Color
    let height: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(fraction: Double?, tint: Color = RocketColor.accent, height: CGFloat = RocketSize.progressBarRow) {
        self.fraction = fraction
        self.tint = tint
        self.height = height
    }

    public var body: some View {
        GeometryReader { proxy in
            Capsule()
                .fill(RocketColor.track)
                .overlay(alignment: .leading) {
                    if let fraction {
                        Capsule()
                            .fill(tint)
                            .frame(width: max(height, proxy.size.width * min(1, max(0, fraction))))
                            // Interpolate between 5 Hz updates; never ahead of real data.
                            .animation(reduceMotion ? nil : RocketMotion.progress, value: fraction)
                    } else if reduceMotion {
                        Capsule().fill(tint.opacity(0.4)).frame(width: proxy.size.width * 0.35)
                    } else {
                        TimelineView(.animation) { context in
                            let phase = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.4) / 1.4
                            Capsule()
                                .fill(tint.opacity(0.7))
                                .frame(width: proxy.size.width * 0.3)
                                .offset(x: proxy.size.width * (1.3 * phase - 0.3))
                        }
                    }
                }
                .clipShape(Capsule())
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

/// Small rotating arc for waits we can't measure.
public struct RocketSpinner: View {
    let size: CGFloat
    let tint: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(size: CGFloat = 14, tint: Color = RocketColor.textSecondary) {
        self.size = size
        self.tint = tint
    }

    public var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { context in
            let turns = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 0.8) / 0.8
            ZStack {
                Circle().stroke(tint.opacity(0.2), lineWidth: 1.5)
                Circle()
                    .trim(from: 0, to: 0.28)
                    .stroke(tint, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                    .rotationEffect(.degrees(reduceMotion ? 0 : turns * 360))
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel(Text("Loading"))
    }
}

/// Drawn status icon, one shape language for every download state. Active carries its progress as a pie.
public struct StatusGlyph: View {
    public enum Kind: Equatable, Sendable {
        case queued, active(Double?), verifying, paused(Double?), done, failed, cancelled
    }

    let kind: Kind
    let size: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(_ kind: Kind, size: CGFloat = 14) {
        self.kind = kind
        self.size = size
    }

    public var body: some View {
        ZStack {
            switch kind {
            case .queued:
                Circle()
                    .stroke(color, style: StrokeStyle(lineWidth: 1.5, dash: [2.2, 2.1]))
                    .padding(0.75)
            case .paused:
                Circle().stroke(color, lineWidth: 1.5).padding(0.75)
                HStack(spacing: size * 0.12) {
                    Capsule().fill(color).frame(width: size * 0.12)
                    Capsule().fill(color).frame(width: size * 0.12)
                }
                .padding(.vertical, size * 0.3)
            case .active(let fraction):
                Circle().stroke(color, lineWidth: 1.5).padding(0.75)
                Pie(fraction: max(0.08, fraction ?? 0.25))
                    .fill(color)
                    .padding(size * 0.22)
                    .animation(reduceMotion ? nil : RocketMotion.progress, value: fraction)
            case .verifying:
                Circle().stroke(color, lineWidth: 1.5).padding(0.75)
                Circle().fill(color).padding(size * 0.3)
            case .done:
                Circle().fill(color)
                Check().stroke(RocketColor.textInverse, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                    .padding(size * 0.28)
            case .failed:
                Circle().fill(color)
                Bang().stroke(RocketColor.textInverse, style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                    .padding(size * 0.27)
            case .cancelled:
                Circle().fill(color)
                Cross().stroke(RocketColor.textInverse, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                    .padding(size * 0.32)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    public var color: Color { Self.color(for: kind) }

    public static func color(for kind: Kind) -> Color {
        switch kind {
        case .queued: RocketColor.textSecondary
        case .active, .verifying: RocketColor.accent
        case .paused: RocketColor.textSecondary
        case .done: RocketColor.success
        case .failed: RocketColor.danger
        case .cancelled: RocketColor.textTertiary
        }
    }

    private struct Pie: Shape {
        var fraction: Double
        var animatableData: Double {
            get { fraction }
            set { fraction = newValue }
        }

        func path(in rect: CGRect) -> Path {
            var path = Path()
            let center = CGPoint(x: rect.midX, y: rect.midY)
            path.move(to: center)
            path.addArc(center: center, radius: rect.width / 2, startAngle: .degrees(-90),
                        endAngle: .degrees(-90 + 360 * min(1, fraction)), clockwise: false)
            path.closeSubpath()
            return path
        }
    }

    private struct Check: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            path.move(to: CGPoint(x: rect.minX, y: rect.midY + rect.height * 0.05))
            path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.36, y: rect.maxY - rect.height * 0.12))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.12))
            return path
        }
    }

    private struct Bang: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.midY + rect.height * 0.12))
            path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY - 0.01))
            return path
        }
    }

    private struct Cross: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            return path
        }
    }
}

/// Rounded square with a monochrome type symbol.
public struct FileTile: View {
    let symbol: String
    let size: CGFloat

    public init(symbol: String, size: CGFloat = RocketSize.fileTile) {
        self.symbol = symbol
        self.size = size
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
        RocketIcon(symbol: symbol, size: size * 0.55)
            .foregroundStyle(RocketColor.textSecondary)
            .frame(width: size, height: size)
            .background(RocketColor.control, in: shape)
            .overlay(shape.strokeBorder(RocketColor.border))
            .accessibilityHidden(true)
    }
}

/// Keyboard shortcut hint ("⌘N").
public struct Keycap: View {
    let text: String

    public init(_ text: String) {
        self.text = text
    }

    public var body: some View {
        Text(text)
            .font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(RocketColor.textTertiary)
            .padding(.horizontal, 5)
            .frame(minWidth: RocketSize.keycapHeight, minHeight: RocketSize.keycapHeight)
            .background(RocketColor.control, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(RocketColor.border))
            .accessibilityHidden(true)
    }
}

/// Rocket's mark: an ember tile with a downward stroke.
public struct RocketMark: View {
    let size: CGFloat

    public init(size: CGFloat = 22) {
        self.size = size
    }

    public var body: some View {
        RocketIcon(.arrowDown, size: size * 0.55)
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                LinearGradient(colors: [RocketColor.accent, RocketColor.accent.opacity(0.82)], startPoint: .top, endPoint: .bottom),
                in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            )
            .overlay(RoundedRectangle(cornerRadius: size * 0.28, style: .continuous).strokeBorder(.white.opacity(0.18)))
            .accessibilityHidden(true)
    }
}
