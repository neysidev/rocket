import AppKit
import SwiftUI

// Custom menus, selects, context menus, tooltips and modals. Menus and tooltips live in borderless child panels
// so they can extend past the window; modals are overlays inside the window.

// MARK: Dismiss

/// Closes the modal or menu the view is inside. Replaces `\.dismiss` for Rocket overlays.
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

    /// False inside panels that close when they lose key (the menu bar extra): menus then open without taking focus.
    var rocketPopoverTakesKey: Bool {
        get { self[PopoverTakesKeyKey.self] }
        set { self[PopoverTakesKeyKey.self] = newValue }
    }
}

// MARK: Floating panel

private final class FloatingPanel: NSPanel {
    var acceptsKey = true
    override var canBecomeKey: Bool { acceptsKey }
    override var canBecomeMain: Bool { false }
}

/// Owns one floating panel: shows SwiftUI content next to an anchor rect and closes on outside clicks or scrolling.
@MainActor
final class PopoverController {
    private var panel: FloatingPanel?
    private var hosting: NSHostingView<AnyView>?
    private var monitor: Any?
    private weak var parent: NSWindow?
    /// Called when the panel closes itself (outside click, Escape, an item was chosen).
    var onDismiss: (() -> Void)?
    private(set) var lastClosed = Date.distantPast
    static let margin: CGFloat = 18

    var isShown: Bool { panel?.isVisible == true }

    func show(_ content: AnyView, anchor: NSRect, parent: NSWindow?, trailing: Bool, takesKey: Bool) {
        let panel = panel ?? makePanel()
        panel.acceptsKey = takesKey
        panel.appearance = parent?.effectiveAppearance
        self.parent = parent
        let below = fits(below: anchor, height: measure(content, flipped: false).height)
        let size = measure(content, flipped: !below)
        let screen = (parent?.screen ?? NSScreen.main)?.visibleFrame ?? .infinite
        let margin = Self.margin
        var x = trailing ? anchor.maxX - size.width + margin : anchor.minX - margin
        var y = below ? anchor.minY - 4 - size.height + margin : anchor.maxY + 4 - margin
        x = min(max(x, screen.minX - margin), screen.maxX - size.width + margin)
        y = max(y, screen.minY - margin)
        panel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
        parent?.addChildWindow(panel, ordered: .above)
        if takesKey { panel.makeKeyAndOrderFront(nil) } else { panel.orderFront(nil) }
        startMonitoring()
    }

    func update(_ content: AnyView) {
        guard isShown, let hosting else { return }
        hosting.rootView = wrap(content, flipped: false)
    }

    func close(notify: Bool) {
        guard let panel, panel.isVisible else { return }
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        parent?.removeChildWindow(panel)
        panel.orderOut(nil)
        lastClosed = .now
        if notify { onDismiss?() }
    }

    private func makePanel() -> FloatingPanel {
        let panel = FloatingPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = true
        panel.animationBehavior = .none
        panel.collectionBehavior = [.transient, .ignoresCycle, .fullScreenAuxiliary]
        let hosting = NSHostingView(rootView: AnyView(EmptyView()))
        panel.contentView = hosting
        self.panel = panel
        self.hosting = hosting
        return panel
    }

    private func measure(_ content: AnyView, flipped: Bool) -> CGSize {
        _ = panel ?? makePanel()
        hosting?.rootView = wrap(content, flipped: flipped)
        return hosting?.fittingSize ?? .zero
    }

    private func fits(below anchor: NSRect, height: CGFloat) -> Bool {
        let screen = (parent?.screen ?? NSScreen.main)?.visibleFrame ?? .infinite
        return anchor.minY - height + Self.margin >= screen.minY
    }

    private func wrap(_ content: AnyView, flipped: Bool) -> AnyView {
        AnyView(
            PopIn(anchor: flipped ? .bottom : .top) { content }
                .padding(Self.margin)
                .environment(\.rocketDismiss, RocketDismissAction { [weak self] in self?.close(notify: true) })
        )
    }

