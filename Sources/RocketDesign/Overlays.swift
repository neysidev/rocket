import SwiftUI

// Menus, pickers, context menus, help tags, sheets and alerts: all system-provided.

// MARK: Dismiss

/// Closes the sheet the view is inside.
public struct RocketDismissAction: @unchecked Sendable {
    let action: () -> Void

    public init(_ action: @escaping () -> Void) {
        self.action = action
    }

    @MainActor public func callAsFunction() {
        action()
    }
}

private struct RocketDismissKey: EnvironmentKey {
    static let defaultValue = RocketDismissAction {}
}

private struct PopoverTakesKeyKey: EnvironmentKey {
    static let defaultValue = true
}

public extension EnvironmentValues {
    var rocketDismiss: RocketDismissAction {
        get { self[RocketDismissKey.self] }
        set { self[RocketDismissKey.self] = newValue }
    }

    var rocketPopoverTakesKey: Bool {
        get { self[PopoverTakesKeyKey.self] }
        set { self[PopoverTakesKeyKey.self] = newValue }
    }
}

// MARK: Menus

public struct RocketMenuItem: Identifiable {
    public let id = UUID()
    public var title: String
    public var symbol: String?
    public var shortcut: String?
    public var isChecked: Bool
    public var role: ButtonRole?
    public var isEnabled: Bool
    public var children: [RocketMenuItem]
    public var action: (() -> Void)?

    public init(_ title: String, symbol: String? = nil, shortcut: String? = nil, checked: Bool = false,
                role: ButtonRole? = nil, enabled: Bool = true, action: @escaping () -> Void) {
        self.title = title
        self.symbol = symbol
        self.shortcut = shortcut
        isChecked = checked
        self.role = role
        isEnabled = enabled
        children = []
        self.action = action
    }

    public static func submenu(_ title: String, symbol: String? = nil, children: [RocketMenuItem]) -> RocketMenuItem {
        var item = RocketMenuItem(title, symbol: symbol, enabled: !children.isEmpty) {}
        item.action = nil
        item.children = children
        return item
    }
}

public struct RocketMenuSection: Identifiable {
    public let id = UUID()
    public var title: String?
    public var items: [RocketMenuItem]

    public init(_ title: String? = nil, items: [RocketMenuItem]) {
        self.title = title
        self.items = items
    }
}

/// Sections as native menu content (menus, context menus, the menu bar).
public struct RocketNativeMenuItems: View {
    let sections: [RocketMenuSection]

    public init(sections: [RocketMenuSection]) {
        self.sections = sections
    }

    public var body: some View {
        ForEach(Array(sections.enumerated()), id: \.element.id) { index, section in
            if index > 0 { Divider() }
            if let title = section.title {
                Section(title) { ForEach(section.items) { NativeMenuItem(item: $0) } }
            } else {
                ForEach(section.items) { NativeMenuItem(item: $0) }
            }
        }
    }
}

private struct NativeMenuItem: View {
    let item: RocketMenuItem

    var body: some View {
        if !item.children.isEmpty {
            Menu { ForEach(item.children) { NativeMenuItem(item: $0) } } label: { label }
        } else if item.isChecked {
            Toggle(isOn: Binding(get: { true }, set: { _ in item.action?() })) { Text(item.title) }
                .disabled(!item.isEnabled)
        } else {
            Button(role: item.role) { item.action?() } label: { label }
                .disabled(!item.isEnabled)
        }
    }

    @ViewBuilder
    private var label: some View {
        if let symbol = item.symbol { Label(item.title, systemImage: symbol) } else { Text(item.title) }
    }
}

/// A borderless pull-down menu.
public struct RocketMenuButton<Label: View>: View {
    let sections: () -> [RocketMenuSection]
    let label: Label

    public init(alignment: HorizontalAlignment = .leading, sections: @escaping () -> [RocketMenuSection], @ViewBuilder label: () -> Label) {
        self.sections = sections
        self.label = label()
    }

    public var body: some View {
        Menu { RocketNativeMenuItems(sections: sections()) } label: { label }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
    }
}

// MARK: Select

public struct RocketOption<Value: Hashable> {
    public let value: Value
    public let title: String

    public init(_ value: Value, _ title: String) {
        self.value = value
        self.title = title
    }
}

/// Pop-up button. Groups are separated by dividers.
public struct RocketSelect<Value: Hashable>: View {
    let label: String
    @Binding var selection: Value
    let groups: [[RocketOption<Value>]]

    public init(_ label: String, selection: Binding<Value>, options: [RocketOption<Value>], compact: Bool = false) {
        self.init(label, selection: selection, groups: [options], compact: compact)
    }

    public init(_ label: String, selection: Binding<Value>, groups: [[RocketOption<Value>]], compact: Bool = false) {
        self.label = label
        _selection = selection
        self.groups = groups
    }

    public var body: some View {
        Picker(label, selection: $selection) {
            ForEach(groups.indices, id: \.self) { index in
                if index > 0 { Divider() }
                ForEach(groups[index], id: \.value) { option in
                    Text(option.title).tag(option.value)
                }
            }
        }
        .labelsHidden()
    }
}

// MARK: Context menus, help, sheets, alerts

public extension View {
    func rocketContextMenu(sections: @escaping () -> [RocketMenuSection]) -> some View {
        contextMenu { RocketNativeMenuItems(sections: sections()) }
    }

    /// System help tag; the shortcut is appended in parentheses.
    @ViewBuilder
    func rocketTooltip(_ text: String, shortcut: String? = nil) -> some View {
        if text.isEmpty { self } else { help(shortcut.map { "\(text) (\($0))" } ?? text) }
    }

    /// System sheet. `rocketDismiss` inside closes it.
    func rocketModal(isPresented: Binding<Bool>, @ViewBuilder content: @escaping () -> some View) -> some View {
        sheet(isPresented: isPresented) {
            content().environment(\.rocketDismiss, RocketDismissAction { isPresented.wrappedValue = false })
        }
    }

    func rocketModal<Item: Identifiable>(item: Binding<Item?>, @ViewBuilder content: @escaping (Item) -> some View) -> some View {
        sheet(item: item) { value in
            content(value).environment(\.rocketDismiss, RocketDismissAction { item.wrappedValue = nil })
        }
    }

    /// One-button system alert.
    func rocketAlert(_ message: Binding<String?>) -> some View {
        alert(message.wrappedValue ?? "", isPresented: Binding(get: { message.wrappedValue != nil }, set: { if !$0 { message.wrappedValue = nil } })) {
            Button("OK", role: .cancel) {}
        }
    }
}

/// Sheet layout: title and optional subtitle, content, then trailing buttons, as in standard macOS sheets.
public struct RocketModalLayout<Content: View, Actions: View>: View {
    let title: String
    let subtitle: String?
    let content: Content
    let actions: Actions

    public init(_ title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content, @ViewBuilder actions: () -> Actions) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
        self.actions = actions()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                if let subtitle {
                    Text(subtitle)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 8)
            content
            HStack(spacing: 8) {
                Spacer()
                actions
            }
            .padding(20)
        }
    }
}
