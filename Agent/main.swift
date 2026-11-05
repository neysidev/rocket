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
    let database = try RocketDatabase.onDisk()
    let repository = GRDBDownloadRepository(db: database)
    scheduler = DownloadScheduler(
        repository: repository, checkpoints: repository, queues: repository, rules: repository,
        contexts: GRDBRequestContextStore(db: database),
        transport: URLSessionHTTPTransport(proxy: { RocketDefaults().proxy }),
        runPostAction: { await PostQueueActions.run($0) },
        onActivityChange: { await SleepAssertion.shared.update(downloading: $0) }
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

// Resume interrupted downloads, retry transient failures whenever the network comes back, and reconnect
// running downloads after wake from sleep (FR-ENG-08).
// ponytail: agent never idles out; add the TRD's 60 s idle exit once clients reconnect on demand.
Task {
    do { try await scheduler.start() } catch { log.error("Start failed: \(error.localizedDescription, privacy: .public)") }
    await withDiscardingTaskGroup { group in
        group.addTask {
            for await isOnline in NetworkReachability.updates() where isOnline {
                try? await scheduler.networkAvailable()
            }
        }
        group.addTask {
            for await _ in SystemWake.events() {
                log.info("Woke from sleep; reconnecting downloads")
                try? await scheduler.systemDidWake()
            }
        }
        group.addTask {
            // Opens and closes scheduled queues. ponytail: fixed 30 s tick; sleep until the next window
            // boundary instead if idle wake-ups show up in energy measurements (PERF-05).
            while true {
                try? await Task.sleep(for: .seconds(30))
                try? await scheduler.tick()
            }
        }
    }
}

log.info("rocketd \(Rocket.version, privacy: .public) listening on \(RocketAPI.machServiceName, privacy: .public)")
dispatchMain()
