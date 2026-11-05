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
    let repository = GRDBDownloadRepository(db: try RocketDatabase.onDisk())
    scheduler = DownloadScheduler(repository: repository, checkpoints: repository, transport: URLSessionHTTPTransport())
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

// Resume interrupted downloads, then retry transient failures whenever the network comes back
// (network loss and wake from sleep both end with a satisfied path).
// ponytail: agent never idles out; add the TRD's 60 s idle exit once clients reconnect on demand.
Task {
    do { try await scheduler.start() } catch { log.error("Start failed: \(error.localizedDescription, privacy: .public)") }
    for await isOnline in NetworkReachability.updates() where isOnline {
        try? await scheduler.networkAvailable()
    }
}

log.info("rocketd \(Rocket.version, privacy: .public) listening on \(RocketAPI.machServiceName, privacy: .public)")
dispatchMain()
