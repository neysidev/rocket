import Foundation

/// An ordered list of downloads with its own concurrency limit, speed limit and schedule (FR-QUE).
public struct DownloadQueue: Codable, Sendable, Identifiable, Hashable {
    public static let defaultID = "default"

    public var id: String
    public var name: String
    /// Simultaneous downloads (FR-QUE-02).
    public var maxActive: Int
    /// When the queue may run; nil = always (FR-QUE-04).
    public var schedule: QueueSchedule?
    /// What happens after the queue runs dry (FR-QUE-05).
    public var postAction: PostQueueAction
    public var shortcutName: String?
    /// Bytes per second for the whole queue (FR-SPD-02); nil = unlimited.
    public var speedLimit: Int64?
    public var sortOrder: Int

    public init(
        id: String = UUID().uuidString, name: String, maxActive: Int = 3, schedule: QueueSchedule? = nil,
        postAction: PostQueueAction = .none, shortcutName: String? = nil, speedLimit: Int64? = nil, sortOrder: Int = 0
    ) {
        self.id = id
        self.name = name
        self.maxActive = maxActive
        self.schedule = schedule
        self.postAction = postAction
        self.shortcutName = shortcutName
        self.speedLimit = speedLimit
        self.sortOrder = sortOrder
    }

    public var isDefault: Bool { id == Self.defaultID }

    enum CodingKeys: String, CodingKey {
        case id, name, maxActive, postAction, shortcutName, speedLimit, sortOrder
        case schedule = "scheduleJSON"
    }
}

/// Daily window on chosen weekdays. A window whose stop is before its start runs overnight (01:00–07:00 fine,
/// 22:00–06:00 too: it belongs to the weekday it starts on).
public struct QueueSchedule: Codable, Sendable, Hashable {
    /// Minutes since midnight.
    public var start: Int
    public var stop: Int
    /// Calendar weekdays, 1 = Sunday … 7 = Saturday.
    public var weekdays: Set<Int>

    public init(start: Int, stop: Int, weekdays: Set<Int> = Set(1...7)) {
        self.start = start
        self.stop = stop
        self.weekdays = weekdays
    }

    public func isOpen(at date: Date, calendar: Calendar = .current) -> Bool {
        let parts = calendar.dateComponents([.weekday, .hour, .minute], from: date)
        let minute = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        let weekday = parts.weekday ?? 1
        if start == stop { return weekdays.contains(weekday) }
        if start < stop { return weekdays.contains(weekday) && minute >= start && minute < stop }
        // Overnight: evening part today, or morning part of a window that started yesterday.
        let yesterday = weekday == 1 ? 7 : weekday - 1
        return (weekdays.contains(weekday) && minute >= start) || (weekdays.contains(yesterday) && minute < stop)
    }

    /// "01:00–07:00, Mon–Fri"
    public var summary: String {
        func time(_ minutes: Int) -> String { String(format: "%02d:%02d", minutes / 60, minutes % 60) }
        let days: String
        switch weekdays {
        case Set(1...7): days = String(localized: "every day")
        case Set(2...6): days = String(localized: "weekdays")
        case [1, 7]: days = String(localized: "weekends")
        default:
            let symbols = Calendar.current.shortWeekdaySymbols
            days = weekdays.sorted().map { symbols[$0 - 1] }.joined(separator: " ")
        }
        return "\(time(start))–\(time(stop)), \(days)"
    }
}

public enum PostQueueAction: String, Codable, Sendable, CaseIterable {
    case none, notify, sleep, shutDown, quitRocket, runShortcut

    public var title: String {
        switch self {
        case .none: String(localized: "Do nothing")
        case .notify: String(localized: "Notify me")
        case .sleep: String(localized: "Sleep")
        case .shutDown: String(localized: "Shut down")
        case .quitRocket: String(localized: "Quit Rocket")
        case .runShortcut: String(localized: "Run Shortcut")
        }
    }
}

/// Persistence port for queues; the default queue always exists.
public protocol QueueRepository: Sendable {
    func queues() async throws -> [DownloadQueue]
    func save(_ queue: DownloadQueue) async throws
    func deleteQueue(id: String) async throws
}

/// When the agent keeps the Mac awake while downloading (FR-QUE-06).
public enum SleepPrevention: String, Codable, Sendable, CaseIterable {
    case never, onPower, always

    public var title: String {
        switch self {
        case .never: String(localized: "Never")
        case .onPower: String(localized: "On power adapter only")
        case .always: String(localized: "Always")
        }
    }
}
