import AppKit
import Foundation

/// Offers download links the user copies (FR-INT-03). Opt-in; while on it reads only `changeCount` once a
/// second and looks at the text only when that changes (TRD). Each link is offered once per app run.
@MainActor
public final class ClipboardWatcher {
    private let pasteboard: NSPasteboard
    private let extensions: () -> Set<String>
    private let offer: ([URL]) -> Void
    private var task: Task<Void, Never>?
    private var offered: Set<URL> = []

    public init(pasteboard: NSPasteboard = .general, extensions: @escaping () -> Set<String>, offer: @escaping ([URL]) -> Void) {
        self.pasteboard = pasteboard
        self.extensions = extensions
        self.offer = offer
    }

    public func setEnabled(_ enabled: Bool) {
        task?.cancel()
        task = nil
        guard enabled else { return }
        // Start from the current contents: enabling the watcher must not offer what was copied before.
        var lastChange = pasteboard.changeCount
        task = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, self.pasteboard.changeCount != lastChange else { continue }
                lastChange = self.pasteboard.changeCount
                self.check(self.pasteboard.string(forType: .string) ?? "")
            }
        }
    }

    /// Offers links in `text` whose file type is on the list and that were not offered before.
    func check(_ text: String) {
        let types = extensions()
        let links = LinkExtractor.urls(in: text).filter { types.contains($0.pathExtension.lowercased()) && !offered.contains($0) }
        guard !links.isEmpty else { return }
        offered.formUnion(links)
        offer(links)
    }
}
