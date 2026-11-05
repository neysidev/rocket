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
    }

    enum Action: String {
        case open = "download.open"
        case reveal = "download.reveal"
        case retry = "download.retry"
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
        ])
    }

    public func post(_ event: DownloadEvent) {
        guard isEnabled() else { return }
        let request = Self.request(for: event)
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
        case .failed(let failed):
            download = failed
            content.title = String(localized: "Download failed")
            content.body = download.fileName
            content.subtitle = download.failure?.userMessage ?? ""
            content.categoryIdentifier = Category.failed.rawValue
            content.sound = .default
        }
        content.userInfo = ["id": download.id.uuidString]
        return UNNotificationRequest(identifier: download.id.uuidString, content: content, trigger: nil)
    }

    // MARK: UNUserNotificationCenterDelegate

    public nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    public nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let action = response.actionIdentifier
        guard let id = (response.notification.request.content.userInfo["id"] as? String).flatMap(UUID.init) else { return }
        await handle(action: action, id: id)
    }

    func handle(action: String, id: UUID) async {
        switch Action(rawValue: action) {
        case .open: downloads.open(id)
        case .reveal: downloads.reveal([id])
        case .retry: await downloads.resume([id])
        case nil: // clicked the notification itself
            downloads.filter = .all
            downloads.selection = [id]
        }
    }
}
