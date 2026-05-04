import SwiftUI

struct BaselineComparisonChartView: View {
    let baseline: SleepBaseline?
    let latestSession: SleepSession?

    var body: some View {
        VStack(alignment: .leading, spacing: BetterSpacing.medium) {
            Text("Baseline Comparison")
                .font(BetterTypography.headline)
                .foregroundStyle(BetterColors.text)

            if let baseline, let latestSession {
                metricRow("Total Sleep", current: latestSession.totalSleepTime / 3_600, baseline: baseline.totalSleepAverage / 3_600, unit: "h", color: BetterColors.brand)
                metricRow("Deep", current: latestSession.deepDuration / 60, baseline: baseline.deepAverage / 60, unit: "m", color: BetterColors.stageDeep)
                metricRow("REM", current: latestSession.remDuration / 60, baseline: baseline.remAverage / 60, unit: "m", color: BetterColors.stageREM)
                metricRow("HRV", current: latestSession.biometrics?.hrvAverage ?? 0, baseline: baseline.hrvAverage, unit: "ms", color: BetterColors.hrv)
            } else {
                Text("Baseline appears after at least five valid cached nights.")
                    .font(BetterTypography.footnote)
                    .foregroundStyle(BetterColors.subtext)
            }
        }
        .padding(BetterSpacing.large)
        .background(BetterColors.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func metricRow(_ label: String, current: Double, baseline: Double, unit: String, color: Color) -> some View {
        let maxValue = max(current, baseline, 0.1)
        return VStack(alignment: .leading, spacing: BetterSpacing.xSmall) {
            HStack {
                Text(label).font(BetterTypography.footnote).foregroundStyle(BetterColors.text)
                Spacer()
                Text("\(formatted(current))\(unit) vs \(formatted(baseline))\(unit)")
                    .font(BetterTypography.caption)
                    .foregroundStyle(BetterColors.subtext)
            }
            ZStack(alignment: .leading) {
                Capsule().fill(BetterColors.cardSecondary).frame(height: 9)
                Capsule().fill(BetterColors.subtext.opacity(0.45)).frame(width: CGFloat(baseline / maxValue) * 260, height: 9)
                Capsule().fill(color).frame(width: CGFloat(current / maxValue) * 260, height: 9)
            }
        }
    }

    private func formatted(_ value: Double) -> String {
        value >= 10 ? String(format: "%.0f", value) : String(format: "%.1f", value)
    }
}

