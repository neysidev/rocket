import Charts
import RocketCore
import RocketDesign
import SwiftUI

/// Throughput, totals, category mix and top sources (FR-APP insights).
public struct DownloadInsightsView: View {
    @Bindable var model: DownloadsModel
    @Environment(\.rocketDismiss) private var dismiss

    public init(model: DownloadsModel) {
        self.model = model
    }

    public var body: some View {
        let stats = model.statistics
        RocketModalLayout(String(localized: "Download Insights")) {
            ScrollView {
                VStack(alignment: .leading, spacing: RocketSpace.s5) {
                    HStack(spacing: RocketSpace.s3) {
                        insightStat(String(localized: "Completed"), value: "\(stats.completedCount)", detail: Format.bytes(stats.totalCompletedBytes))
                        insightStat(String(localized: "Active"), value: "\(stats.activeCount)", detail: model.isDownloading ? Format.speed(model.totalSpeed) : String(localized: "Idle"))
                        insightStat(String(localized: "Queued"), value: "\(stats.queuedCount)", detail: stats.failedCount > 0 ? String(localized: "\(stats.failedCount) failed") : nil)
                    }
                    ThroughputCard(buckets: model.hourlyThroughput())
                    categorySection(stats)
                    sourcesSection(stats)
                    HStack(spacing: RocketSpace.s2) {
                        Sparkline(values: model.speedHistory)
                        Text(model.isDownloading ? Format.speed(model.totalSpeed) : String(localized: "No live traffic"))
                            .font(.rocketCaption)
                            .foregroundStyle(RocketColor.textSecondary)
                            .monospacedDigit()
                    }
                    .padding(RocketSpace.s4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .rocketCard()
                }
                .padding(.horizontal, RocketSpace.s6)
                .padding(.bottom, RocketSpace.s5)
            }
            .frame(height: 480)
        } actions: {
            Button("Done") { dismiss() }
                .buttonStyle(.rocketPrimary)
                .keyboardShortcut(.defaultAction)
        }
        .frame(width: 560)
    }

    private func insightStat(_ label: String, value: String, detail: String?) -> some View {
        VStack(alignment: .leading, spacing: RocketSpace.s2) {
            Text(label).font(.rocketLabel).foregroundStyle(RocketColor.textSecondary)
            Text(value).font(.rocketMetricLarge).foregroundStyle(RocketColor.textPrimary).monospacedDigit()
            if let detail {
                Text(detail).font(.rocketCaption).foregroundStyle(RocketColor.textTertiary).lineLimit(1)
            }
        }
        .padding(RocketSpace.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .rocketCard()
    }

    @ViewBuilder
    private func categorySection(_ stats: DownloadStatistics) -> some View {
        let categories = FileCategory.allCases.filter { stats.countByCategory[$0, default: 0] > 0 }
        if categories.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: RocketSpace.s3) {
                Text("By type").font(.rocketHeadline).foregroundStyle(RocketColor.textPrimary)
                Chart(categories, id: \.self) { category in
                    BarMark(x: .value("Bytes", stats.bytesByCategory[category, default: 0]))
                        .foregroundStyle(RocketColor.chartNeutral)
                        .annotation(position: .overlay, alignment: .leading) {
                            Label(category.title, systemImage: category.symbol)
                                .font(.rocketCaption)
                                .foregroundStyle(RocketColor.textPrimary)
                                .padding(.leading, RocketSpace.s2)
                        }
                }
                .chartXAxis(.hidden)
                .frame(height: CGFloat(categories.count) * 28)
                .accessibilityLabel(String(localized: "Completed data by file type"))
            }
            .padding(RocketSpace.s4)
            .rocketCard()
        }
    }

    @ViewBuilder
    private func sourcesSection(_ stats: DownloadStatistics) -> some View {
        if stats.topSources.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: RocketSpace.s3) {
                Text("Top sources").font(.rocketHeadline).foregroundStyle(RocketColor.textPrimary)
                ForEach(stats.topSources) { source in
                    Button {
                        model.sourceHost = source.host
                        model.filter = .all
                        dismiss()
                    } label: {
                        HStack {
                            Text(source.host).font(.rocketBody).foregroundStyle(RocketColor.textPrimary).lineLimit(1)
                            Spacer()
                            Text(Format.bytes(source.completedBytes))
                                .font(.rocketLabel.monospacedDigit())
                                .foregroundStyle(RocketColor.textSecondary)
                            Text("\(source.downloadCount)")
                                .font(.rocketCaption.monospacedDigit())
                                .foregroundStyle(RocketColor.textTertiary)
                        }
                    }
                    .buttonStyle(.plain)
                    .rocketFormRowChrome()
                }
            }
            .padding(RocketSpace.s4)
            .rocketCard()
        }
    }
}
