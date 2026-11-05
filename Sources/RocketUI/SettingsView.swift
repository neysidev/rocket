import Observation
import RocketCore
import RocketDesign
import ServiceManagement
import SwiftUI

/// Observable wrapper over `RocketDefaults` plus launch at login (FR-APP-08).
@MainActor
@Observable
public final class AppSettings {
    private let defaults: RocketDefaults

    public var folder: URL { didSet { defaults.folder = folder } }
    public var connections: Int { didSet { defaults.connections = connections } }
    public var notificationsEnabled: Bool { didSet { defaults.notificationsEnabled = notificationsEnabled } }
    /// Mirror of the agent's global limit; the agent persists it when the app sets it over XPC.
    public var globalSpeedLimit: Int64?
    public var sleepPrevention: SleepPrevention { didSet { defaults.sleepPrevention = sleepPrevention } }
    public var autoSort: Bool { didSet { defaults.autoSort = autoSort } }
    public var showDockProgress: Bool { didSet { defaults.showDockProgress = showDockProgress } }
    /// The agent reads it before each request.
    public var proxy: ProxySettings { didSet { defaults.proxy = proxy } }
    public var watchClipboard: Bool {
        didSet {
            defaults.watchClipboard = watchClipboard
            onWatchClipboardChange?(watchClipboard)
        }
    }
    /// Comma-separated, as typed; saved as a clean list.
    public var clipboardExtensions: String { didSet { defaults.clipboardExtensions = Self.extensions(clipboardExtensions) } }
    /// The app starts or stops the clipboard watcher here.
    public var onWatchClipboardChange: ((Bool) -> Void)?
    public var clipboardExtensionSet: Set<String> { Set(Self.extensions(clipboardExtensions)) }
    public private(set) var launchAtLogin = false
    public private(set) var launchAtLoginError: String?

    public init(defaults: RocketDefaults = RocketDefaults()) {
        self.defaults = defaults
        folder = defaults.folder
        connections = defaults.connections
        notificationsEnabled = defaults.notificationsEnabled
        globalSpeedLimit = defaults.globalSpeedLimit
        sleepPrevention = defaults.sleepPrevention
        autoSort = defaults.autoSort
        showDockProgress = defaults.showDockProgress
        proxy = defaults.proxy
        watchClipboard = defaults.watchClipboard
        clipboardExtensions = defaults.clipboardExtensions.joined(separator: ", ")
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    static func extensions(_ text: String) -> [String] {
        text.split(whereSeparator: { $0 == "," || $0 == " " }).map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased() }
            .filter { !$0.isEmpty }
    }

    public func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            launchAtLoginError = nil
        } catch {
            launchAtLoginError = error.localizedDescription
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}

/// Settings window: a sidebar of sections, each a scrolling page of Rocket form sections.
public struct SettingsView: View {
    let model: DownloadsModel
    /// App-provided sections (the Sparkle updater lives in the app target, TRD: one module per package).
    let extra: AnyView
    @State private var page: Page = .general
    @State private var editingRule: DownloadRule?

    enum Page: CaseIterable {
        case general, network, rules

        var title: String {
            switch self {
            case .general: String(localized: "General")
            case .network: String(localized: "Network & Clipboard")
            case .rules: String(localized: "Rules")
            }
        }

        var symbol: String {
            switch self {
            case .general: "gearshape"
            case .network: "network"
            case .rules: "line.3.horizontal.decrease"
            }
        }
    }

    public init(model: DownloadsModel, @ViewBuilder extra: () -> some View = { EmptyView() }) {
        self.model = model
        self.extra = AnyView(extra())
    }

    public var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 1) {
                Color.clear.frame(height: 40).rocketWindowDragArea()
                Text("Settings").rocketEyebrow().padding(.leading, RocketSpace.s3).padding(.bottom, RocketSpace.s3)
                ForEach(Page.allCases, id: \.self) { page in
                    SidebarRow(title: page.title, symbol: page.symbol, count: 0, isSelected: self.page == page) {
                        withAnimation(RocketMotion.standard) { self.page = page }
                    }
                }
                Spacer()
            }
            .padding(.horizontal, RocketSpace.s3)
            .frame(width: 200)
            .background(RocketColor.sidebar)
            .overlay(alignment: .trailing) { Rectangle().fill(RocketColor.border).frame(width: 1) }

            VStack(alignment: .leading, spacing: 0) {
                Text(page.title)
                    .font(.rocketTitle)
                    .foregroundStyle(RocketColor.textPrimary)
                    .padding(.horizontal, RocketSpace.s7)
                    .frame(maxWidth: .infinity, minHeight: RocketSize.headerHeight, alignment: .leading)
                    .rocketWindowDragArea()
                ScrollView {
                    Group {
                        switch page {
                        case .general:
                            GeneralSettings(settings: model.settings, extra: extra) { rate in Task { await model.setGlobalLimit(rate) } }
                        case .network:
                            NetworkSettings(settings: model.settings)
                        case .rules:
                            RulesSettings(model: model, editing: $editingRule)
                        }
                    }
                    .id(page)
                    .rocketTransition(RocketTransition.content)
                    .rocketAnimation(RocketMotion.standard, value: page)
                    .padding(.horizontal, RocketSpace.s7)
                    .padding(.bottom, RocketSpace.s7)
                }
            }
            .background(RocketColor.canvas)
        }
        .frame(width: 760, height: 580)
        .ignoresSafeArea()
        .rocketWindowChrome(color: RocketColor.sidebar)
        .rocketModal(item: $editingRule) { rule in
            RuleEditor(rule: rule, queues: model.queues) { saved in Task { await model.saveRule(saved) } }
        }
        .task { await model.refreshRules() }
    }
}

