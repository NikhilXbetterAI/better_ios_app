import SwiftUI

struct InsightsSleepInsightsCard: View {
    let insights: [SleepInsight]

    var body: some View {
        BetterHealthCard {
            VStack(alignment: .leading, spacing: BetterSpacing.medium) {
                header

                if insights.isEmpty {
                    emptyState
                } else {
                    ForEach(insights.prefix(4)) { insight in
                        insightRow(insight)
                    }
                }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: BetterSpacing.small) {
            Image(systemName: "lightbulb.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(BetterColors.warning, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text("Sleep Insights")
                    .font(BetterTypography.subheadline)
                    .foregroundStyle(BetterColors.text)
                Text("Based on your most recent tracked night")
                    .font(BetterTypography.caption)
                    .foregroundStyle(BetterColors.subtext)
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        HStack(spacing: BetterSpacing.medium) {
            Image(systemName: "moon.zzz.fill")
                .font(.system(size: 22))
                .foregroundStyle(BetterColors.subtext)
            Text("Track more nights to receive personalized sleep insights.")
                .font(BetterTypography.footnote)
                .foregroundStyle(BetterColors.subtext)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, BetterSpacing.small)
    }

    // MARK: - Insight Row

    private func insightRow(_ insight: SleepInsight) -> some View {
        HStack(alignment: .top, spacing: BetterSpacing.small) {
            Image(systemName: iconName(for: insight.category))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(iconColor(for: insight.displayStyle), in: RoundedRectangle(cornerRadius: 7, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: BetterSpacing.xSmall) {
                    Text(insight.title)
                        .font(BetterTypography.footnote)
                        .foregroundStyle(BetterColors.text)
                    Spacer()
                    if let delta = insight.metricDelta, abs(delta.value) >= 1 {
                        deltaChip(delta)
                    }
                }
                Text(insight.body)
                    .font(BetterTypography.caption)
                    .foregroundStyle(BetterColors.subtext)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(BetterSpacing.medium)
        .background(BetterColors.cardSecondary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Delta Chip

    @ViewBuilder
    private func deltaChip(_ delta: SleepMetricDelta) -> some View {
        if delta.unit == "nights" {
            Text("\(Int(delta.value.rounded())) nights")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(BetterColors.brand)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(BetterColors.brand.opacity(0.14), in: Capsule())
        } else {
            let isPositive = delta.value > 0
            let color: Color = isPositive ? BetterColors.success : BetterColors.warning
            let symbol = isPositive ? "+" : ""
            let unitSuffix: String = {
                switch delta.unit {
                case "minutes": return "m"
                case "percentagePoints": return "pp"
                default: return ""
                }
            }()
            Text("\(symbol)\(Int(delta.value.rounded()))\(unitSuffix)")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(color)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(color.opacity(0.14), in: Capsule())
        }
    }

    // MARK: - Helpers

    private func iconName(for category: SleepInsightCategory) -> String {
        switch category {
        case .duration:           "clock.fill"
        case .efficiency:         "gauge.with.dots.needle.67percent"
        case .consistency:        "calendar"
        case .recovery:           "arrow.up.heart.fill"
        case .sleepStages:        "moon.stars.fill"
        case .missingData:        "exclamationmark.triangle.fill"
        case .baselineBuilding:   "calendar.badge.clock"
        case .protocolComparison: "pills.fill"
        case .contextComparison:  "chart.bar.fill"
        }
    }

    private func iconColor(for style: SleepInsightDisplayStyle?) -> Color {
        switch style {
        case .positive:       BetterColors.success
        case .caution:        BetterColors.warning
        case .informational:  BetterColors.brand
        case .neutral, nil:   BetterColors.subtext
        }
    }
}
