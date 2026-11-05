import RocketCore
import SwiftUI

/// Native picker for a speed limit (Unlimited or a preset), for use inside menus.
public struct SpeedLimitPicker: View {
    let title: LocalizedStringKey
    let current: Int64?
    let set: (Int64?) -> Void

    public init(_ title: LocalizedStringKey = "Speed Limit", current: Int64?, set: @escaping (Int64?) -> Void) {
        self.title = title
        self.current = current
        self.set = set
    }

    public var body: some View {
        Picker(title, selection: Binding(get: { current }, set: set)) {
            Text("Unlimited").tag(Int64?.none)
            Divider()
            ForEach(options, id: \.self) { rate in
                Text(Format.speed(Double(rate))).tag(Int64?.some(rate))
            }
        }
        .pickerStyle(.inline)
    }

    /// Presets, plus the current value if it was set elsewhere (e.g. `rocket limit 3M`).
    private var options: [Int64] {
        guard let current, !ByteRate.presets.contains(current) else { return ByteRate.presets }
        return (ByteRate.presets + [current]).sorted()
    }
}
