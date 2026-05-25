import Foundation
import Observation

@MainActor
@Observable
final class SleepDashboardViewModel {
    private let syncCoordinator: SyncCoordinator
    private let localRepository: LocalDataRepositoryProtocol
    private let processor: SleepDataProcessor
    private let insightService: SleepInsightService
    private let chronotypeService: ChronotypeCalculationService
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
    var displayName: String?
    var sleepInsights: [SleepInsight] = []
    var bodyClockResult: ChronotypeCalculationResult?
    var selectedSleepBodyClockAlignment: BodyClockSleepAlignment?

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

    /// Derived from current session + baseline data.  Non-nil when the data state
    /// requires user attention beyond the standard authorization banner.
    var healthKitFallbackState: HealthKitFallbackState? {
        // Permission denied takes priority.
        if authorizationState == .healthDataUnavailable {
            return .permissionDenied
        }

        guard authorizationState == .canQueryHealthData else { return nil }

        // No sleep stage data available for selected session.
        if let session = selectedSession, session.dataQuality == .inBedOnly {
            return .noSleepStages
        }

        // Baseline still building.
        let nightsLogged = selectedBaseline?.validNights ?? 0
        if nightsLogged < 7 {
            return .baselineBuilding(nightsLogged: nightsLogged, nightsNeeded: 7)
        }

        return nil
    }

    init(
        syncCoordinator: SyncCoordinator,
        localRepository: LocalDataRepositoryProtocol,
        processor: SleepDataProcessor = SleepDataProcessor(),
        insightService: SleepInsightService = SleepInsightService(),
        chronotypeService: ChronotypeCalculationService = ChronotypeCalculationService(),
        calendar: Calendar = .current
    ) {
        self.syncCoordinator = syncCoordinator
        self.localRepository = localRepository
        self.processor = processor
        self.insightService = insightService
        self.chronotypeService = chronotypeService
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
        let loadKey = selectedSleepDateKey
        do {
            let loadedSession = try await localRepository.fetchSession(forSleepDateKey: loadKey)
            let profile = try await localRepository.fetchProfile()
            let loadedBaseline = try await baseline(asOfSleepDateKey: loadKey, windowDays: profile.baselineWindowDays)
            let loadedRecentSessions = try await loadRecentSessions(endingAt: loadKey, selectedSession: loadedSession)
            guard selectedSleepDateKey == loadKey else { return }

            selectedSession = loadedSession
            sleepGoalHours = profile.sleepGoalHours
            displayName = profile.displayName
            selectedBaseline = loadedBaseline
            recentSessions = loadedRecentSessions
            let loadedSleepInsights = try await buildSleepInsights()
            let loadedBodyClockResult = try await loadBodyClockResult(endingAtSleepDateKey: loadKey)
            let loadedBodyClockAlignment = Self.bodyClockAlignment(
                for: loadedSession,
                result: loadedBodyClockResult,
                service: chronotypeService,
                calendar: calendar
            )
            guard selectedSleepDateKey == loadKey else { return }

            sleepInsights = loadedSleepInsights
            bodyClockResult = loadedBodyClockResult
            selectedSleepBodyClockAlignment = loadedBodyClockAlignment
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
        let selection = BaselineEngine(processor: processor, calendar: calendar).selectBaseline(
            from: previousSessions.filter { $0.sleepDateKey < key },
            generatedAt: SleepDateKey.date(from: key, calendar: calendar) ?? Date()
        )

        return selection.activeBaseline ?? selection.stableBaseline ?? processor.computeBaseline(
            from: [],
            windowDays: effectiveWindowDays,
            generatedAt: SleepDateKey.date(from: key, calendar: calendar) ?? Date()
        )
    }

    func refreshIfNeededForToday() async {
        guard isViewingToday else { return }
        // Skip if a sync is already running (e.g. performLaunchSync still in flight)
        guard syncCoordinator.phase != .syncing else { return }
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
            .filter { BaselineEngine.isValidNight($0, calendar: calendar) }

        if let selectedSession,
           BaselineEngine.isValidNight(selectedSession, calendar: calendar) {
            sessions.append(selectedSession)
        }

        return Array(
            sessions
                .sorted { $0.sleepDateKey < $1.sleepDateKey }
                .suffix(30)
        )
    }

    func buildSleepInsights() async throws -> [SleepInsight] {
        // Legacy ProtocolComparison-driven insights have been removed alongside the
        // legacy Protocol tab. Formula-aware sleep insights are a follow-up.
        return insightService.insights(
            session: selectedSession,
            baseline: selectedBaseline,
            recentSessions: recentSessions
        )
    }

    func loadBodyClockResult(endingAtSleepDateKey key: String) async throws -> ChronotypeCalculationResult? {
        guard let selectedDate = SleepDateKey.date(from: key, calendar: calendar) else { return nil }
        let windowEnd = calendar.date(byAdding: .day, value: 1, to: selectedDate) ?? selectedDate.addingTimeInterval(86_400)
        let windowStart = calendar.date(byAdding: .day, value: -91, to: windowEnd) ?? windowEnd.addingTimeInterval(-91 * 86_400)
        let startKey = SleepDateKey.calendarDateKey(for: windowStart, calendar: calendar)
        let endKey = SleepDateKey.calendarDateKey(for: windowEnd, calendar: calendar)

        async let sessions = localRepository.fetchCachedSessions(from: windowStart, to: windowEnd)
        async let contextEntries = localRepository.fetchContextEntries(from: startKey, to: endKey)
        async let activityLogs = localRepository.fetchActivityStatusLogs(from: startKey, to: endKey)
        let (loadedSessions, loadedContextEntries, loadedActivityLogs) = try await (sessions, contextEntries, activityLogs)

        let service = chronotypeService
        let calendar = calendar
        return service.estimate(
            sessions: loadedSessions,
            contextEntries: loadedContextEntries,
            activityLogs: loadedActivityLogs,
            windowDays: 90,
            endingAt: windowEnd,
            calendar: calendar
        )
    }

    static func bodyClockAlignment(
        for session: SleepSession?,
        result: ChronotypeCalculationResult?,
        service: ChronotypeCalculationService,
        calendar: Calendar
    ) -> BodyClockSleepAlignment? {
        guard let session,
              let estimate = result?.estimate,
              result?.status == .estimated
        else {
            return nil
        }

        return service.alignment(for: session, estimate: estimate, calendar: calendar)
    }
}
