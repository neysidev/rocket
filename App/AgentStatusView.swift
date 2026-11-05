import RocketDesign
import SwiftUI

/// Agent health indicator with a fix-it action (TRD: Observability > Health).
struct AgentStatusView: View {
    @Environment(AgentConnection.self) private var agent

    var body: some View {
        // The sidebar's activity line covers the healthy case; only problems get a row.
        if agent.status != .live { status }
    }

    private var status: some View {
        HStack(spacing: RocketSpace.s2) {
            Image(systemName: symbol)
                .foregroundStyle(color)
            Text(word)
                .font(.rocketLabel)
                .foregroundStyle(color)
                .help(detail)
            Spacer(minLength: 0)
            if agent.status == .needsApproval {
                Button("Open Login Items") { agent.openLoginItems() }
                    .buttonStyle(.link)
                    .font(.rocketLabel)
            } else if case .unavailable = agent.status {
                Button("Retry") { Task { await agent.connect() } }
                    .buttonStyle(.link)
                    .font(.rocketLabel)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Agent \(word). \(detail)")
    }

    private var word: String {
        switch agent.status {
        case .connecting: "Connecting"
        case .live: "Live"
        case .needsApproval: "Needs approval"
        case .unavailable: "Agent unavailable"
        }
    }

    private var detail: String {
        switch agent.status {
        case .connecting: "Connecting to the background agent."
        case .live: "Background agent is running."
        case .needsApproval: "Allow Rocket in System Settings > General > Login Items."
        case .unavailable(let reason): reason
        }
    }

    private var symbol: String {
        switch agent.status {
        case .connecting: "circle.dotted"
        case .live: "checkmark.circle"
        case .needsApproval, .unavailable: "exclamationmark.triangle"
        }
    }

    private var color: Color {
        switch agent.status {
        case .connecting: RocketColor.textSecondary
        case .live: RocketColor.success
        case .needsApproval: RocketColor.warning
        case .unavailable: RocketColor.danger
        }
    }
}
