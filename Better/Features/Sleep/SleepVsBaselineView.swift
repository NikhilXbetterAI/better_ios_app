import SwiftUI

// MARK: - Baseline comparison card matching CompBar / "vs Average" in SleepTab.tsx

struct SleepVsBaselineView: View {
    let session: SleepSession
    let baseline: SleepBaseline

    private var durationDiffMinutes: Int {
        Int((session.totalSleepTime - baseline.totalSleepAverage) / 60)
    }

    private var isAboveBaseline: Bool { durationDiffMinutes >= 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: BetterSpacing.large) {
            // Summary banner
            summaryBanner

            // Comparison bars — ordered by USP priority
            ComparisonBar(
                label: "Deep Sleep",
                tonightValue: session.deepDuration / 60,
                baselineValue: baseline.deepAverage / 60,
                unit: "min",
                maxValue: 180,
                higherIsBetter: true
            )
            ComparisonBar(
                label: "REM Sleep",
                tonightValue: session.remDuration / 60,
                baselineValue: baseline.remAverage / 60,
                unit: "min",
                maxValue: 200,
                higherIsBetter: true
            )
            ComparisonBar(
                label: "Duration",
                tonightValue: session.totalSleepTime / 60,
                baselineValue: baseline.totalSleepAverage / 60,
                unit: "min",
                maxValue: 540,
                higherIsBetter: true
            )
            ComparisonBar(
                label: "Time to Fall Asleep",
                tonightValue: session.sleepLatency / 60,
                baselineValue: baseline.latencyAverage / 60,
                unit: "min",
                maxValue: 60,
                higherIsBetter: false
            )
            TimeComparisonRow(
                label: "Bedtime",
                sessionDate: session.startDate,
                baselineMinuteAverage: baseline.bedtimeMinuteAverage,
                earlierIsBetter: true
            )
            TimeComparisonRow(
                label: "Wake Time",
                sessionDate: session.endDate,
                baselineMinuteAverage: baseline.wakeMinuteAverage,
                earlierIsBetter: false
            )
        }
    }

    private var summaryBanner: some View {
        let diffAbs = abs(durationDiffMinutes)
        let direction = isAboveBaseline ? "above" : "below"
        let color = isAboveBaseline ? BetterColors.success : BetterColors.warning

        return HStack(spacing: BetterSpacing.small) {
            Image(systemName: isAboveBaseline ? "arrow.up" : "arrow.down")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(color)
            Text("\(diffAbs) min \(direction) \(baseline.windowDays)-day avg")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(color)
        }
        .padding(.horizontal, BetterSpacing.medium)
        .padding(.vertical, BetterSpacing.small)
        .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(color.opacity(0.25), lineWidth: 1)
        )
    }
}

// MARK: - Single comparison bar

private struct ComparisonBar: View {
    let label: String
    let tonightValue: Double
    let baselineValue: Double
    let unit: String
    let maxValue: Double
    let higherIsBetter: Bool

    private var tonightFraction: CGFloat { CGFloat(min(tonightValue / maxValue, 1)) }
    private var baselineFraction: CGFloat { CGFloat(min(baselineValue / maxValue, 1)) }

    private var barColor: Color {
        let isGood = higherIsBetter ? tonightValue >= baselineValue : tonightValue <= baselineValue
        return isGood ? BetterColors.success : BetterColors.warning
    }

    var body: some View {
        VStack(spacing: 5) {
            HStack {
                Text(label)
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(BetterColors.text)
                Spacer()
                HStack(spacing: 4) {
                    Text(formatted(tonightValue))
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(BetterColors.text)
                    Text("vs \(formatted(baselineValue)) \(unit)")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(BetterColors.subtext)
                }
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(BetterColors.cardTertiary)
                        .frame(height: 8)

                    // Baseline ghost
                    RoundedRectangle(cornerRadius: 4)
                        .fill(BetterColors.subtext.opacity(0.25))
                        .frame(width: geo.size.width * baselineFraction, height: 8)

                    // Tonight
                    RoundedRectangle(cornerRadius: 4)
                        .fill(barColor)
                        .frame(width: geo.size.width * tonightFraction, height: 8)
                }
            }
            .frame(height: 8)
        }
    }

    private func formatted(_ value: Double) -> String {
        unit == "ms" ? String(format: "%.0f", value) : String(format: "%.0f", value)
    }
}

