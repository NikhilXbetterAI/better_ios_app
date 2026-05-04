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

            // Comparison bars
            ComparisonBar(
                label: "Duration",
                tonightValue: session.totalSleepTime / 60,
                baselineValue: baseline.totalSleepAverage / 60,
                unit: "min",
                maxValue: 540,
                higherIsBetter: true
            )
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
                label: "WASO",
                tonightValue: session.waso / 60,
                baselineValue: baseline.wasoAverage / 60,
                unit: "min",
                maxValue: 80,
                higherIsBetter: false
            )
            if let hrv = session.biometrics?.hrvAverage {
                ComparisonBar(
                    label: "HRV",
                    tonightValue: hrv,
                    baselineValue: baseline.hrvAverage,
                    unit: "ms",
                    maxValue: max(hrv, baseline.hrvAverage) * 1.3,
                    higherIsBetter: true
                )
            }
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
            Text("\(diffAbs) min \(direction) average")
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
