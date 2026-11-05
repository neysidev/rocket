import SwiftUI

// MARK: Text fields

/// Text field chrome: control fill, border that strengthens on hover, ember ring on focus.
private struct RocketField: ViewModifier {
    let mono: Bool
    let multiline: Bool
    @FocusState private var focused: Bool
    @State private var hovering = false

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: RocketRadius.control, style: .continuous)
        content
            .textFieldStyle(.plain)
            .font(mono ? .rocketMono : .rocketBody)
            .foregroundStyle(RocketColor.textPrimary)
            .focused($focused)
            .padding(.horizontal, RocketSpace.s3 + 2)
            .padding(.vertical, multiline ? RocketSpace.s3 : 0)
            .frame(minHeight: RocketSize.control)
            .background(RocketColor.control.opacity(focused ? 0.6 : 1), in: shape)
            .overlay(shape.strokeBorder(focused ? RocketColor.accent : hovering ? RocketColor.borderStrong : RocketColor.border))
            .background(shape.stroke(RocketColor.accentSoft, lineWidth: focused ? 6 : 0).padding(-1))
            .onHover { hovering = $0 }
            .animation(RocketMotion.fast, value: focused)
            .animation(RocketMotion.fast, value: hovering)
    }
}

public extension View {
    /// Apply to a `TextField`, `SecureField` or `TextEditor`.
    func rocketField(mono: Bool = false, multiline: Bool = false) -> some View {
        modifier(RocketField(mono: mono, multiline: multiline))
    }
}

// MARK: Toggles

/// Switch: ember track when on, the knob slides with a spring. The label is for VoiceOver only;
/// put the visible title in a `RocketFormRow`.
public struct RocketSwitchStyle: ToggleStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        StyledBody(configuration: configuration)
    }

    private struct StyledBody: View {
        let configuration: ToggleStyleConfiguration
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            Button {
                configuration.isOn.toggle()
            } label: {
                track.contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .opacity(isEnabled ? 1 : 0.4)
            .accessibilityRepresentation { Toggle(isOn: configuration.$isOn) { configuration.label } }
        }

        private var track: some View {
            Capsule()
                .fill(configuration.isOn ? RocketColor.accent : RocketColor.control)
                .overlay(Capsule().strokeBorder(configuration.isOn ? .clear : RocketColor.borderStrong))
                .frame(width: 30, height: 18)
                .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                    Circle()
                        .fill(.white)
                        .shadow(color: .black.opacity(0.25), radius: 1, y: 0.5)
                        .padding(2)
                }
                .animation(RocketMotion.spring, value: configuration.isOn)
        }
    }
}

/// Checkbox: ember square with a drawn check.
public struct RocketCheckboxStyle: ToggleStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(spacing: RocketSpace.s3) {
                let shape = RoundedRectangle(cornerRadius: 4, style: .continuous)
                shape
                    .fill(configuration.isOn ? RocketColor.accent : RocketColor.control)
                    .overlay(shape.strokeBorder(configuration.isOn ? .clear : RocketColor.borderStrong))
                    .overlay {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                            .opacity(configuration.isOn ? 1 : 0)
                            .scaleEffect(configuration.isOn ? 1 : 0.6)
                    }
                    .frame(width: 15, height: 15)
                    .animation(RocketMotion.fast, value: configuration.isOn)
                configuration.label
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(configuration.isOn ? Text("On") : Text("Off"))
    }
}

public extension ToggleStyle where Self == RocketSwitchStyle {
    static var rocketSwitch: RocketSwitchStyle { RocketSwitchStyle() }
}

public extension ToggleStyle where Self == RocketCheckboxStyle {
    static var rocketCheckbox: RocketCheckboxStyle { RocketCheckboxStyle() }
}

// MARK: Stepper

/// − value + in one control.
public struct RocketStepper: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    let label: String

    public init(_ label: String, value: Binding<Int>, in range: ClosedRange<Int>) {
        self.label = label
        _value = value
        self.range = range
    }

    public var body: some View {
        HStack(spacing: 0) {
            Button("Decrease", systemImage: "minus") { value = max(range.lowerBound, value - 1) }
                .buttonStyle(IconButtonStyle(size: RocketSize.controlSmall))
                .disabled(value <= range.lowerBound)
            Text("\(value)")
                .font(.rocketHeadline)
                .monospacedDigit()
                .foregroundStyle(RocketColor.textPrimary)
                .frame(minWidth: 28)
                .contentTransition(.numericText(value: Double(value)))
                .animation(RocketMotion.fast, value: value)
            Button("Increase", systemImage: "plus") { value = min(range.upperBound, value + 1) }
                .buttonStyle(IconButtonStyle(size: RocketSize.controlSmall))
                .disabled(value >= range.upperBound)
        }
        .padding(2)
        .background(RocketColor.control, in: RoundedRectangle(cornerRadius: RocketRadius.control, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: RocketRadius.control, style: .continuous).strokeBorder(RocketColor.border))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue("\(value)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = min(range.upperBound, value + 1)
            case .decrement: value = max(range.lowerBound, value - 1)
            @unknown default: break
            }
        }
    }
}

