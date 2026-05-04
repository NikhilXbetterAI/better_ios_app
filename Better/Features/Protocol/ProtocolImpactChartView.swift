import SwiftUI

struct ProtocolImpactChartView: View {
    let summary: ProtocolImpactSummary?

    var body: some View {
        VStack(alignment: .leading, spacing: BetterSpacing.medium) {
            Text("Protocol Impact")
                .font(BetterTypography.headline)
                .foregroundStyle(BetterColors.text)

            if let summary,
               let followedSleep = summary.adherentSleepAverage,
               let missedSleep = summary.missedSleepAverage,
               let followedScore = summary.adherentScoreAverage,
               let missedScore = summary.missedScoreAverage {
                comparison("Sleep", followed: followedSleep / 3_600, missed: missedSleep / 3_600, unit: "h")
                comparison("Score", followed: followedScore, missed: missedScore, unit: "")
                Text("\(summary.adherentNightCount) followed nights · \(summary.missedNightCount) missed nights")
                    .font(BetterTypography.caption)
                    .foregroundStyle(BetterColors.subtext)
                Text("Shown as associated with nights when followed, not as a causal claim.")
                    .font(BetterTypography.caption)
                    .foregroundStyle(BetterColors.subtext)
            } else {
                Text("Log more nights to compare followed and missed protocol outcomes.")
                    .font(BetterTypography.footnote)
                    .foregroundStyle(BetterColors.subtext)
            }
        }
        .padding(BetterSpacing.large)
        .background(BetterColors.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func comparison(_ label: String, followed: Double, missed: Double, unit: String) -> some View {
        let maxValue = max(followed, missed, 0.1)
        return VStack(alignment: .leading, spacing: BetterSpacing.xSmall) {
            HStack {
                Text(label).font(BetterTypography.footnote).foregroundStyle(BetterColors.text)
                Spacer()
                Text("\(format(followed))\(unit)")
                    .font(BetterTypography.caption)
                    .foregroundStyle(BetterColors.success)
            }
            ZStack(alignment: .leading) {
                Capsule().fill(BetterColors.cardSecondary).frame(height: 10)
                Capsule().fill(BetterColors.subtext.opacity(0.45)).frame(width: CGFloat(missed / maxValue) * 260, height: 10)
                Capsule().fill(BetterColors.success).frame(width: CGFloat(followed / maxValue) * 260, height: 10)
            }
        }
    }

    private func format(_ value: Double) -> String {
        value >= 10 ? String(format: "%.0f", value) : String(format: "%.1f", value)
    }
}

