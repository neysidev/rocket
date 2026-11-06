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
        HStack(spacing: RocketSpace.s3) {
            Group {
                if agent.status == .connecting { RocketSpinner(size: 12) } else { StatusGlyph(.failed, size: 12) }
            }
            .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 1) {
                Text(word).font(.rocketLabel).foregroundStyle(RocketColor.textPrimary)
                Text(detail).font(.rocketCaption).foregroundStyle(RocketColor.textSecondary).lineLimit(2)
            }
            Spacer(minLength: 0)
            if agent.status == .needsApproval {
                Button("Open") { agent.openLoginItems() }
                    .buttonStyle(RocketButtonStyle(.secondary, size: .small))
                    .rocketTooltip(String(localized: "Open Login Items"))
            } else if case .unavailable = agent.status {
                Button("Retry") { Task { await agent.connect() } }
                    .buttonStyle(RocketButtonStyle(.secondary, size: .small))
            }
        }
        .padding(RocketSpace.s3)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: RocketRadius.card, style: .continuous))
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
