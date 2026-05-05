import HealthKit
import XCTest
@testable import Better

final class SleepDataProcessorTests: XCTestCase {
    private var processor: SleepDataProcessor!

    override func setUp() {
        super.setUp()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        processor = SleepDataProcessor(calendar: calendar, sleepGoalHours: 8)
    }

    func testOverlappingInBedAndStagesDoesNotDoubleCountSleep() {
        let samples = [
            sample(.inBed, start: "2026-05-03T22:00:00Z", end: "2026-05-04T06:00:00Z"),
            sample(.asleepCore, start: "2026-05-03T22:30:00Z", end: "2026-05-04T02:00:00Z"),
            sample(.asleepDeep, start: "2026-05-04T02:00:00Z", end: "2026-05-04T03:30:00Z"),
            sample(.asleepREM, start: "2026-05-04T03:30:00Z", end: "2026-05-04T05:30:00Z")
        ]

        let sessions = processor.process(samples: samples)

        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions[0].totalSleepTime, 7 * 3_600)
        XCTAssertEqual(sessions[0].totalInBedTime, 8 * 3_600)
        XCTAssertEqual(sessions[0].sleepLatency, 30 * 60)
        XCTAssertEqual(sessions[0].dataQuality, .detailedStages)
    }

    func testSessionsUnderFiveMinutesAreFiltered() {
        let sessions = processor.process(samples: [
            sample(.asleepCore, start: "2026-05-03T22:00:00Z", end: "2026-05-03T22:04:00Z")
        ])

        XCTAssertTrue(sessions.isEmpty)
    }

    func testGapOverThirtyMinutesSplitsSessions() {
        let samples = [
            sample(.asleepCore, start: "2026-05-03T21:00:00Z", end: "2026-05-03T22:00:00Z"),
            sample(.asleepREM, start: "2026-05-03T22:45:00Z", end: "2026-05-03T23:45:00Z")
        ]

        let sessions = processor.process(samples: samples)

        XCTAssertEqual(sessions.count, 2)
        XCTAssertEqual(sessions.map(\.totalSleepTime), [3_600, 3_600])
    }

    func testAwakeInsideSleepWindowContributesToWasoAndEfficiency() {
        let samples = [
            sample(.inBed, start: "2026-05-03T22:00:00Z", end: "2026-05-04T06:00:00Z"),
            sample(.asleepCore, start: "2026-05-03T22:30:00Z", end: "2026-05-04T01:00:00Z"),
            sample(.awake, start: "2026-05-04T01:00:00Z", end: "2026-05-04T01:20:00Z"),
            sample(.asleepREM, start: "2026-05-04T01:20:00Z", end: "2026-05-04T05:30:00Z")
        ]

        let session = processor.process(samples: samples)[0]

        XCTAssertEqual(session.waso, 20 * 60)
        XCTAssertEqual(session.awakeDuration, 20 * 60)
        XCTAssertEqual(session.totalSleepTime, 400 * 60)
        XCTAssertEqual(session.efficiency, (400 * 60) / (8 * 3_600), accuracy: 0.0001)
    }

    func testUnspecifiedSleepProducesPartialScoreWithoutRemDeepPenalty() {
        let samples = [
            sample(.inBed, start: "2026-05-03T22:00:00Z", end: "2026-05-04T06:00:00Z"),
            sample(.asleepUnspecified, start: "2026-05-03T22:20:00Z", end: "2026-05-04T05:50:00Z")
        ]

        let session = processor.process(samples: samples)[0]

        XCTAssertEqual(session.dataQuality, .unspecifiedSleepOnly)
        XCTAssertTrue(session.qualityScore.isPartial)
        XCTAssertEqual(session.qualityScore.remScore, 0)
        XCTAssertEqual(session.qualityScore.deepScore, 0)
        XCTAssertGreaterThan(session.qualityScore.overall, 80)
    }

    func testEveningStartAssignsSleepDateKeyToFollowingMorning() {
        let session = processor.process(samples: [
            sample(.asleepCore, start: "2026-05-03T21:30:00Z", end: "2026-05-04T05:30:00Z")
        ])[0]

        XCTAssertEqual(session.sleepDateKey, "2026-05-04")
    }

    func testBaselineRulesExcludeInBedOnlyAndDetailedStageStatsFromUnspecifiedOnly() {
        let detailed = session(
            key: "2026-05-01",
            quality: .detailedStages,
            totalSleep: 8 * 3_600,
            rem: 90 * 60,
            deep: 70 * 60,
            efficiency: 0.91
        )
        let unspecified = session(
            key: "2026-05-02",
            quality: .unspecifiedSleepOnly,
            totalSleep: 7 * 3_600,
            rem: 0,
            deep: 0,
            efficiency: 0.86
        )
        let inBedOnly = session(
            key: "2026-05-03",
            quality: .inBedOnly,
            totalSleep: 8 * 3_600,
            rem: 120 * 60,
            deep: 120 * 60,
            efficiency: 0.9
        )

        let baseline = processor.computeBaseline(
            from: [detailed, unspecified, inBedOnly],
            windowDays: 30,
            generatedAt: Date(timeIntervalSince1970: 0)
        )

        XCTAssertEqual(baseline.validNights, 2)
        XCTAssertEqual(baseline.totalSleepAverage, 7.5 * 3_600)
        XCTAssertEqual(baseline.remAverage, 90 * 60)
        XCTAssertEqual(baseline.deepAverage, 70 * 60)
    }

    func testBaselineScheduleStatsWrapAcrossMidnight() {
        let sessions = [
            session(
                key: "2026-05-01",
                quality: .detailedStages,
                totalSleep: 7 * 3_600,
                rem: 90 * 60,
                deep: 70 * 60,
                efficiency: 0.9,
                start: "2026-04-30T23:30:00Z",
                end: "2026-05-01T06:30:00Z"
            ),
            session(
                key: "2026-05-02",
                quality: .detailedStages,
                totalSleep: 7 * 3_600,
                rem: 90 * 60,
                deep: 70 * 60,
                efficiency: 0.9,
                start: "2026-05-02T00:30:00Z",
                end: "2026-05-02T07:30:00Z"
            )
        ]

        let baseline = processor.computeBaseline(from: sessions, windowDays: 30)

        XCTAssertEqual(baseline.bedtimeMinuteAverage, 0, accuracy: 0.1)
        XCTAssertEqual(baseline.bedtimeMinuteStandardDeviation, 30, accuracy: 0.1)
        XCTAssertEqual(baseline.wakeMinuteAverage, 420, accuracy: 0.1)
        XCTAssertEqual(baseline.wakeMinuteStandardDeviation, 30, accuracy: 0.1)
    }

    func testBaselineScheduleStatsWrapAtMidnightBoundary() {
        let sessions = [
            session(
                key: "2026-05-01",
                quality: .detailedStages,
                totalSleep: 7 * 3_600,
                rem: 90 * 60,
                deep: 70 * 60,
                efficiency: 0.9,
                start: "2026-04-30T23:50:00Z",
                end: "2026-05-01T06:50:00Z"
            ),
            session(
                key: "2026-05-02",
                quality: .detailedStages,
                totalSleep: 7 * 3_600,
                rem: 90 * 60,
                deep: 70 * 60,
                efficiency: 0.9,
                start: "2026-05-02T00:10:00Z",
                end: "2026-05-02T07:10:00Z"
            )
        ]

        let baseline = processor.computeBaseline(from: sessions, windowDays: 30)

        XCTAssertEqual(baseline.bedtimeMinuteAverage, 0, accuracy: 1.0)
        XCTAssertEqual(baseline.bedtimeMinuteStandardDeviation, 10, accuracy: 0.1)
    }

    func testHealthSleepScoreEstimateUsesHealthDerivedComponents() {
        let session = SleepSession(
            sleepDateKey: "2026-05-04",
            startDate: date("2026-05-04T02:18:00Z"),
            endDate: date("2026-05-04T07:47:00Z"),
            dataQuality: .detailedStages,
            totalInBedTime: 329 * 60,
            totalSleepTime: 328 * 60,
            waso: 2 * 60
        )
        let baseline = SleepBaseline(
            windowDays: 30,
            validNights: 10,
            totalSleepAverage: 0,
            totalSleepStandardDeviation: 0,
            remAverage: 0,
            remStandardDeviation: 0,
            deepAverage: 0,
            deepStandardDeviation: 0,
            efficiencyAverage: 0,
            efficiencyStandardDeviation: 0,
            wasoAverage: 0,
            wasoStandardDeviation: 0,
            latencyAverage: 0,
            latencyStandardDeviation: 0,
            hrvAverage: 0,
            hrvStandardDeviation: 0,
            respiratoryRateAverage: 0,
            respiratoryRateStandardDeviation: 0,
            oxygenSaturationAverage: 0,
            oxygenSaturationStandardDeviation: 0,
            bedtimeMinuteAverage: 55,
            bedtimeMinuteStandardDeviation: 30,
            wakeMinuteAverage: 0,
            wakeMinuteStandardDeviation: 0
        )

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let score = HealthSleepScoreEstimator.estimate(session: session, baseline: baseline, calendar: calendar)

        XCTAssertEqual(score.duration, 34)
        XCTAssertEqual(score.bedtime, 15)
        XCTAssertEqual(score.interruptions, 20)
        XCTAssertEqual(score.overall, 69)
    }

    func testBiometricSummaryToleratesMissingTypesAndComputesStats() {
        let sessionID = UUID()
        let samples = [
            biometric(.heartRate, value: 60),
            biometric(.heartRate, value: 54),
            biometric(.heartRate, value: 66),
            biometric(.heartRateVariabilitySDNN, value: 40),
            biometric(.heartRateVariabilitySDNN, value: 44),
            biometric(.oxygenSaturation, value: 0.95)
        ]

        let summary = processor.summarizeBiometrics(
            samples,
            sessionID: sessionID,
            sleepDateKey: "2026-05-04"
        )

        XCTAssertEqual(summary.sleepSessionID, sessionID)
        XCTAssertEqual(summary.heartRateAverage, 60)
        XCTAssertEqual(summary.heartRateMinimum, 54)
        XCTAssertEqual(summary.heartRateMaximum, 66)
        XCTAssertEqual(summary.hrvAverage, 42)
        XCTAssertEqual(summary.hrvMedian, 42)
        XCTAssertEqual(summary.oxygenSaturationMinimum, 0.95)
        XCTAssertNil(summary.respiratoryRateAverage)
    }
}

