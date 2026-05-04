import Foundation
import Observation

@MainActor
@Observable
final class SleepDashboardViewModel {
    private let syncCoordinator: SyncCoordinator
    private let localRepository: LocalDataRepositoryProtocol
    private let processor: SleepDataProcessor
    private let calendar: Calendar

    var selectedSleepDateKey: String
    var selectedMonth: Date
    var selectedSession: SleepSession?
    var selectedBaseline: SleepBaseline?
    var selectedMonthSummaries: [SleepDaySummary] = []
    var dataQuality: SleepDataQuality = .noData
    var authorizationState: HealthAuthorizationPresentationState = .notRequested
    var isLoading = false
    var errorMessage: String?
    var lastSyncedAt: Date?

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
        await refresh()
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
            selectedBaseline = try await baseline(asOfSleepDateKey: selectedSleepDateKey, windowDays: profile.baselineWindowDays)
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
        let previousSessions = try await localRepository.fetchSessions(
            beforeSleepDateKey: key,
            limit: max(windowDays * 4, 90)
        )
        let validSessions = previousSessions
            .filter { $0.totalSleepTime >= SleepDataProcessor.minimumSleepDuration }
            .filter { $0.dataQuality != .inBedOnly && $0.dataQuality != .noData }
            .prefix(windowDays)

        return processor.computeBaseline(
            from: Array(validSessions),
            windowDays: windowDays,
            generatedAt: SleepDateKey.date(from: key, calendar: calendar) ?? Date()
        )
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
}
