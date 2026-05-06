import Foundation

nonisolated struct ProtocolInsightService: Sendable {
    static let meaningfulDurationDelta: TimeInterval = 20 * 60
    static let meaningfulEfficiencyDelta = 0.03
    static let meaningfulStageDelta: TimeInterval = 10 * 60
    static let meaningfulAwakeDelta: TimeInterval = 10 * 60

    func insights(from result: ProtocolComparisonResult) -> [SleepInsight] {
        switch result.confidence {
        case .unavailable:
            return [
                insight(
                    id: "protocol-unavailable",
                    title: "Not enough protocol data yet",
                    body: "Log more taken and not-taken nights before comparing protocol sleep patterns.",
                    priority: 65,
                    confidence: .unavailable,
                    style: .informational
                )
            ]
        case .low:
            return [
                insight(
                    id: "protocol-low-confidence",
                    title: "Early protocol signal only",
                    body: "Low confidence: add more nights to compare protocol vs non-protocol sleep.",
                    priority: 65,
                    confidence: .low,
                    style: .informational
                )
            ] + meaningfulMetricInsights(from: result, includeStageInsights: false)
        case .medium, .high:
            let metricInsights = meaningfulMetricInsights(from: result, includeStageInsights: true)
            if metricInsights.isEmpty {
                return [
                    insight(
                        id: "protocol-similar",
                        title: "Protocol nights look similar so far",
                        body: confidencePrefix(result.confidence) + "So far, protocol nights look similar to non-protocol nights.",
                        priority: 55,
                        confidence: result.confidence,
                        style: .neutral
                    )
                ]
            }
            return metricInsights
        }
    }
}

nonisolated private extension ProtocolInsightService {
    func meaningfulMetricInsights(from result: ProtocolComparisonResult, includeStageInsights: Bool) -> [SleepInsight] {
        var insights: [SleepInsight] = []

        if let delta = result.deltaTotalSleep, abs(delta) >= Self.meaningfulDurationDelta {
            let minutes = Int((abs(delta) / 60).rounded())
            let direction = delta > 0 ? "higher" : "lower"
            insights.append(
                insight(
                    id: "protocol-duration",
                    title: "Protocol sleep duration pattern",
                    body: confidencePrefix(result.confidence) + "On protocol nights, your sleep duration averaged \(minutes) minutes \(direction) than non-protocol nights.",
                    priority: 85,
                    confidence: result.confidence,
                    delta: SleepMetricDelta(value: delta / 60, unit: "minutes"),
                    style: delta >= 0 ? .positive : .caution
                )
            )
        }

        if let delta = result.deltaEfficiency, abs(delta) >= Self.meaningfulEfficiencyDelta {
            let points = Int((abs(delta) * 100).rounded())
            let direction = delta > 0 ? "higher" : "lower"
            insights.append(
                insight(
                    id: "protocol-efficiency",
                    title: "Protocol efficiency pattern",
                    body: confidencePrefix(result.confidence) + "Sleep efficiency was \(points) percentage points \(direction) on protocol nights.",
                    priority: 75,
                    confidence: result.confidence,
                    delta: SleepMetricDelta(value: delta * 100, unit: "percentagePoints"),
                    style: delta >= 0 ? .positive : .caution
                )
            )
        }

        if includeStageInsights {
            if let delta = result.deltaDeepSleep, abs(delta) >= Self.meaningfulStageDelta {
                insights.append(stageInsight(id: "protocol-deep", label: "deep sleep", delta: delta, confidence: result.confidence))
            }
            if let delta = result.deltaREMSleep, abs(delta) >= Self.meaningfulStageDelta {
                insights.append(stageInsight(id: "protocol-rem", label: "REM sleep", delta: delta, confidence: result.confidence))
            }
        }

        if let delta = result.deltaAwakeTime, abs(delta) >= Self.meaningfulAwakeDelta {
            let minutes = Int((abs(delta) / 60).rounded())
            let direction = delta > 0 ? "higher" : "lower"
            insights.append(
                insight(
                    id: "protocol-awake",
                    title: "Awake time pattern",
                    body: confidencePrefix(result.confidence) + "Awake time averaged \(minutes) minutes \(direction) on protocol nights.",
                    priority: 50,
                    confidence: result.confidence,
                    delta: SleepMetricDelta(value: delta / 60, unit: "minutes"),
                    style: delta <= 0 ? .positive : .neutral
                )
            )
        }

        return insights
    }

    func stageInsight(id: String, label: String, delta: TimeInterval, confidence: ComparisonConfidence) -> SleepInsight {
        let minutes = Int((abs(delta) / 60).rounded())
        let direction = delta > 0 ? "higher" : "lower"
        return insight(
            id: id,
            title: "Protocol stage pattern",
            body: confidencePrefix(confidence) + "On protocol nights, \(label) averaged \(minutes) minutes \(direction).",
            priority: 45,
            confidence: confidence,
            delta: SleepMetricDelta(value: delta / 60, unit: "minutes"),
            style: delta >= 0 ? .positive : .neutral
        )
    }

    func insight(
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
            category: .protocolComparison,
            priority: priority,
            confidence: confidence,
            metricDelta: delta,
            displayStyle: style
        )
    }

    func confidencePrefix(_ confidence: ComparisonConfidence) -> String {
        switch confidence {
        case .low:
            "Low confidence: "
        case .medium:
            "Medium confidence: "
        case .unavailable, .high:
            ""
        }
    }
}

nonisolated extension ComparisonConfidence {
    var displayName: String {
        switch self {
        case .unavailable:
            "Unavailable"
        case .low:
            "Low"
        case .medium:
            "Medium"
        case .high:
            "High"
        }
    }
}

nonisolated extension ProtocolComparisonWindow {
    var displayName: String {
        switch self {
        case .last7Days:
            "7 Days"
        case .last15Days:
            "15 Days"
        case .last30Days:
            "30 Days"
        case .all:
            "All"
        }
    }
}
