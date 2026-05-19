import Foundation
@preconcurrency import HealthKit
import Observation
import OSLog

enum SyncCoordinatorPhase: Sendable, Hashable {
    case idle
    case authorizing
    case syncing
    case observing
    case failed(String)
}

@MainActor
@Observable
final class SyncCoordinator {
    static let minimumBaselineWindowDays = 15
    static let maximumBaselineWindowDays = 60
    static let dataRetentionDays = 60
    private static let lastForegroundRefreshMetadataKey = "better.metadata.lastForegroundRefresh"
    private static let lastDailyProcessingMetadataKey = "better.metadata.lastDailyProcessing"
    private static let windowMetadataKey = "better.metadata.window"

    private let healthRepository: HealthKitRepositoryProtocol
    private let localRepository: LocalDataRepositoryProtocol
    private let processor: SleepDataProcessor
    private let alertService: AlertGenerationService
    private let notificationPreferencesStore: AlertNotificationPreferencesStoring
    private let calendar: Calendar
    private let logger = Logger(subsystem: "Better", category: "SyncCoordinator")
    private var observationTask: Task<Void, Never>?

    private(set) var phase: SyncCoordinatorPhase = .idle
    private(set) var authorizationState: HealthAuthorizationPresentationState = .notRequested
    private(set) var lastSyncedAt: Date?
    private(set) var lastErrorMessage: String?

    static func clampedBaselineWindowDays(_ days: Int) -> Int {
        min(max(days, minimumBaselineWindowDays), maximumBaselineWindowDays)
    }

    init(
        healthRepository: HealthKitRepositoryProtocol,
        localRepository: LocalDataRepositoryProtocol,
        processor: SleepDataProcessor = SleepDataProcessor(),
        alertService: AlertGenerationService = AlertGenerationService(),
        notificationPreferencesStore: AlertNotificationPreferencesStoring = UserDefaultsAlertNotificationPreferencesStore(),
        calendar: Calendar = .current
    ) {
        self.healthRepository = healthRepository
        self.localRepository = localRepository
        self.processor = processor
        self.alertService = alertService
        self.notificationPreferencesStore = notificationPreferencesStore
        self.calendar = calendar
    }

    func requestHealthAuthorization() async {
        phase = .authorizing
        lastErrorMessage = nil

        do {
            let result = try await healthRepository.requestAuthorization()
            authorizationState = Self.presentationState(for: result)
            phase = .idle
        } catch {
            fail(with: error)
            authorizationState = .failed(error.localizedDescription)
        }
    }

    func performInitialSync(now: Date = Date()) async {
        let startDate = calendar.date(byAdding: .day, value: -Self.maximumBaselineWindowDays, to: now)
            ?? now.addingTimeInterval(Double(-Self.maximumBaselineWindowDays) * 86_400)
        let endDate = now.addingTimeInterval(2 * 3_600)
        await syncHealthRange(from: startDate, to: endDate, forceDailyProcessing: true)
    }

    func performForegroundRefresh(now: Date = Date()) async {
        let startDate = calendar.date(byAdding: .hour, value: -36, to: now) ?? now.addingTimeInterval(-36 * 3_600)
        await syncHealthRange(from: startDate, to: now)
        if case .failed = phase {
            return
        }
        do {
            try await saveMetadataDate(now, for: Self.lastForegroundRefreshMetadataKey)
        } catch {
            logger.error("Failed to save foreground refresh timestamp: \(error.localizedDescription, privacy: .public)")
        }
    }

    func performHistoricalRefresh(forSleepDateKey sleepDateKey: String) async {
        guard let date = SleepDateKey.date(from: sleepDateKey, calendar: calendar) else { return }
        let startDate = calendar.date(byAdding: .hour, value: -18, to: date) ?? date.addingTimeInterval(-18 * 3_600)
        let endDate = calendar.date(byAdding: .hour, value: 18, to: date) ?? date.addingTimeInterval(18 * 3_600)
        await syncHealthRange(from: startDate, to: endDate, updateState: false)
    }

    func shouldPerformForegroundRefresh(hasCachedSessionForToday: Bool, now: Date = Date()) async -> Bool {
        do {
            guard let lastRefresh = try await fetchMetadataDate(for: Self.lastForegroundRefreshMetadataKey) else {
                return true
            }

            if !hasCachedSessionForToday {
                return now.timeIntervalSince(lastRefresh) >= 60 * 60
            }

            return !calendar.isDate(lastRefresh, inSameDayAs: now)
        } catch {
            return true
        }
    }

