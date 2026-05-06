import XCTest
@testable import Better

final class ContextInsightServiceTests: XCTestCase {
    private let service = ContextInsightService()
    private let causalWords = ["causes", "cause", "leads to", "caused by", "result of", "responsible for", "triggers", "trigger"]

    // MARK: - Language rules (most important requirement)

    func testNoInsightContainsCausalLanguage() {
        let results = allResultVariants()
        for result in results {
            let insights = service.insights(from: result)
            for insight in insights {
                for word in causalWords {
                    XCTAssertFalse(
                        insight.body.localizedCaseInsensitiveContains(word),
                        "Insight body must not contain causal word '\(word)': \(insight.body)"
                    )
                }
            }
        }
    }

    func testHighConfidenceInsightsContainAssociationLanguage() {
        let result = makeResult(factor: .caffeineLate, yesCount: 7, noCount: 7, durationDeltaMinutes: -30)
        let insights = service.insights(from: result)
        let bodies = insights.map(\.body)

        let containsAssociation = bodies.contains { body in
            body.localizedCaseInsensitiveContains("on nights with") ||
            body.localizedCaseInsensitiveContains("was associated with") ||
            body.localizedCaseInsensitiveContains("associated with")
        }
        XCTAssertTrue(containsAssociation, "Insights must use association language")
    }

    // MARK: - Insufficient data state

    func testUnavailableConfidenceReturnsInsufficientDataInsight() {
        let result = makeResult(factor: .alcohol, yesCount: 0, noCount: 0, durationDeltaMinutes: 0)
        let insights = service.insights(from: result)
        XCTAssertEqual(insights.count, 1)
        XCTAssertEqual(insights[0].confidence, .unavailable)
        XCTAssertEqual(insights[0].category, .contextComparison)
    }

    func testUnavailableInsightBodyMentionsFactor() {
        let result = makeResult(factor: .highStress, yesCount: 0, noCount: 0, durationDeltaMinutes: 0)
        let insight = service.insights(from: result)[0]
        XCTAssertTrue(
            insight.body.localizedCaseInsensitiveContains("high stress") ||
            insight.title.localizedCaseInsensitiveContains("high stress"),
            "Insight should mention the factor name"
        )
    }

    // MARK: - Low confidence prefix

    func testLowConfidenceInsightBodyContainsConfidencePrefix() {
        let result = makeResult(factor: .alcohol, yesCount: 2, noCount: 3, durationDeltaMinutes: -45)
        let insights = service.insights(from: result)
        let hasLowPrefix = insights.contains { $0.body.lowercased().contains("low confidence") }
        XCTAssertTrue(hasLowPrefix, "At least one low-confidence insight must contain 'Low confidence' prefix")
    }

    // MARK: - Meaningful delta → insight generated

    func testMeaningfulDurationDeltaProducesDurationInsight() {
        let result = makeResult(factor: .workout, yesCount: 7, noCount: 7, durationDeltaMinutes: 25)
        let insights = service.insights(from: result)
        let durationInsight = insights.first { $0.id.contains("duration") }
        XCTAssertNotNil(durationInsight, "A meaningful duration delta must generate a duration insight")
        XCTAssertEqual(durationInsight?.category, .contextComparison)
    }

    func testBelowThresholdDeltaProducesNoMeaningfulInsight() {
        let result = makeResult(factor: .nap, yesCount: 7, noCount: 7, durationDeltaMinutes: 5)
        let insights = service.insights(from: result)
        let hasDurationInsight = insights.contains { $0.id.contains("duration") }
        XCTAssertFalse(hasDurationInsight, "Sub-threshold delta must not generate a duration insight")
    }

    // MARK: - No meaningful difference

    func testNoMeaningfulDifferenceReturnsNeutralInsight() {
        let result = makeResult(factor: .travel, yesCount: 7, noCount: 7, durationDeltaMinutes: 2)
        let insights = service.insights(from: result)
        XCTAssertEqual(insights.count, 1)
        XCTAssertEqual(insights[0].displayStyle, .neutral)
    }

    // MARK: - Insight category

    func testAllInsightsCategorisedAsContextComparison() {
        let results = allResultVariants()
        for result in results {
            for insight in service.insights(from: result) {
                XCTAssertEqual(insight.category, .contextComparison, "All context insights must have .contextComparison category")
            }
        }
    }
}

// MARK: - Helpers

private extension ContextInsightServiceTests {

    func makeResult(
        factor: ContextFactor,
        yesCount: Int,
        noCount: Int,
        durationDeltaMinutes: Double,
        efficiencyDelta: Double = 0
    ) -> ContextComparisonResult {
        let confidence = ProtocolComparisonService.confidence(takenCount: yesCount, notTakenCount: noCount)
        let durationDelta = durationDeltaMinutes * 60.0
        let meaningful = abs(durationDelta) >= ContextComparisonService.meaningfulDurationDelta ||
                         abs(efficiencyDelta) >= ContextComparisonService.meaningfulEfficiencyDelta
        return ContextComparisonResult(
            factor: factor,
            window: .all,
            yesNightCount: yesCount,
            noNightCount: noCount,
            unknownNightCount: 0,
            confidence: confidence,
            averageSleepDurationYes: yesCount > 0 ? 7 * 3_600 + durationDelta : nil,
            averageSleepDurationNo:  noCount  > 0 ? 7 * 3_600                 : nil,
            durationDelta: (yesCount > 0 && noCount > 0) ? durationDelta : nil,
            averageEfficiencyYes: yesCount > 0 ? 0.88 + efficiencyDelta : nil,
            averageEfficiencyNo:  noCount  > 0 ? 0.88                   : nil,
            efficiencyDelta: (yesCount > 0 && noCount > 0) ? efficiencyDelta : nil,
            hasMeaningfulDifference: meaningful
        )
    }

    /// Returns a representative set of results covering all confidence states.
    func allResultVariants() -> [ContextComparisonResult] {
        ContextFactor.allCases.flatMap { factor -> [ContextComparisonResult] in [
            makeResult(factor: factor, yesCount: 0,  noCount: 0,  durationDeltaMinutes: 0),
            makeResult(factor: factor, yesCount: 2,  noCount: 3,  durationDeltaMinutes: -30),
            makeResult(factor: factor, yesCount: 5,  noCount: 5,  durationDeltaMinutes: 25),
            makeResult(factor: factor, yesCount: 8,  noCount: 8,  durationDeltaMinutes: 5),
        ]}
    }
}
