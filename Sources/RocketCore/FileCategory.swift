import Foundation
import UniformTypeIdentifiers

/// Coarse file type, used for row icons now and auto-sorting folders later (FR-ORG-01).
public enum FileCategory: String, Sendable, CaseIterable, Codable {
    case video, archive, document, app, music, image, other

    /// Known extensions first, then the system type database for the extension, then the server's MIME type.
    public init(fileName: String, mimeType: String? = nil) {
        let ext = (fileName as NSString).pathExtension.lowercased()
        if let known = Self.byExtension[ext] {
            self = known
            return
        }
        let byExtension = ext.isEmpty ? nil : UTType(filenameExtension: ext).flatMap { $0.isDynamic ? nil : $0 }
        let byMIME = mimeType.flatMap { UTType(mimeType: $0.split(separator: ";")[0].trimmingCharacters(in: .whitespaces)) }
        let category = byExtension.map(Self.init(type:)) ?? .other
        self = category != .other ? category : byMIME.map(Self.init(type:)) ?? .other
    }

    public init(type: UTType) {
        let rules: [(UTType, FileCategory)] = [
            (.movie, .video), (.video, .video), (.audio, .music), (.image, .image),
            (.archive, .archive), (.diskImage, .app), (.application, .app), (.executable, .app),
            (.pdf, .document), (.text, .document), (.presentation, .document), (.spreadsheet, .document), (.epub, .document),
        ]
        self = rules.first { type.conforms(to: $0.0) }?.1 ?? .other
    }

    private static let byExtension: [String: FileCategory] = {
        var map: [String: FileCategory] = [:]
        for ext in ["mp4", "mkv", "mov", "avi", "webm", "m4v", "wmv", "flv"] { map[ext] = .video }
        for ext in ["zip", "rar", "7z", "tar", "gz", "tgz", "bz2", "xz", "zst", "iso", "img"] { map[ext] = .archive }
        for ext in ["pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "txt", "md", "epub", "csv", "pages", "key", "numbers"] { map[ext] = .document }
        for ext in ["dmg", "pkg", "app", "exe", "msi", "deb", "rpm", "apk", "ipa"] { map[ext] = .app }
        for ext in ["mp3", "flac", "wav", "aac", "m4a", "ogg", "aiff", "opus"] { map[ext] = .music }
        // Generic binaries the system database would call archives (MacBinary).
        for ext in ["bin", "dat"] { map[ext] = .other }
        for ext in ["jpg", "jpeg", "png", "gif", "heic", "webp", "tiff", "svg", "raw", "psd"] { map[ext] = .image }
        return map
    }()
}
