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

    @Test func addSheetRenders() async throws {
        let model = AddDownloadsModel(
            text: "https://releases.example.com/ubuntu-24.04-desktop-amd64.iso\nhttps://broken.example/x.zip\nhttps://example.com/paper.pdf",
            folder: URL(filePath: "/Users/me/Downloads", directoryHint: .isDirectory), agent: ProbingAgent(), existing: [],
            fileExists: { $0.lastPathComponent == "paper.pdf" }
        )
        await model.review()
        let view = AddDownloadsSheet(model: model) { _ in }
            .background(RocketColor.panel)
            .environment(\.colorScheme, .dark)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        var image: CGImage?
        NSAppearance(named: .darkAqua)!.performAsCurrentDrawingAppearance { image = renderer.cgImage }
        let rendered = try #require(image)
        if let dir = ProcessInfo.processInfo.environment["ROCKET_RENDER_DIR"] {
            try NSBitmapImageRep(cgImage: rendered).representation(using: .png, properties: [:])!
                .write(to: URL(filePath: dir).appending(path: "add-sheet.png"))
        }
    }

    @Test(arguments: [NSAppearance.Name.aqua, .darkAqua])
    func menuBarPanelRenders(appearance: NSAppearance.Name) throws {
        let model = DownloadsModel()
        var history = Self.items.map(\.download)
        for hoursAgo in [0.3, 2.2, 3.1, 7, 12, 13, 20] {
            var done = Self.sample("old-\(hoursAgo).zip", .completed, 0, Int64(hoursAgo * 400_000_000)).download
            done.completedAt = Date.now.addingTimeInterval(-hoursAgo * 3600)
            history.append(done)
        }
        model.queues = [
            DownloadQueue(id: "default", name: "Default"),
            DownloadQueue(id: "night", name: "Night", schedule: QueueSchedule(start: 60, stop: 420), postAction: .sleep),
        ]
        history[2].queueID = "night"
        model.apply(history, now: .now)
        model.apply(history.map { var d = $0; if d.state == .downloading { d.receivedBytes += 84_000_000 }; return d }, now: .now + .seconds(1))
        let view = MenuBarPanel(model: model) {}
            .background(RocketColor.panel)
            .environment(\.colorScheme, appearance == .darkAqua ? .dark : .light)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        var image: CGImage?
        NSAppearance(named: appearance)!.performAsCurrentDrawingAppearance { image = renderer.cgImage }
        let rendered = try #require(image)
        if let dir = ProcessInfo.processInfo.environment["ROCKET_RENDER_DIR"] {
            try NSBitmapImageRep(cgImage: rendered).representation(using: .png, properties: [:])!
                .write(to: URL(filePath: dir).appending(path: "panel-\(appearance.rawValue).png"))
        }
    }

    @Test func detailPartsRender() throws {
        let mib: Int64 = 1 << 20
        let segments = [
            Segment(start: 0, end: 4 * mib - 1, received: 4 * mib), Segment(start: 4 * mib, end: 6 * mib - 1, received: mib),
            Segment(start: 6 * mib, end: 8 * mib - 1, received: mib / 2), Segment(start: 8 * mib, end: 16 * mib - 1, received: 3 * mib),
        ]
        let samples = (0..<300).map { 40_000_000 + 30_000_000 * sin(Double($0) / 25) }
        let view = VStack(alignment: .leading, spacing: 16) {
            SegmentsBar(segments: segments, total: 16 * mib, live: true)
            SpeedChart(samples: samples)
            LogList(entries: [
                LogEntry(message: "Added: 16777216 bytes, resumable"),
                LogEntry(message: "Downloading with up to 8 connections"),
                LogEntry(message: "Connection 3: The server is busy (503). Retrying in 1.2s (attempt 2 of 5)."),
                LogEntry(message: "Failed: The disk is full.", isError: true),
            ])
        }
        .padding(16)
        .frame(width: 300)
        .background(RocketColor.canvas)
        .environment(\.colorScheme, .dark)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        var image: CGImage?
        NSAppearance(named: .darkAqua)!.performAsCurrentDrawingAppearance { image = renderer.cgImage }
        let rendered = try #require(image)
        if let dir = ProcessInfo.processInfo.environment["ROCKET_RENDER_DIR"] {
            try NSBitmapImageRep(cgImage: rendered).representation(using: .png, properties: [:])!
                .write(to: URL(filePath: dir).appending(path: "detail.png"))
        }
    }
}
