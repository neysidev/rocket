import AppKit
import Foundation

/// When `ROCKET_RENDER_DIR` is set, writes PNG snapshots for manual visual review.
enum RenderExport {
    static func writePNG(_ rep: NSBitmapImageRep, named filename: String) throws {
        guard let dir = ProcessInfo.processInfo.environment["ROCKET_RENDER_DIR"] else { return }
        let folder = URL(filePath: dir)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try rep.representation(using: .png, properties: [:])!.write(to: folder.appending(path: filename))
    }

    static func writePNG(_ image: CGImage, named filename: String) throws {
        try writePNG(NSBitmapImageRep(cgImage: image), named: filename)
    }
}
