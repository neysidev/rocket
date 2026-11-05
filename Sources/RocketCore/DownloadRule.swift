import Foundation

/// "Downloads from these sites / with these extensions / of this size go here, in this queue, at this speed" (FR-ORG-02).
public struct DownloadRule: Codable, Sendable, Identifiable, Hashable {
    public var id: String
    public var name: String
    public var enabled: Bool
    /// Lower runs first; the first enabled match wins.
    public var priority: Int
    public var match: RuleMatch
    public var action: RuleAction

    public init(id: String = UUID().uuidString, name: String, enabled: Bool = true, priority: Int = 0, match: RuleMatch = RuleMatch(), action: RuleAction = RuleAction()) {
        self.id = id
        self.name = name
        self.enabled = enabled
        self.priority = priority
        self.match = match
        self.action = action
    }

    enum CodingKeys: String, CodingKey {
        case id, name, enabled, priority
        case match = "matchJSON"
        case action = "actionJSON"
    }

    /// The first enabled rule, by priority, that matches.
    public static func first(in rules: [DownloadRule], url: URL, fileName: String, size: Int64?) -> DownloadRule? {
        rules.filter(\.enabled).sorted { $0.priority < $1.priority }.first { $0.match.matches(url: url, fileName: fileName, size: size) }
    }
}

/// Every non-empty condition must hold; an empty match matches everything.
public struct RuleMatch: Codable, Sendable, Hashable {
    /// Host names; "example.com" also matches "cdn.example.com".
    public var domains: [String]
    /// Without dots, case-insensitive: ["iso", "dmg"].
    public var extensions: [String]
    public var minBytes: Int64?
    public var maxBytes: Int64?

    public init(domains: [String] = [], extensions: [String] = [], minBytes: Int64? = nil, maxBytes: Int64? = nil) {
        self.domains = domains
        self.extensions = extensions
        self.minBytes = minBytes
        self.maxBytes = maxBytes
    }

    public func matches(url: URL, fileName: String, size: Int64?) -> Bool {
        if !domains.isEmpty {
            let host = url.host()?.lowercased() ?? ""
            let hit = domains.map { $0.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ". ")) }
                .contains { !$0.isEmpty && (host == $0 || host.hasSuffix("." + $0)) }
            guard hit else { return false }
        }
        if !extensions.isEmpty {
            let ext = (fileName as NSString).pathExtension.lowercased()
            guard extensions.map({ $0.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ". ")) }).contains(ext) else { return false }
        }
        // Unknown sizes never match a size condition.
        if let minBytes { guard let size, size >= minBytes else { return false } }
        if let maxBytes { guard let size, size <= maxBytes else { return false } }
        return true
    }
}

/// What a matching rule sets; nil leaves the default.
public struct RuleAction: Codable, Sendable, Hashable {
    public var folderPath: String?
    public var queueID: String?
    public var connections: Int?
    public var speedLimit: Int64?

    public init(folderPath: String? = nil, queueID: String? = nil, connections: Int? = nil, speedLimit: Int64? = nil) {
        self.folderPath = folderPath
        self.queueID = queueID
        self.connections = connections
        self.speedLimit = speedLimit
    }
}

public protocol RuleRepository: Sendable {
    func rules() async throws -> [DownloadRule]
    func save(_ rule: DownloadRule) async throws
    func deleteRule(id: String) async throws
}

public extension FileCategory {
    /// Subfolder used by auto-sort (FR-ORG-01).
    var folderName: String {
        switch self {
        case .video: String(localized: "Video")
        case .archive: String(localized: "Archives")
        case .document: String(localized: "Documents")
        case .app: String(localized: "Apps")
        case .music: String(localized: "Music")
        case .image: String(localized: "Images")
        case .other: String(localized: "Other")
        }
    }
}
