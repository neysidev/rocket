import AppKit
import Foundation
import IOKit.ps
import IOKit.pwr_mgt
import RocketCore

/// What happens after a queue runs dry (FR-QUE-05). "Notify" is posted by the app, which owns notifications.
enum PostQueueActions {
    static func run(_ queue: DownloadQueue) async {
        switch queue.postAction {
        case .none, .notify:
            break
        case .sleep:
            run("/usr/bin/pmset", ["sleepnow"])
        case .shutDown:
            // Asks System Events, so the user gets the usual chance to save; needs Automation permission once.
            run("/usr/bin/osascript", ["-e", "tell application \"System Events\" to shut down"])
        case .quitRocket:
            await MainActor.run {
                NSRunningApplication.runningApplications(withBundleIdentifier: Rocket.bundleID).forEach { $0.terminate() }
            }
        case .runShortcut:
            if let name = queue.shortcutName, !name.isEmpty { run("/usr/bin/shortcuts", ["run", name]) }
        }
    }

    private static func run(_ tool: String, _ arguments: [String]) {
        let process = Process()
        process.executableURL = URL(filePath: tool)
        process.arguments = arguments
        do { try process.run() } catch {
            Rocket.logger("Agent").error("After-queue action failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

/// Keeps the Mac from idle-sleeping while downloads run, per the user's setting (FR-QUE-06).
actor SleepAssertion {
    static let shared = SleepAssertion()
    private var assertion: IOPMAssertionID?

    func update(downloading: Bool) {
        let wanted = downloading && Self.allowed(RocketDefaults().sleepPrevention)
        if wanted, assertion == nil {
            var id = IOPMAssertionID(0)
            let reason = "Rocket is downloading" as CFString
            if IOPMAssertionCreateWithName(kIOPMAssertPreventUserIdleSystemSleep as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn), reason, &id) == kIOReturnSuccess {
                assertion = id
            }
        } else if !wanted, let id = assertion {
            IOPMAssertionRelease(id)
            assertion = nil
        }
    }

    private static func allowed(_ setting: SleepPrevention) -> Bool {
        switch setting {
        case .never: false
        case .always: true
        case .onPower:
            IOPSGetProvidingPowerSourceType(IOPSCopyPowerSourcesInfo()?.takeRetainedValue())?.takeUnretainedValue() as String? == kIOPMACPowerKey
        }
    }
}
