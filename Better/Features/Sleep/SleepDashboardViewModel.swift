import Foundation
import Observation

@MainActor
@Observable
final class SleepDashboardViewModel {
    private let syncCoordinator: SyncCoordinator
    private let localRepository: LocalDataRepositoryProtocol
    private let processor: SleepDataProcessor
    private let calendar: Calendar
    private var requestedHistoricalKeys = Set<String>()

    var selectedSleepDateKey: String
    var selectedMonth: Date
    var selectedSession: SleepSession?
    var selectedBaseline: SleepBaseline?
    var recentSessions: [SleepSession] = []
    var selectedMonthSummaries: [SleepDaySummary] = []
    var dataQuality: SleepDataQuality = .noData
    var authorizationState: HealthAuthorizationPresentationState = .notRequested
    var isLoading = false
    var errorMessage: String?
    var lastSyncedAt: Date?
    var sleepGoalHours: Double = 8.0

    var isViewingToday: Bool {
        selectedSleepDateKey == SleepDateKey.today(calendar: calendar)
    }

    var baselineConfidenceLabel: String? {
        guard let validNights = selectedBaseline?.validNights else { return nil }
        switch validNights {
        case 0..<5: return nil
        case 5..<10: return "warming up"
        case 10..<15: return "usable"
        default: return "reliable"
        }
    }

    init(
        syncCoordinator: SyncCoordinator,
        localRepository: LocalDataRepositoryProtocol,
        processor: SleepDataProcessor = SleepDataProcessor(),
        calendar: Calendar = .current
    ) {
        self.syncCoordinator = syncCoordinator
        self.localRepository = localRepository
        self.processor = processor
        self.calendar = calendar
        let todayKey = SleepDateKey.today(calendar: calendar)
        self.selectedSleepDateKey = todayKey
        self.selectedMonth = SleepDateKey.date(from: todayKey, calendar: calendar) ?? Date()
    }

    func onAppear() async {
        selectedSleepDateKey = SleepDateKey.today(calendar: calendar)
        selectedMonth = SleepDateKey.date(from: selectedSleepDateKey, calendar: calendar) ?? Date()
        await loadSelectedDate()
        await refreshIfNeededForToday()
    }

    func refresh() async {
        isLoading = true
        errorMessage = nil
        await syncCoordinator.performForegroundRefresh()
        await loadSelectedDate()
        lastSyncedAt = syncCoordinator.lastSyncedAt
        if case .failed(let message) = syncCoordinator.phase {
            errorMessage = message
        }
        isLoading = false
    }

    func requestHealthKitAccess() async {
        await syncCoordinator.requestHealthAuthorization()
        authorizationState = syncCoordinator.authorizationState
        if authorizationState == .canQueryHealthData {
            await syncCoordinator.performInitialSync()
            await loadSelectedDate()
        }
    }

    func selectDate(_ sleepDateKey: String) async {
        selectedSleepDateKey = sleepDateKey
        if let date = SleepDateKey.date(from: sleepDateKey, calendar: calendar) {
            selectedMonth = date
        }
        await loadSelectedDate()
        await loadHistoricalDateOnDemandIfNeeded(sleepDateKey)
    }

    func jumpToToday() async {
        selectedSleepDateKey = SleepDateKey.today(calendar: calendar)
        selectedMonth = SleepDateKey.date(from: selectedSleepDateKey, calendar: calendar) ?? Date()
        await loadSelectedDate()
    }

    func loadMonth(_ month: Date) async {
        selectedMonth = month
        await loadMonthSummaries()
    }

