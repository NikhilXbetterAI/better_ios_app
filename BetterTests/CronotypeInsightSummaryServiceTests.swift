import XCTest
@testable import Better

final class ChronotypeInsightSummaryServiceTests: XCTestCase {
    func testFormulaAndAvoidTimingWrapAroundMidnight() {
        let state = service.dashboardState(
            result: makeResult(windowStart: 30, windowEnd: 510),
            sessions: sessions,
            baseline: nil,
            sleepGoalHours: 8,
            calendar: Self.calendar
        )

        XCTAssertEqual(state.recommendedFormulaMinute, 1_410)
        XCTAssertEqual(state.avoidSleepBeforeMinute, 1_410)
        XCTAssertEqual(state.avoidSleepAfterMinute, 90)
    }

    func testBestAndWorstNightRankingUsesSleepScore() {
        let best = makeSession(
            key: "2026-04-01",
            onset: "2026-04-01T23:00:00Z",
            durationHours: 8,
            deepHours: 1.5,
            remHours: 1.5,
            wasoMinutes: 10
        )
        let worst = makeSession(
            key: "2026-04-02",
            onset: "2026-04-02T23:00:00Z",
            durationHours: 4,
            deepHours: 0.2,
            remHours: 0.2,
            wasoMinutes: 90
        )

        XCTAssertEqual(
            service.bestNight(sessions: [worst, best], baseline: nil, sleepGoalHours: 8, calendar: Self.calendar)?.sleepDateKey,
            best.sleepDateKey
        )
        XCTAssertEqual(
            service.worstNight(sessions: [worst, best], estimate: makeEstimate(windowStart: 1_380, windowEnd: 420), baseline: nil, sleepGoalHours: 8, calendar: Self.calendar)?.sleepDateKey,
            worst.sleepDateKey
        )
    }

    func testSleepWindowImpactRequiresThreeNightsPerGroup() {
        let estimate = makeEstimate(windowStart: 1_380, windowEnd: 420)
        let impact = service.impactSummary(
            sessions: Array(sessions.prefix(5)),
            estimate: estimate,
            baseline: nil,
            sleepGoalHours: 8,
            calendar: Self.calendar
        )

        XCTAssertFalse(impact.hasEnoughData)
        XCTAssertNil(impact.deepDelta)
    }

    func testSleepWindowImpactDeltasCompareInWindowAgainstOutsideWindow() {
        let estimate = makeEstimate(windowStart: 1_380, windowEnd: 420)
        let impact = service.impactSummary(
            sessions: sessions,
            estimate: estimate,
            baseline: nil,
            sleepGoalHours: 8,
            calendar: Self.calendar
        )

        XCTAssertTrue(impact.hasEnoughData)
        XCTAssertGreaterThan(impact.scoreDelta ?? 0, 0)
        XCTAssertEqual(impact.restorativeDelta ?? 0, 90 * 60, accuracy: 1)
        XCTAssertEqual(impact.deepDelta ?? 0, 45 * 60, accuracy: 1)
        XCTAssertEqual(impact.remDelta ?? 0, 45 * 60, accuracy: 1)
        XCTAssertEqual(impact.awakeDelta ?? 0, -30 * 60, accuracy: 1)
        XCTAssertEqual(impact.durationDelta ?? 0, 60 * 60, accuracy: 1)
    }
}

private extension ChronotypeInsightSummaryServiceTests {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    var service: ChronotypeInsightSummaryService {
        ChronotypeInsightSummaryService()
    }

