import Foundation

/// Default action when the same URL or target path already exists (FR-ADD-03).
public enum DuplicateResolution: String, CaseIterable, Codable, Sendable, Identifiable {
    case keepBoth, overwrite, skip, showExisting

    public var id: Self { self }

    public var title: String {
        switch self {
        case .keepBoth: String(localized: "Keep both")
        case .overwrite: String(localized: "Replace existing file")
        case .skip: String(localized: "Skip")
        case .showExisting: String(localized: "Show existing")
        }
    }
}
