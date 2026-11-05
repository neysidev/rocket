import AppKit
import Foundation
import RocketCore
import RocketDesign
@testable import RocketUI
import SwiftUI
import Testing

/// Renders whole screens through AppKit (text fields, scroll views and tasks included) in both appearances.
/// Set ROCKET_RENDER_DIR to keep the PNGs for visual review.
@MainActor
@Suite struct ScreenRenderTests {
    static func model() -> DownloadsModel {
        let model = DownloadsModel()
        model.queues = [
            DownloadQueue(id: "default", name: "Default"),
            DownloadQueue(id: "night", name: "Night", schedule: QueueSchedule(start: 60, stop: 420), postAction: .sleep),
        ]
        model.rules = [
            DownloadRule(name: "Linux ISOs", match: RuleMatch(domains: ["releases.ubuntu.com"], extensions: ["iso"]),
                         action: RuleAction(folderPath: "/Users/me/Linux", queueID: "night")),
            DownloadRule(name: "Big files", enabled: false, match: RuleMatch(minBytes: 1_000_000_000), action: RuleAction(connections: 16)),
        ]
        var history = RenderTests.items.map(\.download)
        history[2].queueID = "night"
        model.apply(history, now: .now)
        model.apply(history.map { var d = $0; if d.state == .downloading { d.receivedBytes += 84_000_000 }; return d }, now: .now + .seconds(1))
        model.selection = [history[1].id]
        return model
    }

    /// Hosts the view in an offscreen window so AppKit-backed controls draw, lets tasks run, then snapshots it.
    static func snapshot(_ view: some View, size: CGSize, name: String, appearance: NSAppearance.Name) async throws {
        let hosting = NSHostingView(rootView: view.environment(\.colorScheme, appearance == .darkAqua ? .dark : .light))
        let window = NSWindow(contentRect: CGRect(origin: CGPoint(x: -10_000, y: 0), size: size), styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: appearance)
        window.contentView = hosting
        window.orderFrontRegardless()
        try await Task.sleep(for: .milliseconds(400))
        hosting.layoutSubtreeIfNeeded()
        let rep = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        window.orderOut(nil)
        #expect(rep.pixelsWide > 0)
        let suffix = appearance == .darkAqua ? "dark" : "light"
        try RenderExport.writePNG(rep, named: "\(name)-\(suffix).png")
    }

    static func main(_ model: DownloadsModel) -> some View {
        HStack(spacing: 0) {
            DownloadSidebar(model: model) { EmptyView() }.frame(width: RocketSize.sidebarWidth)
            DownloadListView(model: model)
        }
        .background(RocketColor.canvas)
    }

    @Test(arguments: [NSAppearance.Name.aqua, .darkAqua])
    func mainWindowRenders(appearance: NSAppearance.Name) async throws {
        let model = Self.model()
        try await Self.snapshot(Self.main(model), size: CGSize(width: 1080, height: 640), name: "main-list", appearance: appearance)
        model.viewMode = .grid
        try await Self.snapshot(Self.main(model), size: CGSize(width: 1080, height: 640), name: "main-grid", appearance: appearance)
        model.viewMode = .list
        model.filter = .failed
        model.search = "nothing"
        try await Self.snapshot(Self.main(model), size: CGSize(width: 900, height: 480), name: "main-empty", appearance: appearance)
    }

    @Test(arguments: [NSAppearance.Name.aqua, .darkAqua])
    func dialogsRender(appearance: NSAppearance.Name) async throws {
        let model = Self.model()
        let id = model.items[0].id
        let detail = DownloadDetailView(model: model, id: id).frame(width: 540).rocketFloating(radius: RocketRadius.modal)
        try await Self.snapshot(detail.padding(30).background(RocketColor.canvas), size: CGSize(width: 600, height: 660), name: "details", appearance: appearance)

        let queue = QueueEditor(queue: model.queues[1]) { _ in }.rocketFloating(radius: RocketRadius.modal)
        try await Self.snapshot(queue.padding(30).background(RocketColor.canvas), size: CGSize(width: 540, height: 640), name: "queue-editor", appearance: appearance)

        let adding = AddDownloadsModel(text: "https://releases.example.com/ubuntu-24.04-desktop-amd64.iso",
                                       folder: URL(filePath: "/Users/me/Downloads", directoryHint: .isDirectory), agent: ProbingAgent(), existing: [])
        let add = AddDownloadsSheet(model: adding) { _ in }.rocketFloating(radius: RocketRadius.modal)
        try await Self.snapshot(add.padding(30).background(RocketColor.canvas), size: CGSize(width: 680, height: 420), name: "add-input", appearance: appearance)

        let review = AddDownloadsModel(
            text: "https://releases.example.com/ubuntu-24.04-desktop-amd64.iso\nhttps://broken.example/x.zip\nhttps://example.com/paper.pdf",
            folder: URL(filePath: "/Users/me/Downloads", directoryHint: .isDirectory), agent: ProbingAgent(), existing: [],
            fileExists: { $0.lastPathComponent == "paper.pdf" }
        )
        await review.review()
        let reviewSheet = AddDownloadsSheet(model: review) { _ in }.rocketFloating(radius: RocketRadius.modal)
        try await Self.snapshot(reviewSheet.padding(30).background(RocketColor.canvas), size: CGSize(width: 680, height: 560), name: "add-review", appearance: appearance)

        let menu = RocketMenuContent(sections: DownloadMenu.sections(ids: [model.items[3].id], model: model))
        try await Self.snapshot(menu.padding(30).background(RocketColor.canvas), size: CGSize(width: 320, height: 420), name: "menu", appearance: appearance)

        let alert = Color.clear.rocketAlert(.constant("The disk is full. Free up space and resume the download."))
        try await Self.snapshot(alert, size: CGSize(width: 500, height: 300), name: "alert", appearance: appearance)
    }

    @Test(arguments: [NSAppearance.Name.aqua, .darkAqua])
    func settingsRender(appearance: NSAppearance.Name) async throws {
        let model = Self.model()
        try await Self.snapshot(SettingsView(model: model), size: CGSize(width: 760, height: 580), name: "settings-general", appearance: appearance)
        let pages = VStack(alignment: .leading, spacing: 24) {
            NetworkSettings(settings: model.settings)
            RulesSettings(model: model, editing: .constant(nil))
        }
        .padding(32)
        .frame(width: 560)
        .background(RocketColor.canvas)
        try await Self.snapshot(pages, size: CGSize(width: 560, height: 600), name: "settings-pages", appearance: appearance)
        let editor = RuleEditor(rule: model.rules[0], queues: model.queues) { _ in }.rocketFloating(radius: RocketRadius.modal)
        try await Self.snapshot(editor.padding(30).background(RocketColor.canvas), size: CGSize(width: 560, height: 580), name: "rule-editor", appearance: appearance)
    }
}
