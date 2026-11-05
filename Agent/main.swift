import Foundation
import RocketCore
import RocketEngine
import RocketNetworking
import RocketPersistence
import RocketIPC

// Composition root for the background agent.
let log = Rocket.logger("Agent")

do {
    let db = try RocketDatabase.onDisk()
    let scheduler = DownloadScheduler(
        repository: GRDBDownloadRepository(db: db),
        transport: URLSessionHTTPTransport()
    )
    _ = scheduler
    log.info("rocketd \(Rocket.version, privacy: .public) ready on \(RocketAPI.machServiceName, privacy: .public)")
    print("rocketd ready, database at \(Rocket.supportDirectory.path)")
} catch {
    log.error("Startup failed: \(error.localizedDescription, privacy: .public)")
    exit(1)
}

// ponytail: XPC listener not wired yet; needs a signed bundle + SMAppService registration.
dispatchMain()
