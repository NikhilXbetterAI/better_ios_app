import SwiftUI

struct ChronotypeInsightsPreviewCard: View {
    let result: ChronotypeCalculationResult
    let onOpenChronotype: () -> Void

    @ViewBuilder
    var body: some View {
        if let estimate = result.estimate {
            BetterHealthCard {
                Button {
                    onOpenChronotype()
                } label: {
                    HStack(spacing: BetterSpacing.medium) {
                        Image(systemName: "sun.horizon.fill")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 42, height: 42)
                            .background(
                                LinearGradient(
                                    colors: [BetterColors.cyan, BetterColors.brand],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                            )

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Chronotype")
                                .font(BetterTypography.subheadline)
                                .foregroundStyle(BetterColors.text)
                            Text("Best window: \(formatMinute(estimate.optimalSleepWindow.startMinute))-\(formatMinute(estimate.optimalSleepWindow.endMinute))")
                                .font(BetterTypography.footnote)
                                .foregroundStyle(BetterColors.subtext)
                                .lineLimit(1)
                                .minimumScaleFactor(0.82)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(BetterColors.mutedText.opacity(0.7))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open Chronotype. Best sleep window \(formatMinute(estimate.optimalSleepWindow.startMinute)) to \(formatMinute(estimate.optimalSleepWindow.endMinute))")
            }
        }
    }

    private func formatMinute(_ minute: Int) -> String {
        let normalized = ((minute % 1_440) + 1_440) % 1_440
        let hour = normalized / 60
        let minute = normalized % 60
        let hour12 = hour % 12 == 0 ? 12 : hour % 12
        let suffix = hour < 12 ? "AM" : "PM"
        return String(format: "%d:%02d %@", hour12, minute, suffix)
    }
}
