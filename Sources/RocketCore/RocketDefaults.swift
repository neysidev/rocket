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
        static let soundEffects = "soundEffectsEnabled"
        static let globalSpeedLimit = "globalSpeedLimit"
        static let sleepPrevention = "sleepPrevention"
        static let autoSort = "autoSortByType"
        static let dockProgress = "showDockProgress"
        static let watchClipboard = "watchClipboard"
        static let clipboardExtensions = "clipboardExtensions"
    }

    /// File types the clipboard watcher offers by default (FR-INT-03).
    public static let defaultClipboardExtensions = [
        "zip", "dmg", "pkg", "iso", "img", "7z", "rar", "gz", "xz", "tar", "bz2", "xip", "ipsw",
        "mp4", "mkv", "mov", "avi", "webm", "mp3", "flac", "wav", "m4a", "pdf", "epub", "exe", "msi", "apk", "bin",
    ]

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

    /// Off on battery by default (FR-QUE-06).
    public var sleepPrevention: SleepPrevention {
        get { store.string(forKey: Key.sleepPrevention).flatMap(SleepPrevention.init(rawValue:)) ?? .onPower }
        nonmutating set { store.set(newValue.rawValue, forKey: Key.sleepPrevention) }
    }

    /// Files downloads into Video, Archives, … under the default folder (FR-ORG-01). Off until the user opts in.
    public var autoSort: Bool {
        get { store.bool(forKey: Key.autoSort) }
        nonmutating set { store.set(newValue, forKey: Key.autoSort) }
    }

    func storeData(_ key: String) -> Data? { store.data(forKey: key) }
    func setStoreData(_ data: Data?, _ key: String) { store.set(data, forKey: key) }

    public var showDockProgress: Bool {
        get { store.object(forKey: Key.dockProgress) as? Bool ?? true }
        nonmutating set { store.set(newValue, forKey: Key.dockProgress) }
    }

    /// Offer copied download links (FR-INT-03). Off until the user opts in.
    public var watchClipboard: Bool {
        get { store.bool(forKey: Key.watchClipboard) }
        nonmutating set { store.set(newValue, forKey: Key.watchClipboard) }
    }

    /// Lowercase extensions without dots.
    public var clipboardExtensions: [String] {
        get { store.stringArray(forKey: Key.clipboardExtensions) ?? Self.defaultClipboardExtensions }
        nonmutating set { store.set(newValue, forKey: Key.clipboardExtensions) }
    }

    public var notificationsEnabled: Bool {
        get { store.object(forKey: Key.notifications) as? Bool ?? true }
        nonmutating set { store.set(newValue, forKey: Key.notifications) }
    }

    /// In-app and notification sounds. Off by default so audio is opt-in.
    public var soundEffectsEnabled: Bool {
        get { store.bool(forKey: Key.soundEffects) }
        nonmutating set { store.set(newValue, forKey: Key.soundEffects) }
    }
}