    var sessions: [SleepSession] {
        [
            makeSession(key: "2026-04-01", onset: "2026-04-01T23:00:00Z", durationHours: 8, deepHours: 1.5, remHours: 1.5, wasoMinutes: 20),
            makeSession(key: "2026-04-02", onset: "2026-04-02T23:15:00Z", durationHours: 8, deepHours: 1.5, remHours: 1.5, wasoMinutes: 20),
            makeSession(key: "2026-04-03", onset: "2026-04-03T22:45:00Z", durationHours: 8, deepHours: 1.5, remHours: 1.5, wasoMinutes: 20),
            makeSession(key: "2026-04-04", onset: "2026-04-04T02:00:00Z", durationHours: 7, deepHours: 0.75, remHours: 0.75, wasoMinutes: 50),
            makeSession(key: "2026-04-05", onset: "2026-04-05T02:15:00Z", durationHours: 7, deepHours: 0.75, remHours: 0.75, wasoMinutes: 50),
            makeSession(key: "2026-04-06", onset: "2026-04-06T01:45:00Z", durationHours: 7, deepHours: 0.75, remHours: 0.75, wasoMinutes: 50)
        ]
    }

    func makeResult(windowStart: Int, windowEnd: Int) -> ChronotypeCalculationResult {
        ChronotypeCalculationResult(
            status: .estimated,
            estimate: makeEstimate(windowStart: windowStart, windowEnd: windowEnd),
            includedNights: sessions.map { session in
                ChronotypeNight(
                    sleepDateKey: session.sleepDateKey,
                    dayType: .workday,
                    onset: session.startDate,
                    wake: session.endDate,
                    duration: session.totalSleepTime,
                    midpointMinute: 180
                )
            },
            excludedCountsByReason: [:],
            totalCandidateNightCount: sessions.count,
            validNightCount: sessions.count,
            workdayNightCount: sessions.count,
            freeDayNightCount: 0,
            missingRequirements: [],
            windowDays: 90,
            windowStart: date("2026-01-01T00:00:00Z"),
            windowEnd: date("2026-05-01T00:00:00Z")
        )
    }

    func makeEstimate(windowStart: Int, windowEnd: Int) -> ChronotypeEstimate {
        ChronotypeEstimate(
            bucket: .intermediate,
            correctedMidpointMinute: 180,
            workdayMidpointMinute: 180,
            freeDayMidpointMinute: 180,
            workdayMedianDuration: 8 * 3_600,
            freeDayMedianDuration: 8 * 3_600,
            weeklyAverageDuration: 8 * 3_600,
            validNightCount: 10,
            workdayNightCount: 8,
            freeDayNightCount: 2,
            excludedNightCount: 0,
            excludedCountsByReason: [:],
            confidence: .low,
            bodyClockReadiness: .preview,
            optimalSleepWindow: SleepWindowRecommendation(startMinute: windowStart, endMinute: windowEnd, duration: 8 * 3_600)
        )
    }

    func makeSession(
        key: String,
        onset: String,
        durationHours: Double,
        deepHours: Double,
        remHours: Double,
        wasoMinutes: Double
    ) -> SleepSession {
        let onsetDate = date(onset)
        let duration = durationHours * 3_600
        let endDate = onsetDate.addingTimeInterval(duration + wasoMinutes * 60)
        return SleepSession(
            sleepDateKey: key,
            startDate: onsetDate,
            endDate: endDate,
            stages: [
                SleepStage(type: .core, startDate: onsetDate, endDate: onsetDate.addingTimeInterval(duration), source: nil)
            ],
            sources: [SleepSource(name: "Apple Watch", bundleIdentifier: "com.apple.watch", productType: "Watch7,1")],
            dataQuality: .detailedStages,
            totalInBedTime: duration + wasoMinutes * 60,
            totalSleepTime: duration,
            awakeDuration: wasoMinutes * 60,
            coreDuration: max(0, duration - deepHours * 3_600 - remHours * 3_600),
            deepDuration: deepHours * 3_600,
            remDuration: remHours * 3_600,
            waso: wasoMinutes * 60,
            efficiency: duration / (duration + wasoMinutes * 60)
        )
    }

    func date(_ string: String) -> Date {
        ISO8601DateFormatter().date(from: string)!
    }
}
