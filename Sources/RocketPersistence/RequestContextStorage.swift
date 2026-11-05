import Foundation
import GRDB
import RocketCore
import Security

/// Where cookies and passwords live. Keychain in the agent, memory in tests.
public protocol SecretStore: Sendable {
    func secret(for account: String) throws -> Data?
    func setSecret(_ data: Data?, for account: String) throws
}

/// Generic passwords in the login keychain, one per download.
public struct KeychainSecretStore: SecretStore {
    let service: String

    public init(service: String = "\(Rocket.bundleID).request") {
        self.service = service
    }

    public func secret(for account: String) throws -> Data? {
        var result: CFTypeRef?
        let status = SecItemCopyMatching([
            kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account,
            kSecReturnData: true, kSecMatchLimit: kSecMatchLimitOne,
        ] as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainError(status: status) }
        return result as? Data
    }

    public func setSecret(_ data: Data?, for account: String) throws {
        let query = [kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account] as CFDictionary
        SecItemDelete(query)
        guard let data else { return }
        var item = [kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account] as [CFString: Any]
        item[kSecValueData] = data
        item[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError(status: status) }
    }
}

public struct KeychainError: Error, Sendable {
    public let status: OSStatus
}

/// Non-secret parts in the `requestContext` table, secrets in a `SecretStore` keyed by download ID.
public struct GRDBRequestContextStore: RequestContextStore {
    private let db: RocketDatabase
    private let secrets: any SecretStore

    public init(db: RocketDatabase, secrets: any SecretStore = KeychainSecretStore()) {
        self.db = db
        self.secrets = secrets
    }

    private struct Row: Codable, FetchableRecord, PersistableRecord {
        static let databaseTableName = "requestContext"
        var downloadId: UUID
        var headersJSON: Public
        /// "keychain" when secrets exist; the value itself never touches SQLite.
        var cookiesRef: String?
        var referrer: String?
        var userAgent: String?
    }

    private struct Public: Codable {
        var headers: [String: String]
        var username: String?
    }

    private struct Secrets: Codable {
        var cookies: String?
        var password: String?
    }

    public func context(for downloadID: UUID) async throws -> RequestContext? {
        guard let row = try read({ try Row.fetchOne($0, key: downloadID) }) else { return nil }
        var context = RequestContext(headers: row.headersJSON.headers, referrer: row.referrer, userAgent: row.userAgent, username: row.headersJSON.username)
        if row.cookiesRef != nil, let data = try secrets.secret(for: downloadID.uuidString) {
            let stored = try JSONDecoder().decode(Secrets.self, from: data)
            context.cookies = stored.cookies
            context.password = stored.password
        }
        return context
    }

    public func saveContext(_ context: RequestContext, for downloadID: UUID) async throws {
        let hasSecrets = context.cookies != nil || context.password != nil
        try secrets.setSecret(hasSecrets ? JSONEncoder().encode(Secrets(cookies: context.cookies, password: context.password)) : nil, for: downloadID.uuidString)
        let row = Row(
            downloadId: downloadID, headersJSON: Public(headers: context.headers, username: context.username),
            cookiesRef: hasSecrets ? "keychain" : nil, referrer: context.referrer, userAgent: context.userAgent
        )
        try write { try row.save($0) }
    }

    public func deleteContext(for downloadID: UUID) async throws {
        try secrets.setSecret(nil, for: downloadID.uuidString)
        try write { _ = try Row.deleteOne($0, key: downloadID) }
    }

    // Synchronous on purpose, like GRDBDownloadRepository: callers may be cancelled tasks.
    private func read<T>(_ body: (Database) throws -> T) throws -> T { try db.writer.read(body) }
    private func write(_ body: (Database) throws -> Void) throws { try db.writer.write(body) }
}
