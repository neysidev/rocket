import Observation
import RocketIPC
import ServiceManagement

/// Registers `rocketd` with launchd and reports whether the app can reach it.
@MainActor
@Observable
final class AgentConnection {
    enum Status: Equatable {
        case connecting
        case live
        case needsApproval
        case unavailable(String)
    }

    private(set) var status: Status = .connecting
    private var client: AgentClient?
    private let service = SMAppService.agent(plistName: "io.github.neysidev.rocket.agent.plist")

    func connect() async {
        status = .connecting
        do {
            #if DEBUG
            // Ad-hoc Debug builds change the agent's code signature on every build. run-app.sh boots the stale
            // job out of launchd; registering again here loads the new binary with a fresh launch constraint.
            if service.status == .enabled { try await service.unregister() }
            #endif
            if service.status != .enabled { try service.register() }
        } catch {
            status = service.status == .requiresApproval ? .needsApproval : .unavailable(error.localizedDescription)
            return
        }
        if service.status == .requiresApproval {
            status = .needsApproval
            return
        }
        do {
            let client = try self.client ?? AgentClient()
            self.client = client
            if case .error(let message) = try await client.send(.snapshot) {
                status = .unavailable(message)
            } else {
                status = .live
            }
        } catch {
            client = nil // a timed-out client's session is cancelled
            status = .unavailable(error.localizedDescription)
        }
    }

    func openLoginItems() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
