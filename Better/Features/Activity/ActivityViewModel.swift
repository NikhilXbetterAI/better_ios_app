import Foundation
import Observation

@MainActor
@Observable
final class ActivityViewModel {
    private let localRepository: LocalDataRepositoryProtocol
    private let healthRepository: HealthKitRepositoryProtocol
    private let calendar: Calendar

    var selectedDate: Date
    var selectedDateKey: String
    var selectedStatusLog: ActivityStatusLog?
    var weekSummaries: [SleepDaySummary] = []
    var recentStatusLogs: [ActivityStatusLog] = []
    var activitySummary = ActivityMetricSummary()
    var isLoading = false
    var errorMessage: String?

    init(
        localRepository: LocalDataRepositoryProtocol,
        healthRepository: HealthKitRepositoryProtocol,
        calendar: Calendar = .current,
        now: Date = Date()
    ) {
        self.localRepository = localRepository
        self.healthRepository = healthRepository
        self.calendar = calendar
        self.selectedDate = now
        self.selectedDateKey = SleepDateKey.calendarDateKey(for: now, calendar: calendar)
    }

    func onAppear(now: Date = Date()) async {
        selectedDate = now
        selectedDateKey = SleepDateKey.calendarDateKey(for: now, calendar: calendar)
        await load()
    }

    func selectDate(_ date: Date) async {
        let newKey = SleepDateKey.calendarDateKey(for: date, calendar: calendar)
        guard newKey != selectedDateKey else { return }
        selectedDate = date
        selectedDateKey = newKey
        await loadSelectedDay()
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        do {
            let interval = weekInterval(containing: selectedDate)
            let startKey = SleepDateKey.calendarDateKey(for: interval.start, calendar: calendar)
            let endKey = SleepDateKey.calendarDateKey(for: interval.end.addingTimeInterval(-1), calendar: calendar)
            weekSummaries = try await localRepository.fetchAvailableSleepDates(from: startKey, to: endKey)
            recentStatusLogs = try await localRepository.fetchActivityStatusLogs(from: startKey, to: endKey)
            selectedStatusLog = try await localRepository.fetchActivityStatusLog(forDateKey: selectedDateKey)
            activitySummary = try await fetchActivitySummary(for: selectedDate)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func saveStatus(_ status: UserActivityStatus, note: String?) async {
        let now = Date()
        let log = ActivityStatusLog(
            id: selectedStatusLog?.id ?? UUID(),
            dateKey: selectedDateKey,
            status: status,
            note: note?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            createdAt: selectedStatusLog?.createdAt ?? now,
            updatedAt: now
        )

        do {
            try await localRepository.saveActivityStatusLog(log)
            selectedStatusLog = log
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private extension ActivityViewModel {
    func weekInterval(containing date: Date) -> DateInterval {
        calendar.dateInterval(of: .weekOfYear, for: date)
            ?? DateInterval(start: date.addingTimeInterval(-6 * 86_400), duration: 7 * 86_400)
    }

    func fetchActivitySummary(for date: Date) async throws -> ActivityMetricSummary {
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        let dateKey = SleepDateKey.calendarDateKey(for: date, calendar: calendar)

        async let steps = sum(.stepCount, from: start, to: end)
        async let energy = sum(.activeEnergyBurned, from: start, to: end)
        async let exercise = sum(.appleExerciseTime, from: start, to: end)
        async let stand = sum(.appleStandTime, from: start, to: end)
        async let flights = sum(.flightsClimbed, from: start, to: end)
        async let distance = sum(.distanceWalkingRunning, from: start, to: end)

        let summary = try await DailyActivitySummary(
            dateKey: dateKey,
            steps: steps,
            activeEnergy: energy,
            exerciseMinutes: exercise,
            standHours: stand.map { $0 / 60 },
            flights: flights,
            distanceMeters: distance
        )
        try await localRepository.saveDailyActivitySummary(summary)

        return ActivityMetricSummary(
            steps: summary.steps,
            activeEnergy: summary.activeEnergy,
            exerciseMinutes: summary.exerciseMinutes,
            standHours: summary.standHours,
            flights: summary.flights,
            distanceMeters: summary.distanceMeters
        )
    }

    func sum(_ type: BiometricType, from start: Date, to end: Date) async throws -> Double? {
        let samples = try await healthRepository.fetchBiometrics(for: type, from: start, to: end)
        guard !samples.isEmpty else { return nil }
        return samples.map(\.value).reduce(0, +)
    }

    func loadSelectedDay() async {
        do {
            selectedStatusLog = try await localRepository.fetchActivityStatusLog(forDateKey: selectedDateKey)
            activitySummary = try await fetchActivitySummary(for: selectedDate)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
