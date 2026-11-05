import RocketDesign
import SwiftUI

/// Placeholder shell: sidebar → list → (inspector later). Features land here from v0.1.
struct MainWindow: View {
    // ponytail: no @State yet — Command Line Tools ship without SwiftUI macro plugins; needs full Xcode.

    var body: some View {
        NavigationSplitView {
            List {
                Section("Status") {
                    Label("All downloads", systemImage: "tray.full").tag("All downloads")
                    Label("Active", systemImage: "arrow.down").tag("Active")
                    Label("Completed", systemImage: "checkmark.circle").tag("Completed")
                    Label("Failed", systemImage: "exclamationmark.triangle").tag("Failed")
                }
                Section("Queues") {
                    Label("Default", systemImage: "list.bullet").tag("Default")
                }
            }
            .navigationSplitViewColumnWidth(RocketSize.sidebarWidth)
        } detail: {
            EmptyState()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(RocketColor.canvas)
        }
        .toolbar {
            ToolbarItem { Button("Add", systemImage: "plus") {}.disabled(true) }
        }
    }
}

struct EmptyState: View {
    var body: some View {
        VStack(spacing: RocketSpace.s3) {
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 28))
                .foregroundStyle(RocketColor.textSecondary)
            Text("No downloads yet")
                .font(.rocketHeadline)
                .foregroundStyle(RocketColor.textPrimary)
            Text("Paste a link to start downloading.")
                .font(.rocketBody)
                .foregroundStyle(RocketColor.textSecondary)
        }
        .padding(RocketSpace.s6)
    }
}

struct MenuBarPanel: View {
    var body: some View {
        VStack(alignment: .leading, spacing: RocketSpace.s3) {
            Text("Rocket")
                .font(.rocketTitle)
                .foregroundStyle(RocketColor.textPrimary)
            HStack(spacing: RocketSpace.s3) {
                StatCard(label: "Active", value: "0", unit: nil)
                StatCard(label: "Speed", value: "0", unit: "MB/s")
                StatCard(label: "Queued", value: "0", unit: nil)
            }
        }
        .padding(RocketSpace.s3)
        .frame(width: RocketSize.menuBarPanelWidth)
    }
}

struct StatCard: View {
    let label: String
    let value: String
    let unit: String?

    var body: some View {
        VStack(alignment: .leading, spacing: RocketSpace.s3) {
            Text(label).font(.rocketLabel).foregroundStyle(RocketColor.textSecondary)
            HStack(alignment: .firstTextBaseline, spacing: RocketSpace.s2) {
                Text(value).font(.rocketMetricLarge).foregroundStyle(RocketColor.textPrimary)
                if let unit { Text(unit).font(.rocketLabel).foregroundStyle(RocketColor.textSecondary) }
            }
        }
        .padding(RocketSpace.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RocketColor.card, in: RoundedRectangle(cornerRadius: RocketRadius.card))
    }
}
