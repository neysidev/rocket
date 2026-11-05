import Foundation
import RocketCore
@testable import RocketUI
import Testing

@MainActor
@Suite struct SettingsTests {
    let store = UserDefaults(suiteName: "RocketSettingsTests-\(UUID().uuidString)")!

    @Test func defaultsWhenUnset() {
        let defaults = RocketDefaults(store: store)
        #expect(defaults.folder == .downloadsDirectory)
        #expect(defaults.connections == 8)
        #expect(defaults.notificationsEnabled)
    }

    @Test func settingsPersistForTheAgent() {
        let settings = AppSettings(defaults: RocketDefaults(store: store))
        settings.folder = URL(filePath: "/Volumes/Media/Incoming", directoryHint: .isDirectory)
        settings.connections = 4
        settings.notificationsEnabled = false

        let agentView = RocketDefaults(store: store)
        #expect(agentView.folder.path == "/Volumes/Media/Incoming")
        #expect(agentView.connections == 4)
        #expect(!agentView.notificationsEnabled)
    }

    @Test func connectionsAreClamped() {
        store.set(99, forKey: "defaultConnections")
        #expect(RocketDefaults(store: store).connections == 16)
    }

    @Test func addSheetStartsFromSettings() {
        let settings = AppSettings(defaults: RocketDefaults(store: store))
        settings.folder = URL(filePath: "/tmp/elsewhere", directoryHint: .isDirectory)
        settings.connections = 2
        let model = DownloadsModel(settings: settings)
        model.beginAdding([URL(string: "https://example.com/a.iso")!])
        #expect(model.adding?.folder.path == "/tmp/elsewhere")
        #expect(model.adding?.connections == 2)
    }
}