    func performIncrementalRefresh(now: Date = Date()) async {
        phase = .syncing
        lastErrorMessage = nil

        do {
            let typeIdentifier = HKCategoryType(.sleepAnalysis).identifier
            let existingAnchor = try await localRepository.fetchSyncAnchor(for: typeIdentifier)
            let result = try await healthRepository.fetchIncrementalSleepChanges(anchor: existingAnchor)

            if result.deletedObjects.isEmpty, result.samples.isEmpty {
                try await localRepository.saveSyncAnchor(result.newAnchor, for: typeIdentifier)
                finishSync(at: now)
                return
            }

            if result.deletedObjects.isEmpty, let range = Self.expandedRange(for: result.samples, fallbackEndDate: now) {
                try await performSyncHealthRange(from: range.start, to: range.end, forceDailyProcessing: true)
            } else {
                let startDate = calendar.date(byAdding: .day, value: -30, to: now) ?? now.addingTimeInterval(-30 * 86_400)
                try await performSyncHealthRange(from: startDate, to: now, forceDailyProcessing: true)
            }

            try await localRepository.saveSyncAnchor(result.newAnchor, for: typeIdentifier)
            finishSync(at: now)
        } catch {
            fail(with: error)
        }
    }

    func startObservingHealthChanges() async {
        guard observationTask == nil else { return }

        do {
            let stream = try await healthRepository.startObservingSleepChanges()
            phase = .observing
            observationTask = Task { [weak self] in
                for await event in stream {
                    guard let self else {
                        event.acknowledge()
                        continue
                    }

                    await self.handleHealthKitChange(event)
                }
            }
        } catch {
            fail(with: error)
        }
    }

    func stopObservingHealthChanges() {
        observationTask?.cancel()
        observationTask = nil
        phase = .idle
    }
}

private extension SyncCoordinator {
    func handleHealthKitChange(_ event: HealthKitChangeEvent) async {
        defer { event.acknowledge() }
        await performIncrementalRefresh()
    }

    func syncHealthRange(
        from startDate: Date,
        to endDate: Date,
        updateState: Bool = true,
        forceDailyProcessing: Bool = false
    ) async {
        if updateState {
            phase = .syncing
            lastErrorMessage = nil
        }

        do {
            try await performSyncHealthRange(
                from: startDate,
                to: endDate,
                forceDailyProcessing: forceDailyProcessing
            )
            finishSync(at: endDate)
        } catch {
            fail(with: error)
        }
    }

    func performSyncHealthRange(
        from startDate: Date,
        to endDate: Date,
        forceDailyProcessing: Bool = false
    ) async throws {
        let samples = try await healthRepository.fetchSleepSamples(from: startDate, to: endDate)
        let sessions = processor.process(samples: samples)
        
        let hydratedSessions = try await withThrowingTaskGroup(of: SleepSession.self) { group in
            for session in sessions {
                group.addTask {
                    try await self.attachBiometrics(to: session)
                }
            }
            
            var results: [SleepSession] = []
            for try await session in group {
                results.append(session)
            }
            return results.sorted { $0.startDate < $1.startDate }
        }

        try await localRepository.replaceSessions(hydratedSessions, from: startDate, to: endDate)

        let profile = try await localRepository.fetchProfile()
        guard try await shouldRunDailyProcessing(
            at: endDate,
            force: forceDailyProcessing
        ) else {
            return
        }

        // Daily maintenance: Prune data older than 60 days
        try await localRepository.pruneDataOlderThan(days: Self.dataRetentionDays)

        // Per-window baseline computation
        let windowDays = [7, 15, 30]
        var latestSelection: BaselineSelection?

        for days in windowDays {
            let shouldRun = try await shouldRunWindowedBaseline(windowDays: days, at: endDate, force: forceDailyProcessing)
            if shouldRun {
                let windowStart = calendar.date(byAdding: .day, value: -days, to: endDate)!
                let sessions = try await localRepository.fetchCachedSessions(from: windowStart, to: endDate)
                
                // We use BaselineEngine to compute the baseline for this specific window.
                // Note: selectBaseline produces three baselines, but we only care about the one matching 'days'.
                let selection = BaselineEngine(processor: processor, calendar: calendar).selectBaseline(
                    from: sessions,
                    generatedAt: endDate
                )
                
                // Save the relevant baseline for this window
                if let baseline = selection.allBaselines.first(where: { $0.windowDays <= days }) {
                    try await localRepository.saveBaseline(baseline)
                }
                
                try await saveMetadataDate(endDate, for: "\(Self.windowMetadataKey).\(days)")
                latestSelection = selection
            }
        }

        // For alerts, we need the active baseline. If we didn't recompute any today, fetch the latest stored one.
        let activeBaseline: SleepBaseline?
        if let selection = latestSelection {
            activeBaseline = selection.activeBaseline
        } else {
            let baselineWindowDays = Self.clampedBaselineWindowDays(profile.baselineWindowDays)
            activeBaseline = try await localRepository.fetchLatestBaseline(windowDays: baselineWindowDays)
        }

        let baselineWindowDays = Self.clampedBaselineWindowDays(profile.baselineWindowDays)
        let baselineStart = calendar.date(byAdding: .day, value: -baselineWindowDays, to: endDate)
            ?? endDate.addingTimeInterval(Double(-baselineWindowDays) * 86_400)
        let cachedSessions = try await localRepository.fetchCachedSessions(from: baselineStart, to: endDate)
        let adherence = try await localRepository.fetchAdherence(from: baselineStart, to: endDate)
        let appStartKey = SleepDateKey.calendarDateKey(for: profile.createdAt, calendar: calendar)
        let alertEligibleSessions = hydratedSessions.filter { $0.sleepDateKey >= appStartKey }

        if let activeBaseline {
            let alertSettings = notificationPreferencesStore.load().alertGenerationSettings
            let previousAlerts = try await localRepository.fetchAlerts(
                unreadOnly: false,
                fromSleepDateKey: appStartKey,
                limit: nil
            )
            let protocolComparison = ProtocolComparisonService(calendar: calendar).compare(
                sessions: cachedSessions,
                adherence: adherence,
                window: .last30Days,
                endingAt: endDate
            )
            let alerts = try await alertService.generateAlerts(
                sessions: alertEligibleSessions,
                recentSessions: cachedSessions,
                baseline: activeBaseline,
                profile: profile,
                adherence: adherence,
                settings: alertSettings,
                protocolComparison: protocolComparison,
                previousAlerts: previousAlerts,
                createdAt: endDate
            )
            try await localRepository.saveAlerts(alerts)
        }
        try await saveMetadataDate(endDate, for: Self.lastDailyProcessingMetadataKey)
    }