    private func startMonitoring() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel]) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self, let panel = self.panel else { return }
                if event.window !== panel { self.close(notify: true) }
            }
            return event
        }
    }
}

/// Scale-and-fade from the edge nearest the trigger; fade only under Reduce Motion.
private struct PopIn<Content: View>: View {
    let anchor: UnitPoint
    @ViewBuilder let content: Content
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        content
            .scaleEffect(shown || reduceMotion ? 1 : 0.97, anchor: anchor)
            .opacity(shown ? 1 : 0)
            .onAppear { withAnimation(RocketMotion.enter) { shown = true } }
    }
}

private struct PopoverAnchor: NSViewRepresentable {
    @Binding var isPresented: Bool
    let trailing: Bool
    let content: () -> AnyView

    func makeCoordinator() -> PopoverController { PopoverController() }
    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ view: NSView, context: Context) {
        let controller = context.coordinator
        let binding = $isPresented
        controller.onDismiss = { binding.wrappedValue = false }
        if isPresented {
            if controller.isShown {
                controller.update(content())
            } else if Date.now.timeIntervalSince(controller.lastClosed) < 0.25 || view.window == nil {
                // The click that closed the panel was on this trigger: stay closed instead of reopening.
                DispatchQueue.main.async { binding.wrappedValue = false }
            } else {
                let rect = view.window?.convertToScreen(view.convert(view.bounds, to: nil)) ?? .zero
                controller.show(content(), anchor: rect, parent: view.window, trailing: trailing,
                                takesKey: context.environment.rocketPopoverTakesKey)
            }
        } else {
            controller.close(notify: false)
        }
    }

    static func dismantleNSView(_ view: NSView, coordinator: PopoverController) {
        coordinator.close(notify: false)
    }
}

