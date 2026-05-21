import SwiftUI

/// Rich detail sheet presented when the user taps an Impact vs Baseline metric card.
struct ImpactMetricDetailSheet: View {
    let metric: ProtocolFormulaMetric
    let impact: ProtocolImpactSummary
    let activeVersion: ProtocolFormulaVersion

    @Environment(\.dismiss) private var dismiss

    private var color: Color { ProtocolPalette.versionColor(hex: metric.colorHex) }

    private var pair: (you: Double?, baseline: Double?, delta: Double?) {
        switch metric {
        case .restorativePct:
            return (impact.versionMeanRestorativePctOfInBed,
                    impact.baselineMeanRestorativePctOfInBed,
                    impact.deltaRestorativePctOfInBed)
        case .deep:
            return (impact.versionMeanDeepMin,
                    impact.baselineMeanDeepMin,
                    impact.deltaDeepMin)
        case .rem:
            return (impact.versionMeanRemMin,
                    impact.baselineMeanRemMin,
                    impact.deltaRemMin)
        case .duration:
            return (impact.versionMeanTotalSleepMin,
                    impact.baselineMeanTotalSleepMin,
                    impact.deltaTotalSleepMin)
        case .longestBlock:
            return (impact.versionMeanLongestRestorativeBlockMin,
                    impact.baselineMeanLongestRestorativeBlockMin,
                    impact.deltaLongestRestorativeBlockMin)
        case .awake:
            return (impact.versionMeanAwakeMin,
                    impact.baselineMeanAwakeMin,
                    impact.deltaAwakeMin)
        case .latency:
            return (impact.versionMeanLatencyMin,
                    impact.baselineMeanLatencyMin,
                    impact.deltaLatencyMin)
        case .restorativeMin:
            return (impact.versionMeanRestorativeMin,
                    impact.baselineMeanRestorativeMin,
                    impact.deltaRestorativeMin)
        case .score:
            return (impact.versionMeanSleepScore,
                    impact.baselineMeanSleepScore,
                    impact.deltaSleepScore)
        }
    }

    private func formatted(_ value: Double?) -> String {
        guard let v = value else { return "—" }
        switch metric.unit {
        case "%":   return "\(Int(v.rounded()))%"
        case "pts": return "\(Int(v.rounded()))pts"
        default:
            let h = Int(v) / 60
            let m = Int(v) % 60
            return h > 0 ? "\(h)h \(m)m" : "\(m)m"
        }
    }

    private var improvedText: String {
        guard let delta = pair.delta else { return "" }
        let sign = delta >= 0 ? "+" : ""
        let isGood = (delta > 0) != metric.betterIsLower
        let direction = isGood ? "better" : "worse"
        let fmtDelta: String = {
            if metric.unit == "%" {
                return "\(sign)\(String(format: "%.1f", delta))%"
            } else if metric.unit == "pts" {
                return "\(sign)\(Int(delta.rounded()))pts"
            } else {
                let h = Int(abs(delta)) / 60
                let m = Int(abs(delta)) % 60
                let abs = h > 0 ? "\(h)h \(m)m" : "\(m)m"
                return "\(delta >= 0 ? "+" : "-")\(abs)"
            }
        }()
        return "Your \(metric.fullLabel.lowercased()) on \(activeVersion.resolvedLabel) averages \(formatted(pair.you)), which is \(fmtDelta) \(direction) than your baseline of \(formatted(pair.baseline))."
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                // — Handle
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.white.opacity(0.15))
                    .frame(width: 36, height: 4)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 12)

                // — Header
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        Circle()
                            .fill(color)
                            .frame(width: 10, height: 10)
                        Text(metric.fullLabel)
                            .font(.title2.weight(.black))
                            .foregroundStyle(BetterColors.text)
                        Spacer()
                        // Delta badge — prominent
                        if let delta = pair.delta {
                            let sign = delta >= 0 ? "+" : ""
                            let isGood = (delta > 0) != metric.betterIsLower
                            Text("\(sign)\(formatted(pair.delta ?? 0))")
                                .font(.title3.weight(.black).monospacedDigit())
                                .foregroundStyle(isGood ? ProtocolPalette.goodColor : ProtocolPalette.badColor)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    Capsule().fill((isGood ? ProtocolPalette.goodColor : ProtocolPalette.badColor).opacity(0.12))
                                )
                        }
                    }
                    VersionChip(version: activeVersion, size: .small)
                        .padding(.top, 2)
                }

                ProtocolMetricComparisonStrip(
                    metric: metric,
                    yourValue: pair.you,
                    baselineValue: pair.baseline,
                    compact: false
                )

                VStack(alignment: .leading, spacing: 8) {
                    Text("Before vs after")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(ProtocolPalette.dimText)
                        .textCase(.uppercase)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 2), spacing: 10) {
                        ForEach([ProtocolFormulaMetric.restorativePct, .deep, .rem, .duration, .longestBlock, .awake, .latency], id: \.self) { comparisonMetric in
                            comparisonStrip(for: comparisonMetric)
                        }
                    }
                }

                // — Nights count
                if impact.nightCount > 0 {
                    HStack(spacing: 6) {
                        Image(systemName: "moon.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(ProtocolPalette.dimText)
                        Text("Based on \(impact.nightCount) night\(impact.nightCount == 1 ? "" : "s") with \(activeVersion.resolvedLabel)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(ProtocolPalette.dimText)
                    }
                }

                // — Narrative explanation
                if !improvedText.isEmpty {
                    Text(improvedText)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(ProtocolPalette.mutedText)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(14)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(color.opacity(0.06))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(color.opacity(0.18), lineWidth: 1)
                        )
                }

                // — What does this mean
                VStack(alignment: .leading, spacing: 8) {
                    Text("What this means")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(ProtocolPalette.dimText)
                        .textCase(.uppercase)
                    Text(metric.explanationText)
                        .font(.caption)
                        .foregroundStyle(ProtocolPalette.mutedText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(14)
                .background(ProtocolPalette.surfaceColor)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(ProtocolPalette.borderColor, lineWidth: 1))

                // — Caveat
                Text(ProtocolImpactSummary.causalityCaveat)
                    .font(.caption2)
                    .foregroundStyle(ProtocolPalette.dimText)
                    .multilineTextAlignment(.leading)

                Spacer(minLength: 20)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
        }
        .background(ProtocolPalette.backgroundColor.ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.hidden) // we draw our own handle
        .presentationBackground(ProtocolPalette.backgroundColor)
    }

    private func comparisonStrip(for metric: ProtocolFormulaMetric) -> some View {
        ProtocolMetricComparisonStrip(
            metric: metric,
            yourValue: value(for: metric).you,
            baselineValue: value(for: metric).baseline,
            compact: true
        )
    }
}

