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
    private let biomarkerBaselineService: BiomarkerBaselineService?
    private let calendar: Calendar
    private var requestedHistoricalKeys = Set<String>()

    var selectedSleepDateKey: String
    var selectedMonth: Date
    var selectedSession: SleepSession?
    var selectedBaseline: SleepBaseline?
    var selectedContextEntry: SleepContextEntry?
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
    var biomarkerBaseline: BiomarkerBaseline?
    var biomarkerReactions: [BiomarkerKey: SleepBiomarkerReaction] = [:]
    var biomarkerReadiness: [BiomarkerKey: BiomarkerBaselineReadiness] = [:]
    var biomarkerProvenance: [BiomarkerKey: BiomarkerProvenance] = [:]

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

    /// True when the dashboard-specific 30/60 baseline doesn't have enough
    /// valid nights to render a "vs your baseline sleep" comparison.
    var baselineIsBuilding: Bool {
        (selectedBaseline?.validNights ?? 0) < BaselineEngine.dashboardMinimumValidNights
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

        // Baseline still building — use the same threshold as every other
        // baseline-gated surface so the banner and card agree.
        let nightsLogged = selectedBaseline?.validNights ?? 0
        let needed = BaselineEngine.dashboardMinimumValidNights
        if nightsLogged < needed {
            return .baselineBuilding(nightsLogged: nightsLogged, nightsNeeded: needed)
        }

        return nil
    }

    init(
        syncCoordinator: SyncCoordinator,
        localRepository: LocalDataRepositoryProtocol,
        processor: SleepDataProcessor = SleepDataProcessor(),
        insightService: SleepInsightService = SleepInsightService(),
        chronotypeService: ChronotypeCalculationService = ChronotypeCalculationService(),
        biomarkerBaselineService: BiomarkerBaselineService? = nil,
        calendar: Calendar = .current
    ) {
        self.syncCoordinator = syncCoordinator
        self.localRepository = localRepository
        self.processor = processor
        self.insightService = insightService
        self.chronotypeService = chronotypeService
        self.biomarkerBaselineService = biomarkerBaselineService
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
            let loadedContextEntry = try await localRepository.fetchContextEntry(forSleepDateKey: loadKey)
            guard selectedSleepDateKey == loadKey else { return }

            selectedSession = loadedSession
            sleepGoalHours = profile.sleepGoalHours
            displayName = profile.displayName
            selectedBaseline = loadedBaseline
            recentSessions = loadedRecentSessions
            selectedContextEntry = loadedContextEntry
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
            await refreshBiomarkerBaseline()
            await loadMonthSummaries()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private extension SleepDashboardViewModel {
    /// Pulls the cached biomarker baseline (recompute if stale) and recomputes
    /// tonight's reaction map. Safe to call after `selectedSession` lands.
    func refreshBiomarkerBaseline() async {
        let baseline = await biomarkerBaselineService?.currentBaseline()
        let bio = selectedSession?.biometrics
        var reactions: [BiomarkerKey: SleepBiomarkerReaction] = [:]
        var readiness: [BiomarkerKey: BiomarkerBaselineReadiness] = [:]
        var provenance: [BiomarkerKey: BiomarkerProvenance] = [:]
        for key in BiomarkerKey.allCases {
            let tonight: Double? = {
                switch key {
                case .rhr:    return bio?.heartRateMinimum
                case .hrv:    return bio?.hrvAverage
                case .spo2:   return bio?.oxygenSaturationAverage.map { $0 * 100 }
                case .breath: return bio?.respiratoryRateAverage
                }
            }()
            readiness[key] = baseline?.readiness(for: key) ?? .unavailable(minimumCount: 5)
            provenance[key] = BiomarkerProvenance.make(
                key: key,
                samples: bio?.samples ?? [],
                fallbackSources: selectedSession?.sources ?? [],
                hasValue: tonight != nil
            )
            if let reaction = SleepBiomarkerReaction.make(key: key, tonight: tonight, baseline: baseline) {
                reactions[key] = reaction
            }
        }
        self.biomarkerBaseline = baseline
        self.biomarkerReactions = reactions
        self.biomarkerReadiness = readiness
        self.biomarkerProvenance = provenance
    }

    /// 7-day TTL for persisted baseline snapshots. Fresh enough that a week of
    /// new sessions won't silently skew the "vs your usual sleep" comparison.
    private static let baselineSnapshotTTL: TimeInterval = 7 * 86_400

    func baseline(asOfSleepDateKey key: String, windowDays: Int) async throws -> SleepBaseline {
        // The dashboard uses a dedicated 30-day primary / 60-day fallback
        // selector — the user's `profile.baselineWindowDays` is ignored here on
        // purpose (it still drives Trends and other consumers).
        _ = windowDays
        let selectedDate = SleepDateKey.date(from: key, calendar: calendar) ?? Date()

        // Cache-first: try the persisted snapshot (primary 30-day, then 60-day fallback).
        // Using `reconstructBaseline(from:)` on a fresh snapshot avoids the 60-day
        // session fetch + BaselineEngine run on every date swipe.
        for windowKind in ["dashboard30", "dashboard60"] {
            if let snapshot = try? await localRepository.fetchBaselineSnapshot(
                asOfSleepDateKey: key,
                windowKind: windowKind
            ),
            Date().timeIntervalSince(snapshot.generatedAt) < Self.baselineSnapshotTTL,
            let cached = BaselineEngine.reconstructBaseline(from: snapshot) {
                return cached
            }
        }

        // Cache miss: compute the full 60-day window, persist for next call.
        let fetchWindowDays = BaselineEngine.dashboardFallbackWindow
        let baselineStart = calendar.date(
            byAdding: .day,
            value: -fetchWindowDays,
            to: selectedDate
        ) ?? selectedDate.addingTimeInterval(Double(-fetchWindowDays) * 86_400)
        let previousSessions = try await localRepository.fetchCachedSessions(
            from: baselineStart,
            to: selectedDate
        )
        let selection = BaselineEngine(processor: processor, calendar: calendar).selectDashboardBaseline(
            from: previousSessions.filter { $0.sleepDateKey < key },
            generatedAt: selectedDate
        )

        let result = selection.activeBaseline ?? processor.computeBaseline(
            from: [],
            windowDays: BaselineEngine.dashboardPrimaryWindow,
            generatedAt: selectedDate
        )

        // Persist the snapshot so subsequent date swipes hit the cache.
        let windowKind = (result.windowDays == BaselineEngine.dashboardFallbackWindow)
            ? "dashboard60" : "dashboard30"
        await persistBaselineSnapshot(result, asOfSleepDateKey: key, windowKind: windowKind, generatedAt: selectedDate)

        return result
    }

    /// Serialises a computed `SleepBaseline` into `DashboardBaselineSnapshotRecord`
    /// and saves it.  Errors are swallowed — a failed cache write is non-fatal.
    private func persistBaselineSnapshot(
        _ baseline: SleepBaseline,
        asOfSleepDateKey key: String,
        windowKind: String,
        generatedAt: Date
    ) async {
        let duration = baseline.totalSleepAverage
        let snapshot = DashboardBaselineSnapshotRecord(
            asOfSleepDateKey: key,
            windowKind: windowKind,
            generatedAt: generatedAt,
            validNightCount: baseline.validNights,
            sourceWindowStart: generatedAt.addingTimeInterval(-Double(baseline.windowDays) * 86_400),
            sourceWindowEnd: generatedAt,
            durationMean: duration,
            durationStdDev: baseline.totalSleepStandardDeviation,
            bedtimeMeanHour: baseline.bedtimeMinuteAverage / 60.0,
            bedtimeStdDev: baseline.bedtimeMinuteStandardDeviation / 60.0,
            remRatioMean: duration > 0 ? baseline.remAverage / duration : 0,
            deepRatioMean: duration > 0 ? baseline.deepAverage / duration : 0,
            baselineData: try? PersistenceJSON.encode(baseline)
        )
        try? await localRepository.saveBaselineSnapshot(snapshot)
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
            let summaries = try await localRepository.fetchAvailableSleepDates(from: startKey, to: endKey)
            // Recompute each day's score using the Apple formula + current baseline
            // so the calendar rings match the hero dial exactly.
            let baseline = selectedBaseline
            let goal = sleepGoalHours
            selectedMonthSummaries = summaries.map { summary in
                var s = summary
                guard let sleep = summary.totalSleepTime else { return s }
                let durationPts = min(sleep / (goal * 3_600), 1.0) * 50.0
                let wasoMin = summary.waso / 60.0
                let interruptionsPts = max(0.0, (1.0 - wasoMin / 120.0) * 20.0)
                let bedtimePts: Double
                if let bedStart = summary.inBedStartDate, let b = baseline, b.validNights >= 5 {
                    let bedMin = Double(calendar.component(.hour, from: bedStart) * 60 + calendar.component(.minute, from: bedStart))
                    let baseMin = b.bedtimeMinuteAverage
                    let raw = abs(bedMin - baseMin).truncatingRemainder(dividingBy: 1_440)
                    let deviation = min(raw, 1_440 - raw)
                    bedtimePts = max(0.0, (1.0 - deviation / 180.0) * 30.0)
                } else {
                    bedtimePts = 0
                }
                s.score = (durationPts + interruptionsPts + bedtimePts).rounded()
                return s
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadRecentSessions(endingAt key: String, selectedSession: SleepSession?) async throws -> [SleepSession] {
        var sessions = try await localRepository.fetchSessions(beforeSleepDateKey: key, limit: 59)
            .filter { BaselineEngine.isValidNight($0, calendar: calendar) }

        if let selectedSession,
           BaselineEngine.isValidNight(selectedSession, calendar: calendar) {
            sessions.append(selectedSession)
        }

        return Array(
            sessions
                .sorted { $0.sleepDateKey < $1.sleepDateKey }
                .suffix(60)
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
        let windowEndKey = SleepDateKey.calendarDateKey(for: windowEnd, calendar: calendar)

        // Cache-first: avoid the 90-day session/context/activity fetch on every date swipe.
        if let cached = await chronotypeService.cachedEstimate(
            windowEndSleepDateKey: windowEndKey,
            localRepository: localRepository
        ) {
            return cached
        }

        // Cache miss — run the full computation.
        let windowStart = calendar.date(byAdding: .day, value: -91, to: windowEnd) ?? windowEnd.addingTimeInterval(-91 * 86_400)
        let startKey = SleepDateKey.calendarDateKey(for: windowStart, calendar: calendar)

        async let sessions = localRepository.fetchCachedSessions(from: windowStart, to: windowEnd)
        async let contextEntries = localRepository.fetchContextEntries(from: startKey, to: windowEndKey)
        async let activityLogs = localRepository.fetchActivityStatusLogs(from: startKey, to: windowEndKey)
        let (loadedSessions, loadedContextEntries, loadedActivityLogs) = try await (sessions, contextEntries, activityLogs)

        let service = chronotypeService
        let cal = calendar
        let result = service.estimate(
            sessions: loadedSessions,
            contextEntries: loadedContextEntries,
            activityLogs: loadedActivityLogs,
            windowDays: 90,
            endingAt: windowEnd,
            calendar: cal
        )
        await service.saveSnapshot(
            result: result,
            windowEndSleepDateKey: windowEndKey,
            localRepository: localRepository
        )
        return result
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
