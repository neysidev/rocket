import RocketDesign
import Sparkle
import SwiftUI

/// Sparkle auto-updates (FR-APP-10). Pre-release builds (0.x, -rc) also take the `beta` channel; 1.0 and later
/// only the default (stable) channel. Builds without an EdDSA key (local and Debug) never start the updater.
@MainActor
final class Updater: NSObject, SPUUpdaterDelegate {
    private var controller: SPUStandardUpdaterController?

    var updater: SPUUpdater? { controller?.updater }

    override init() {
        super.init()
        let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String ?? ""
        guard !key.isEmpty else { return }
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self, userDriverDelegate: nil)
    }

    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }

    nonisolated func allowedChannels(for updater: SPUUpdater) -> Set<String> {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        return version.hasPrefix("0.") || version.contains("-") ? ["beta"] : []
    }
}

/// "Check for Updates…" in the app menu.
struct UpdateCommands: Commands {
    let updater: Updater

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button("Check for Updates…") { updater.checkForUpdates() }
                .disabled(updater.updater == nil)
        }
    }
}

/// The Updates section of General settings; lets users opt out of automatic checks.
struct UpdateSettings: View {
    let updater: SPUUpdater?
    @State private var automatic: Bool

    init(updater: SPUUpdater?) {
        self.updater = updater
        _automatic = State(initialValue: updater?.automaticallyChecksForUpdates ?? false)
    }

    var body: some View {
        RocketFormSection(String(localized: "Updates")) {
            RocketFormRow(String(localized: "Check for updates automatically"),
                          detail: updater == nil ? String(localized: "Updates are off in this build.") : nil) {
                Toggle("Check for updates automatically", isOn: $automatic)
                    .labelsHidden()
                    .toggleStyle(.rocketSwitch)
                    .disabled(updater == nil)
                    .onChange(of: automatic) { updater?.automaticallyChecksForUpdates = automatic }
            }
        }
    }
}
