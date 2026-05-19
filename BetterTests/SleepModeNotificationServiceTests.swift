import XCTest
@preconcurrency import UserNotifications
@testable import Better

final class SleepModeNotificationServiceTests: XCTestCase {
    func testReminderSchedulingCreatesOneRepeatingRequestPerActiveWeekday() async throws {
        let center = MockSleepModeNotificationCenter(authorizationStatus: .authorized)
        let service = SleepModeNotificationService(center: center, now: { Self.date("2026-05-04T12:00:00Z") })
        let schedule = SleepModeSchedule(
            isEnabled: true,
            startHour: 22,
            startMinute: 30,
            endHour: 6,
            endMinute: 30,
            activeWeekdays: [2, 3, 4],
            remindersEnabled: true
        )

        let status = try await service.scheduleReminders(for: schedule, calendar: Self.utcCalendar)

        let requests = await center.pendingNotificationRequests()
        XCTAssertEqual(requests.count, 3)
        XCTAssertEqual(requests.map(\.identifier).sorted(), ["sleep-mode-start-2", "sleep-mode-start-3", "sleep-mode-start-4"])
        XCTAssertTrue(requests.allSatisfy { ($0.trigger as? UNCalendarNotificationTrigger)?.repeats == true })
        if case .scheduled(let count, _) = status {
            XCTAssertEqual(count, 3)
        } else {
            XCTFail("Expected scheduled status, got \(status)")
        }
    }

    func testDisabledScheduleRemovesExistingRequestsAndSchedulesNothing() async throws {
        let center = MockSleepModeNotificationCenter(authorizationStatus: .authorized)
        let service = SleepModeNotificationService(center: center)
        try await center.add(UNNotificationRequest(
            identifier: "sleep-mode-start-2",
            content: UNMutableNotificationContent(),
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 60, repeats: false)
        ))

        let status = try await service.scheduleReminders(for: SleepModeSchedule(isEnabled: false), calendar: Self.utcCalendar)

        let requests = await center.pendingNotificationRequests()
        XCTAssertEqual(requests.count, 0)
        XCTAssertEqual(status, .notScheduled(.scheduleDisabled))
    }

    func testDeniedPermissionReturnsPermissionDeniedStatus() async throws {
        let center = MockSleepModeNotificationCenter(authorizationStatus: .denied)
        let service = SleepModeNotificationService(center: center)
        let schedule = SleepModeSchedule(isEnabled: true, remindersEnabled: true)

        let status = try await service.scheduleReminders(for: schedule, calendar: Self.utcCalendar)

        XCTAssertEqual(status, .notScheduled(.permissionDenied))
        let requests = await center.pendingNotificationRequests()
        XCTAssertEqual(requests.count, 0)
    }

    func testDeniedPermissionPreservesExistingReminderRequests() async throws {
        let center = MockSleepModeNotificationCenter(authorizationStatus: .denied)
        let service = SleepModeNotificationService(center: center)
        let existingRequest = UNNotificationRequest(
            identifier: "sleep-mode-start-2",
            content: UNMutableNotificationContent(),
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 60, repeats: false)
        )
        try await center.add(existingRequest)

        let status = try await service.scheduleReminders(
            for: SleepModeSchedule(isEnabled: true, remindersEnabled: true),
            calendar: Self.utcCalendar
        )

        let requests = await center.pendingNotificationRequests()
        XCTAssertEqual(status, .notScheduled(.permissionDenied))
        XCTAssertEqual(requests.map(\.identifier), ["sleep-mode-start-2"])
    }

    func testAddFailureRestoresExistingReminderRequests() async throws {
        let center = MockSleepModeNotificationCenter(authorizationStatus: .authorized)
        center.failingAddIdentifiers = ["sleep-mode-start-3"]
        let service = SleepModeNotificationService(center: center)
        let existingRequest = UNNotificationRequest(
            identifier: "sleep-mode-start-2",
            content: UNMutableNotificationContent(),
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 60, repeats: false)
        )
        try await center.add(existingRequest)

        do {
            _ = try await service.scheduleReminders(
                for: SleepModeSchedule(isEnabled: true, activeWeekdays: [2, 3], remindersEnabled: true),
                calendar: Self.utcCalendar
            )
            XCTFail("Expected add failure")
        } catch {
            let requests = await center.pendingNotificationRequests()
            XCTAssertEqual(requests.map(\.identifier), ["sleep-mode-start-2"])
        }
    }

    func testReminderLeadMinutesCanShiftToPreviousWeekday() async throws {
        let center = MockSleepModeNotificationCenter(authorizationStatus: .authorized)
        let service = SleepModeNotificationService(center: center, now: { Self.date("2026-05-04T12:00:00Z") })
        let schedule = SleepModeSchedule(
            isEnabled: true,
            startHour: 0,
            startMinute: 10,
            endHour: 7,
            endMinute: 0,
            activeWeekdays: [2],
            remindersEnabled: true,
            reminderLeadMinutes: 20
        )

        _ = try await service.scheduleReminders(for: schedule, calendar: Self.utcCalendar)

        let requests = await center.pendingNotificationRequests()
        let request = try XCTUnwrap(requests.first)
        let trigger = try XCTUnwrap(request.trigger as? UNCalendarNotificationTrigger)
        XCTAssertEqual(trigger.dateComponents.weekday, 1)
        XCTAssertEqual(trigger.dateComponents.hour, 23)
        XCTAssertEqual(trigger.dateComponents.minute, 50)
    }

    func testNotificationActionMapsToLaunchReason() {
        XCTAssertEqual(
            SleepModeCoordinator.launchReason(for: SleepModeNotificationService.startActionIdentifier),
            .notificationAction
        )
        XCTAssertEqual(
            SleepModeCoordinator.launchReason(for: UNNotificationDefaultActionIdentifier),
            .scheduled
        )
    }
}

private final class MockSleepModeNotificationCenter: SleepModeNotificationCenterClient, @unchecked Sendable {
    var authorizationStatus: SleepModeNotificationAuthorizationStatus
    var failingAddIdentifiers: Set<String> = []
    private var requests: [UNNotificationRequest] = []
    private(set) var categories: Set<UNNotificationCategory> = []

    init(authorizationStatus: SleepModeNotificationAuthorizationStatus) {
        self.authorizationStatus = authorizationStatus
    }

    func notificationSettings() async -> SleepModeNotificationAuthorizationStatus {
        authorizationStatus
    }

    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        if authorizationStatus == .notDetermined {
            authorizationStatus = .authorized
            return true
        }
        return authorizationStatus.canScheduleAlerts
    }

    func pendingNotificationRequests() async -> [UNNotificationRequest] {
        requests
    }

    func add(_ request: UNNotificationRequest) async throws {
        if failingAddIdentifiers.contains(request.identifier) {
            throw MockNotificationCenterError.addFailed
        }
        requests.removeAll { $0.identifier == request.identifier }
        requests.append(request)
    }

    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) async {
        requests.removeAll { identifiers.contains($0.identifier) }
    }

    func setNotificationCategories(_ categories: Set<UNNotificationCategory>) async {
        self.categories = categories
    }
}

private enum MockNotificationCenterError: Error {
    case addFailed
}

private extension SleepModeNotificationServiceTests {
    static let utcCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    static func date(_ string: String) -> Date {
        ISO8601DateFormatter().date(from: string)!
    }
}
