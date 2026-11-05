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
    private(set) var client: AgentClient?
    private let service = SMAppService.agent(plistName: "io.github.neysidev.rocket.agent.plist")

    func connect() async {
        status = .connecting
        #if !DEBUG
        // Release: register the bundled LaunchAgent. Debug builds are loaded by Scripts/run-app.sh instead,
        // because registration pins the agent's code signature, which ad-hoc builds change on every build.
        do {
            if service.status != .enabled { try service.register() }
        } catch {
            status = service.status == .requiresApproval ? .needsApproval : .unavailable(error.localizedDescription)
            return
        }
        if service.status == .requiresApproval {
            status = .needsApproval
            return
        }
        #endif
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
