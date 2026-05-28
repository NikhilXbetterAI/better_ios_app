import XCTest
@testable import Better

final class BaselineEngineDashboardTests: XCTestCase {
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    private let asOf = ISO8601DateFormatter().date(from: "2026-05-25T00:00:00Z")!

    func testPrimary30DayWindowWhenLast30DaysHaveEnoughValidNights() {
        let engine = BaselineEngine(processor: SleepDataProcessor(calendar: Self.calendar), calendar: Self.calendar)
        // 6 nights all within the last 30 days
        let sessions = (1...6).map { Self.session(day: 19 + $0, hours: 7) } // 2026-05-20..25
        let result = engine.selectDashboardBaseline(from: sessions, generatedAt: asOf)
        XCTAssertEqual(result.activeBaseline?.windowDays, 30)
        XCTAssertEqual(result.activeBaseline?.validNights, 6)
        XCTAssertFalse(result.isBuilding)
    }

    func testFallsBackTo60DayWindowWhenLast30DaysAreSparse() {
        let engine = BaselineEngine(processor: SleepDataProcessor(calendar: Self.calendar), calendar: Self.calendar)
        // Only 4 nights in the last 30 days (insufficient) but 5+ total within last 60 days.
        let recent = (1...4).map { Self.session(day: 19 + $0, hours: 7) }
        let older = (1...3).map { Self.session(month: 4, day: 5 + $0, hours: 7) } // April → inside 60-day window
        let result = engine.selectDashboardBaseline(from: recent + older, generatedAt: asOf)
        XCTAssertEqual(result.activeBaseline?.windowDays, 60)
        XCTAssertEqual(result.activeBaseline?.validNights, 7)
    }

    func testBuildingWhenBothWindowsHaveTooFewValidNights() {
        let engine = BaselineEngine(processor: SleepDataProcessor(calendar: Self.calendar), calendar: Self.calendar)
        let sessions = (1...4).map { Self.session(day: 19 + $0, hours: 7) }
        let result = engine.selectDashboardBaseline(from: sessions, generatedAt: asOf)
        XCTAssertNil(result.activeBaseline)
        XCTAssertTrue(result.isBuilding)
    }

    func testGenericSelectBaselineUnchanged() {
        // Regression guard: the dashboard override must not have altered the
        // generic 14/7 selector used by Trends / Research / CSV.
        let engine = BaselineEngine(processor: SleepDataProcessor(calendar: Self.calendar), calendar: Self.calendar)
        let result = engine.selectBaseline(
            from: (1...14).map { Self.session(day: $0, hours: 7) },
            generatedAt: Self.date("2026-05-15T00:00:00Z")
        )
        XCTAssertEqual(result.activeBaseline?.windowDays, 14)
    }

    // MARK: - helpers

    private static func session(
        month: Int = 5,
        day: Int,
        hours: Double,
        quality: SleepDataQuality = .detailedStages
    ) -> SleepSession {
        let key = String(format: "2026-%02d-%02d", month, day)
        let start = date(String(format: "2026-%02d-%02dT22:00:00Z", month, day))
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

    private static func date(_ string: String) -> Date {
        ISO8601DateFormatter().date(from: string)!
    }
}
