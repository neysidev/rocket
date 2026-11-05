import Foundation
import RocketCore
import RocketNetworking
import RocketTestServer
import Testing

@Suite struct RequestContextTests {
    let transport = URLSessionHTTPTransport()

    func path(_ require: String) -> String {
        "/file/1000?require=" + require.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!
    }

    @Test func sendsHeadersCookiesAndBasicAuth() async throws {
        let server = try await RocketTestServer()
        let context = RequestContext(headers: ["X-Token": "abc"], referrer: "https://example.com/page", cookies: "session=42", username: "me", password: "pw")
        let basic = "Basic " + Data("me:pw".utf8).base64EncodedString()
        for require in ["X-Token:abc", "Referer:https://example.com/page", "Cookie:session=42", "Authorization:\(basic)"] {
            #expect(try await transport.probe(server.url(path(require)), context: context).totalBytes == 1000)
        }
        await #expect(throws: DownloadError.http(status: 401)) {
            _ = try await transport.probe(server.url(path("Authorization:\(basic)")), context: nil)
        }
    }

    @Test func credentialsDoNotFollowRedirectsToAnotherHost() async throws {
        let server = try await RocketTestServer()
        let context = RequestContext(cookies: "session=42", username: "me", password: "pw")
        let basic = "Basic " + Data("me:pw".utf8).base64EncodedString()
        let target = "http://localhost:\(server.port)" + path("Authorization:\(basic)") // localhost ≠ 127.0.0.1
        let redirect = server.url("/redirect?to=" + target.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!)
        await #expect(throws: DownloadError.http(status: 401)) {
            _ = try await transport.probe(redirect, context: context)
        }
        // Same host keeps them.
        let sameHost = server.url("/redirect?to=" + path("Authorization:\(basic)").addingPercentEncoding(withAllowedCharacters: .alphanumerics)!)
        #expect(try await transport.probe(sameHost, context: context).totalBytes == 1000)
    }

    @Test func rejectsHeaderInjection() {
        #expect(throws: RequestContextError.invalidHeaderValue("X")) { try RequestContext(headers: ["X": "a\r\nEvil: 1"]).validate() }
        #expect(throws: RequestContextError.invalidHeaderName("Bad Name")) { try RequestContext(headers: ["Bad Name": "a"]).validate() }
        #expect(RequestContext.headers(fromLines: ["X-A: 1", "junk", " X-B :two words "]) == ["X-A": "1", "X-B": "two words"])
    }
}
