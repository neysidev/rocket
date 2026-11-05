import AppKit
import Foundation
import os
import RocketCore
import UserNotifications

/// Native notifications on completion and failure, with Open / Show in Finder / Retry actions (FR-APP-05).
@MainActor
public final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    enum Category: String {
        case completed = "download.completed"
        case failed = "download.failed"
        case copiedLinks = "clipboard.links"
    }

    enum Action: String {
        case open = "download.open"
        case reveal = "download.reveal"
        case retry = "download.retry"
        case review = "clipboard.review"
    }

    private let center: UNUserNotificationCenter
    private let downloads: DownloadsModel
    /// Settings toggle; checked each time.
    private let isEnabled: () -> Bool
    private let log = Rocket.logger("UI")

    public init(downloads: DownloadsModel, center: UNUserNotificationCenter = .current(), isEnabled: @escaping () -> Bool = { true }) {
        self.downloads = downloads
        self.center = center
        self.isEnabled = isEnabled
        super.init()
        center.delegate = self
        center.setNotificationCategories([
            UNNotificationCategory(identifier: Category.completed.rawValue, actions: [
                UNNotificationAction(identifier: Action.open.rawValue, title: String(localized: "Open"), options: .foreground),
                UNNotificationAction(identifier: Action.reveal.rawValue, title: String(localized: "Show in Finder"), options: .foreground),
            ], intentIdentifiers: []),
            UNNotificationCategory(identifier: Category.failed.rawValue, actions: [
                UNNotificationAction(identifier: Action.retry.rawValue, title: String(localized: "Retry")),
            ], intentIdentifiers: []),
            UNNotificationCategory(identifier: Category.copiedLinks.rawValue, actions: [
                UNNotificationAction(identifier: Action.review.rawValue, title: String(localized: "Download…"), options: .foreground),
            ], intentIdentifiers: []),
        ])
    }

    public func post(_ event: DownloadEvent) {
        guard isEnabled() else { return }
        deliver(Self.request(for: event))
    }

    /// The clipboard watcher's prompt (FR-INT-03). Its own opt-in, so the completion toggle does not apply.
    public func offer(copied links: [URL]) {
        deliver(Self.request(offering: links))
    }

    static func request(offering links: [URL]) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = links.count == 1 ? String(localized: "Download copied link?") : String(localized: "Download \(links.count) copied links?")
        content.body = links.map { $0.lastPathComponent }.joined(separator: ", ")
        content.categoryIdentifier = Category.copiedLinks.rawValue
        content.userInfo = ["links": links.map(\.absoluteString)]
        return UNNotificationRequest(identifier: "clipboard", content: content, trigger: nil)
    }

    private func deliver(_ request: UNNotificationRequest) {
        log.notice("Notifying \(request.content.categoryIdentifier, privacy: .public)")
        Task {
            let granted: Bool
            do {
                granted = try await center.requestAuthorization(options: [.alert, .sound])
            } catch {
                log.error("Notification authorization failed: \(error.localizedDescription, privacy: .public)")
                return
            }
            guard granted else { return log.notice("Notifications not allowed; skipping") }
            do {
                try await center.add(request)
                log.notice("Posted notification \(request.content.categoryIdentifier, privacy: .public)")
            } catch {
                log.error("Notification failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    static func request(for event: DownloadEvent) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        let download: Download
        switch event {
        case .completed(let completed):
            download = completed
            content.title = String(localized: "Download complete")
            content.body = download.fileName
            if let size = download.totalBytes { content.subtitle = Format.bytes(size) }
            content.categoryIdentifier = Category.completed.rawValue
        case .queueFinished(let queue):
            let content = UNMutableNotificationContent()
            content.title = String(localized: "Queue finished")
            content.body = String(localized: "Everything in \(queue.name) is done.")
            return UNNotificationRequest(identifier: "queue-\(queue.id)", content: content, trigger: nil)
        case .failed(let failed):
            download = failed
            content.title = String(localized: "Download failed")
            content.body = download.fileName
            content.subtitle = download.failure?.userMessage ?? ""
            content.categoryIdentifier = Category.failed.rawValue
        }
        content.userInfo = ["id": download.id.uuidString]
        return UNNotificationRequest(identifier: download.id.uuidString, content: content, trigger: nil)
    }

    // MARK: UNUserNotificationCenterDelegate

    public nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list]
    }

    public nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let action = response.actionIdentifier
        if let links = response.notification.request.content.userInfo["links"] as? [String] {
            // Through rocket://add, so the add sheet opens in the main window (creating it if it was closed).
            guard action != UNNotificationDismissActionIdentifier else { return }
            let urls = links.compactMap(URL.init(string:))
            await MainActor.run { _ = NSWorkspace.shared.open(RocketURLRequest.url(adding: urls)) }
            return
        }
        guard let id = (response.notification.request.content.userInfo["id"] as? String).flatMap(UUID.init) else { return }
        await handle(action: action, id: id)
    }

    func handle(action: String, id: UUID) async {
        switch Action(rawValue: action) {
        case .open: downloads.open(id)
        case .reveal: downloads.reveal([id])
        case .retry: await downloads.resume([id])
        case .review: break // clipboard offers carry links, not an id; handled above
        case nil: // clicked the notification itself
            downloads.filter = .all
            downloads.selection = [id]
        }
    }
}