public extension View {
    /// Floating content below (or above, when there is no room) this view.
    func rocketPopover(isPresented: Binding<Bool>, alignment: HorizontalAlignment = .leading,
                       @ViewBuilder content: @escaping () -> some View) -> some View {
        background(PopoverAnchor(isPresented: isPresented, trailing: alignment == .trailing) { AnyView(content()) })
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

    /// Expands in place in Rocket menus; a submenu in native context menus.
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

/// Menu body: sections with eyebrow titles, hover and keyboard highlight, inline submenus.
public struct RocketMenuContent: View {
    let sections: [RocketMenuSection]
    @Environment(\.rocketDismiss) private var dismiss
    @State private var highlighted: UUID?
    @State private var expanded: Set<UUID> = []
    @FocusState private var focused: Bool

    public init(sections: [RocketMenuSection]) {
        self.sections = sections.filter { !$0.items.isEmpty }
    }

    private enum Row: Identifiable {
        case header(String, UUID)
        case separator(UUID)
        case item(RocketMenuItem, depth: Int)

        var id: UUID {
            switch self {
            case .header(_, let id), .separator(let id): id
            case .item(let item, _): item.id
            }
        }
    }

    private var rows: [Row] {
        var rows: [Row] = []
        for (index, section) in sections.enumerated() {
            if index > 0 { rows.append(.separator(section.id)) }
            if let title = section.title { rows.append(.header(title, section.id)) }
            for item in section.items {
                rows.append(.item(item, depth: 0))
                if expanded.contains(item.id) { rows += item.children.map { .item($0, depth: 1) } }
            }
        }
        return rows
    }

    private var hasSymbols: Bool { sections.contains { $0.items.contains { $0.symbol != nil } } }

    public var body: some View {
        let rows = rows
        let height = rows.reduce(CGFloat(8)) { total, row in
            switch row {
            case .header: total + 26
            case .separator: total + 9
            case .item: total + 28
            }
        }
        let list = VStack(alignment: .leading, spacing: 0) {
            ForEach(rows) { row in
                switch row {
                case .header(let title, _):
                    Text(title).rocketEyebrow().padding(.horizontal, RocketSpace.s3).frame(height: 26, alignment: .bottomLeading)
                        .padding(.bottom, 0)
                case .separator:
                    Rectangle().fill(RocketColor.border).frame(height: 1).padding(.vertical, RocketSpace.s2)
                case .item(let item, let depth):
                    itemRow(item, depth: depth)
                }
            }
        }
        .padding(RocketSpace.s2)
        .frame(minWidth: 200, alignment: .leading)
        .fixedSize(horizontal: true, vertical: false)

        Group {
            if height > 440 {
                ScrollView { list }.frame(height: 440)
            } else {
                list
            }
        }
        .rocketFloating()
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onAppear { focused = true }
        .onKeyPress(.downArrow) { move(1) }
        .onKeyPress(.upArrow) { move(-1) }
        .onKeyPress(.rightArrow) { expand(true) }
        .onKeyPress(.leftArrow) { expand(false) }
        .onKeyPress(.return) {
            guard let item = enabledItems.first(where: { $0.id == highlighted }) else { return .ignored }
            activate(item)
            return .handled
        }
        .onExitCommand { dismiss() }
        .rocketAnimation(RocketMotion.fast, value: expanded)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }

    private func itemRow(_ item: RocketMenuItem, depth: Int) -> some View {
        let isHighlighted = highlighted == item.id && item.isEnabled
        let tint = !item.isEnabled ? RocketColor.textTertiary : item.role == .destructive ? RocketColor.danger : RocketColor.textPrimary
        return HStack(spacing: RocketSpace.s3) {
            if hasSymbols {
                RocketIcon(symbol: item.symbol ?? "doc", size: 14)
                    .foregroundStyle(item.role == .destructive ? RocketColor.danger : RocketColor.textSecondary)
                    .opacity(item.symbol == nil ? 0 : 1)
                    .frame(width: 16)
            }
            Text(item.title).font(.rocketBody).foregroundStyle(tint).lineLimit(1)
            Spacer(minLength: RocketSpace.s5)
            if let shortcut = item.shortcut {
                Text(shortcut).font(.rocketCaption).foregroundStyle(RocketColor.textTertiary)
            }
            if item.isChecked {
                RocketIcon(.check, size: 12).foregroundStyle(RocketColor.accentText)
            }
            if !item.children.isEmpty {
                RocketIcon(.chevronRight, size: 11)
                    .foregroundStyle(RocketColor.textTertiary)
                    .rotationEffect(.degrees(expanded.contains(item.id) ? 90 : 0))
                    .rocketAnimation(RocketMotion.fast, value: expanded.contains(item.id))
            }
        }
        .padding(.leading, RocketSpace.s3 + (depth > 0 ? (hasSymbols ? 24 : 12) : 0))
        .padding(.trailing, RocketSpace.s3)
        .frame(height: 28)
        .background(isHighlighted ? RocketColor.selected : .clear, in: RoundedRectangle(cornerRadius: RocketRadius.small + 1, style: .continuous))
        .rocketAnimation(RocketMotion.fast, value: isHighlighted)
        .contentShape(Rectangle())
        .onHover { if $0 { highlighted = item.id } else if highlighted == item.id { highlighted = nil } }
        .onTapGesture { if item.isEnabled { activate(item) } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.title)
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(item.isChecked ? .isSelected : [])
        .accessibilityAction { if item.isEnabled { activate(item) } }
    }

    private var enabledItems: [RocketMenuItem] {
        rows.compactMap { if case .item(let item, _) = $0, item.isEnabled { item } else { nil } }
    }

    private func move(_ step: Int) -> KeyPress.Result {
        let items = enabledItems
        guard !items.isEmpty else { return .ignored }
        let index = items.firstIndex { $0.id == highlighted }.map { ($0 + step + items.count) % items.count } ?? (step > 0 ? 0 : items.count - 1)
        highlighted = items[index].id
        return .handled
    }

    private func expand(_ open: Bool) -> KeyPress.Result {
        guard let item = enabledItems.first(where: { $0.id == highlighted }), !item.children.isEmpty else { return .ignored }
        withAnimation(RocketMotion.fast) { if open { expanded.insert(item.id) } else { expanded.remove(item.id) } }
        return .handled
    }

    private func activate(_ item: RocketMenuItem) {
        if !item.children.isEmpty {
            withAnimation(RocketMotion.fast) {
                if expanded.contains(item.id) { expanded.remove(item.id) } else { expanded.insert(item.id) }
            }
            return
        }
        dismiss()
        item.action?()
    }
}

/// The same sections as a native menu, for the system's own menus (the menu bar, VoiceOver).
public struct RocketNativeMenuItems: View {
    let sections: [RocketMenuSection]

    public init(sections: [RocketMenuSection]) {
        self.sections = sections
    }

    public var body: some View {
        ForEach(Array(sections.enumerated()), id: \.element.id) { index, section in
            if index > 0 { Divider() }
            ForEach(section.items) { item in
                if item.children.isEmpty {
                    Button(role: item.role) { item.action?() } label: {
                        if item.isChecked { Label(item.title, systemImage: "checkmark") } else { Text(item.title) }
                    }
                    .disabled(!item.isEnabled)
                } else {
                    Menu(item.title) { RocketNativeMenuItems(sections: [RocketMenuSection(items: item.children)]) }
                }
            }
        }
    }
}

/// A button that opens a Rocket menu. Style the trigger with `.buttonStyle`.
public struct RocketMenuButton<Label: View>: View {
    let alignment: HorizontalAlignment
    let sections: () -> [RocketMenuSection]
    let label: Label
    @State private var open = false

    public init(alignment: HorizontalAlignment = .leading, sections: @escaping () -> [RocketMenuSection], @ViewBuilder label: () -> Label) {
        self.alignment = alignment
        self.sections = sections
        self.label = label()
    }

    public var body: some View {
        Button { open.toggle() } label: { label }
            .rocketPopover(isPresented: $open, alignment: alignment) { RocketMenuContent(sections: sections()) }
            .accessibilityAddTraits(.isButton)
            .accessibilityHint(Text("Opens a menu"))
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

/// Dropdown field: shows the current choice, opens a Rocket menu with a check on it.
public struct RocketSelect<Value: Hashable>: View {
    let label: String
    @Binding var selection: Value
    let groups: [[RocketOption<Value>]]
    let compact: Bool

    public init(_ label: String, selection: Binding<Value>, options: [RocketOption<Value>], compact: Bool = false) {
        self.init(label, selection: selection, groups: [options], compact: compact)
    }

    public init(_ label: String, selection: Binding<Value>, groups: [[RocketOption<Value>]], compact: Bool = false) {
        self.label = label
        _selection = selection
        self.groups = groups
        self.compact = compact
    }

    public var body: some View {
        let current = groups.joined().first { $0.value == selection }?.title ?? ""
        RocketMenuButton(alignment: .leading) {
            groups.map { group in
                RocketMenuSection(items: group.map { option in
                    RocketMenuItem(option.title, checked: option.value == selection) { selection = option.value }
                })
            }
        } label: {
            HStack(spacing: RocketSpace.s3) {
                Text(current).lineLimit(1)
                Spacer(minLength: compact ? 0 : RocketSpace.s4)
                RocketIcon(.chevronUpDown, size: 11)
                    .foregroundStyle(RocketColor.textTertiary)
            }
        }
        .buttonStyle(SelectTriggerStyle(compact: compact))
        .accessibilityLabel(label)
        .accessibilityValue(current)
    }
}

/// Field-like trigger for selects.
public struct SelectTriggerStyle: ButtonStyle {
    let compact: Bool

    public init(compact: Bool = false) {
        self.compact = compact
    }

    public func makeBody(configuration: Configuration) -> some View {
        StyledBody(configuration: configuration, compact: compact)
    }

    private struct StyledBody: View {
        let configuration: ButtonStyleConfiguration
        let compact: Bool
        @State private var hovering = false
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: compact ? RocketRadius.small + 1 : RocketRadius.control, style: .continuous)
            configuration.label
                .font(compact ? .rocketLabel : .rocketBody)
                .foregroundStyle(RocketColor.textPrimary)
                .padding(.horizontal, compact ? RocketSpace.s3 : RocketSpace.s3 + 2)
                .frame(height: compact ? RocketSize.controlSmall : RocketSize.control)
                .background(configuration.isPressed ? RocketColor.selected : RocketColor.control, in: shape)
                .overlay(shape.strokeBorder(hovering ? RocketColor.borderStrong : RocketColor.border))
                .contentShape(shape)
                .opacity(isEnabled ? 1 : 0.4)
                .onHover { hovering = isEnabled && $0 }
                .animation(RocketMotion.fast, value: hovering)
        }
    }
}

// MARK: Context menus

private final class ContextClickView: NSView {
    var onMenu: ((NSEvent) -> Void)?

    private static func isMenuClick(_ event: NSEvent?) -> Bool {
        guard let event else { return false }
        return event.type == .rightMouseDown || (event.type == .leftMouseDown && event.modifierFlags.contains(.control))
    }

    // Transparent to every click except right- and control-clicks.
    override func hitTest(_ point: NSPoint) -> NSView? {
        Self.isMenuClick(NSApp.currentEvent) ? super.hitTest(point) : nil
    }

    override func rightMouseDown(with event: NSEvent) { onMenu?(event) }
    override func mouseDown(with event: NSEvent) { onMenu?(event) }
}

private struct ContextMenuCatcher: NSViewRepresentable {
    let onOpen: (() -> Void)?
    let sections: () -> [RocketMenuSection]

    func makeCoordinator() -> PopoverController { PopoverController() }

    func makeNSView(context: Context) -> ContextClickView { ContextClickView() }

    func updateNSView(_ view: ContextClickView, context: Context) {
        let controller = context.coordinator
        let takesKey = context.environment.rocketPopoverTakesKey
        view.onMenu = { [weak view] _ in
            onOpen?()
            controller.close(notify: false)
            let point = NSEvent.mouseLocation
            controller.show(AnyView(RocketMenuContent(sections: sections())), anchor: NSRect(origin: point, size: .zero),
                            parent: view?.window, trailing: false, takesKey: takesKey)
        }
    }

    static func dismantleNSView(_ view: ContextClickView, coordinator: PopoverController) {
        coordinator.close(notify: false)
    }
}

public extension View {
    /// Right-click (or control-click) opens a Rocket menu at the pointer. `onOpen` runs first, e.g. to select the row.
    func rocketContextMenu(onOpen: (() -> Void)? = nil, sections: @escaping () -> [RocketMenuSection]) -> some View {
        overlay(ContextMenuCatcher(onOpen: onOpen, sections: sections))
    }
}

// MARK: Tooltips

/// One tooltip at a time. The first waits 600 ms; moving to a neighbor while one is (or just was) open is instant.
@MainActor
private final class TooltipCenter {
    static let shared = TooltipCenter()
    private var panel: FloatingPanel?
    private var hosting: NSHostingView<AnyView>?
    private var pending: Task<Void, Never>?
    private var owner: ObjectIdentifier?
    private var lastHidden = Date.distantPast
    private var monitor: Any?

    func hover(_ hovering: Bool, text: String, shortcut: String?, view: NSView) {
        let id = ObjectIdentifier(view)
        if hovering {
            pending?.cancel()
            let warm = panel?.isVisible == true || Date.now.timeIntervalSince(lastHidden) < 0.5
            owner = id
            pending = Task { [weak view] in
                if !warm { try? await Task.sleep(for: .milliseconds(600)) }
                guard !Task.isCancelled, let view, self.owner == id else { return }
                self.show(text: text, shortcut: shortcut, view: view, animated: !warm)
            }
        } else if owner == id {
            hide()
        }
    }

    func viewGone(_ view: NSView) {
        if owner == ObjectIdentifier(view) { hide() }
    }

    private func show(text: String, shortcut: String?, view: NSView, animated: Bool) {
        guard let window = view.window else { return }
        let panel = panel ?? makePanel()
        panel.appearance = window.effectiveAppearance
        hosting?.rootView = AnyView(
            TooltipBody(text: text, shortcut: shortcut, animated: animated).padding(PopoverController.margin)
        )
        let size = hosting?.fittingSize ?? .zero
        let anchor = window.convertToScreen(view.convert(view.bounds, to: nil))
        let screen = window.screen?.visibleFrame ?? .infinite
        let margin = PopoverController.margin
        var y = anchor.minY - 6 - size.height + margin
        if y + margin < screen.minY { y = anchor.maxY + 6 - margin }
        let x = min(max(anchor.midX - size.width / 2, screen.minX - margin), screen.maxX - size.width + margin)
        panel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
        window.addChildWindow(panel, ordered: .above)
        panel.orderFront(nil)
        if monitor == nil {
            // Pressing the control hides its tooltip until the pointer leaves.
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown, .scrollWheel]) { [weak self] event in
                MainActor.assumeIsolated { self?.hide(keepOwner: true) }
                return event
            }
        }
    }

