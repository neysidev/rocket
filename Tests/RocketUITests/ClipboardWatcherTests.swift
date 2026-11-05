import AppKit
import Foundation
@testable import RocketUI
import Testing

@MainActor
@Suite struct ClipboardWatcherTests {
    @Test func offersMatchingLinksOnce() {
        var offers: [[URL]] = []
        let watcher = ClipboardWatcher(pasteboard: .withUniqueName(), extensions: { ["zip", "iso"] }, offer: { offers.append($0) })
        watcher.check("see https://example.com/a.zip and https://example.com/page.html and https://example.com/b.ISO")
        watcher.check("https://example.com/a.zip again")
        watcher.check("nothing here")
        #expect(offers == [[URL(string: "https://example.com/a.zip")!, URL(string: "https://example.com/b.ISO")!]])
    }

    @Test func buildsAddLinkThatParsesBack() {
        let links = [URL(string: "https://example.com/a b.zip?x=1&y=2")!, URL(string: "http://example.com/c.iso")!]
        #expect(RocketURLRequest(RocketURLRequest.url(adding: links))?.links == links)
    }

    @Test func extensionListIsCleanedUp() {
        #expect(AppSettings.extensions(" .ZIP, dmg  iso,,") == ["zip", "dmg", "iso"])
    }
}
