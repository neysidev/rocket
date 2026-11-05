import RocketCore
import RocketDesign
import SwiftUI

/// Speed limit choices (Unlimited or a preset) for Rocket menus and selects.
public enum SpeedLimitOptions {
    /// Presets, plus the current value if it was set elsewhere (e.g. `rocket limit 3M`).
    static func rates(including current: Int64?) -> [Int64] {
        guard let current, !ByteRate.presets.contains(current) else { return ByteRate.presets }
        return (ByteRate.presets + [current]).sorted()
    }

    @MainActor
    public static func menuItems(current: Int64?, set: @escaping (Int64?) -> Void) -> [RocketMenuItem] {
        [RocketMenuItem(String(localized: "Unlimited"), checked: current == nil) { set(nil) }]
            + rates(including: current).map { rate in
                RocketMenuItem(Format.speed(Double(rate)), checked: current == rate) { set(rate) }
            }
    }

    public static func selectGroups(current: Int64?, unlimited: String = String(localized: "Unlimited")) -> [[RocketOption<Int64?>]] {
        [[RocketOption(nil, unlimited)], rates(including: current).map { RocketOption(Optional($0), Format.speed(Double($0))) }]
    }
}
