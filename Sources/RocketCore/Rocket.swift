import Foundation
import os

/// Process-wide constants shared by every module.
public enum Rocket {
    public static let bundleID = "io.github.neysidev.rocket"
    public static let version = "0.0.1"

    /// `~/Library/Application Support/io.github.neysidev.rocket/`
    public static var supportDirectory: URL {
        URL.applicationSupportDirectory.appending(path: bundleID, directoryHint: .isDirectory)
    }

    public static func logger(_ category: String) -> Logger {
        Logger(subsystem: bundleID, category: category)
    }
}

/// Compile-time flags so unfinished features ship dark and `main` stays releasable.
public enum FeatureFlags {
    public static let browserCapture = false
    public static let scheduling = false
}
