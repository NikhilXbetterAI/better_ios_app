import SwiftUI

struct ProtocolBeforeAfterCard: View {
    let startDate: Date
    let before: SleepPeriodSummary?
    let after: SleepPeriodSummary?

    var body: some View {
        VStack(alignment: .leading, spacing: BetterSpacing.medium) {
            header
            if before == nil && after == nil {
                loadingState
            } else {
                comparisonGrid
                nightsCounts
                disclaimer
            }
        }
        .padding(BetterSpacing.large)
        .background(BetterColors.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var header: some View {
        HStack(alignment: .center) {
            Label("Sleep Before vs After", systemImage: "arrow.left.arrow.right")
                .font(BetterTypography.headline)
                .foregroundStyle(BetterColors.text)
            Spacer()
            Text(startDate.formatted(.dateTime.month(.abbreviated).day().year()))
                .font(BetterTypography.caption)
                .foregroundStyle(BetterColors.subtext)
                .padding(.horizontal, BetterSpacing.small)
                .padding(.vertical, 4)
                .background(BetterColors.cardSecondary, in: Capsule())
        }
    }

    private var loadingState: some View {
        Text("Loading comparison data…")
            .font(BetterTypography.footnote)
            .foregroundStyle(BetterColors.subtext)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, BetterSpacing.medium)
    }

    private var comparisonGrid: some View {
        VStack(spacing: BetterSpacing.small) {
            columnLabels
            Divider().overlay(BetterColors.border)
            if let beforeScore = before?.averageSleepScore, let afterScore = after?.averageSleepScore {
                metricRow(
                    label: "Sleep Score",
                    beforeValue: String(format: "%.0f pts", beforeScore),
                    afterValue: String(format: "%.0f pts", afterScore),
                    delta: afterScore - beforeScore,
                    deltaFormatter: { d in String(format: "%+.0f pts", d) },
                    higherIsBetter: true
                )
            }
            if let beforeDur = before?.averageSleepDuration, let afterDur = after?.averageSleepDuration {
                metricRow(
                    label: "Duration",
                    beforeValue: formatDuration(beforeDur),
                    afterValue: formatDuration(afterDur),
                    delta: afterDur - beforeDur,
                    deltaFormatter: { d in formatSignedMinutes(d) },
                    higherIsBetter: true
                )
            }
            if let beforeDeep = before?.averageDeepSleep, let afterDeep = after?.averageDeepSleep {
                metricRow(
                    label: "Deep Sleep",
                    beforeValue: formatDuration(beforeDeep),
                    afterValue: formatDuration(afterDeep),
                    delta: afterDeep - beforeDeep,
                    deltaFormatter: { d in formatSignedMinutes(d) },
                    higherIsBetter: true
                )
            }
            if let beforeREM = before?.averageREMSleep, let afterREM = after?.averageREMSleep {
                metricRow(
                    label: "REM Sleep",
                    beforeValue: formatDuration(beforeREM),
                    afterValue: formatDuration(afterREM),
                    delta: afterREM - beforeREM,
                    deltaFormatter: { d in formatSignedMinutes(d) },
                    higherIsBetter: true
                )
            }
        }
    }

    private var columnLabels: some View {
        HStack {
            Text("Metric")
                .font(BetterTypography.caption)
                .foregroundStyle(BetterColors.subtext)
            Spacer()
            Text("Before")
                .font(BetterTypography.caption)
                .foregroundStyle(BetterColors.subtext)
                .frame(width: 70, alignment: .trailing)
            Text("After")
                .font(BetterTypography.caption)
                .foregroundStyle(BetterColors.brand)
                .frame(width: 70, alignment: .trailing)
            Text("Δ")
                .font(BetterTypography.caption)
                .foregroundStyle(BetterColors.subtext)
                .frame(width: 52, alignment: .trailing)
        }
    }

    private func metricRow(
        label: String,
        beforeValue: String,
        afterValue: String,
        delta: Double,
        deltaFormatter: (Double) -> String,
        higherIsBetter: Bool
    ) -> some View {
        let isPositive = higherIsBetter ? delta > 0 : delta < 0
        let isMeaningful = abs(delta) > 60
        let deltaColor: Color = isMeaningful
            ? (isPositive ? BetterColors.success : BetterColors.warning)
            : BetterColors.subtext

        return HStack {
            Text(label)
                .font(BetterTypography.footnote)
                .foregroundStyle(BetterColors.text)
            Spacer()
            Text(beforeValue)
                .font(BetterTypography.footnote)
                .foregroundStyle(BetterColors.subtext)
                .frame(width: 70, alignment: .trailing)
            Text(afterValue)
                .font(BetterTypography.footnote)
                .foregroundStyle(BetterColors.text)
                .frame(width: 70, alignment: .trailing)
            Text(deltaFormatter(delta))
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(deltaColor)
                .frame(width: 52, alignment: .trailing)
        }
        .padding(.vertical, 4)
    }

    private var nightsCounts: some View {
        HStack(spacing: BetterSpacing.small) {
            nightCountPill(
                "\(before?.nightCount ?? 0) nights",
                label: "before",
                color: BetterColors.subtext
            )
            Image(systemName: "arrow.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(BetterColors.subtext)
            nightCountPill(
                "\(after?.nightCount ?? 0) nights",
                label: "after",
                color: BetterColors.brand
            )
        }
    }

    private func nightCountPill(_ count: String, label: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Text(count)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(color)
            Text(label)
                .font(BetterTypography.caption)
                .foregroundStyle(BetterColors.subtext)
        }
        .padding(.horizontal, BetterSpacing.medium)
        .padding(.vertical, BetterSpacing.xSmall)
        .background(color.opacity(0.12), in: Capsule())
    }

    private var disclaimer: some View {
        Text("Shows association between your start date and sleep metrics. Not causation.")
            .font(BetterTypography.caption)
            .foregroundStyle(BetterColors.subtext)
    }

    private func formatDuration(_ seconds: Double) -> String {
        let mins = max(0, Int(seconds / 60))
        let h = mins / 60
        let m = mins % 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }

    private func formatSignedMinutes(_ seconds: Double) -> String {
        let mins = Int(seconds / 60)
        return "\(mins >= 0 ? "+" : "")\(mins)m"
    }
}
