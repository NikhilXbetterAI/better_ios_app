import XCTest
@testable import Better

final class ProtocolInsightServiceTests: XCTestCase {
    private let service = ProtocolInsightService()

    func testUnavailableConfidenceReturnsNotEnoughDataInsight() {
        let insights = service.insights(from: result(confidence: .unavailable))

        XCTAssertEqual(insights.first?.title, "Not enough protocol data yet")
        XCTAssertEqual(insights.first?.confidence, .unavailable)
    }

    func testLowConfidenceReturnsEarlySignalInsight() {
        let insights = service.insights(from: result(confidence: .low, deltaTotalSleep: 30 * 60))

        XCTAssertTrue(insights.contains { $0.title == "Early protocol signal only" })
        XCTAssertTrue(insights.contains { $0.body.contains("Low confidence") })
    }

    func testMeaningfulPositiveDurationDeltaUsesAssociationLanguage() {
        let insights = service.insights(from: result(confidence: .medium, deltaTotalSleep: 28 * 60))

        let duration = insights.first { $0.id == "protocol-duration" }
        XCTAssertEqual(duration?.metricDelta?.value ?? 0, 28, accuracy: 0.001)
        XCTAssertTrue(duration?.body.contains("On protocol nights") == true)
        XCTAssertTrue(duration?.body.contains("higher") == true)
    }

    func testMeaningfulNegativeDurationDelta() {
        let insights = service.insights(from: result(confidence: .high, deltaTotalSleep: -25 * 60))

        let duration = insights.first { $0.id == "protocol-duration" }
        XCTAssertTrue(duration?.body.contains("25 minutes lower") == true)
        XCTAssertEqual(duration?.displayStyle, .caution)
    }

    func testNoMeaningfulDifference() {
        let insights = service.insights(from: result(confidence: .medium, deltaTotalSleep: 5 * 60, deltaEfficiency: 0.01))

        XCTAssertEqual(insights.count, 1)
        XCTAssertEqual(insights.first?.id, "protocol-similar")
    }

    func testMissingStageDataSuppressesStageInsights() {
        let insights = service.insights(from: result(confidence: .high, deltaTotalSleep: 25 * 60, deltaDeepSleep: nil, deltaREMSleep: nil))

        XCTAssertFalse(insights.contains { $0.id == "protocol-deep" })
        XCTAssertFalse(insights.contains { $0.id == "protocol-rem" })
    }

    func testProtocolInsightTextDoesNotUseCausalLanguage() {
        let insights = service.insights(from: result(
            confidence: .high,
            deltaTotalSleep: 32 * 60,
            deltaEfficiency: 0.04,
            deltaDeepSleep: 12 * 60,
            deltaREMSleep: 11 * 60
        ))
        let text = insights.map { "\($0.title) \($0.body)" }.joined(separator: " ").lowercased()

        XCTAssertFalse(text.contains("improved"))
        XCTAssertFalse(text.contains("caused"))
        XCTAssertFalse(text.contains("treated"))
        XCTAssertFalse(text.contains("diagnosed"))
    }
}

private extension ProtocolInsightServiceTests {
    func result(
        confidence: ComparisonConfidence,
        deltaTotalSleep: TimeInterval? = nil,
        deltaEfficiency: Double? = nil,
        deltaDeepSleep: TimeInterval? = nil,
        deltaREMSleep: TimeInterval? = nil
    ) -> ProtocolComparisonResult {
        ProtocolComparisonResult(
            window: .last30Days,
            takenNightCount: confidence == .unavailable ? 1 : 7,
            notTakenNightCount: confidence == .unavailable ? 1 : 7,
            unknownNightCount: 0,
            confidence: confidence,
            averageTotalSleepTaken: deltaTotalSleep.map { 8 * 3_600 + $0 },
            averageTotalSleepNotTaken: deltaTotalSleep.map { _ in 8 * 3_600 },
            deltaTotalSleep: deltaTotalSleep,
            averageEfficiencyTaken: deltaEfficiency.map { 0.90 + $0 },
            averageEfficiencyNotTaken: deltaEfficiency.map { _ in 0.90 },
            deltaEfficiency: deltaEfficiency,
            averageDeepSleepTaken: deltaDeepSleep.map { 90 * 60 + $0 },
            averageDeepSleepNotTaken: deltaDeepSleep.map { _ in 90 * 60 },
            deltaDeepSleep: deltaDeepSleep,
            averageREMSleepTaken: deltaREMSleep.map { 100 * 60 + $0 },
            averageREMSleepNotTaken: deltaREMSleep.map { _ in 100 * 60 },
            deltaREMSleep: deltaREMSleep,
            averageAwakeTimeTaken: nil,
            averageAwakeTimeNotTaken: nil,
            deltaAwakeTime: nil
        )
    }
}