// MARK: - Time comparison row (bedtime / wake time)

private struct TimeComparisonRow: View {
    let label: String
    let sessionDate: Date
    let baselineMinuteAverage: Double
    let earlierIsBetter: Bool

    private var sessionMinutes: Double {
        let cal = Calendar.current
        let h = Double(cal.component(.hour, from: sessionDate))
        let m = Double(cal.component(.minute, from: sessionDate))
        return h * 60 + m
    }

    private var diffMinutes: Double {
        var d = sessionMinutes - baselineMinuteAverage
        // Wrap across midnight for values near 0/1440 boundary
        if d > 720 { d -= 1440 }
        if d < -720 { d += 1440 }
        return d
    }

    private var isPositive: Bool {
        earlierIsBetter ? diffMinutes <= 0 : diffMinutes >= 0
    }

    private var diffLabel: String {
        let abs = Int(Swift.abs(diffMinutes).rounded())
        let direction = diffMinutes < 0 ? "earlier" : "later"
        return "\(abs)m \(direction) than avg"
    }

    private var color: Color { isPositive ? BetterColors.success : BetterColors.warning }

    private static let timeFmt: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return f
    }()

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(BetterColors.text)
            Spacer()
            HStack(spacing: 6) {
                Text(Self.timeFmt.string(from: sessionDate))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(BetterColors.text)
                HStack(spacing: 2) {
                    Image(systemName: diffMinutes < 0 ? "arrow.up" : "arrow.down")
                        .font(.system(size: 10, weight: .semibold))
                    Text(diffLabel)
                        .font(.system(size: 11, design: .rounded))
                }
                .foregroundStyle(color)
            }
        }
    }
}

// MARK: - "What Changed" grid (4-cell summary)

struct WhatChangedGridView: View {
    let session: SleepSession
    let baseline: SleepBaseline

    private struct ChangeItem {
        let label: String
        let diff: Double
        let unit: String
        let higherIsBetter: Bool
    }

    private var items: [ChangeItem] {
        [
            ChangeItem(label: "Deep Sleep", diff: (session.deepDuration - baseline.deepAverage) / 60, unit: "min", higherIsBetter: true),
            ChangeItem(label: "Total Sleep", diff: (session.totalSleepTime - baseline.totalSleepAverage) / 60, unit: "min", higherIsBetter: true),
            ChangeItem(label: "REM Sleep",   diff: (session.remDuration - baseline.remAverage) / 60,   unit: "min", higherIsBetter: true),
            ChangeItem(label: "Efficiency",  diff: (session.efficiency - baseline.efficiencyAverage) * 100, unit: "%", higherIsBetter: true),
        ]
    }

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: BetterSpacing.small) {
            ForEach(items.indices, id: \.self) { i in
                let item = items[i]
                let positive = item.higherIsBetter ? item.diff >= 0 : item.diff <= 0
                let color = positive ? BetterColors.success : BetterColors.warning

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Image(systemName: item.diff >= 0 ? "arrow.up" : "arrow.down")
                            .font(.system(size: 11, weight: .semibold))
                        Text(formatDiff(item.diff, unit: item.unit))
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(color)

                    Text(item.label)
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(BetterColors.text)
                    Text("vs \(baseline.windowDays)-day avg")
                        .font(.system(size: 10, design: .rounded))
                        .foregroundStyle(BetterColors.subtext)
                }
                .padding(BetterSpacing.medium)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private func formatDiff(_ diff: Double, unit: String) -> String {
        let absDiff = Swift.abs(diff)
        if unit == "%" {
            return String(format: "%.0f%%", absDiff)
        }
        let h = Int(absDiff) / 60
        let m = Int(absDiff) % 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }
}
