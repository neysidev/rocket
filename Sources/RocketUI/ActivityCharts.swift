import Charts
import RocketCore
import RocketDesign
import SwiftUI

/// 16 bars, 2 pt wide, 14 pt tall; the latest in Ember.
struct Sparkline: View {
    let values: [Double]

    var body: some View {
        let peak = max(values.max() ?? 0, 1)
        HStack(alignment: .bottom, spacing: 1) {
            ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                Capsule()
                    .fill(index == values.count - 1 ? RocketColor.accent : RocketColor.chartNeutral)
                    .frame(width: 2, height: max(2, 14 * value / peak))
                    .animation(RocketMotion.progress, value: value)
            }
        }
        .frame(height: 14, alignment: .bottom)
        .accessibilityHidden(true)
    }
}

/// 24 hourly bars of completed bytes; the current hour in Ember. No gridlines, two captions.
struct ThroughputCard: View {
    let buckets: [Int64]

    var body: some View {
        VStack(alignment: .leading, spacing: RocketSpace.s3) {
            HStack {
                Text("Last 24 hours").font(.rocketHeadline).foregroundStyle(RocketColor.textPrimary)
                Spacer()
                Text(Format.bytes(buckets.reduce(0, +)))
                    .font(.rocketLabel)
                    .foregroundStyle(RocketColor.textSecondary)
                    .monospacedDigit()
            }
            if buckets.allSatisfy({ $0 == 0 }) {
                Capsule().fill(RocketColor.track).frame(height: 2).padding(.top, 40)
                Text("No downloads in the last 24 hours")
                    .font(.rocketCaption)
                    .foregroundStyle(RocketColor.textTertiary)
            } else {
                Chart(Array(buckets.enumerated()), id: \.offset) { hour, bytes in
                    BarMark(x: .value("Hour", hour), y: .value("Bytes", bytes), width: .fixed(10))
                        .foregroundStyle(hour == buckets.count - 1 ? RocketColor.accent : RocketColor.chartNeutral)
                        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 2, topTrailingRadius: 2))
                }
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .frame(height: 56)
                .accessibilityLabel(summary)
                HStack {
                    Text(Date.now.addingTimeInterval(-23 * 3600), format: .dateTime.hour())
                    Spacer()
                    Text("Now")
                }
                .font(.rocketCaption)
                .foregroundStyle(RocketColor.textTertiary)
            }
        }
        .padding(RocketSpace.s4)
        .rocketCard()
    }

    private var summary: String {
        guard let peak = buckets.indices.max(by: { buckets[$0] < buckets[$1] }) else { return "" }
        let hour = Date.now.addingTimeInterval(Double(peak - 23) * 3600).formatted(.dateTime.hour())
        return String(localized: "Peak \(Format.bytes(buckets[peak])) at \(hour)")
    }
}