    private func hide(keepOwner: Bool = false) {
        pending?.cancel()
        if !keepOwner { owner = nil }
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        guard let panel, panel.isVisible else { return }
        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil)
        lastHidden = .now
    }

    private func makePanel() -> FloatingPanel {
        let panel = FloatingPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.acceptsKey = false
        panel.ignoresMouseEvents = true
        panel.level = .popUpMenu
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = true
        panel.animationBehavior = .none
        let hosting = NSHostingView(rootView: AnyView(EmptyView()))
        panel.contentView = hosting
        self.panel = panel
        self.hosting = hosting
        return panel
    }
}

private struct TooltipBody: View {
    let text: String
    let shortcut: String?
    let animated: Bool
    @State private var shown = false

    var body: some View {
        HStack(spacing: RocketSpace.s3) {
            Text(text).font(.system(size: 11.5, weight: .medium)).foregroundStyle(RocketColor.textPrimary)
            if let shortcut { Keycap(shortcut) }
        }
        .padding(.horizontal, RocketSpace.s3)
        .padding(.vertical, 5)
        .rocketFloating(radius: RocketRadius.small + 1)
        .opacity(shown || !animated ? 1 : 0)
        .onAppear { withAnimation(RocketMotion.fast) { shown = true } }
    }
}

private struct TooltipAnchor: NSViewRepresentable {
    let text: String
    let shortcut: String?
    let hovering: Bool

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ view: NSView, context: Context) {
        TooltipCenter.shared.hover(hovering, text: text, shortcut: shortcut, view: view)
    }

    static func dismantleNSView(_ view: NSView, coordinator: ()) {
        TooltipCenter.shared.viewGone(view)
    }
}

