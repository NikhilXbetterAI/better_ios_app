import SwiftUI

// MARK: - Baseline comparison card

struct SleepVsBaselineView: View {
    let session: SleepSession
    let baseline: SleepBaseline

    private var durationDiffMinutes: Int {
        Int((session.totalSleepTime - baseline.totalSleepAverage) / 60)
    }

    private var isAboveBaseline: Bool { durationDiffMinutes >= 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: BetterSpacing.large) {
            summaryBanner

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 2),
                spacing: 10
            ) {
                SleepMetricComparisonStrip(
                    label: "Deep Sleep",
                    accentColor: BetterColors.stageDeep,
                    yourValue: session.deepDuration / 60,
                    baselineValue: baseline.deepAverage / 60,
                    unit: "min",
                    lowerIsBetter: false
                )
                SleepMetricComparisonStrip(
                    label: "REM Sleep",
                    accentColor: ProtocolPalette.goodColor,
                    yourValue: session.remDuration / 60,
                    baselineValue: baseline.remAverage / 60,
                    unit: "min",
                    lowerIsBetter: false
                )
                SleepMetricComparisonStrip(
                    label: "Total Sleep",
                    accentColor: BetterColors.brand,
                    yourValue: session.totalSleepTime / 60,
                    baselineValue: baseline.totalSleepAverage / 60,
                    unit: "min",
                    lowerIsBetter: false
                )
                SleepMetricComparisonStrip(
                    label: "Latency",
                    accentColor: BetterColors.warning,
                    yourValue: session.sleepLatency / 60,
                    baselineValue: baseline.latencyAverage / 60,
                    unit: "min",
                    lowerIsBetter: true
                )
            }

            VStack(spacing: 8) {
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
    }

    private var summaryBanner: some View {
        let diffAbs = abs(durationDiffMinutes)
        let direction = isAboveBaseline ? "above" : "below"
        let color: Color = isAboveBaseline ? ProtocolPalette.goodColor : ProtocolPalette.badColor

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
        .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(color.opacity(0.22), lineWidth: 1)
        )
    }
}

// MARK: - Protocol-style metric comparison strip for sleep

private struct SleepMetricComparisonStrip: View {
    let label: String
    let accentColor: Color
    let yourValue: Double?
    let baselineValue: Double?
    let unit: String
    var lowerIsBetter: Bool = false

    private var delta: Double? {
        guard let y = yourValue, let b = baselineValue else { return nil }
        return y - b
    }

    private var scaleMax: Double {
        max(yourValue ?? 0, baselineValue ?? 0, 1) * 1.15
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Circle()
                    .fill(accentColor)
                    .frame(width: 6, height: 6)
                Text(label)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(BetterColors.text)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if let delta {
                    sleepDeltaBadge(delta)
                }
            }

            comparisonRow(label: "You", value: yourValue, color: accentColor)
            comparisonRow(label: "Base", value: baselineValue, color: Color.white.opacity(0.34))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.white.opacity(0.02))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(ProtocolPalette.borderColor, lineWidth: 1))
    }

    private func sleepDeltaBadge(_ value: Double) -> some View {
        let sign = value > 0 ? "+" : ""
        let isGood = (value > 0) != lowerIsBetter && value != 0
        let color: Color = value == 0 ? ProtocolPalette.mutedText
            : (isGood ? ProtocolPalette.goodColor : ProtocolPalette.badColor)
        let formatted: String = {
            if unit == "%" { return "\(sign)\(String(format: "%.1f", value))%" }
            let abs = Swift.abs(value)
            let h = Int(abs) / 60; let m = Int(abs) % 60
            let numStr = h > 0 ? "\(h)h\(m)m" : "\(Int(abs))m"
            return "\(sign)\(numStr)"
        }()
        return Text(formatted)
            .font(.system(size: 10, weight: .bold).monospacedDigit())
            .foregroundStyle(color)
    }

    @ViewBuilder
    private func comparisonRow(label: String, value: Double?, color: Color) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(ProtocolPalette.dimText)
                .frame(width: 30, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.05))
                    Capsule()
                        .fill(color)
                        .frame(width: max(4, geo.size.width * CGFloat((value ?? 0) / scaleMax)))
                }
            }
            .frame(height: 5)
            Text(formatted(value))
                .font(.system(size: 9, weight: .bold).monospacedDigit())
                .foregroundStyle(value == nil ? ProtocolPalette.dimText : BetterColors.text)
                .frame(width: 52, alignment: .trailing)
        }
    }

    private func formatted(_ value: Double?) -> String {
        guard let value else { return "—" }
        if unit == "%" { return "\(String(format: "%.1f", value))%" }
        let h = Int(value) / 60; let m = Int(value) % 60
        return h > 0 ? "\(h)h \(m)m" : "\(Int(value))m"
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

    private var color: Color { isPositive ? ProtocolPalette.goodColor : ProtocolPalette.badColor }

    private static let timeFmt: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return f
    }()

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(ProtocolPalette.mutedText)
            Spacer()
            HStack(spacing: 6) {
                Text(Self.timeFmt.string(from: sessionDate))
                    .font(.system(size: 12, weight: .bold, design: .rounded))
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
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.02))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(ProtocolPalette.borderColor, lineWidth: 1))
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
                let color: Color = positive ? ProtocolPalette.goodColor : ProtocolPalette.badColor

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
                        .foregroundStyle(ProtocolPalette.dimText)
                }
                .padding(BetterSpacing.medium)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(color.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(color.opacity(0.18), lineWidth: 1))
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
