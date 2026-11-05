import Foundation

/// Download defaults shared by the app (which edits them) and the agent (which applies them to CLI and
/// browser adds). Both read the app's preferences domain.
/// ponytail: plain paths; switch to security-scoped bookmarks when a sandboxed build is attempted (TRD).
public struct RocketDefaults: @unchecked Sendable { // UserDefaults is thread-safe
    public static let connectionRange = 1...16

    enum Key {
        static let folder = "defaultFolderPath"
        static let connections = "defaultConnections"
        static let notifications = "notificationsEnabled"
        static let globalSpeedLimit = "globalSpeedLimit"
    }

    private let store: UserDefaults

    public init(store: UserDefaults = UserDefaults(suiteName: Rocket.bundleID) ?? .standard) {
        self.store = store
    }

    public var folder: URL {
        get {
            store.string(forKey: Key.folder).map { URL(filePath: $0, directoryHint: .isDirectory) } ?? .downloadsDirectory
        }
        nonmutating set { store.set(newValue.path, forKey: Key.folder) }
    }

    public var connections: Int {
        get {
            let value = store.integer(forKey: Key.connections)
            return value == 0 ? 8 : min(max(value, Self.connectionRange.lowerBound), Self.connectionRange.upperBound)
        }
        nonmutating set { store.set(newValue, forKey: Key.connections) }
    }

    /// Bytes per second for all downloads together; nil = unlimited (FR-SPD-01).
    public var globalSpeedLimit: Int64? {
        get { (store.object(forKey: Key.globalSpeedLimit) as? NSNumber).map(\.int64Value).flatMap { $0 > 0 ? $0 : nil } }
        nonmutating set { store.set(newValue.map(NSNumber.init(value:)), forKey: Key.globalSpeedLimit) }
    }

    public var notificationsEnabled: Bool {
        get { store.object(forKey: Key.notifications) as? Bool ?? true }
        nonmutating set { store.set(newValue, forKey: Key.notifications) }
    }
}