private struct TooltipModifier: ViewModifier {
    let text: String
    let shortcut: String?
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .onHover { hovering = $0 }
            .background(TooltipAnchor(text: text, shortcut: shortcut, hovering: hovering))
            .accessibilityHint(Text(text))
    }
}

public extension View {
    /// Rocket tooltip below the view, with an optional shortcut keycap. Empty text shows nothing.
    @ViewBuilder
    func rocketTooltip(_ text: String, shortcut: String? = nil) -> some View {
        if text.isEmpty { self } else { modifier(TooltipModifier(text: text, shortcut: shortcut)) }
    }
}

// MARK: Modals

private struct ModalModifier<Modal: View>: ViewModifier {
    let isPresented: Bool
    let dismiss: () -> Void
    @ViewBuilder let modal: () -> Modal
    func body(content: Content) -> some View {
        content
            .disabled(isPresented)
            .accessibilityHidden(isPresented)
            .overlay {
                ZStack {
                    if isPresented {
                        RocketColor.scrim
                            .ignoresSafeArea()
                            .contentShape(Rectangle())
                            .onTapGesture {}
                            .transition(.opacity)
                        modal()
                            .environment(\.rocketDismiss, RocketDismissAction(dismiss))
                            .clipShape(RoundedRectangle(cornerRadius: RocketRadius.modal, style: .continuous))
                            .rocketFloating(radius: RocketRadius.modal)
                            .padding(RocketSpace.s7)
                            .onExitCommand(perform: dismiss)
                            .accessibilityAddTraits(.isModal)
                            .rocketTransition(RocketTransition.reveal)
                    }
                }
                .rocketAnimation(isPresented ? RocketMotion.enter : RocketMotion.exit, value: isPresented)
            }
    }
}

