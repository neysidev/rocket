import AppKit
import Foundation
import RocketCore
import RocketDesign
@testable import RocketUI
import SwiftUI
import Testing

/// Renders rows offscreen in both appearances. Set ROCKET_RENDER_DIR to keep the PNGs for review.
@MainActor
@Suite struct RenderTests {
    static func sample(_ name: String, _ state: DownloadState, _ received: Int64, _ total: Int64, failure: DownloadError? = nil) -> DownloadItem {
        var download = Download(url: URL(string: "https://example.com/\(name)")!, destinationPath: "/tmp", fileName: name, state: state)
        download.totalBytes = total
        download.receivedBytes = received
        download.failure = failure
        return DownloadItem(download: download, speed: state == .downloading ? 84_300_000 : 0)
    }

    static let items = [
        sample("ubuntu-24.04-desktop-amd64.iso", .downloading, 3_700_000_000, 6_000_000_000),
        sample("Footage pack.mov", .paused, 1_200_000_000, 4_800_000_000),
        sample("sample-library.zip", .queued, 0, 900_000_000),
        sample("paper.pdf", .completed, 2_000_000, 2_000_000),
        sample("dataset.tar.gz", .failed, 10_000_000, 50_000_000, failure: .http(status: 404)),
    ]

    @Test(arguments: [NSAppearance.Name.aqua, .darkAqua])
    func rowsRender(appearance: NSAppearance.Name) throws {
        let model = DownloadsModel()
        let view = VStack(spacing: 0) {
            ForEach(Self.items) { item in
                DownloadRow(item: item, model: model)
                    .padding(.horizontal, RocketSpace.s4)
                    .padding(.vertical, RocketSpace.s3)
            }
        }
        .frame(width: 640)
        .background(RocketColor.canvas)
        .environment(\.colorScheme, appearance == .darkAqua ? .dark : .light)

        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        var image: CGImage?
        NSAppearance(named: appearance)!.performAsCurrentDrawingAppearance { image = renderer.cgImage }
        let rendered = try #require(image)
        #expect(rendered.width == 1280)

        if let dir = ProcessInfo.processInfo.environment["ROCKET_RENDER_DIR"] {
            let url = URL(filePath: dir).appending(path: "rows-\(appearance.rawValue).png")
            let rep = NSBitmapImageRep(cgImage: rendered)
            try rep.representation(using: .png, properties: [:])!.write(to: url)
        }
    }
}
