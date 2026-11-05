import AppKit
import RocketUI

/// "Download with Rocket" in the Services menu for selected text or links (FR-INT-05). Opens the add sheet
/// through rocket://add, like every other outside entry point.
@MainActor
final class ServicesProvider: NSObject {
    /// Selector `downloadWithRocket:userData:error:`, named by `NSMessage` in Info.plist.
    @objc func downloadWithRocket(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        let urls = pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL] ?? []
        let text = urls.map(\.absoluteString).joined(separator: "\n") + "\n" + (pasteboard.string(forType: .string) ?? "")
        let links = LinkExtractor.urls(in: text)
        guard !links.isEmpty else {
            error.pointee = String(localized: "The selection has no http or https links.") as NSString
            return
        }
        NSWorkspace.shared.open(RocketURLRequest.url(adding: links))
    }
}
