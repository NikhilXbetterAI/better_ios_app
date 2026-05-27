import Foundation
import Observation

@MainActor
@Observable
final class SleepModeScheduleService {
    @ObservationIgnored
    private let repository: LocalDataRepositoryProtocol?
    @ObservationIgnored
    private let notificationService: SleepModeNotificationService?
    @ObservationIgnored
    private let defaults: UserDefaults
    @ObservationIgnored
    private let calendar: Calendar
    private(set) var schedule: SleepModeSchedule
    @ObservationIgnored
    var onForegroundActivation: ((SleepModePresentation) -> Void)?

    init(
        repository: LocalDataRepositoryProtocol,
        notificationService: SleepModeNotificationService? = nil,
        defaults: UserDefaults = .standard,
        calendar: Calendar = .current,
        schedule: SleepModeSchedule = SleepModeSchedule()
    ) {
        self.repository = repository
        self.notificationService = notificationService
        self.defaults = defaults
        self.calendar = calendar
        self.schedule = schedule
    }

    init(
        notificationService: SleepModeNotificationService,
        defaults: UserDefaults = .standard,
        calendar: Calendar = .current
    ) {
        self.repository = nil
        self.notificationService = notificationService
        self.defaults = defaults
        self.calendar = calendar
        self.schedule = SleepModeSchedule()
    }

    func loadSchedule() async {
        if let stored = try? await repository?.fetchSleepModeSchedule() {
            schedule = stored
            return
        }

        if let data = defaults.data(forKey: Self.scheduleDefaultsKey),
           let decoded = try? JSONDecoder().decode(SleepModeSchedule.self, from: data) {
            schedule = decoded
        } else {
            schedule = SleepModeSchedule()
        }
    }

    func saveSchedule(_ schedule: SleepModeSchedule) async throws {
        var updated = schedule
        updated.updatedAt = Date()
        try await notificationService?.scheduleReminders(for: updated, calendar: calendar)
        if let repository {
            try await repository.saveSleepModeSchedule(updated)
        }
        defaults.set(try JSONEncoder().encode(updated), forKey: Self.scheduleDefaultsKey)
        self.schedule = updated
        if !updated.isEnabled {
            clearAutoEnteredKey()
        }
    }

    func rescheduleRemindersIfNeeded() async {
        _ = try? await notificationService?.scheduleReminders(for: schedule, calendar: calendar)
    }

    func notificationStatus() async -> SleepModeNotificationStatus {
        guard let notificationService else {
            return .notScheduled(.unavailable)
        }
        return await notificationService.notificationStatus(for: schedule)
    }

    #if DEBUG
    func scheduleTestReminder() async -> SleepModeNotificationStatus {
        guard let notificationService else {
            return .notScheduled(.unavailable)
        }
        do {
            return try await notificationService.scheduleTestReminder()
        } catch {
            return .notScheduled(.unavailable)
        }
    }
    #endif

    func nextStartDate(now: Date = Date()) -> Date? {
        Self.nextStartDate(for: schedule, now: now, calendar: calendar)
    }

    func currentInterval(now: Date = Date()) -> DateInterval? {
        Self.currentInterval(for: schedule, now: now, calendar: calendar)
    }

    func shouldAutoEnterForeground(now: Date = Date()) -> Bool {
        guard schedule.autoEnterWhenForeground, let interval = currentInterval(now: now) else { return false }
        guard now.timeIntervalSince(interval.start) <= 45 * 60 else { return false }
        let stored = defaults.double(forKey: Self.autoEnteredAtKey)
        if stored == interval.start.timeIntervalSince1970 { return false }
        return true
    }

    func evaluateForegroundActivation(now: Date = Date()) {
        guard shouldAutoEnterForeground(now: now), let interval = currentInterval(now: now) else { return }
        defaults.set(interval.start.timeIntervalSince1970, forKey: Self.autoEnteredAtKey)
        onForegroundActivation?(.init(reason: .scheduled, startedAt: now))
    }

    func clearAutoEnteredKey() {
        defaults.removeObject(forKey: Self.autoEnteredAtKey)
    }

    nonisolated static func nextStartDate(
        for schedule: SleepModeSchedule,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Date? {
        guard schedule.isEnabled, !schedule.activeWeekdays.isEmpty else { return nil }

        return candidateIntervals(for: schedule, around: now, calendar: calendar)
            .map(\.start)
            .filter { $0 > now }
            .min()
    }

    nonisolated static func currentInterval(
        for schedule: SleepModeSchedule,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> DateInterval? {
        guard schedule.isEnabled, !schedule.activeWeekdays.isEmpty else { return nil }

        return candidateIntervals(for: schedule, around: now, calendar: calendar)
            .first { $0.contains(now) }
    }

    /// Whether the Sleep dashboard launcher button should be shown. True when
    /// the user is currently inside their configured Sleep Mode interval, or
    /// when local time is ≥ 20:00 — i.e. the button is hidden during the day
    /// and surfaces only when the action is actually relevant.
    nonisolated static func shouldShowLauncher(
        schedule: SleepModeSchedule,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        if currentInterval(for: schedule, now: now, calendar: calendar) != nil {
            return true
        }
        return calendar.component(.hour, from: now) >= 20
    }

    nonisolated static func scheduleSummary(
        for schedule: SleepModeSchedule,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> String {
        guard schedule.isEnabled else { return "Schedule off" }
        guard let nextStart = nextStartDate(for: schedule, now: now, calendar: calendar) else {
            return "No active days"
        }

        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return "Tonight at \(formatter.string(from: nextStart))"
    }

    private static let scheduleDefaultsKey = "better.sleepMode.schedule.v1"
    private static let autoEnteredAtKey = "better.sleepMode.lastAutoEnteredAt"
}

private extension SleepModeScheduleService {
    nonisolated static func candidateIntervals(
        for schedule: SleepModeSchedule,
        around now: Date,
        calendar: Calendar
    ) -> [DateInterval] {
        (-7...14).compactMap { offset -> DateInterval? in
            guard
                let day = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now)),
                schedule.activeWeekdays.contains(calendar.component(.weekday, from: day)),
                let start = date(on: day, hour: schedule.startHour, minute: schedule.startMinute, calendar: calendar)
            else {
                return nil
            }

            let endDay = schedule.isOvernight
                ? calendar.date(byAdding: .day, value: 1, to: day)
                : day
            guard
                let endDay,
                let end = date(on: endDay, hour: schedule.endHour, minute: schedule.endMinute, calendar: calendar),
                end > start
            else {
                return nil
            }

            return DateInterval(start: start, end: end)
        }
        .sorted { $0.start < $1.start }
    }

    nonisolated static func date(on day: Date, hour: Int, minute: Int, calendar: Calendar) -> Date? {
        let dayComponents = calendar.dateComponents([.year, .month, .day], from: day)
        return calendar.date(from: DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: dayComponents.year,
            month: dayComponents.month,
            day: dayComponents.day,
            hour: hour,
            minute: minute
        ))
    }
}
