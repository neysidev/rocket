import RocketCore
import RocketDesign
import SwiftUI

/// Name, limits, schedule and after-action for one queue (FR-QUE-01/02/04/05, FR-SPD-02).
public struct QueueEditor: View {
    @State private var queue: DownloadQueue
    let onSave: (DownloadQueue) -> Void
    @Environment(\.rocketDismiss) private var dismiss

    public init(queue: DownloadQueue, onSave: @escaping (DownloadQueue) -> Void) {
        _queue = State(initialValue: queue)
        self.onSave = onSave
    }

    public var body: some View {
        RocketModalLayout(queue.isDefault ? String(localized: "Default queue") : String(localized: "Edit queue")) {
            Form {
                Group {
                    RocketFormSection {
                        RocketFormRow(String(localized: "Name")) {
                            TextField("Name", text: $queue.name).rocketField().frame(width: 200)
                        }
                        RocketFormRow(String(localized: "Downloads at a time")) {
                            RocketStepper(String(localized: "Downloads at a time"), value: $queue.maxActive, in: 1...16)
                        }
                        RocketFormRow(String(localized: "Speed limit")) {
                            RocketSelect(String(localized: "Speed limit"), selection: $queue.speedLimit,
                                         groups: SpeedLimitOptions.selectGroups(current: queue.speedLimit))
                                .fixedSize()
                        }
                    }
                    RocketFormSection(String(localized: "Schedule"), footer: overnight ? String(localized: "Runs overnight, until the next morning.") : nil) {
                        RocketFormRow(String(localized: "Run only on a schedule")) {
                            Toggle("Run only on a schedule", isOn: Binding(
                                get: { queue.schedule != nil },
                                set: { queue.schedule = $0 ? QueueSchedule(start: 60, stop: 7 * 60) : nil }
                            ))
                            .labelsHidden()
                            .toggleStyle(.rocketSwitch)
                        }
                        if queue.schedule != nil {
                            RocketFormRow(String(localized: "Start")) { TimeSelect(label: String(localized: "Start"), minutes: time(\.start)) }
                            RocketFormRow(String(localized: "Stop")) { TimeSelect(label: String(localized: "Stop"), minutes: time(\.stop)) }
                            RocketFormRow(String(localized: "Days")) { WeekdayPicker(days: weekdays) }
                        }
                    }
                    RocketFormSection(String(localized: "When the queue finishes")) {
                        RocketFormRow(String(localized: "Then")) {
                            RocketSelect(String(localized: "When the queue finishes"), selection: $queue.postAction,
                                         options: PostQueueAction.allCases.map { RocketOption($0, $0.title) })
                                .fixedSize()
                        }
                        if queue.postAction == .runShortcut {
                            RocketFormRow(String(localized: "Shortcut")) {
                                TextField("Shortcut name", text: Binding(get: { queue.shortcutName ?? "" }, set: { queue.shortcutName = $0 }),
                                          prompt: Text("Shortcut name"))
                                    .rocketField()
                                    .frame(width: 200)
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .frame(height: 440)
        } actions: {
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button("Save") {
                onSave(queue)
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(queue.name.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .frame(width: 480)
    }

    private var overnight: Bool {
        guard let schedule = queue.schedule else { return false }
        return schedule.stop < schedule.start
    }

    /// Minutes since midnight of the schedule's start or stop.
    private func time(_ keyPath: WritableKeyPath<QueueSchedule, Int>) -> Binding<Int> {
        Binding { queue.schedule?[keyPath: keyPath] ?? 0 } set: { queue.schedule?[keyPath: keyPath] = $0 }
    }

    private var weekdays: Binding<Set<Int>> {
        Binding { queue.schedule?.weekdays ?? [] } set: { queue.schedule?.weekdays = $0 }
    }
}

/// Seven toggle buttons, in the locale's week order.
struct WeekdayPicker: View {
    @Binding var days: Set<Int>

    var body: some View {
        let calendar = Calendar.current
        let order = (0..<7).map { (calendar.firstWeekday - 1 + $0) % 7 + 1 }
        HStack(spacing: 2) {
            ForEach(order, id: \.self) { day in
                Toggle(calendar.veryShortWeekdaySymbols[day - 1], isOn: Binding(
                    get: { days.contains(day) },
                    set: { if $0 { days.insert(day) } else { days.remove(day) } }
                ))
                .toggleStyle(.button)
                .controlSize(.small)
                .accessibilityLabel(calendar.weekdaySymbols[day - 1])
            }
        }
    }
}

/// Time of day in 15-minute steps, plus the current value if it is off the grid (set from the CLI).
struct TimeSelect: View {
    let label: String
    @Binding var minutes: Int

    var body: some View {
        let steps = Set(stride(from: 0, to: 24 * 60, by: 15)).union([minutes]).sorted()
        RocketSelect(label, selection: $minutes, options: steps.map { RocketOption($0, Self.title($0)) })
            .fixedSize()
    }

    static func title(_ minutes: Int) -> String {
        let date = Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: .now) ?? .now
        return date.formatted(date: .omitted, time: .shortened)
    }
}