    func loadSelectedDate() async {
        do {
            selectedSession = try await localRepository.fetchSession(forSleepDateKey: selectedSleepDateKey)
            let profile = try await localRepository.fetchProfile()
            sleepGoalHours = profile.sleepGoalHours
            selectedBaseline = try await baseline(asOfSleepDateKey: selectedSleepDateKey, windowDays: profile.baselineWindowDays)
            recentSessions = try await loadRecentSessions(endingAt: selectedSleepDateKey, selectedSession: selectedSession)
            dataQuality = selectedSession?.dataQuality ?? .noData
            authorizationState = syncCoordinator.authorizationState
            lastSyncedAt = syncCoordinator.lastSyncedAt
            await loadMonthSummaries()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private extension SleepDashboardViewModel {
    func baseline(asOfSleepDateKey key: String, windowDays: Int) async throws -> SleepBaseline {
        let effectiveWindowDays = SyncCoordinator.clampedBaselineWindowDays(windowDays)
        let selectedDate = SleepDateKey.date(from: key, calendar: calendar) ?? Date()
        let baselineStart = calendar.date(
            byAdding: .day,
            value: -effectiveWindowDays,
            to: selectedDate
        ) ?? selectedDate.addingTimeInterval(Double(-effectiveWindowDays) * 86_400)
        let previousSessions = try await localRepository.fetchCachedSessions(
            from: baselineStart,
            to: selectedDate
        )
        let validSessions = previousSessions
            .filter { $0.sleepDateKey < key }
            .filter { $0.totalSleepTime >= SleepDataProcessor.minimumSleepDuration }
            .filter { $0.dataQuality != .inBedOnly && $0.dataQuality != .noData }
            .sorted { $0.sleepDateKey > $1.sleepDateKey }
            .prefix(effectiveWindowDays)

        return processor.computeBaseline(
            from: Array(validSessions),
            windowDays: effectiveWindowDays,
            generatedAt: SleepDateKey.date(from: key, calendar: calendar) ?? Date()
        )
    }

    func refreshIfNeededForToday() async {
        guard isViewingToday else { return }
        let shouldRefresh = await syncCoordinator.shouldPerformForegroundRefresh(
            hasCachedSessionForToday: selectedSession != nil
        )
        guard shouldRefresh else { return }
        await refresh()
    }

    func loadHistoricalDateOnDemandIfNeeded(_ sleepDateKey: String) async {
        guard selectedSession == nil, !isViewingToday else { return }
        guard requestedHistoricalKeys.insert(sleepDateKey).inserted else { return }
        guard let date = SleepDateKey.date(from: sleepDateKey, calendar: calendar), date <= Date() else { return }

        await syncCoordinator.performHistoricalRefresh(forSleepDateKey: sleepDateKey)
        await loadSelectedDate()
    }

    func loadMonthSummaries() async {
        guard let monthInterval = calendar.dateInterval(of: .month, for: selectedMonth) else {
            selectedMonthSummaries = []
            return
        }

        let startKey = SleepDateKey.calendarDateKey(for: monthInterval.start, calendar: calendar)
        let endDate = calendar.date(byAdding: DateComponents(day: -1), to: monthInterval.end) ?? monthInterval.end
        let endKey = SleepDateKey.calendarDateKey(for: endDate, calendar: calendar)
        do {
            selectedMonthSummaries = try await localRepository.fetchAvailableSleepDates(from: startKey, to: endKey)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadRecentSessions(endingAt key: String, selectedSession: SleepSession?) async throws -> [SleepSession] {
        var sessions = try await localRepository.fetchSessions(beforeSleepDateKey: key, limit: 29)
            .filter { $0.totalSleepTime >= SleepDataProcessor.minimumSleepDuration }
            .filter { $0.dataQuality != .inBedOnly && $0.dataQuality != .noData }

        if let selectedSession,
           selectedSession.totalSleepTime >= SleepDataProcessor.minimumSleepDuration,
           selectedSession.dataQuality != .inBedOnly,
           selectedSession.dataQuality != .noData {
            sessions.append(selectedSession)
        }

        return Array(
            sessions
                .sorted { $0.sleepDateKey < $1.sleepDateKey }
                .suffix(30)
        )
    }
}