public extension View {
    /// Centered dialog over a scrim. Escape and `rocketDismiss` close it; clicks outside don't, so typing is never lost.
    func rocketModal(isPresented: Binding<Bool>, @ViewBuilder content: @escaping () -> some View) -> some View {
        modifier(ModalModifier(isPresented: isPresented.wrappedValue, dismiss: { isPresented.wrappedValue = false }, modal: content))
    }

    func rocketModal<Item: Identifiable>(item: Binding<Item?>, @ViewBuilder content: @escaping (Item) -> some View) -> some View {
        modifier(ModalModifier(isPresented: item.wrappedValue != nil, dismiss: { item.wrappedValue = nil }) {
            if let value = item.wrappedValue { content(value) }
        })
    }

    /// One-button message dialog.
    func rocketAlert(_ message: Binding<String?>) -> some View {
        modifier(ModalModifier(isPresented: message.wrappedValue != nil, dismiss: { message.wrappedValue = nil }) {
            RocketAlert(message: message.wrappedValue ?? "")
        })
    }
}

private struct RocketAlert: View {
    let message: String
    @Environment(\.rocketDismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: RocketSpace.s4) {
            StatusGlyph(.failed, size: 22)
            Text(message)
                .font(.rocketBody)
                .foregroundStyle(RocketColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("OK") { dismiss() }
                    .buttonStyle(.rocketPrimary)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(RocketSpace.s6)
        .frame(width: 380)
    }
}

/// Header and footer of a modal: title and optional subtitle, then content, then right-aligned actions on a hairline.
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
            VStack(alignment: .leading, spacing: RocketSpace.s2) {
                Text(title).font(.rocketTitle).foregroundStyle(RocketColor.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(.rocketBody)
                        .foregroundStyle(RocketColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, RocketSpace.s6)
            .padding(.top, RocketSpace.s6 - 2)
            .padding(.bottom, RocketSpace.s5)
            content
            HStack(spacing: RocketSpace.s3) { actions }
                .padding(.horizontal, RocketSpace.s5)
                .padding(.vertical, RocketSpace.s4)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .background(RocketColor.raised.opacity(0.5))
                .overlay(alignment: .top) { Rectangle().fill(RocketColor.border).frame(height: 1) }
        }
    }
}

// MARK: Window chrome

private final class ChromeView: NSView {
    var background: NSColor = .windowBackgroundColor

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.styleMask.insert(.fullSizeContentView)
        window.backgroundColor = background
    }
}

private struct WindowChrome: NSViewRepresentable {
    let background: Color

    func makeNSView(context: Context) -> NSView {
        let view = ChromeView()
        view.background = NSColor(background)
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {}
}

/// Lets a custom header move the window: drag to move, double-click to zoom.
private final class DragView: NSView {
    override var mouseDownCanMoveWindow: Bool { true }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 { window?.performZoom(nil) } else { window?.performDrag(with: event) }
    }
}

private struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ view: NSView, context: Context) {}
}

public extension View {
    /// Transparent title bar, hidden title, content under the traffic lights.
    func rocketWindowChrome(color: Color = RocketColor.canvas) -> some View {
        background(WindowChrome(background: color))
    }

    /// Empty parts of this view drag the window.
    func rocketWindowDragArea() -> some View {
        background(WindowDragArea())
    }
}
