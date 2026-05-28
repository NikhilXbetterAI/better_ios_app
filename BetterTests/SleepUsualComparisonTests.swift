import XCTest
@testable import Better

final class SleepUsualComparisonTests: XCTestCase {
    func testRowStatusAboutUsualWhenDifferenceIsWithinHalfSD() {
        let status = SleepUsualComparison.rowStatus(
            value: 7 * 60,
            baselineAverage: 7 * 60,
            baselineStdDev: 30,
            lowerIsBetter: false
        )
        XCTAssertEqual(status, .aboutUsual)
    }

    func testRowStatusMoreThanUsualWhenAboveBaseline() {
        let status = SleepUsualComparison.rowStatus(
            value: 8 * 60,
            baselineAverage: 7 * 60,
            baselineStdDev: 30,
            lowerIsBetter: false
        )
        XCTAssertEqual(status, .moreThanUsual)
    }

    func testFewerWakeUpsForAwakeMetricBelowBaseline() {
        let status = SleepUsualComparison.rowStatus(
            value: 5,
            baselineAverage: 30,
            baselineStdDev: 10,
            lowerIsBetter: true,
            isAwakeMetric: true
        )
        XCTAssertEqual(status, .fewerWakeUps)
    }

    func testFavorabilityFlipsForLowerIsBetterMetrics() {
        XCTAssertEqual(
            SleepUsualComparison.isFavorable(status: .moreThanUsual, lowerIsBetter: true),
            false
        )
        XCTAssertEqual(
            SleepUsualComparison.isFavorable(status: .moreThanUsual, lowerIsBetter: false),
            true
        )
        XCTAssertNil(SleepUsualComparison.isFavorable(status: .aboutUsual, lowerIsBetter: false))
    }

    func testVerdictBetterWhenSessionClearlyExceedsBaseline() {
        let baseline = Self.baseline(totalHours: 7)
        let session = Self.session(totalHours: 8, deepMinutes: 110, remMinutes: 100, awakeMinutes: 10, latencyMin: 5)
        XCTAssertEqual(SleepUsualComparison.classify(session: session, baseline: baseline), .better)
    }

    func testVerdictHarderWhenSessionClearlyBelowBaseline() {
        let baseline = Self.baseline(totalHours: 7)
        let session = Self.session(totalHours: 5, deepMinutes: 30, remMinutes: 40, awakeMinutes: 90, latencyMin: 60)
        XCTAssertEqual(SleepUsualComparison.classify(session: session, baseline: baseline), .harder)
    }

    func testVerdictUsualWhenNearBaseline() {
        let baseline = Self.baseline(totalHours: 7)
        let session = Self.session(totalHours: 7, deepMinutes: 80, remMinutes: 90, awakeMinutes: 25, latencyMin: 14)
        XCTAssertEqual(SleepUsualComparison.classify(session: session, baseline: baseline), .usual)
    }

    // MARK: - helpers

    private static func session(
        totalHours: Double,
        deepMinutes: Double,
        remMinutes: Double,
        awakeMinutes: Double,
        latencyMin: Double
    ) -> SleepSession {
        SleepSession(
            sleepDateKey: "2026-05-25",
            startDate: Date(),
            endDate: Date().addingTimeInterval(totalHours * 3600),
            dataQuality: .detailedStages,
            totalInBedTime: totalHours * 3600 + awakeMinutes * 60,
            totalSleepTime: totalHours * 3600,
            awakeDuration: awakeMinutes * 60,
            coreDuration: totalHours * 3600 - (deepMinutes + remMinutes) * 60,
            deepDuration: deepMinutes * 60,
            remDuration: remMinutes * 60,
            sleepLatency: latencyMin * 60,
            waso: awakeMinutes * 60,
            efficiency: 0.9
        )
    }

    private static func baseline(totalHours: Double) -> SleepBaseline {
        SleepBaseline(
            windowDays: 30,
            validNights: 14,
            totalSleepAverage: totalHours * 3600,
            totalSleepStandardDeviation: 30 * 60,
            remAverage: 90 * 60,
            remStandardDeviation: 15 * 60,
            deepAverage: 80 * 60,
            deepStandardDeviation: 15 * 60,
            efficiencyAverage: 0.88,
            efficiencyStandardDeviation: 0.04,
            wasoAverage: 25 * 60,
            wasoStandardDeviation: 10 * 60,
            latencyAverage: 15 * 60,
            latencyStandardDeviation: 8 * 60,
            hrvAverage: 0, hrvStandardDeviation: 0,
            respiratoryRateAverage: 0, respiratoryRateStandardDeviation: 0,
            oxygenSaturationAverage: 0, oxygenSaturationStandardDeviation: 0,
            bedtimeMinuteAverage: 22 * 60, bedtimeMinuteStandardDeviation: 30,
            wakeMinuteAverage: 6 * 60, wakeMinuteStandardDeviation: 30
        )
    }
}
