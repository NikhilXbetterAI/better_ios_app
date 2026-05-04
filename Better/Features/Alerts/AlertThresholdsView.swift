import SwiftUI

struct AlertThresholdsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: BetterSpacing.medium) {
            Text("Alert Thresholds")
                .font(BetterTypography.headline)
                .foregroundStyle(BetterColors.text)
            threshold("Low Score", value: "< 70", color: BetterColors.danger)
            threshold("Min Deep Sleep", value: "< 60 min", color: BetterColors.stageDeep)
            threshold("Min REM Sleep", value: "< 75 min", color: BetterColors.stageREM)
            threshold("Max WASO", value: "> 45 min", color: BetterColors.warning)
            threshold("Low HRV", value: "< 80% baseline", color: BetterColors.hrv)
            threshold("Low SpO2", value: "< 94% avg", color: BetterColors.stageCore)
            threshold("Sleep Debt", value: "> 1h deficit", color: BetterColors.stageREM)
        }
        .padding(BetterSpacing.large)
        .background(BetterColors.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func threshold(_ label: String, value: String, color: Color) -> some View {
        HStack {
            Text(label).font(BetterTypography.footnote).foregroundStyle(BetterColors.text)
            Spacer()
            Text(value).font(BetterTypography.caption).foregroundStyle(color)
        }
    }
}
