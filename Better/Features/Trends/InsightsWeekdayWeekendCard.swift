import SwiftUI

struct InsightsWeekdayWeekendCard: View {
    let weekdayAvgHours: Double?
    let weekendAvgHours: Double?
    let weekdayCount: Int
    let weekendCount: Int

    @State private var appeared = false

    private var maxHours: Double {
        max(weekdayAvgHours ?? 0, weekendAvgHours ?? 0, 5.0)
    }

    private var difference: Double? {
        guard let wd = weekdayAvgHours, let we = weekendAvgHours else { return nil }
        return we - wd
    }

    var body: some View {
        BetterHealthCard {
            VStack(alignment: .leading, spacing: BetterSpacing.medium) {
                header
                barsSection
                if let diff = difference, abs(diff) >= 0.25 {
                    diffNote(diff)
                }
            }
        }
        .onAppear { withAnimation(.spring(response: 0.7, dampingFraction: 0.8).delay(0.1)) { appeared = true } }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: BetterSpacing.small) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(BetterColors.activity, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text("Weekday vs Weekend")
                    .font(BetterTypography.subheadline)
                    .foregroundStyle(BetterColors.text)
                Text("Average sleep duration comparison")
                    .font(BetterTypography.caption)
                    .foregroundStyle(BetterColors.subtext)
            }
        }
    }

    // MARK: - Bars

    private var barsSection: some View {
        VStack(spacing: BetterSpacing.medium) {
            sleepBar(
                label: "Weekday",
                hours: weekdayAvgHours,
                count: weekdayCount,
                color: BetterColors.brand
            )
            sleepBar(
                label: "Weekend",
                hours: weekendAvgHours,
                count: weekendCount,
                color: BetterColors.success
            )
        }
    }

    private func sleepBar(label: String, hours: Double?, count: Int, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(BetterColors.text)

                Spacer()

                if let h = hours {
                    Text(formatHours(h))
                        .font(.system(size: 14, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(color)
                } else {
                    Text("No data")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(BetterColors.subtext)
                }

                Text("(\(count)n)")
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(BetterColors.subtext)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(BetterColors.cardSecondary).frame(height: 10)
                    if let h = hours {
                        let fraction = min(h / maxHours, 1.0)
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [color, color.opacity(0.7)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(
                                width: max(10, geo.size.width * CGFloat(appeared ? fraction : 0)),
                                height: 10
                            )
                            .animation(.spring(response: 0.75, dampingFraction: 0.78).delay(0.1), value: appeared)
                    }
                }
            }
            .frame(height: 10)
        }
    }

    // MARK: - Diff Note

    private func diffNote(_ diff: Double) -> some View {
        let positive = diff > 0
        let color: Color = positive ? BetterColors.success : BetterColors.warning
        let absMin = Int(abs(diff * 60).rounded())
        let label = positive
            ? "You get \(absMin) more minutes of sleep on weekends"
            : "You sleep \(absMin) fewer minutes on weekends"

        return HStack(spacing: 6) {
            Image(systemName: positive ? "moon.fill" : "moon")
                .font(.system(size: 11))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(BetterColors.subtext)
        }
        .padding(.horizontal, BetterSpacing.medium)
        .padding(.vertical, BetterSpacing.small)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: - Helpers

    private func formatHours(_ hours: Double) -> String {
        let h = Int(hours)
        let m = Int((hours - Double(h)) * 60)
        return "\(h)h \(m)m"
    }
}