struct GeneralSettings: View {
    @Bindable var settings: AppSettings
    let extra: AnyView
    /// Sends the global limit to the agent (applies live to running downloads).
    let setSpeedLimit: (Int64?) -> Void
    @State private var choosingFolder = false

    var body: some View {
        VStack(alignment: .leading, spacing: RocketSpace.s6) {
            RocketFormSection(String(localized: "Downloads"),
                              footer: String(localized: "More connections are faster on servers that allow them. Rocket lowers the count automatically when a server pushes back.")) {
                RocketFormRow(String(localized: "Save to")) {
                    Button {
                        choosingFolder = true
                    } label: {
                        HStack(spacing: RocketSpace.s2 + 2) {
                            Image(systemName: "folder").foregroundStyle(RocketColor.textSecondary)
                            Text(settings.folder.lastPathComponent)
                        }
                    }
                    .buttonStyle(RocketButtonStyle(.secondary, size: .small))
                    .rocketTooltip(settings.folder.path)
                }
                RocketFormRow(String(localized: "Sort into folders by type"), detail: String(localized: "Video, Archives, Documents, …")) {
                    Toggle("Sort into folders by type", isOn: $settings.autoSort).labelsHidden().toggleStyle(.rocketSwitch)
                }
                RocketFormRow(String(localized: "Connections per download")) {
                    RocketSelect(String(localized: "Connections per download"), selection: $settings.connections,
                                 options: [1, 2, 4, 8, 12, 16].map { RocketOption($0, "\($0)") })
                        .fixedSize()
                }
            }
            RocketFormSection(String(localized: "Speed"),
                              footer: String(localized: "Applies right away to every running download. Set per-download limits from a download's menu.")) {
                RocketFormRow(String(localized: "Limit all downloads")) {
                    RocketSelect(String(localized: "Limit all downloads"),
                                 selection: Binding(get: { settings.globalSpeedLimit }, set: { setSpeedLimit($0) }),
                                 groups: SpeedLimitOptions.selectGroups(current: settings.globalSpeedLimit))
                        .fixedSize()
                }
            }
            RocketFormSection(String(localized: "Power")) {
                RocketFormRow(String(localized: "Keep the Mac awake while downloading")) {
                    RocketSelect(String(localized: "Keep the Mac awake while downloading"), selection: $settings.sleepPrevention,
                                 options: SleepPrevention.allCases.map { RocketOption($0, $0.title) })
                        .fixedSize()
                }
            }
            RocketFormSection(String(localized: "Notifications")) {
                RocketFormRow(String(localized: "Notify when downloads finish or fail")) {
                    Toggle("Notify when downloads finish or fail", isOn: $settings.notificationsEnabled).labelsHidden().toggleStyle(.rocketSwitch)
                }
                RocketFormRow(String(localized: "Show progress and count on the Dock icon")) {
                    Toggle("Show progress and count on the Dock icon", isOn: $settings.showDockProgress).labelsHidden().toggleStyle(.rocketSwitch)
                }
            }
            RocketFormSection(String(localized: "Startup"), footer: settings.launchAtLoginError) {
                RocketFormRow(String(localized: "Open Rocket at login"),
                              detail: String(localized: "Downloads keep running in the background after you quit the window.")) {
                    Toggle("Open Rocket at login", isOn: Binding(get: { settings.launchAtLogin }, set: settings.setLaunchAtLogin))
                        .labelsHidden()
                        .toggleStyle(.rocketSwitch)
                }
            }
            extra
        }
        .fileImporter(isPresented: $choosingFolder, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result { settings.folder = url }
        }
    }
}

struct NetworkSettings: View {
    @Bindable var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: RocketSpace.s6) {
            RocketFormSection(String(localized: "Proxy"),
                              footer: settings.proxy.kind != .system && !settings.proxy.isCustom
                                  ? String(localized: "Enter a server and a port from 1 to 65535. Until then Rocket uses the system settings.") : nil) {
                RocketFormRow(String(localized: "Proxy")) {
                    RocketSelect(String(localized: "Proxy"), selection: $settings.proxy.kind,
                                 options: ProxySettings.Kind.allCases.map { RocketOption($0, $0.title) })
                        .fixedSize()
                }
                if settings.proxy.kind != .system {
                    RocketFormRow(String(localized: "Server")) {
                        TextField("Server", text: $settings.proxy.host, prompt: Text(verbatim: "proxy.example.com")).rocketField().frame(width: 220)
                    }
                    RocketFormRow(String(localized: "Port")) {
                        TextField("Port", value: $settings.proxy.port, format: .number.grouping(.never), prompt: Text(verbatim: "8080"))
                            .rocketField(mono: true)
                            .frame(width: 90)
                    }
                }
            }
            RocketFormSection(String(localized: "Clipboard"),
                              footer: String(localized: "Rocket checks the clipboard once a second while this is on and never reads it otherwise.")) {
                RocketFormRow(String(localized: "Offer download links I copy")) {
                    Toggle("Offer download links I copy", isOn: $settings.watchClipboard).labelsHidden().toggleStyle(.rocketSwitch)
                }
                if settings.watchClipboard {
                    RocketFormRow(String(localized: "File types")) {
                        TextField("File types", text: $settings.clipboardExtensions, prompt: Text(verbatim: "zip, dmg, iso"), axis: .vertical)
                            .lineLimit(1...3)
                            .rocketField(mono: true)
                            .frame(width: 220)
                    }
                }
            }
        }
        .animation(RocketMotion.enter, value: settings.proxy.kind)
        .animation(RocketMotion.enter, value: settings.watchClipboard)
    }
}
