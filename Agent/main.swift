import Foundation
import RocketCore
import RocketEngine
import RocketIPC
import RocketNetworking
import RocketPersistence
import XPC

// Composition root for the background agent.
let log = Rocket.logger("Agent")

let scheduler: DownloadScheduler
do {
    let db = try RocketDatabase.onDisk()
    scheduler = DownloadScheduler(
        repository: GRDBDownloadRepository(db: db),
        transport: URLSessionHTTPTransport()
    )
} catch {
    log.error("Database failed to open: \(error.localizedDescription, privacy: .public)")
    exit(1)
}

let listener: XPCListener
do {
    listener = try XPCListener(service: RocketAPI.machServiceName) { request in
        // ponytail: no peer check while builds are ad-hoc signed (no Team ID);
        // switch to `requirement: .isFromSameTeam()` once a Developer ID team is set.
        request.accept { _ in AgentPeerHandler(scheduler: scheduler) }
    }
} catch {
    log.error("XPC listener failed: \(error.localizedDescription, privacy: .public)")
    exit(1)
}

log.info("rocketd \(Rocket.version, privacy: .public) listening on \(RocketAPI.machServiceName, privacy: .public)")
dispatchMain()