// MARK: - Metric explanation text

private extension ProtocolFormulaMetric {
    var explanationText: String {
        switch self {
        case .restorativePct:
            return "Restorative % measures how much of your time in bed was spent in deep or REM sleep. Higher means your sleep was more efficient and regenerative."
        case .restorativeMin:
            return "Total minutes of restorative sleep (deep + REM). More is generally better for recovery and memory consolidation."
        case .deep:
            return "Deep (slow-wave) sleep is critical for physical recovery, immune function, and growth hormone release. Most adults need 1–2 hours per night."
        case .rem:
            return "REM sleep supports emotional processing, creativity, and memory consolidation. It typically increases across your sleep cycles."
        case .awake:
            return "Time spent awake while in bed. Lower is better — less awake time means fewer sleep disruptions and more consolidated rest."
        case .duration:
            return "Total minutes of actual sleep (excluding time awake in bed). Most adults need 7–9 hours, though individual needs vary."
        case .latency:
            return "Sleep latency is how long it takes you to fall asleep after going to bed. Lower is generally better, though under 5 minutes can indicate sleep deprivation."
        case .longestBlock:
            return "The longest uninterrupted stretch of restorative (deep + REM) sleep. A longer block typically means fewer mid-night awakenings disrupting your sleep architecture."
        case .score:
            return "An overall score combining sleep efficiency, duration, stage composition, and continuity. Higher is better."
        }
    }
}

private extension ImpactMetricDetailSheet {
    func value(for metric: ProtocolFormulaMetric) -> (you: Double?, baseline: Double?) {
        switch metric {
        case .restorativePct:
            return (impact.versionMeanRestorativePctOfInBed, impact.baselineMeanRestorativePctOfInBed)
        case .deep:
            return (impact.versionMeanDeepMin, impact.baselineMeanDeepMin)
        case .rem:
            return (impact.versionMeanRemMin, impact.baselineMeanRemMin)
        case .duration:
            return (impact.versionMeanTotalSleepMin, impact.baselineMeanTotalSleepMin)
        case .longestBlock:
            return (impact.versionMeanLongestRestorativeBlockMin, impact.baselineMeanLongestRestorativeBlockMin)
        case .awake:
            return (impact.versionMeanAwakeMin, impact.baselineMeanAwakeMin)
        case .latency:
            return (impact.versionMeanLatencyMin, impact.baselineMeanLatencyMin)
        case .restorativeMin:
            return (impact.versionMeanRestorativeMin, impact.baselineMeanRestorativeMin)
        case .score:
            return (impact.versionMeanSleepScore, impact.baselineMeanSleepScore)
        }
    }
}
