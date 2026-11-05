import Foundation

/// Coarse file type, used for row icons now and auto-sorting folders later (FR-ORG-01).
public enum FileCategory: String, Sendable, CaseIterable, Codable {
    case video, archive, document, app, music, image, other

    public init(fileName: String) {
        let ext = (fileName as NSString).pathExtension.lowercased()
        self = Self.byExtension[ext] ?? .other
    }

    private static let byExtension: [String: FileCategory] = {
        var map: [String: FileCategory] = [:]
        for ext in ["mp4", "mkv", "mov", "avi", "webm", "m4v", "wmv", "flv"] { map[ext] = .video }
        for ext in ["zip", "rar", "7z", "tar", "gz", "tgz", "bz2", "xz", "zst", "iso", "img"] { map[ext] = .archive }
        for ext in ["pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "txt", "md", "epub", "csv", "pages", "key", "numbers"] { map[ext] = .document }
        for ext in ["dmg", "pkg", "app", "exe", "msi", "deb", "rpm", "apk", "ipa"] { map[ext] = .app }
        for ext in ["mp3", "flac", "wav", "aac", "m4a", "ogg", "aiff", "opus"] { map[ext] = .music }
        for ext in ["jpg", "jpeg", "png", "gif", "heic", "webp", "tiff", "svg", "raw", "psd"] { map[ext] = .image }
        return map
    }()
}
