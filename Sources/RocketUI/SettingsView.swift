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
    public private(set) var launchAtLogin = false
    public private(set) var launchAtLoginError: String?

    public init(defaults: RocketDefaults = RocketDefaults()) {
        self.defaults = defaults
        folder = defaults.folder
        connections = defaults.connections
        notificationsEnabled = defaults.notificationsEnabled
        globalSpeedLimit = defaults.globalSpeedLimit
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

public struct SettingsView: View {
    @Bindable var settings: AppSettings
    @State private var choosingFolder = false

    public init(settings: AppSettings) {
        self.settings = settings
    }

    public var body: some View {
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
                Picker("Connections per download", selection: $settings.connections) {
                    ForEach([1, 2, 4, 8, 12, 16], id: \.self) { Text("\($0)").tag($0) }
                }
                Text("More connections are faster on servers that allow them. Rocket lowers the count automatically when a server pushes back.")
                    .font(.rocketCaption)
                    .foregroundStyle(RocketColor.textSecondary)
            }
            Section("Notifications") {
                Toggle("Notify when downloads finish or fail", isOn: $settings.notificationsEnabled)
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
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        .fileImporter(isPresented: $choosingFolder, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result { settings.folder = url }
        }
    }
}
