import SwiftUI

struct InsightsBedtimeCard: View {
    let baseline: SleepBaseline

    var body: some View {
        BetterHealthCard {
            VStack(alignment: .leading, spacing: BetterSpacing.medium) {
                header
                timesRow
                Divider().background(BetterColors.border.opacity(0.45))
                consistencySection
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: BetterSpacing.small) {
            Image(systemName: "moon.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(BetterColors.stageDeep, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text("Sleep Schedule")
                    .font(BetterTypography.subheadline)
                    .foregroundStyle(BetterColors.text)
                Text("Averages from your \(baseline.windowDays)-day baseline")
                    .font(BetterTypography.caption)
                    .foregroundStyle(BetterColors.subtext)
            }
        }
    }

    // MARK: - Times Row

    private var timesRow: some View {
        HStack(spacing: 0) {
            timeCell(
                icon: "bed.double.fill",
                label: "Avg Bedtime",
                time: minutesToTimeString(baseline.bedtimeMinuteAverage),
                color: BetterColors.stageDeep
            )
            Rectangle().fill(BetterColors.border).frame(width: 1, height: 44)
            timeCell(
                icon: "alarm",
                label: "Avg Wake",
                time: minutesToTimeString(baseline.wakeMinuteAverage),
                color: BetterColors.stageAwake
            )
            Rectangle().fill(BetterColors.border).frame(width: 1, height: 44)
            timeCell(
                icon: "clock.fill",
                label: "Avg Duration",
                time: formatHoursInterval(baseline.totalSleepAverage),
                color: BetterColors.brand
            )
        }
    }

    private func timeCell(icon: String, label: String, time: String, color: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(color)
            Text(time)
                .font(.system(size: 15, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(BetterColors.text)
                .minimumScaleFactor(0.8)
                .lineLimit(1)
            Text(label)
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundStyle(BetterColors.subtext)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Consistency Section

    private var consistencySection: some View {
        VStack(alignment: .leading, spacing: BetterSpacing.small) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Bedtime Consistency")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(BetterColors.text)
                    Text("Variation: ±\(Int(baseline.bedtimeMinuteStandardDeviation.rounded())) min")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(BetterColors.subtext)
                }
                Spacer()
                consistencyBadge
            }
            ConsistencyBarView(standardDeviation: baseline.bedtimeMinuteStandardDeviation)
            consistencyHint
        }
    }

    private var consistencyBadge: some View {
        let sd = baseline.bedtimeMinuteStandardDeviation
        let label: String
        let color: Color
        let icon: String
        if sd < 20 {
            label = "Very Consistent"; color = BetterColors.success; icon = "checkmark.circle.fill"
        } else if sd < 40 {
            label = "Consistent"; color = BetterColors.success; icon = "checkmark.circle.fill"
        } else if sd < 60 {
            label = "Moderate"; color = BetterColors.warning; icon = "minus.circle.fill"
        } else {
            label = "Variable"; color = BetterColors.danger; icon = "exclamationmark.circle.fill"
        }
        return HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 12))
            Text(label)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(color.opacity(0.12), in: Capsule())
    }

    @ViewBuilder
    private var consistencyHint: some View {
        let sd = baseline.bedtimeMinuteStandardDeviation
        if sd >= 45 {
            HStack(spacing: 5) {
                Image(systemName: "info.circle")
                    .font(.system(size: 11))
                    .foregroundStyle(BetterColors.brand)
                Text("A consistent bedtime helps strengthen your circadian rhythm.")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(BetterColors.subtext)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Helpers

    private func minutesToTimeString(_ minutes: Double) -> String {
        let totalMinutes = Int(minutes.rounded()) % (24 * 60)
        let h = totalMinutes / 60
        let m = totalMinutes % 60
        let hour12 = h % 12 == 0 ? 12 : h % 12
        let amPm = h < 12 ? "AM" : "PM"
        return String(format: "%d:%02d %@", hour12, m, amPm)
    }

    private func formatHoursInterval(_ seconds: Double) -> String {
        let hours = seconds / 3_600
        let h = Int(hours)
        let m = Int((hours - Double(h)) * 60)
        return "\(h)h \(m)m"
    }
}

// MARK: - Consistency Bar

struct ConsistencyBarView: View {
    let standardDeviation: Double // minutes

    @State private var appeared = false

    private var consistencyFraction: Double {
        max(0, min(1, 1 - standardDeviation / 90))
    }

    private var barColor: Color {
        switch standardDeviation {
        case ..<20: BetterColors.success
        case ..<45: BetterColors.brand
        case ..<70: BetterColors.warning
        default:    BetterColors.danger
        }
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(BetterColors.cardSecondary).frame(height: 7)
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [barColor, barColor.opacity(0.7)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(7, geo.size.width * CGFloat(appeared ? consistencyFraction : 0)), height: 7)
                    .animation(.spring(response: 0.7, dampingFraction: 0.78).delay(0.15), value: appeared)
            }
        }
        .frame(height: 7)
        .onAppear { appeared = true }
    }
}
