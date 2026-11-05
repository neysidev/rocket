import RocketCore
import RocketDesign
import SwiftUI

/// Name, limits, schedule and after-action for one queue (FR-QUE-01/02/04/05, FR-SPD-02).
public struct QueueEditor: View {
    @State private var queue: DownloadQueue
    let onSave: (DownloadQueue) -> Void
    @Environment(\.dismiss) private var dismiss

    public init(queue: DownloadQueue, onSave: @escaping (DownloadQueue) -> Void) {
        _queue = State(initialValue: queue)
        self.onSave = onSave
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: RocketSpace.s4) {
            Text(queue.isDefault ? "Default Queue" : "Queue")
                .font(.rocketTitle)
                .padding(.horizontal, RocketSpace.s6)
                .padding(.top, RocketSpace.s6)
            Form {
                Section {
                    TextField("Name", text: $queue.name)
                    Stepper("Downloads at a time: \(queue.maxActive)", value: $queue.maxActive, in: 1...16)
                    Picker("Speed limit", selection: $queue.speedLimit) {
                        Text("Unlimited").tag(Int64?.none)
                        ForEach(ByteRate.presets, id: \.self) { Text(Format.speed(Double($0))).tag(Int64?.some($0)) }
                    }
                }
                Section {
                    Toggle("Run only on a schedule", isOn: Binding(
                        get: { queue.schedule != nil },
                        set: { queue.schedule = $0 ? QueueSchedule(start: 60, stop: 7 * 60) : nil }
                    ))
                    if queue.schedule != nil {
                        DatePicker("Start", selection: time(\.start), displayedComponents: .hourAndMinute)
                        DatePicker("Stop", selection: time(\.stop), displayedComponents: .hourAndMinute)
                        LabeledContent("Days") { WeekdayPicker(days: weekdays) }
                        if let schedule = queue.schedule, schedule.stop < schedule.start {
                            Text("Runs overnight, until the next morning.")
                                .font(.rocketCaption)
                                .foregroundStyle(RocketColor.textSecondary)
                        }
                    }
                }
                Section {
                    Picker("When the queue finishes", selection: $queue.postAction) {
                        ForEach(PostQueueAction.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    if queue.postAction == .runShortcut {
                        TextField("Shortcut name", text: Binding(get: { queue.shortcutName ?? "" }, set: { queue.shortcutName = $0 }))
                    }
                }
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    onSave(queue)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(queue.name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding([.horizontal, .bottom], RocketSpace.s6)
        }
        .frame(width: 440)
    }

    /// Minutes since midnight ↔ a time-of-day Date for DatePicker.
    private func time(_ keyPath: WritableKeyPath<QueueSchedule, Int>) -> Binding<Date> {
        Binding {
            let minutes = queue.schedule?[keyPath: keyPath] ?? 0
            return Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: .now) ?? .now
        } set: { date in
            let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
            queue.schedule?[keyPath: keyPath] = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        }
    }

    private var weekdays: Binding<Set<Int>> {
        Binding { queue.schedule?.weekdays ?? [] } set: { queue.schedule?.weekdays = $0 }
    }
}

/// Seven toggle buttons, Monday first where the locale starts weeks on Monday.
struct WeekdayPicker: View {
    @Binding var days: Set<Int>

    var body: some View {
        let calendar = Calendar.current
        let order = (0..<7).map { (calendar.firstWeekday - 1 + $0) % 7 + 1 }
        HStack(spacing: RocketSpace.s1) {
            ForEach(order, id: \.self) { day in
                Toggle(calendar.veryShortWeekdaySymbols[day - 1], isOn: Binding(
                    get: { days.contains(day) },
                    set: { if $0 { days.insert(day) } else { days.remove(day) } }
                ))
                .toggleStyle(.button)
                .accessibilityLabel(calendar.weekdaySymbols[day - 1])
            }
        }
    }
}
