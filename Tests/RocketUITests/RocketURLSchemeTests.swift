import Foundation
import RocketUI
import Testing

@Suite struct RocketURLSchemeTests {
    @Test func readsLinksAndFolder() throws {
        let url = try #require(URL(string: "rocket://add?url=https%3A%2F%2Fexample.com%2Fa.zip&url=http://example.com/b.iso&dir=~/Movies"))
        let request = try #require(RocketURLRequest(url))
        #expect(request.links.map(\.absoluteString) == ["https://example.com/a.zip", "http://example.com/b.iso"])
        #expect(request.folder?.path == NSHomeDirectory() + "/Movies")
    }

    @Test func rejectsOtherLinks() throws {
        #expect(RocketURLRequest(try #require(URL(string: "rocket://add"))) == nil)
        #expect(RocketURLRequest(try #require(URL(string: "rocket://add?url=file:///etc/passwd"))) == nil)
        #expect(RocketURLRequest(try #require(URL(string: "rocket://delete?url=https://example.com/a"))) == nil)
        #expect(RocketURLRequest(try #require(URL(string: "https://add?url=https://example.com/a"))) == nil)
    }

    @Test func ignoresRelativeFolder() throws {
        let request = RocketURLRequest(try #require(URL(string: "rocket://add?url=https://example.com/a&dir=../x")))
        #expect(request?.folder == nil)
    }
}
