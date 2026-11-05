import Foundation

/// `rocket://add?url=…&url=…&dir=…` from other apps (FR-INT-02). It only fills the add sheet: the user always
/// confirms, so a web page cannot start a download on its own (TRD).
public struct RocketURLRequest: Equatable, Sendable {
    public var links: [URL]
    public var folder: URL?

    /// nil when `url` is not a `rocket://add` link with at least one http(s) link.
    public init?(_ url: URL) {
        guard url.scheme?.lowercased() == "rocket", url.host()?.lowercased() == "add",
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else { return nil }
        links = LinkExtractor.urls(in: items.filter { $0.name == "url" }.compactMap(\.value).joined(separator: "\n"))
        guard !links.isEmpty else { return nil }
        // Absolute or ~ paths only; the sheet shows the folder before anything starts.
        let path = items.first(where: { $0.name == "dir" })?.value.map { ($0 as NSString).expandingTildeInPath }
        folder = path.flatMap { $0.hasPrefix("/") ? URL(filePath: $0, directoryHint: .isDirectory) : nil }
    }
}
