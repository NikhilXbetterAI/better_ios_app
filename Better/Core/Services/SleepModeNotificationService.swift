import Foundation
@preconcurrency import UserNotifications

nonisolated enum SleepModeLaunchReason: String, Codable, Hashable, Sendable, Identifiable {
    case manual
    case scheduled
    case notificationAction

    var id: String { rawValue }
}

nonisolated struct SleepModePresentation: Identifiable, Hashable, Sendable {
    let id = UUID()
    var reason: SleepModeLaunchReason
    var startedAt: Date
}

nonisolated enum SleepModeNotificationAuthorizationStatus: String, Hashable, Sendable {
    case notDetermined
    case authorized
    case denied
    case provisional
    case ephemeral
    case unknown

    var canScheduleAlerts: Bool {
        switch self {
        case .authorized, .provisional, .ephemeral:
            true
        case .notDetermined, .denied, .unknown:
            false
        }
    }
}

nonisolated enum SleepModeNotificationNotScheduledReason: String, Hashable, Sendable {
    case scheduleDisabled
    case remindersDisabled
    case permissionDenied
    case permissionNotDetermined
    case noActiveDays
    case unavailable
}

nonisolated enum SleepModeNotificationStatus: Hashable, Sendable {
    case notDetermined
    case authorized
    case denied
    case scheduled(count: Int, nextDate: Date?)
    case notScheduled(SleepModeNotificationNotScheduledReason)
}

nonisolated protocol SleepModeNotificationCenterClient: Sendable {
    func notificationSettings() async -> SleepModeNotificationAuthorizationStatus
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool
    func pendingNotificationRequests() async -> [UNNotificationRequest]
    func add(_ request: UNNotificationRequest) async throws
    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) async
    func setNotificationCategories(_ categories: Set<UNNotificationCategory>) async
}

struct LiveSleepModeNotificationCenterClient: SleepModeNotificationCenterClient {
    private let center: UNUserNotificationCenter

    nonisolated init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    nonisolated func notificationSettings() async -> SleepModeNotificationAuthorizationStatus {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined:
            return .notDetermined
        case .denied:
            return .denied
        case .authorized:
            return .authorized
        case .provisional:
            return .provisional
        case .ephemeral:
            return .ephemeral
        @unknown default:
            return .unknown
        }
    }

    nonisolated func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        try await center.requestAuthorization(options: options)
    }

    nonisolated func pendingNotificationRequests() async -> [UNNotificationRequest] {
        await center.pendingNotificationRequests()
    }

    nonisolated func add(_ request: UNNotificationRequest) async throws {
        try await center.add(request)
    }

    nonisolated func removePendingNotificationRequests(withIdentifiers identifiers: [String]) async {
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    nonisolated func setNotificationCategories(_ categories: Set<UNNotificationCategory>) async {
        center.setNotificationCategories(categories)
    }
}

