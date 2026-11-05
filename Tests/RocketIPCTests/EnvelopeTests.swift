import Foundation
import RocketIPC
import Testing

@Test func commandRoundTrips() throws {
    let sent = Envelope(Command.add(url: URL(string: "https://example.com/f.zip")!, directory: "~/Downloads"))
    let received = try JSONDecoder().decode(Envelope<Command>.self, from: JSONEncoder().encode(sent))
    #expect(received.apiVersion == RocketAPI.version)
    #expect(received.payload == sent.payload)
}
