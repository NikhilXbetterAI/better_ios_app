import XCTest
@testable import Better

final class BaselineEngineTests: XCTestCase {
    func testSelectsFourteenNightPrimaryBaselineWhenAvailable() {
        let engine = BaselineEngine(
            processor: SleepDataProcessor(calendar: Self.calendar),
            calendar: Self.calendar
        )

        let result = engine.selectBaseline(
            from: (1...14).map { Self.session(day: $0, hours: 7) },
            generatedAt: Self.date("2026-05-15T00:00:00Z")
        )

        XCTAssertEqual(result.activeBaseline?.windowDays, 14)
        XCTAssertEqual(result.activeBaseline?.validNights, 14)
        XCTAssertEqual(result.confidence, .high)
        XCTAssertFalse(result.isBuilding)
    }

    func testFallsBackToSevenNightBaselineWithSevenToThirteenValidNights() {
        let engine = BaselineEngine(
            processor: SleepDataProcessor(calendar: Self.calendar),
            calendar: Self.calendar
        )

        let result = engine.selectBaseline(
            from: (1...10).map { Self.session(day: $0, hours: 7) },
            generatedAt: Self.date("2026-05-11T00:00:00Z")
        )

        XCTAssertEqual(result.activeBaseline?.windowDays, 7)
        XCTAssertEqual(result.activeBaseline?.validNights, 7)
        XCTAssertEqual(result.validNightCount, 10)
        XCTAssertEqual(result.confidence, .medium)
    }

    func testBaselineBuildingWhenFewerThanSevenValidNights() {
        let engine = BaselineEngine(
            processor: SleepDataProcessor(calendar: Self.calendar),
            calendar: Self.calendar
        )

        let result = engine.selectBaseline(
            from: (1...6).map { Self.session(day: $0, hours: 7) },
            generatedAt: Self.date("2026-05-07T00:00:00Z")
        )

        XCTAssertNil(result.activeBaseline)
        XCTAssertTrue(result.isBuilding)
        XCTAssertEqual(result.confidence, .low)
    }

    func testInvalidAndOutlierNightsAreExcluded() {
        let valid = Self.session(day: 1, hours: 7)
        let shortNap = Self.session(day: 2, hours: 1.5)
        let outlier = Self.session(day: 3, hours: 15)
        let inBedOnly = Self.session(day: 4, hours: 7, quality: .inBedOnly)
        var negative = Self.session(day: 5, hours: 7)
        negative.awakeDuration = -1
        var impossibleInBed = Self.session(day: 6, hours: 7)
        impossibleInBed.totalInBedTime = 6 * 3_600

        XCTAssertTrue(BaselineEngine.isValidNight(valid, calendar: Self.calendar))
        XCTAssertFalse(BaselineEngine.isValidNight(shortNap, calendar: Self.calendar))
        XCTAssertFalse(BaselineEngine.isValidNight(outlier, calendar: Self.calendar))
        XCTAssertFalse(BaselineEngine.isValidNight(inBedOnly, calendar: Self.calendar))
        XCTAssertFalse(BaselineEngine.isValidNight(negative, calendar: Self.calendar))
        XCTAssertFalse(BaselineEngine.isValidNight(impossibleInBed, calendar: Self.calendar))
    }
}

private extension BaselineEngineTests {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    static func session(
        day: Int,
        hours: Double,
        quality: SleepDataQuality = .detailedStages
    ) -> SleepSession {
        let key = String(format: "2026-05-%02d", day)
        let start = date(String(format: "2026-05-%02dT22:00:00Z", day))
        let totalSleep = hours * 3_600
        let totalInBed = totalSleep + 30 * 60
        return SleepSession(
            sleepDateKey: key,
            startDate: start,
            endDate: start.addingTimeInterval(totalInBed),
            dataQuality: quality,
            totalInBedTime: totalInBed,
            totalSleepTime: totalSleep,
            awakeDuration: 30 * 60,
            coreDuration: totalSleep * 0.6,
            deepDuration: totalSleep * 0.2,
            remDuration: totalSleep * 0.2,
            sleepLatency: 10 * 60,
            waso: 20 * 60,
            efficiency: totalSleep / totalInBed
        )
    }

    static func date(_ string: String) -> Date {
        ISO8601DateFormatter().date(from: string)!
    }
}