private extension SleepDataProcessorTests {
    func sample(
        _ value: HKCategoryValueSleepAnalysis,
        start: String,
        end: String,
        metadata: [String: Any]? = nil
    ) -> HKCategorySample {
        HKCategorySample(
            type: HKCategoryType(.sleepAnalysis),
            value: value.rawValue,
            start: date(start),
            end: date(end),
            metadata: metadata
        )
    }

    func date(_ string: String) -> Date {
        ISO8601DateFormatter().date(from: string)!
    }

    func session(
        key: String,
        quality: SleepDataQuality,
        totalSleep: TimeInterval,
        rem: TimeInterval,
        deep: TimeInterval,
        efficiency: Double,
        start: String? = nil,
        end: String? = nil
    ) -> SleepSession {
        let startDate = start.map(date) ?? Date(timeIntervalSince1970: 0)
        let endDate = end.map(date) ?? Date(timeIntervalSince1970: totalSleep)
        return SleepSession(
            sleepDateKey: key,
            startDate: startDate,
            endDate: endDate,
            dataQuality: quality,
            totalInBedTime: totalSleep / efficiency,
            totalSleepTime: totalSleep,
            deepDuration: deep,
            remDuration: rem,
            efficiency: efficiency
        )
    }

    func biometric(_ type: BiometricType, value: Double) -> BiometricSample {
        BiometricSample(
            type: type,
            value: value,
            unit: type.unitSymbol,
            startDate: Date(timeIntervalSince1970: 0),
            endDate: Date(timeIntervalSince1970: 60)
        )
    }
}
