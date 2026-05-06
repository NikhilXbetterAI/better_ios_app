import XCTest
@testable import Better

final class ContextComparisonServiceTests: XCTestCase {
    private var service: ContextComparisonService!
    private var endDate: Date!

    override func setUp() {
        super.setUp()
        service = ContextComparisonService(calendar: Self.calendar)
        endDate = Self.date("2026-05-31T12:00:00Z")
    }

    // MARK: - Grouping and unknown exclusion

    func testUnknownNightsExcludedFromAverages() {
        // Yes: nights 1-3 (7h), No: nights 4-6 (5h), Unknown: night 7 (9h — should not affect results)
        let sessions: [SleepSession] = [
            session(day: 1, hours: 7), session(day: 2, hours: 7), session(day: 3, hours: 7),
            session(day: 4, hours: 5), session(day: 5, hours: 5), session(day: 6, hours: 5),
            session(day: 7, hours: 9) // no context entry → unknown
        ]
        let context = [
            entry(day: 1, caffeineLate: true),
            entry(day: 2, caffeineLate: true),
            entry(day: 3, caffeineLate: true),
            entry(day: 4, caffeineLate: false),
            entry(day: 5, caffeineLate: false),
            entry(day: 6, caffeineLate: false),
            // Day 7: no context entry → unknown
        ]
        let result = service.compare(
            sessions: sessions, contextEntries: context, adherence: [],
            factor: .caffeineLate, window: .all, endingAt: endDate
        )
        XCTAssertEqual(result.yesNightCount,     3)
        XCTAssertEqual(result.noNightCount,      3)
        XCTAssertEqual(result.unknownNightCount, 1)
        XCTAssertEqual(result.averageSleepDurationYes ?? 0, 7 * 3_600, accuracy: 1)
        XCTAssertEqual(result.averageSleepDurationNo  ?? 0, 5 * 3_600, accuracy: 1)
        // Delta = yes - no = 2h = 7200s
        XCTAssertEqual(result.durationDelta ?? 0, 2 * 3_600, accuracy: 1)
    }

    func testExplicitFalseIsNotSameAsUnknown() {
        let sessions: [SleepSession] = [session(day: 1, hours: 6), session(day: 2, hours: 8)]
        let context = [
            entry(day: 1, caffeineLate: false), // explicit no
            // day 2: no entry → unknown
        ]
        let result = service.compare(
            sessions: sessions, contextEntries: context, adherence: [],
            factor: .caffeineLate, window: .all, endingAt: endDate
        )
        XCTAssertEqual(result.noNightCount,      1, "explicit false must be counted in 'no' group")
        XCTAssertEqual(result.unknownNightCount, 1, "missing entry must be counted in 'unknown' group")
        XCTAssertEqual(result.yesNightCount,     0)
    }

    // MARK: - Confidence levels

    func testHighConfidenceWith7vs7Nights() {
        let result = makeResultFor(yesCount: 7, noCount: 7)
        XCTAssertEqual(result.confidence, .high)
    }

    func testMediumConfidenceWith4vs4Nights() {
        let result = makeResultFor(yesCount: 4, noCount: 4)
        XCTAssertEqual(result.confidence, .medium)
    }

    func testLowConfidenceWith2vs3Nights() {
        let result = makeResultFor(yesCount: 2, noCount: 3)
        XCTAssertEqual(result.confidence, .low)
    }

    func testUnavailableConfidenceWhenOneSideHasFewerThan2() {
        let result = makeResultFor(yesCount: 1, noCount: 10)
        XCTAssertEqual(result.confidence, .unavailable)
    }

    // MARK: - Stage data suppression

    func testStagesDeltasNilWhenNoDetailedData() {
        let sessions: [SleepSession] = [
            session(day: 1, hours: 7, quality: .unspecifiedSleepOnly),
            session(day: 2, hours: 6, quality: .unspecifiedSleepOnly),
        ]
        let context = [entry(day: 1, caffeineLate: true), entry(day: 2, caffeineLate: false)]
        let result = service.compare(
            sessions: sessions, contextEntries: context, adherence: [],
            factor: .caffeineLate, window: .all, endingAt: endDate
        )
        XCTAssertNil(result.deepSleepDelta, "Stage delta must be nil when data quality is not detailedStages")
        XCTAssertNil(result.remSleepDelta)
    }

    func testStagesDeltaPresentWhenDetailedDataAvailable() {
        let sessions: [SleepSession] = [
            session(day: 1, hours: 7, quality: .detailedStages, deep: 100 * 60, rem: 90 * 60),
            session(day: 2, hours: 7, quality: .detailedStages, deep: 60 * 60, rem: 60 * 60),
        ]
        let context = [entry(day: 1, caffeineLate: true), entry(day: 2, caffeineLate: false)]
        let result = service.compare(
            sessions: sessions, contextEntries: context, adherence: [],
            factor: .caffeineLate, window: .all, endingAt: endDate
        )
        XCTAssertNotNil(result.deepSleepDelta)
        XCTAssertEqual(result.deepSleepDelta ?? 0, 40 * 60, accuracy: 1)
    }