actor SleepModeNotificationService {
    static let reminderIdentifierPrefix = "sleep-mode-start-"
    static let testReminderIdentifier = "sleep-mode-test-reminder"
    static let startActionIdentifier = "SLEEP_MODE_START"
    static let categoryIdentifier = "SLEEP_MODE_REMINDER"
    static let startNotificationResponseName = Notification.Name("SleepModeStartNotificationResponse")

    private let center: SleepModeNotificationCenterClient
    private let now: @Sendable () -> Date

    init(
        center: SleepModeNotificationCenterClient = LiveSleepModeNotificationCenterClient(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.center = center
        self.now = now
    }

    func registerCategories() async {
        let startAction = UNNotificationAction(
            identifier: Self.startActionIdentifier,
            title: "Start Sleep Mode",
            options: [.foreground]
        )
        let category = UNNotificationCategory(
            identifier: Self.categoryIdentifier,
            actions: [startAction],
            intentIdentifiers: [],
            options: []
        )
        await center.setNotificationCategories([category])
    }

    @discardableResult
    func scheduleReminders(for schedule: SleepModeSchedule, calendar: Calendar = .current) async throws -> SleepModeNotificationStatus {
        guard schedule.isEnabled else {
            await removePendingSleepModeReminders()
            return .notScheduled(.scheduleDisabled)
        }
        guard schedule.remindersEnabled else {
            await removePendingSleepModeReminders()
            return .notScheduled(.remindersDisabled)
        }
        guard !schedule.activeWeekdays.isEmpty else {
            await removePendingSleepModeReminders()
            return .notScheduled(.noActiveDays)
        }
        guard try await requestAuthorizationIfNeeded() else {
            return await statusForUnschedulablePermission()
        }

        let replacementRequests = schedule.activeWeekdays.sorted().map { weekday in
            let triggerComponents = reminderTriggerComponents(for: schedule, weekday: weekday, calendar: calendar)
            return reminderRequest(
                identifier: "\(Self.reminderIdentifierPrefix)\(weekday)",
                trigger: UNCalendarNotificationTrigger(dateMatching: triggerComponents, repeats: true)
            )
        }

        let existingRequests = await pendingSleepModeReminderRequests()
        await removePendingSleepModeReminders()
        do {
            for request in replacementRequests {
                try await center.add(request)
            }
        } catch {
            await removePendingSleepModeReminders()
            for request in existingRequests {
                try? await center.add(request)
            }
            throw error
        }

        return await notificationStatus(for: schedule)
    }

    func notificationStatus(for schedule: SleepModeSchedule) async -> SleepModeNotificationStatus {
        let authorization = await center.notificationSettings()
        if authorization == .notDetermined {
            return .notDetermined
        }
        if authorization == .denied {
            return .denied
        }
        guard schedule.isEnabled else { return .notScheduled(.scheduleDisabled) }
        guard schedule.remindersEnabled else { return .notScheduled(.remindersDisabled) }
        guard authorization.canScheduleAlerts else { return .notScheduled(.unavailable) }

        let sleepModeRequests = await pendingSleepModeReminderRequests()
        guard !sleepModeRequests.isEmpty else { return .notScheduled(.unavailable) }
        let nextDate = sleepModeRequests
            .compactMap { ($0.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate() }
            .min()
        return .scheduled(count: sleepModeRequests.count, nextDate: nextDate)
    }

    #if DEBUG
    @discardableResult
    func scheduleTestReminder() async throws -> SleepModeNotificationStatus {
        guard try await requestAuthorizationIfNeeded() else {
            return await statusForUnschedulablePermission()
        }
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 10, repeats: false)
        try await center.add(reminderRequest(identifier: Self.testReminderIdentifier, trigger: trigger))
        return .scheduled(count: 1, nextDate: now().addingTimeInterval(10))
    }
    #endif

    func removePendingSleepModeReminders() async {
        let requests = await center.pendingNotificationRequests()
        let identifiers = requests
            .map(\.identifier)
            .filter {
                $0.hasPrefix(Self.reminderIdentifierPrefix) || $0 == Self.testReminderIdentifier
            }
        await center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    private func pendingSleepModeReminderRequests() async -> [UNNotificationRequest] {
        let requests = await center.pendingNotificationRequests()
        return requests.filter { $0.identifier.hasPrefix(Self.reminderIdentifierPrefix) }
    }

    private func requestAuthorizationIfNeeded() async throws -> Bool {
        let authorization = await center.notificationSettings()
        switch authorization {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined:
            return try await center.requestAuthorization(options: [.alert, .sound])
        case .denied, .unknown:
            return false
        }
    }

    private func statusForUnschedulablePermission() async -> SleepModeNotificationStatus {
        switch await center.notificationSettings() {
        case .denied:
            return .notScheduled(.permissionDenied)
        case .notDetermined:
            return .notScheduled(.permissionNotDetermined)
        case .authorized, .provisional, .ephemeral:
            return .notScheduled(.unavailable)
        case .unknown:
            return .notScheduled(.unavailable)
        }
    }

    private func reminderRequest(identifier: String, trigger: UNNotificationTrigger) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = "Sleep Mode"
        content.body = "Wind down is scheduled now. Open Better to start blackout mode."
        content.categoryIdentifier = Self.categoryIdentifier
        content.sound = .default

        return UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
    }

    private func reminderTriggerComponents(
        for schedule: SleepModeSchedule,
        weekday: Int,
        calendar: Calendar
    ) -> DateComponents {
        let referenceStart = nextDate(for: weekday, hour: schedule.startHour, minute: schedule.startMinute, calendar: calendar)
        let reminderDate = calendar.date(
            byAdding: .minute,
            value: -max(0, schedule.reminderLeadMinutes),
            to: referenceStart
        ) ?? referenceStart

        return calendar.dateComponents([.weekday, .hour, .minute], from: reminderDate)
    }

    private func nextDate(for weekday: Int, hour: Int, minute: Int, calendar: Calendar) -> Date {
        var components = DateComponents()
        components.weekday = weekday
        components.hour = hour
        components.minute = minute
        return calendar.nextDate(
            after: now(),
            matching: components,
            matchingPolicy: .nextTime,
            direction: .forward
        ) ?? now()
    }
}
