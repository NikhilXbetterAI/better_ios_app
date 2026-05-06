import XCTest
@testable import Better

final class ProtocolComparisonDashboardViewModelTests: XCTestCase {
    func testDashboardStateForNotEnoughData() {
        let state = ProtocolComparisonDashboardViewModel.makeState(
            result: result(confidence: .unavailable, taken: 1, notTaken: 1),
            insights: [],
            baselineSelection: baselineSelection(validNights: 14)
        )

        XCTAssertEqual(state.status, .notEnoughData)
        XCTAssertEqual(state.confidence, .unavailable)
    }

    func testDashboardStateForEnoughData() {
        let state = ProtocolComparisonDashboardViewModel.makeState(
            result: result(confidence: .medium, taken: 5, notTaken: 5, deltaTotalSleep: 25 * 60, deltaEfficiency: 0.04),
            insights: [SleepInsight(
                id: "protocol-duration",
                title: "Protocol sleep duration pattern",
                body: "On protocol nights, your sleep duration averaged 25 minutes higher than non-protocol nights.",
                category: .protocolComparison,
                priority: 85,
                confidence: .medium,
                metricDelta: SleepMetricDelta(value: 25, unit: "minutes"),
                displayStyle: .positive
            )],
            baselineSelection: baselineSelection(validNights: 14)
        )

        XCTAssertEqual(state.status, .enoughData)
        XCTAssertEqual(state.takenNightCount, 5)
        XCTAssertEqual(state.notTakenNightCount, 5)
        XCTAssertTrue(state.metricRows.contains { $0.title == "Sleep Duration" && $0.isMeaningful })
        XCTAssertFalse(state.insights.isEmpty)
    }
}

private extension ProtocolComparisonDashboardViewModelTests {
    func result(
        confidence: ComparisonConfidence,
        taken: Int,
        notTaken: Int,
        deltaTotalSleep: TimeInterval? = nil,
        deltaEfficiency: Double? = nil
    ) -> ProtocolComparisonResult {
        ProtocolComparisonResult(
            window: .last30Days,
            takenNightCount: taken,
            notTakenNightCount: notTaken,
            unknownNightCount: 0,
            confidence: confidence,
            averageTotalSleepTaken: deltaTotalSleep.map { 8 * 3_600 + $0 },
            averageTotalSleepNotTaken: deltaTotalSleep.map { _ in 8 * 3_600 },
            deltaTotalSleep: deltaTotalSleep,
            averageEfficiencyTaken: deltaEfficiency.map { 0.90 + $0 },
            averageEfficiencyNotTaken: deltaEfficiency.map { _ in 0.90 },
            deltaEfficiency: deltaEfficiency,
            averageDeepSleepTaken: nil,
            averageDeepSleepNotTaken: nil,
            deltaDeepSleep: nil,
            averageREMSleepTaken: nil,
            averageREMSleepNotTaken: nil,
            deltaREMSleep: nil,
            averageAwakeTimeTaken: nil,
            averageAwakeTimeNotTaken: nil,
            deltaAwakeTime: nil
        )
    }

    func baselineSelection(validNights: Int) -> BaselineSelection {
        let baseline = SleepInsightServiceTests.baseline(validNights: validNights)
        return BaselineSelection(
            activeBaseline: baseline,
            recentBaseline: baseline,
            primaryBaseline: baseline,
            stableBaseline: baseline,
            confidence: BaselineEngine.confidence(validNightCount: validNights),
            validNightCount: validNights,
            excludedNightCount: 0,
            windowUsed: baseline.windowDays
        )
    }
}

