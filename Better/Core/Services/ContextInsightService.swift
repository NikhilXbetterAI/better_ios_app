import Foundation

/// Generates deterministic, association-only insights from a `ContextComparisonResult`.
///
/// Language rules (enforced):
/// - Use "On nights with…" or "was associated with…" — never "caused" or "leads to".
/// - Mention low confidence when confidence is low.
/// - Suppress insights when data is insufficient.
/// - Never make health, medical, or supplement advice.
nonisolated struct ContextInsightService: Sendable {

    func insights(from result: ContextComparisonResult) -> [SleepInsight] {
        switch result.confidence {
        case .unavailable:
            return [insufficientDataInsight(for: result.factor)]
        case .low:
            let base = lowConfidenceInsight(for: result.factor)
            let metrics = metricInsights(from: result, includeStages: false)
            return [base] + metrics
        case .medium, .high:
            let metrics = metricInsights(from: result, includeStages: true)
            if metrics.isEmpty {
                return [noMeaningfulDifferenceInsight(for: result.factor, confidence: result.confidence)]
            }
            return metrics
        }
    }
}

// MARK: - Private builders

nonisolated private extension ContextInsightService {

    func metricInsights(from result: ContextComparisonResult, includeStages: Bool) -> [SleepInsight] {
        var out: [SleepInsight] = []
        let prefix = confidencePrefix(result.confidence)
        let factorLabel = result.factor.displayName.lowercased()

        // Duration
        if let delta = result.durationDelta,
           abs(delta) >= ContextComparisonService.meaningfulDurationDelta {
            let minutes = Int((abs(delta) / 60).rounded())
            let direction = delta < 0 ? "lower" : "higher"
            out.append(makeInsight(
                id: "ctx-\(result.factor.rawValue)-duration",
                title: "\(result.factor.displayName) & sleep duration",
                body: "\(prefix)On nights with \(factorLabel), your sleep averaged \(minutes) minutes \(direction).",
                priority: 85,
                confidence: result.confidence,
                delta: SleepMetricDelta(value: delta / 60, unit: "minutes"),
                style: delta > 0 ? .positive : .caution
            ))
        }

        // Efficiency
        if let delta = result.efficiencyDelta,
           abs(delta) >= ContextComparisonService.meaningfulEfficiencyDelta {
            let points = Int((abs(delta) * 100).rounded())
            let direction = delta < 0 ? "lower" : "higher"
            out.append(makeInsight(
                id: "ctx-\(result.factor.rawValue)-efficiency",
                title: "\(result.factor.displayName) & sleep efficiency",
                body: "\(prefix)Sleep efficiency was \(points) percentage points \(direction) on nights with \(factorLabel).",
                priority: 75,
                confidence: result.confidence,
                delta: SleepMetricDelta(value: delta * 100, unit: "percentagePoints"),
                style: delta > 0 ? .positive : .caution
            ))
        }

        // Deep sleep
        if includeStages,
           let delta = result.deepSleepDelta,
           abs(delta) >= ContextComparisonService.meaningfulStageDelta {
            let minutes = Int((abs(delta) / 60).rounded())
            let direction = delta < 0 ? "lower" : "higher"
            out.append(makeInsight(
                id: "ctx-\(result.factor.rawValue)-deep",
                title: "\(result.factor.displayName) & deep sleep",
                body: "\(prefix)Deep sleep was associated with \(minutes) minutes \(direction) on nights with \(factorLabel).",
                priority: 60,
                confidence: result.confidence,
                delta: SleepMetricDelta(value: delta / 60, unit: "minutes"),
                style: delta > 0 ? .positive : .neutral
            ))
        }

        // REM sleep
        if includeStages,
           let delta = result.remSleepDelta,
           abs(delta) >= ContextComparisonService.meaningfulStageDelta {
            let minutes = Int((abs(delta) / 60).rounded())
            let direction = delta < 0 ? "lower" : "higher"
            out.append(makeInsight(
                id: "ctx-\(result.factor.rawValue)-rem",
                title: "\(result.factor.displayName) & REM sleep",
                body: "\(prefix)REM sleep was associated with \(minutes) minutes \(direction) on nights with \(factorLabel).",
                priority: 55,
                confidence: result.confidence,
                delta: SleepMetricDelta(value: delta / 60, unit: "minutes"),
                style: delta > 0 ? .positive : .neutral
            ))
        }

        // Awake time
        if let delta = result.awakeTimeDelta,
           abs(delta) >= ContextComparisonService.meaningfulAwakeDelta {
            let minutes = Int((abs(delta) / 60).rounded())
            let direction = delta < 0 ? "less" : "more"
            out.append(makeInsight(
                id: "ctx-\(result.factor.rawValue)-awake",
                title: "\(result.factor.displayName) & awake time",
                body: "\(prefix)On nights with \(factorLabel), awake time was associated with \(minutes) minutes \(direction).",
                priority: 50,
                confidence: result.confidence,
                delta: SleepMetricDelta(value: delta / 60, unit: "minutes"),
                style: delta <= 0 ? .positive : .neutral
            ))
        }

        return out
    }

    func insufficientDataInsight(for factor: ContextFactor) -> SleepInsight {
        makeInsight(
            id: "ctx-\(factor.rawValue)-unavailable",
            title: "Not enough data for \(factor.displayName)",
            body: "Log more nights to compare sleep on \(factor.displayName.lowercased()) vs. non-\(factor.displayName.lowercased()) nights.",
            priority: 30,
            confidence: .unavailable,
            style: .informational
        )
    }

    func lowConfidenceInsight(for factor: ContextFactor) -> SleepInsight {
        makeInsight(
            id: "ctx-\(factor.rawValue)-low-confidence",
            title: "Early signal for \(factor.displayName)",
            body: "Low confidence — add more nights on both sides to improve the comparison.",
            priority: 40,
            confidence: .low,
            style: .informational
        )
    }

    func noMeaningfulDifferenceInsight(for factor: ContextFactor, confidence: ComparisonConfidence) -> SleepInsight {
        makeInsight(
            id: "ctx-\(factor.rawValue)-similar",
            title: "\(factor.displayName) — no clear pattern yet",
            body: "So far, \(factor.displayName.lowercased()) does not show a meaningful difference in your sleep.",
            priority: 25,
            confidence: confidence,
            style: .neutral
        )
    }

    func makeInsight(
        id: String,
        title: String,
        body: String,
        priority: Int,
        confidence: ComparisonConfidence,
        delta: SleepMetricDelta? = nil,
        style: SleepInsightDisplayStyle
    ) -> SleepInsight {
        SleepInsight(
            id: id,
            title: title,
            body: body,
            category: .contextComparison,
            priority: priority,
            confidence: confidence,
            metricDelta: delta,
            displayStyle: style
        )
    }

    func confidencePrefix(_ confidence: ComparisonConfidence) -> String {
        switch confidence {
        case .low:    "Low confidence: "
        case .medium: "Medium confidence: "
        case .unavailable, .high: ""
        }
    }
}