    // MARK: - Meaningful difference threshold

    func testHasMeaningfulDifferenceWhenDurationExceedsThreshold() {
        // Yes: 8h, No: 5h → delta = 3h ≥ 20min threshold
        let sessions: [SleepSession] = (1...7).map { day in session(day: day, hours: day <= 4 ? 8 : 5) }
        let context = (1...7).map { day in entry(day: day, caffeineLate: day <= 4) }
        let result = service.compare(
            sessions: sessions, contextEntries: context, adherence: [],
            factor: .caffeineLate, window: .all, endingAt: endDate
        )
        XCTAssertTrue(result.hasMeaningfulDifference)
    }

    func testNoMeaningfulDifferenceWhenDeltasBelowThresholds() {
        // Yes: 7h, No: 6h 55min → delta = 5min < 20min threshold
        let sessions: [SleepSession] = [
            session(day: 1, hours: 7),
            session(day: 2, hours: 6 + (55.0 / 60.0)),
        ]
        let context = [entry(day: 1, caffeineLate: true), entry(day: 2, caffeineLate: false)]
        let result = service.compare(
            sessions: sessions, contextEntries: context, adherence: [],
            factor: .caffeineLate, window: .all, endingAt: endDate
        )
        XCTAssertFalse(result.hasMeaningfulDifference)
    }

    // MARK: - protocolTaken factor uses adherence not context

    func testProtocolTakenFactorUsesAdherenceRecords() {
        let sessions = [session(day: 1, hours: 8), session(day: 2, hours: 6)]
        let adherence = [
            ProtocolAdherence(protocolID: "p1", dateKey: "2026-05-01", taken: true),
            ProtocolAdherence(protocolID: "p1", dateKey: "2026-05-02", taken: false),
        ]
        let result = service.compare(
            sessions: sessions, contextEntries: [], adherence: adherence,
            factor: .protocolTaken, window: .all, endingAt: endDate
        )
        XCTAssertEqual(result.yesNightCount, 1)
        XCTAssertEqual(result.noNightCount,  1)
    }
}

// MARK: - Helpers

private extension ContextComparisonServiceTests {
    static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(secondsFromGMT: 0)!
        return c
    }()

    static func date(_ string: String) -> Date {
        ISO8601DateFormatter().date(from: string)!
    }

    func session(
        day: Int,
        hours: Double,
        quality: SleepDataQuality = .detailedStages,
        deep: TimeInterval = 90 * 60,
        rem:  TimeInterval = 90 * 60
    ) -> SleepSession {
        let key   = String(format: "2026-05-%02d", day)
        let start = Self.date(String(format: "2026-05-%02dT22:00:00Z", day))
        let end   = start.addingTimeInterval((hours + 0.5) * 3_600)
        let total = hours * 3_600
        let inBed = total + 30 * 60
        return SleepSession(
            sleepDateKey: key,
            startDate: start,
            endDate: end,
            dataQuality: quality,
            totalInBedTime: inBed,
            totalSleepTime: total,
            awakeDuration: 30 * 60,
            coreDuration: max(0, total - deep - rem),
            deepDuration: deep,
            remDuration: rem,
            efficiency: total / inBed
        )
    }

    func entry(day: Int, caffeineLate: Bool?) -> SleepContextEntry {
        SleepContextEntry(
            sleepDateKey: String(format: "2026-05-%02d", day),
            caffeineLate: caffeineLate
        )
    }

    /// Utility: build a result with N yes and M no nights (7h vs 5h) for confidence tests.
    func makeResultFor(yesCount: Int, noCount: Int) -> ContextComparisonResult {
        let yesNights = (1...yesCount).map { day in session(day: day, hours: 7) }
        let noNights  = (yesCount + 1...yesCount + noCount).map { day in session(day: day, hours: 5) }
        let allSessions = yesNights + noNights

        let yesContext = (1...yesCount).map { day in entry(day: day, caffeineLate: true) }
        let noContext  = (yesCount + 1...yesCount + noCount).map { day in entry(day: day, caffeineLate: false) }
        let allContext = yesContext + noContext

        let lastDay = yesCount + noCount
        let end = Self.date(String(format: "2026-05-%02dT12:00:00Z", lastDay))
        return service.compare(
            sessions: allSessions, contextEntries: allContext, adherence: [],
            factor: .caffeineLate, window: .all, endingAt: end
        )
    }
}
