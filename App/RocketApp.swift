import RocketDesign
import SwiftUI

@main
struct RocketApp: App {
    @State private var agent = AgentConnection()

    var body: some Scene {
        WindowGroup("Rocket") {
            MainWindow()
                .environment(agent)
                .frame(minWidth: 760, minHeight: 480)
                .task { await agent.connect() }
        }
        Settings {
            Text("Settings")
                .font(.rocketBody)
                .padding(RocketSpace.s6)
        }
        MenuBarExtra("Rocket", systemImage: "arrow.down.circle") {
            MenuBarPanel()
        }
        .menuBarExtraStyle(.window)
    }
}
