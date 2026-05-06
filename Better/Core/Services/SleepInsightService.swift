import Foundation

nonisolated enum SleepInsightCategory: String, Codable, CaseIterable, Hashable, Sendable, Identifiable {
    case duration
    case efficiency
    case consistency
    case recovery
    case sleepStages
    case missingData
    case baselineBuilding
    case protocolComparison
    case contextComparison

    var id: String { rawValue }
}

nonisolated enum SleepInsightDisplayStyle: String, Codable, CaseIterable, Hashable, Sendable {
    case neutral
    case positive
    case caution
    case informational
}

nonisolated struct SleepMetricDelta: Codable, Hashable, Sendable {
    var value: Double
    var unit: String
}

nonisolated struct SleepInsight: Codable, Hashable, Sendable, Identifiable {
    var id: String
    var title: String
    var body: String
    var category: SleepInsightCategory
    var priority: Int
    var confidence: ComparisonConfidence
    var metricDelta: SleepMetricDelta?
    var displayStyle: SleepInsightDisplayStyle?
}

nonisolated struct SleepInsightService: Sendable {
    private let protocolInsightService: ProtocolInsightService

    init(protocolInsightService: ProtocolInsightService = ProtocolInsightService()) {
        self.protocolInsightService = protocolInsightService
    }

    func insights(
        session: SleepSession?,
        baseline: SleepBaseline?,
        recentSessions: [SleepSession],
        protocolComparison: ProtocolComparisonResult? = nil
    ) -> [SleepInsight] {
        var insights: [SleepInsight] = []

        guard let session else {
            return [
                SleepInsight(
                    id: "missing-data",
                    title: "No sleep data for this night",
                    body: "Sleep data is not available for the selected night.",
                    category: .missingData,
                    priority: 100,
                    confidence: .unavailable,
                    displayStyle: .informational
                )
            ]
        }

        if let baseline, baseline.validNights >= 7 {
            insights.append(contentsOf: baselineInsights(session: session, baseline: baseline))
            insights.append(contentsOf: consistencyInsights(baseline: baseline))
        } else {
            let nights = baseline?.validNights ?? recentSessions.filter { BaselineEngine.isValidNight($0) }.count
            insights.append(
                SleepInsight(
                    id: "baseline-building",
                    title: "Baseline is still building",
                    body: "A few more valid nights will make your sleep comparisons more accurate.",
                    category: .baselineBuilding,
                    priority: 90,
                    confidence: BaselineEngine.confidence(validNightCount: nights),
                    metricDelta: SleepMetricDelta(value: Double(nights), unit: "nights"),
                    displayStyle: .informational
                )
            )
        }

        if session.dataQuality != .detailedStages && session.dataQuality != .mixedSources {
            insights.append(
                SleepInsight(
                    id: "missing-stages",
                    title: "Sleep stages are limited",
                    body: "This night does not include enough stage detail for REM or deep sleep insights.",
                    category: .sleepStages,
                    priority: 70,
                    confidence: .unavailable,
                    displayStyle: .informational
                )
            )
        }

        if let recovery = recoveryInsight(session: session, recentSessions: recentSessions) {
            insights.append(recovery)
        }

        if let protocolComparison {
            insights.append(contentsOf: protocolInsightService.insights(from: protocolComparison))
        }

        return insights.sorted {
            if $0.priority == $1.priority { return $0.title < $1.title }
            return $0.priority > $1.priority
        }
    }
}

