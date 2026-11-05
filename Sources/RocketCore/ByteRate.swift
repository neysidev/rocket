import Foundation

/// Parses rates typed by people: "2M", "2MB", "2 MB/s", "500k", "1.5G", "1048576". Decimal units, like Finder.
public enum ByteRate {
    public static func parse(_ text: String) -> Int64? {
        var value = text.lowercased().replacingOccurrences(of: " ", with: "")
        for suffix in ["/s", "ps", "b"] where value.hasSuffix(suffix) { value.removeLast(suffix.count) }
        let multipliers: [Character: Double] = ["k": 1e3, "m": 1e6, "g": 1e9]
        var multiplier = 1.0
        if let last = value.last, let factor = multipliers[last] {
            multiplier = factor
            value.removeLast()
        }
        guard let number = Double(value), number > 0 else { return nil }
        return Int64(number * multiplier)
    }

    /// Presets offered in speed-limit menus.
    public static let presets: [Int64] = [500_000, 1_000_000, 2_000_000, 5_000_000, 10_000_000, 50_000_000]
}
