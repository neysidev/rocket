import Foundation
import RocketTestServer

// Runs the development test server until killed: `swift run rocket-test-server`.
setvbuf(stdout, nil, _IONBF, 0)
let server = try await RocketTestServer()
print("RocketTestServer listening on http://127.0.0.1:\(server.port)")
while true { try await Task.sleep(for: .seconds(3600)) }
