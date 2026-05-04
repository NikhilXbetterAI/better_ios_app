import SwiftUI

// MARK: - Schedule consistency matching ScheduleConsistencyView in SleepTab.tsx

struct ScheduleConsistencyView: View {
    let session: SleepSession
    let baseline: SleepBaseline

    private var bedtimeSD: Double { baseline.bedtimeMinuteStandardDeviation }
    private var wakeSD: Double { baseline.wakeMinuteStandardDeviation }

    // Consistency score: 0 = inconsistent (≥60 min SD), 1 = perfect (0 min SD)
    private func consistencyPct(sd: Double) -> Double {
        max(0, min(1, 1 - sd / 60))
    }

    var body: some View {
        VStack(spacing: BetterSpacing.medium) {
            scheduleRow(
                label: "Avg Bed Time",
                timeLabel: formatMinuteOfDay(baseline.bedtimeMinuteAverage),
                spreadLabel: "±\(Int(bedtimeSD)) min",
                consistencyPct: consistencyPct(sd: bedtimeSD),
                color: BetterColors.brand
            )
            scheduleRow(
                label: "Avg Wake Time",
                timeLabel: formatMinuteOfDay(baseline.wakeMinuteAverage),
                spreadLabel: "±\(Int(wakeSD)) min",
                consistencyPct: consistencyPct(sd: wakeSD),
                color: BetterColors.warning
            )
        }
    }

    private func scheduleRow(
        label: String,
        timeLabel: String,
        spreadLabel: String,
        consistencyPct: Double,
        color: Color
    ) -> some View {
        VStack(spacing: 6) {
            HStack {
                Text(label)
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(BetterColors.text)
                Spacer()
                HStack(spacing: 4) {
                    Text(timeLabel)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(BetterColors.text)
                    Text(spreadLabel)
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(BetterColors.subtext)
                }
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(BetterColors.cardTertiary)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(color)
                        .frame(width: geo.size.width * CGFloat(consistencyPct))
                }
            }
            .frame(height: 7)

            HStack {
                Text("Inconsistent")
                    .font(.system(size: 9, design: .rounded))
                    .foregroundStyle(BetterColors.subtext)
                Spacer()
                Text("Consistent")
                    .font(.system(size: 9, design: .rounded))
                    .foregroundStyle(BetterColors.subtext)
            }
        }
    }

    private func formatMinuteOfDay(_ minuteOfDay: Double) -> String {
        let totalMinutes = Int(minuteOfDay)
        let hour = (totalMinutes / 60) % 24
        let minute = totalMinutes % 60
        let ampm = hour >= 12 ? "PM" : "AM"
        let displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour)
        return String(format: "%d:%02d %@", displayHour, minute, ampm)
    }
}

// MARK: - Compact summary for card header

struct ScheduleConsistencySummary: View {
    let baseline: SleepBaseline

    private var worstSD: Double {
        max(baseline.bedtimeMinuteStandardDeviation, baseline.wakeMinuteStandardDeviation)
    }

    var body: some View {
        Text("±\(Int(worstSD)) min variation")
            .font(.system(size: 14, weight: .semibold, design: .rounded))
            .foregroundStyle(BetterColors.text)
    }
}