// MARK: Segmented control

public struct RocketSegment<Value: Hashable>: Identifiable {
    public let value: Value
    public let title: String
    public let symbol: String?

    public var id: Value { value }

    public init(_ value: Value, title: String, symbol: String? = nil) {
        self.value = value
        self.title = title
        self.symbol = symbol
    }
}

/// Segmented control; the thumb slides between segments. Icon-only when every segment has a symbol and `iconOnly` is set.
public struct RocketSegmented<Value: Hashable>: View {
    @Binding var selection: Value
    let segments: [RocketSegment<Value>]
    let iconOnly: Bool
    @Namespace private var thumb

    public init(selection: Binding<Value>, segments: [RocketSegment<Value>], iconOnly: Bool = false) {
        _selection = selection
        self.segments = segments
        self.iconOnly = iconOnly
    }

    public var body: some View {
        HStack(spacing: 2) {
            ForEach(segments) { segment in
                let selected = segment.value == selection
                Button {
                    selection = segment.value
                } label: {
                    Group {
                        if iconOnly, let symbol = segment.symbol {
                            Image(systemName: symbol).frame(width: 26)
                        } else {
                            Text(segment.title).padding(.horizontal, RocketSpace.s3)
                        }
                    }
                    .font(.rocketLabel)
                    .foregroundStyle(selected ? RocketColor.textPrimary : RocketColor.textSecondary)
                    .frame(height: 22)
                    .background {
                        if selected {
                            RoundedRectangle(cornerRadius: RocketRadius.small, style: .continuous)
                                .fill(RocketColor.raised)
                                .overlay(RoundedRectangle(cornerRadius: RocketRadius.small, style: .continuous).strokeBorder(RocketColor.border))
                                .shadow(color: .black.opacity(0.12), radius: 1, y: 1)
                                .matchedGeometryEffect(id: "thumb", in: thumb)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .rocketTooltip(iconOnly ? segment.title : "")
                .accessibilityLabel(segment.title)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(2)
        .background(RocketColor.control, in: RoundedRectangle(cornerRadius: RocketRadius.control, style: .continuous))
        .animation(RocketMotion.spring, value: selection)
    }
}

// MARK: Disclosure

/// Chevron + title that reveals its content below.
public struct RocketDisclosure<Content: View>: View {
    let title: String
    @Binding var isExpanded: Bool
    let content: Content

    public init(_ title: String, isExpanded: Binding<Bool>, @ViewBuilder content: () -> Content) {
        self.title = title
        _isExpanded = isExpanded
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: RocketSpace.s3) {
            Button {
                isExpanded.toggle()
            } label: {
                HStack(spacing: RocketSpace.s2 + 2) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    Text(title)
                }
                .font(.rocketLabel)
                .foregroundStyle(RocketColor.textSecondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(isExpanded ? Text("Expanded") : Text("Collapsed"))
            if isExpanded {
                content
                    .rocketTransition(RocketTransition.content)
            }
        }
        .rocketAnimation(RocketMotion.enter, value: isExpanded)
    }
}

// MARK: Forms

/// Eyebrow title, then a raised card of rows separated by hairlines, then an optional footnote.
public struct RocketFormSection<Content: View>: View {
    let title: String?
    let footer: String?
    let content: Content

    public init(_ title: String? = nil, footer: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.footer = footer
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: RocketSpace.s3) {
            if let title { Text(title).rocketEyebrow().padding(.leading, RocketSpace.s1) }
            VStack(spacing: 0) { content }
                // Each row draws a bottom hairline; the last one falls outside the clip.
                .padding(.bottom, -1)
                .clipShape(RoundedRectangle(cornerRadius: RocketRadius.card, style: .continuous))
                .rocketCard()
            if let footer {
                Text(footer)
                    .font(.rocketCaption)
                    .foregroundStyle(RocketColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, RocketSpace.s1)
            }
        }
    }
}

/// Title (and optional detail) on the left, the control on the right.
public struct RocketFormRow<Control: View>: View {
    let title: String
    let detail: String?
    let control: Control

    public init(_ title: String, detail: String? = nil, @ViewBuilder control: () -> Control) {
        self.title = title
        self.detail = detail
        self.control = control()
    }

    public var body: some View {
        HStack(spacing: RocketSpace.s5) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.rocketBody).foregroundStyle(RocketColor.textPrimary)
                if let detail {
                    Text(detail)
                        .font(.rocketCaption)
                        .foregroundStyle(RocketColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            control
        }
        .rocketFormRowChrome()
    }
}

public extension View {
    /// Padding and bottom hairline of a row inside `RocketFormSection`, for rows with a custom layout.
    func rocketFormRowChrome() -> some View {
        padding(.horizontal, RocketSpace.s4 + 2)
            .padding(.vertical, RocketSpace.s3 + 2)
            .frame(minHeight: 46)
            .overlay(alignment: .bottom) { Rectangle().fill(RocketColor.border).frame(height: 1) }
    }
}
