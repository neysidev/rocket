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
        launchAtLogin = SMAppService.mainApp.status == .enabled
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

/// General and Rules tabs.
public struct SettingsView: View {
    let model: DownloadsModel
    /// App-provided sections (the Sparkle updater lives in the app target, TRD: one module per package).
    let extra: AnyView

    public init(model: DownloadsModel, @ViewBuilder extra: () -> some View = { EmptyView() }) {
        self.model = model
        self.extra = AnyView(extra())
    }

    public var body: some View {
        TabView {
            GeneralSettings(settings: model.settings, extra: extra)
                .tabItem { Label("General", systemImage: "gearshape") }
            RulesSettings(model: model)
                .tabItem { Label("Rules", systemImage: "line.3.horizontal.decrease") }
        }
        .task { await model.refreshRules() }
    }
}

struct GeneralSettings: View {
    @Bindable var settings: AppSettings
    let extra: AnyView
    @State private var choosingFolder = false

    var body: some View {
        Form {
            Section("Downloads") {
                LabeledContent("Save to") {
                    Button {
                        choosingFolder = true
                    } label: {
                        Label(settings.folder.lastPathComponent, systemImage: "folder")
                    }
                    .help(settings.folder.path)
                }
                Toggle("Sort into folders by type (Video, Archives, Documents, …)", isOn: $settings.autoSort)
                Picker("Connections per download", selection: $settings.connections) {
                    ForEach([1, 2, 4, 8, 12, 16], id: \.self) { Text("\($0)").tag($0) }
                }
                Text("More connections are faster on servers that allow them. Rocket lowers the count automatically when a server pushes back.")
                    .font(.rocketCaption)
                    .foregroundStyle(RocketColor.textSecondary)
            }
            Section("Network") {
                Picker("Proxy", selection: $settings.proxy.kind) {
                    ForEach(ProxySettings.Kind.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                if settings.proxy.kind != .system {
                    TextField("Server", text: $settings.proxy.host, prompt: Text("proxy.example.com"))
                    TextField("Port", value: $settings.proxy.port, format: .number.grouping(.never), prompt: Text("8080"))
                    if !settings.proxy.isCustom {
                        Text("Enter a server and a port from 1 to 65535. Until then Rocket uses the system settings.")
                            .font(.rocketCaption)
                            .foregroundStyle(RocketColor.warning)
                    }
                }
            }
            Section("Power") {
                Picker("Keep the Mac awake while downloading", selection: $settings.sleepPrevention) {
                    ForEach(SleepPrevention.allCases, id: \.self) { Text($0.title).tag($0) }
                }
            }
            Section("Notifications") {
                Toggle("Notify when downloads finish or fail", isOn: $settings.notificationsEnabled)
                Toggle("Show progress and count on the Dock icon", isOn: $settings.showDockProgress)
            }
            Section("Startup") {
                Toggle("Open Rocket at login", isOn: Binding(get: { settings.launchAtLogin }, set: settings.setLaunchAtLogin))
                if let error = settings.launchAtLoginError {
                    Text(error)
                        .font(.rocketCaption)
                        .foregroundStyle(RocketColor.danger)
                }
                Text("Downloads keep running in the background after you quit the window.")
                    .font(.rocketCaption)
                    .foregroundStyle(RocketColor.textSecondary)
            }
            extra
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        .fileImporter(isPresented: $choosingFolder, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result { settings.folder = url }
        }
    }
}
