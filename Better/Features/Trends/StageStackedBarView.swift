import SwiftUI

struct StageStackedBarView: View {
    let points: [StageCompositionPoint]

    var body: some View {
        VStack(alignment: .leading, spacing: BetterSpacing.medium) {
            Text("Stage Composition")
                .font(BetterTypography.headline)
                .foregroundStyle(BetterColors.text)

            if points.isEmpty {
                Text("Detailed stages are unavailable for the selected range.")
                    .font(BetterTypography.footnote)
                    .foregroundStyle(BetterColors.subtext)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, BetterSpacing.large)
            } else {
                HStack(alignment: .bottom, spacing: BetterSpacing.small) {
                    ForEach(points) { point in
                        VStack(spacing: BetterSpacing.xSmall) {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(BetterColors.cardSecondary)
                                .frame(height: 118)
                                .overlay(alignment: .bottom) {
                                    VStack(spacing: 0) {
                                        segment(point.awakePercent, BetterColors.stageAwake)
                                        segment(point.remPercent, BetterColors.stageREM)
                                        segment(point.corePercent, BetterColors.stageCore)
                                        segment(point.deepPercent, BetterColors.stageDeep)
                                    }
                                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                }
                            Text(dayLabel(for: point.date))
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                                .foregroundStyle(BetterColors.subtext)
                        }
                    }
                }
                stageLegend
            }
        }
        .padding(BetterSpacing.large)
        .background(BetterColors.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func segment(_ percent: Double, _ color: Color) -> some View {
        color.frame(height: max(2, CGFloat(percent) * 118))
    }

    private var stageLegend: some View {
        HStack(spacing: BetterSpacing.medium) {
            legend("Deep", BetterColors.stageDeep)
            legend("Core", BetterColors.stageCore)
            legend("REM", BetterColors.stageREM)
            legend("Awake", BetterColors.stageAwake)
        }
    }

    private func legend(_ label: String, _ color: Color) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label).font(BetterTypography.caption).foregroundStyle(BetterColors.subtext)
        }
    }

    private func dayLabel(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "E"
        return formatter.string(from: date)
    }
}

