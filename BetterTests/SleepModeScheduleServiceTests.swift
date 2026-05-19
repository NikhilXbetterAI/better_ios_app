import XCTest
@testable import Better

final class SleepModeScheduleServiceTests: XCTestCase {
    func testDisabledScheduleHasNoNextStartOrCurrentInterval() {
        let schedule = SleepModeSchedule(isEnabled: false)
        let now = Self.date("2026-05-04T12:00:00Z")

        XCTAssertNil(SleepModeScheduleService.nextStartDate(for: schedule, now: now, calendar: Self.utcCalendar))
        XCTAssertNil(SleepModeScheduleService.currentInterval(for: schedule, now: now, calendar: Self.utcCalendar))
    }

    func testSameDayScheduleFindsCurrentIntervalAndNextStart() {
        let schedule = SleepModeSchedule(
            isEnabled: true,
            startHour: 20,
            startMinute: 0,
            endHour: 22,
            endMinute: 0,
            activeWeekdays: Set(1...7)
        )

        let inside = Self.date("2026-05-04T21:00:00Z")
        let interval = SleepModeScheduleService.currentInterval(for: schedule, now: inside, calendar: Self.utcCalendar)
        let next = SleepModeScheduleService.nextStartDate(for: schedule, now: inside, calendar: Self.utcCalendar)

        XCTAssertEqual(interval?.start, Self.date("2026-05-04T20:00:00Z"))
        XCTAssertEqual(interval?.end, Self.date("2026-05-04T22:00:00Z"))
        XCTAssertEqual(next, Self.date("2026-05-05T20:00:00Z"))
    }

    func testOvernightScheduleUsesStartWeekdayAndSpansMidnight() {
        let schedule = SleepModeSchedule(
            isEnabled: true,
            startHour: 22,
            startMinute: 30,
            endHour: 6,
            endMinute: 15,
            activeWeekdays: [2]
        )

        let mondayNight = Self.date("2026-05-04T23:30:00Z")
        let tuesdayMorning = Self.date("2026-05-05T05:30:00Z")
        let interval = SleepModeScheduleService.currentInterval(for: schedule, now: tuesdayMorning, calendar: Self.utcCalendar)

        XCTAssertEqual(Self.utcCalendar.component(.weekday, from: mondayNight), 2)
        XCTAssertEqual(interval?.start, Self.date("2026-05-04T22:30:00Z"))
        XCTAssertEqual(interval?.end, Self.date("2026-05-05T06:15:00Z"))
    }

    func testWeekdayFilteringSkipsInactiveDays() {
        let schedule = SleepModeSchedule(
            isEnabled: true,
            startHour: 21,
            startMinute: 0,
            endHour: 22,
            endMinute: 0,
            activeWeekdays: [4]
        )

        let monday = Self.date("2026-05-04T12:00:00Z")
        let next = SleepModeScheduleService.nextStartDate(for: schedule, now: monday, calendar: Self.utcCalendar)

        XCTAssertEqual(next, Self.date("2026-05-06T21:00:00Z"))
    }

    func testDSTTimezoneScheduleProducesOrderedInterval() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let schedule = SleepModeSchedule(
            isEnabled: true,
            startHour: 1,
            startMinute: 30,
            endHour: 3,
            endMinute: 30,
            activeWeekdays: [1]
        )
        let now = Self.date("2026-03-08T09:45:00Z")

        let interval = SleepModeScheduleService.currentInterval(for: schedule, now: now, calendar: calendar)

        XCTAssertNotNil(interval)
        XCTAssertEqual(calendar.component(.hour, from: interval!.start), 1)
        XCTAssertEqual(calendar.component(.minute, from: interval!.start), 30)
        XCTAssertGreaterThan(interval!.end, interval!.start)
        XCTAssertTrue(interval!.contains(now))
    }

    @MainActor
    func testServiceLoadsAndChecksAutoEnter() async throws {
        let schedule = SleepModeSchedule(
            isEnabled: true,
            startHour: 22,
            startMinute: 0,
            endHour: 6,
            endMinute: 0,
            activeWeekdays: Set(1...7),
            autoEnterWhenForeground: true
        )
        let repository = MockLocalDataRepository(sleepModeSchedule: schedule)
        let service = SleepModeScheduleService(repository: repository, calendar: Self.utcCalendar)

        await service.loadSchedule()

        XCTAssertTrue(service.shouldAutoEnterForeground(now: Self.date("2026-05-04T23:00:00Z")))
    }
}

private extension SleepModeScheduleServiceTests {
    static let utcCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    static func date(_ string: String) -> Date {
        ISO8601DateFormatter().date(from: string)!
    }
}
