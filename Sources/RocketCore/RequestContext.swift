import Foundation

/// Extra request details for one download (FR-ADD-04, FR-BRW-03): custom headers, referrer, user agent,
/// cookies and HTTP Basic credentials. Cookies and the password are secrets: stored in the Keychain,
/// never in SQLite, never logged, and only sent to the download's original host.
public struct RequestContext: Codable, Sendable, Hashable {
    public var headers: [String: String]
    public var referrer: String?
    public var userAgent: String?
    /// `Cookie` header value. Secret.
    public var cookies: String?
    public var username: String?
    /// Secret.
    public var password: String?

    public init(
        headers: [String: String] = [:], referrer: String? = nil, userAgent: String? = nil,
        cookies: String? = nil, username: String? = nil, password: String? = nil
    ) {
        self.headers = headers
        self.referrer = referrer
        self.userAgent = userAgent
        self.cookies = cookies
        self.username = username
        self.password = password
    }

    public var isEmpty: Bool { self == RequestContext() }

    /// Every header to send, including referrer, user agent, cookies and Basic auth.
    public var allHeaders: [String: String] {
        var all = headers
        if let referrer, !referrer.isEmpty { all["Referer"] = referrer }
        if let userAgent, !userAgent.isEmpty { all["User-Agent"] = userAgent }
        if let cookies, !cookies.isEmpty { all["Cookie"] = cookies }
        if let username, !username.isEmpty {
            all["Authorization"] = "Basic " + Data("\(username):\(password ?? "")".utf8).base64EncodedString()
        }
        return all
    }

    /// Headers that must not follow a redirect to another host.
    public static let credentialHeaders: Set<String> = ["authorization", "cookie", "proxy-authorization"]

    /// Header names must be tokens and no value may contain line breaks (header injection).
    public func validate() throws {
        let token = CharacterSet(charactersIn: "!#$%&'*+-.^_`|~").union(.alphanumerics)
        for (name, value) in allHeaders {
            guard !name.isEmpty, name.unicodeScalars.allSatisfy(token.contains) else { throw RequestContextError.invalidHeaderName(name) }
            // Scalars, not Characters: "\r\n" is one Character that equals neither "\r" nor "\n".
            guard !value.unicodeScalars.contains(where: { $0 == "\r" || $0 == "\n" }) else { throw RequestContextError.invalidHeaderValue(name) }
        }
    }

    /// Copy without secrets, safe to send to UI clients.
    public var redacted: RequestContext {
        var copy = self
        if copy.cookies != nil { copy.cookies = "••••" }
        if copy.password != nil { copy.password = "••••" }
        return copy
    }

    /// Parses "Name: value" lines, as typed in the add sheet or passed with `--header`.
    public static func headers(fromLines lines: [String]) -> [String: String] {
        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if !name.isEmpty { headers[name] = value }
        }
        return headers
    }
}

public enum RequestContextError: Error, Sendable, Equatable {
    case invalidHeaderName(String)
    case invalidHeaderValue(String)
}

/// Persistence port for request contexts; secrets go to a `SecretStore`.
public protocol RequestContextStore: Sendable {
    func context(for downloadID: UUID) async throws -> RequestContext?
    func saveContext(_ context: RequestContext, for downloadID: UUID) async throws
    func deleteContext(for downloadID: UUID) async throws
}
