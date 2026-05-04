import SwiftUI

struct ProtocolImpactView: View {
    let summary: ProtocolImpactSummary?

    var body: some View {
        VStack(alignment: .leading, spacing: BetterSpacing.medium) {
            HStack {
                Image(systemName: "pills.fill")
                    .foregroundStyle(BetterColors.success)
                Text("Protocol Impact")
                    .font(BetterTypography.headline)
                    .foregroundStyle(BetterColors.text)
            }

            if let summary,
               let adherentScore = summary.adherentScoreAverage,
               let missedScore = summary.missedScoreAverage {
                impactRow("Sleep Score", followed: adherentScore, missed: missedScore, unit: "")
                if let adherentSleep = summary.adherentSleepAverage, let missedSleep = summary.missedSleepAverage {
                    impactRow("Total Sleep", followed: adherentSleep / 3_600, missed: missedSleep / 3_600, unit: "h")
                }
                Text("Values are associated with nights when followed. This does not prove causality.")
                    .font(BetterTypography.caption)
                    .foregroundStyle(BetterColors.subtext)
            } else {
                Text("Log more followed and missed nights to compare outcomes.")
                    .font(BetterTypography.footnote)
                    .foregroundStyle(BetterColors.subtext)
            }
        }
        .padding(BetterSpacing.large)
        .background(BetterColors.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func impactRow(_ label: String, followed: Double, missed: Double, unit: String) -> some View {
        let maxValue = max(followed, missed, 0.1)
        return VStack(alignment: .leading, spacing: BetterSpacing.xSmall) {
            HStack {
                Text(label).font(BetterTypography.footnote).foregroundStyle(BetterColors.text)
                Spacer()
                Text("\(formatted(followed))\(unit) followed")
                    .font(BetterTypography.caption)
                    .foregroundStyle(BetterColors.success)
            }
            ZStack(alignment: .leading) {
                Capsule().fill(BetterColors.cardSecondary).frame(height: 10)
                Capsule().fill(BetterColors.subtext.opacity(0.4)).frame(width: CGFloat(missed / maxValue) * 260, height: 10)
                Capsule().fill(BetterColors.success).frame(width: CGFloat(followed / maxValue) * 260, height: 10)
            }
        }
    }

    private func formatted(_ value: Double) -> String {
        value >= 10 ? String(format: "%.0f", value) : String(format: "%.1f", value)
    }
}