nonisolated private extension SleepInsightService {
    func baselineInsights(session: SleepSession, baseline: SleepBaseline) -> [SleepInsight] {
        let confidence = BaselineEngine.confidence(validNightCount: baseline.validNights)
        let confidencePrefix = confidence == .low || confidence == .medium ? "\(confidence.displayName) confidence: " : ""
        var insights: [SleepInsight] = []

        let durationDeltaMinutes = (session.totalSleepTime - baseline.totalSleepAverage) / 60
        if abs(durationDeltaMinutes) >= 20 {
            let direction = durationDeltaMinutes > 0 ? "more" : "less"
            insights.append(
                SleepInsight(
                    id: "duration-vs-baseline",
                    title: "Sleep duration changed",
                    body: "\(confidencePrefix)You slept \(Int(abs(durationDeltaMinutes).rounded())) minutes \(direction) than your \(baseline.windowDays)-day baseline.",
                    category: .duration,
                    priority: 80,
                    confidence: confidence,
                    metricDelta: SleepMetricDelta(value: durationDeltaMinutes, unit: "minutes"),
                    displayStyle: durationDeltaMinutes >= 0 ? .positive : .caution
                )
            )
        } else {
            insights.append(
                SleepInsight(
                    id: "duration-close",
                    title: "Duration was close to normal",
                    body: "\(confidencePrefix)Your sleep duration was close to your normal range.",
                    category: .duration,
                    priority: 40,
                    confidence: confidence,
                    metricDelta: SleepMetricDelta(value: durationDeltaMinutes, unit: "minutes"),
                    displayStyle: .neutral
                )
            )
        }

        let efficiencyDelta = (session.efficiency - baseline.efficiencyAverage) * 100
        if abs(efficiencyDelta) >= 3 {
            let direction = efficiencyDelta > 0 ? "higher" : "lower"
            insights.append(
                SleepInsight(
                    id: "efficiency-vs-baseline",
                    title: "Sleep efficiency shifted",
                    body: "\(confidencePrefix)Sleep efficiency was \(Int(abs(efficiencyDelta).rounded())) percentage points \(direction) than your baseline.",
                    category: .efficiency,
                    priority: 75,
                    confidence: confidence,
                    metricDelta: SleepMetricDelta(value: efficiencyDelta, unit: "percentagePoints"),
                    displayStyle: efficiencyDelta >= 0 ? .positive : .caution
                )
            )
        } else {
            insights.append(
                SleepInsight(
                    id: "efficiency-close",
                    title: "Efficiency was close to normal",
                    body: "\(confidencePrefix)Your sleep efficiency was close to your normal range.",
                    category: .efficiency,
                    priority: 35,
                    confidence: confidence,
                    metricDelta: SleepMetricDelta(value: efficiencyDelta, unit: "percentagePoints"),
                    displayStyle: .neutral
                )
            )
        }

        if session.dataQuality == .detailedStages || session.dataQuality == .mixedSources {
            let deepDelta = (session.deepDuration - baseline.deepAverage) / 60
            let remDelta = (session.remDuration - baseline.remAverage) / 60
            if abs(deepDelta) >= 10 || abs(remDelta) >= 10 {
                let mainMetric = abs(deepDelta) >= abs(remDelta) ? "deep sleep" : "REM sleep"
                let mainDelta = abs(deepDelta) >= abs(remDelta) ? deepDelta : remDelta
                let direction = mainDelta > 0 ? "higher" : "lower"
                insights.append(
                    SleepInsight(
                        id: "stage-vs-baseline",
                        title: "Sleep stages shifted",
                        body: "\(confidencePrefix)\(mainMetric.capitalized) was \(Int(abs(mainDelta).rounded())) minutes \(direction) than your baseline.",
                        category: .sleepStages,
                        priority: 55,
                        confidence: confidence,
                        metricDelta: SleepMetricDelta(value: mainDelta, unit: "minutes"),
                        displayStyle: mainDelta >= 0 ? .positive : .neutral
                    )
                )
            }
        }

        return insights
    }

    func consistencyInsights(baseline: SleepBaseline) -> [SleepInsight] {
        guard baseline.bedtimeMinuteStandardDeviation >= 60 || baseline.wakeMinuteStandardDeviation >= 60 else {
            return []
        }
        return [
            SleepInsight(
                id: "schedule-consistency",
                title: "Schedule varied recently",
                body: "Your bedtime or wake time has varied by about an hour across your baseline window.",
                category: .consistency,
                priority: 45,
                confidence: BaselineEngine.confidence(validNightCount: baseline.validNights),
                displayStyle: .informational
            )
        ]
    }

    func recoveryInsight(session: SleepSession, recentSessions: [SleepSession]) -> SleepInsight? {
        let ordered = recentSessions.sorted { $0.sleepDateKey < $1.sleepDateKey }
        guard ordered.count >= 3, let latestIndex = ordered.firstIndex(where: { $0.sleepDateKey == session.sleepDateKey }), latestIndex >= 2 else {
            return nil
        }
        let previousTwo = ordered[(latestIndex - 2)..<latestIndex]
        let poorBefore = previousTwo.allSatisfy { $0.qualityScore.overall < 70 }
        guard poorBefore, session.qualityScore.overall >= 75 else { return nil }
        return SleepInsight(
            id: "recovery-after-streak",
            title: "Sleep recovered after a lower stretch",
            body: "After two lower-scoring nights, this night moved back into your usual range.",
            category: .recovery,
            priority: 85,
            confidence: .medium,
            displayStyle: .positive
        )
    }
}