    func attachBiometrics(to session: SleepSession) async throws -> SleepSession {
        let sampleGroups = await withTaskGroup(of: [BiometricSample].self) { group in
            for type in BiometricType.dashboardTypes {
                group.addTask {
                    (try? await self.healthRepository.fetchBiometrics(for: type, from: session.startDate, to: session.endDate)) ?? []
                }
            }

            var all: [[BiometricSample]] = []
            for await samples in group {
                all.append(samples)
            }
            return all
        }
        let samples = sampleGroups.flatMap { $0 }
        guard !samples.isEmpty else { return session }

        let summary = processor.summarizeBiometrics(
            samples,
            sessionID: session.id,
            sleepDateKey: session.sleepDateKey
        )
        try await localRepository.saveBiometricSummary(summary)

        var updatedSession = session
        updatedSession.biometrics = summary
        return updatedSession
    }

    func finishSync(at date: Date) {
        lastSyncedAt = date
        lastErrorMessage = nil
        phase = observationTask == nil ? .idle : .observing
    }

    func fail(with error: Error) {
        let message = error.localizedDescription
        lastErrorMessage = message
        phase = .failed(message)
    }

    static func presentationState(for result: HealthAuthorizationResult) -> HealthAuthorizationPresentationState {
        guard result.healthDataAvailable else { return .healthDataUnavailable }
        guard result.requestCompleted else { return .notRequested }
        guard result.canQuerySleep else { return .requestCompleted }
        if result.lastQueryReturnedSamples == false {
            return .noReadableSleepData
        }
        return .canQueryHealthData
    }

    static func expandedRange(
        for samples: [HKCategorySample],
        fallbackEndDate: Date
    ) -> (start: Date, end: Date)? {
        guard
            let firstStart = samples.map(\.startDate).min(),
            let lastEnd = samples.map(\.endDate).max()
        else {
            return nil
        }

        let start = firstStart.addingTimeInterval(-12 * 3_600)
        let end = max(lastEnd.addingTimeInterval(12 * 3_600), fallbackEndDate)
        return (start, end)
    }

}

private extension SyncCoordinator {
    func shouldRunDailyProcessing(at date: Date, force: Bool) async throws -> Bool {
        if force { return true }
        guard let lastProcessing = try await fetchMetadataDate(for: Self.lastDailyProcessingMetadataKey) else {
            return true
        }
        return !calendar.isDate(lastProcessing, inSameDayAs: date)
    }

    func shouldRunWindowedBaseline(windowDays: Int, at date: Date, force: Bool) async throws -> Bool {
        if force { return true }
        let key = "\(Self.windowMetadataKey).\(windowDays)"
        guard let lastRun = try await fetchMetadataDate(for: key) else {
            return true
        }
        
        let elapsedSeconds = date.timeIntervalSince(lastRun)
        let windowSeconds = Double(windowDays) * 86_400
        return elapsedSeconds >= windowSeconds
    }

    func saveMetadataDate(_ date: Date, for key: String) async throws {
        let data = try PersistenceJSON.encode(date)
        try await localRepository.saveSyncAnchor(data, for: key)
    }

    func fetchMetadataDate(for key: String) async throws -> Date? {
        guard let data = try await localRepository.fetchSyncAnchor(for: key) else { return nil }
        return try? PersistenceJSON.decode(Date.self, from: data)
    }
}

private extension BiometricType {
    static let dashboardTypes: [BiometricType] = [
        .heartRate,
        .heartRateVariabilitySDNN,
        .oxygenSaturation,
        .respiratoryRate
    ]
}

private extension Sequence {
    func asyncMap<T>(_ transform: (Element) async throws -> T) async throws -> [T] {
        var values: [T] = []
        values.reserveCapacity(underestimatedCount)
        for element in self {
            values.append(try await transform(element))
        }
        return values
    }
}
