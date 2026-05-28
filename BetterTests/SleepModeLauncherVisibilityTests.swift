import XCTest
@testable import Better

final class SleepModeLauncherVisibilityTests: XCTestCase {
    private static let calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal
    }()

    func testLauncherHiddenDuringDayWithoutActiveSchedule() {
        let schedule = SleepModeSchedule(isEnabled: false)
        let twoPM = Self.date("2026-05-25T14:00:00Z")
        XCTAssertFalse(SleepModeScheduleService.shouldShowLauncher(schedule: schedule, now: twoPM, calendar: Self.calendar))
    }

    func testLauncherVisibleAfter20LocalWithoutSchedule() {
        let schedule = SleepModeSchedule(isEnabled: false)
        let eightPM = Self.date("2026-05-25T20:05:00Z")
        XCTAssertTrue(SleepModeScheduleService.shouldShowLauncher(schedule: schedule, now: eightPM, calendar: Self.calendar))
    }

    func testLauncherVisibleDuringActiveScheduledIntervalEvenInTheAfternoon() {
        // Build an enabled schedule that spans 13:00 → 16:00 (a contrived but
        // valid daytime window), and assert the launcher surfaces at 14:00.
        let schedule = SleepModeSchedule(
            isEnabled: true,
            startHour: 13,
            startMinute: 0,
            endHour: 16,
            endMinute: 0,
            activeWeekdays: Set(1...7)
        )
        let twoPM = Self.date("2026-05-25T14:00:00Z")
        XCTAssertTrue(SleepModeScheduleService.shouldShowLauncher(schedule: schedule, now: twoPM, calendar: Self.calendar))
    }

    private static func date(_ string: String) -> Date {
        ISO8601DateFormatter().date(from: string)!
    }
}
