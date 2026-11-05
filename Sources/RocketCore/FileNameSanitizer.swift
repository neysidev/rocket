import Foundation

/// Turns an untrusted, server-supplied file name into a safe single path component (TRD threat model:
/// path traversal via `../` or absolute paths).
public enum FileNameSanitizer {
    public static let fallback = "download"

    public static func sanitize(_ name: String) -> String {
        // Keep only the last component of anything path-like, from either separator style.
        var result = name.split(whereSeparator: { $0 == "/" || $0 == "\\" }).last.map(String.init) ?? ""
        result = String(result.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) && $0 != ":" })
        result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        // No hidden files, no "." / "..".
        while result.hasPrefix(".") { result.removeFirst() }
        result = truncated(result, maxBytes: 240) // room for " 999" and ".rocketpart" within NAME_MAX
        return result.isEmpty ? fallback : result
    }

    /// True when `file` resolves to a direct child of `folder` (after resolving `..` and symlinks).
    public static func isInside(_ file: URL, folder: URL) -> Bool {
        let parent = file.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL.path
        return parent == folder.resolvingSymlinksInPath().standardizedFileURL.path
    }

    /// Shortens the base name, keeping the extension, so the UTF-8 size fits.
    private static func truncated(_ name: String, maxBytes: Int) -> String {
        guard name.utf8.count > maxBytes else { return name }
        let ext = (name as NSString).pathExtension
        var base = (name as NSString).deletingPathExtension
        let suffix = ext.isEmpty ? "" : "." + ext
        while !base.isEmpty, base.utf8.count + suffix.utf8.count > maxBytes { base.removeLast() }
        return base + suffix
    }
}
