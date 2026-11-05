import Foundation

/// Recently run palette commands and opened downloads (UserDefaults-backed).
enum CommandRecents {
    private static let commandsKey = "commandPalette.recentCommands"
    private static let downloadsKey = "commandPalette.recentDownloads"
    static let maxCommands = 10
    static let maxDownloads = 8

    static func recentCommandIDs() -> [String] {
        UserDefaults.standard.stringArray(forKey: commandsKey) ?? []
    }

    static func recentDownloadIDs() -> [UUID] {
        (UserDefaults.standard.stringArray(forKey: downloadsKey) ?? []).compactMap(UUID.init(uuidString:))
    }

    static func recordCommand(_ id: String) {
        var list = recentCommandIDs().filter { $0 != id }
        list.insert(id, at: 0)
        UserDefaults.standard.set(Array(list.prefix(maxCommands)), forKey: commandsKey)
    }

    static func recordDownload(_ id: UUID) {
        var list = recentDownloadIDs().filter { $0 != id }
        list.insert(id, at: 0)
        UserDefaults.standard.set(list.prefix(maxDownloads).map(\.uuidString), forKey: downloadsKey)
    }
}
