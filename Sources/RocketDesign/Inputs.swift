import SwiftUI

// Thin names over system controls, so screens keep reading the same while rendering natively.

public extension View {
    /// Rounded-border text field (monospaced for codes, sizes, extensions).
    func rocketField(mono: Bool = false, multiline: Bool = false) -> some View {
        textFieldStyle(.roundedBorder).font(mono ? .rocketMono : .rocketBody)
    }

    /// Kept for rows with a custom layout; grouped forms draw their own separators.
    func rocketFormRowChrome() -> some View { self }
}

public extension ToggleStyle where Self == SwitchToggleStyle {
    static var rocketSwitch: SwitchToggleStyle { .switch }
}

public extension ToggleStyle where Self == CheckboxToggleStyle {
    static var rocketCheckbox: CheckboxToggleStyle { .checkbox }
}

/// System stepper with its value.
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
        Stepper(value: $value, in: range) { Text("\(value)").monospacedDigit() }
            .accessibilityLabel(label)
    }
}

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

/// System segmented control.
public struct RocketSegmented<Value: Hashable>: View {
    @Binding var selection: Value
    let segments: [RocketSegment<Value>]
    let iconOnly: Bool

    public init(selection: Binding<Value>, segments: [RocketSegment<Value>], iconOnly: Bool = false) {
        _selection = selection
        self.segments = segments
        self.iconOnly = iconOnly
    }

    public var body: some View {
        Picker("", selection: $selection) {
            ForEach(segments) { segment in
                Group {
                    if iconOnly, let symbol = segment.symbol { Label(segment.title, systemImage: symbol).labelStyle(.iconOnly) } else { Text(segment.title) }
                }
                .help(segment.title)
                .tag(segment.value)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
    }
}

/// System disclosure group.
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
        DisclosureGroup(title, isExpanded: $isExpanded) { content }
    }
}

// MARK: Forms

/// A `Section` of a grouped `Form`: header, rows, footnote.
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
        Section {
            content
        } header: {
            if let title { Text(title) }
        } footer: {
            if let footer {
                Text(footer)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Title (and optional detail) on the left, the control on the right: `LabeledContent`.
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
        LabeledContent {
            control
        } label: {
            Text(title)
            if let detail { Text(detail) }
        }
    }
}
