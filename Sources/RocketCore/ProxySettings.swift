import Foundation

/// Per-app proxy (FR-ENG-11). `.system` follows System Settings, which URLSession does by default.
/// ponytail: no proxy authentication yet; add username/password (Keychain) when someone needs it.
public struct ProxySettings: Codable, Sendable, Hashable {
    public enum Kind: String, Codable, Sendable, CaseIterable {
        case system, http, socks5

        public var title: String {
            switch self {
            case .system: String(localized: "Use system settings")
            case .http: String(localized: "HTTP and HTTPS proxy")
            case .socks5: String(localized: "SOCKS5 proxy")
            }
        }
    }

    public var kind: Kind
    public var host: String
    public var port: Int

    public init(kind: Kind = .system, host: String = "", port: Int = 0) {
        self.kind = kind
        self.host = host
        self.port = port
    }

    public static let system = ProxySettings()

    /// Usable custom proxy, or nil to follow the system.
    public var isCustom: Bool {
        kind != .system && !host.trimmingCharacters(in: .whitespaces).isEmpty && (1...65535).contains(port)
    }
}

extension RocketDefaults {
    private static let proxyKey = "proxy"

    public var proxy: ProxySettings {
        get {
            storeData(Self.proxyKey)
                .flatMap { try? JSONDecoder().decode(ProxySettings.self, from: $0) } ?? .system
        }
        nonmutating set { setStoreData((try? JSONEncoder().encode(newValue)), Self.proxyKey) }
    }
}
