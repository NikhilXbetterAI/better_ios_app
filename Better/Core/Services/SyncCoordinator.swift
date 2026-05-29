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
    static let maximumBaselineWindowDays = 90
    static let dataRetentionDays = 90
    private static let lastForegroundRefreshMetadataKey = "better.metadata.lastForegroundRefresh"

    private let healthRepository: HealthKitRepositoryProtocol
    private let localRepository: LocalDataRepositoryProtocol
    private let processor: SleepDataProcessor
    private let alertService: AlertGenerationService
    private let notificationPreferencesStore: AlertNotificationPreferencesStoring
    private let calendar: Calendar
    private var biomarkerBaselineService: BiomarkerBaselineService?
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

    /// Wires the dashboard biomarker baseline service so post-sync runs can
    /// invalidate its cache. Optional — set after construction from
    /// `AppEnvironment` to avoid a circular DI dependency.
    func setBiomarkerBaselineService(_ service: BiomarkerBaselineService) {
        self.biomarkerBaselineService = service
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

    /// Called on every cold launch. Runs the full historical sync only when the app
    /// has no stored data (first install or after reset). For returning users it does
    /// nothing — the Sleep tab's `refreshIfNeededForToday` handles the daily refresh.
    func performLaunchSync(now: Date = Date()) async {
        guard phase != .syncing else { return }
        let lookback = calendar.date(byAdding: .day, value: -Self.maximumBaselineWindowDays, to: now)
            ?? now.addingTimeInterval(Double(-Self.maximumBaselineWindowDays) * 86_400)
        let hasPriorData: Bool
        do {
            let sessions = try await localRepository.fetchCachedSessions(from: lookback, to: now)
            hasPriorData = !sessions.isEmpty
        } catch {
            hasPriorData = false
        }
        logger.debug("launch sync lookbackDays=\(Self.maximumBaselineWindowDays, privacy: .public) hasPriorData=\(hasPriorData, privacy: .public)")

        guard !hasPriorData else { return }
        await performInitialSync(now: now)
    }

    func performForegroundRefresh(now: Date = Date()) async {
        let startDate = calendar.date(byAdding: .hour, value: -36, to: now) ?? now.addingTimeInterval(-36 * 3_600)
        await syncHealthRange(from: startDate, to: now)
        if case .failed = phase {
            return
        }
        do {
            try await HealthSyncEngine.saveMetadataDate(
                now,
                for: Self.lastForegroundRefreshMetadataKey,
                localRepository: localRepository
            )
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
            guard let lastRefresh = try await HealthSyncEngine.fetchMetadataDate(
                for: Self.lastForegroundRefreshMetadataKey,
                localRepository: localRepository
            ) else {
                return true
            }

            if !hasCachedSessionForToday {
                return now.timeIntervalSince(lastRefresh) >= 60 * 60
            }

            // Third-party wearables (Zepp, Oura) write daily RHR and HRV to HealthKit
            // hours after wakeup, not during the sleep window. Allow a second foreground
            // refresh on the same calendar day once 2h have elapsed so those writes are
            // captured. Daily maintenance (baseline, alerts) has its own separate gate.
            let biomarkerCatchupInterval: TimeInterval = 2 * 3_600
            return !calendar.isDate(lastRefresh, inSameDayAs: now) ||
                   now.timeIntervalSince(lastRefresh) >= biomarkerCatchupInterval
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
                try await performSyncHealthRange(from: range.start, to: range.end, forceDailyProcessing: false)
            } else {
                let startDate = calendar.date(byAdding: .day, value: -Self.maximumBaselineWindowDays, to: now)
                    ?? now.addingTimeInterval(Double(-Self.maximumBaselineWindowDays) * 86_400)
                logger.debug("incremental refresh fallbackDays=\(Self.maximumBaselineWindowDays, privacy: .public)")
                try await performSyncHealthRange(from: startDate, to: now, forceDailyProcessing: false)
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
        // Capture all Sendable values before hopping off main so the nonisolated
        // engine call does not capture self (which is @MainActor).
        let healthRepo = healthRepository
        let localRepo = localRepository
        let proc = processor
        let alerts = alertService
        let notifPrefs = notificationPreferencesStore
        let cal = calendar
        let bioSvc = biomarkerBaselineService

        // All CPU-heavy work (process, selectBaseline, biometric hydration) runs
        // off the main actor inside HealthSyncEngine.perform.
        _ = try await Task.detached(priority: .userInitiated) {
            try await HealthSyncEngine.perform(
                startDate: startDate,
                endDate: endDate,
                forceDailyProcessing: forceDailyProcessing,
                dataRetentionDays: Self.dataRetentionDays,
                baselineWindowDaysMin: Self.minimumBaselineWindowDays,
                baselineWindowDaysMax: Self.maximumBaselineWindowDays,
                healthRepository: healthRepo,
                localRepository: localRepo,
                processor: proc,
                alertService: alerts,
                notificationPreferencesStore: notifPrefs,
                calendar: cal,
                biomarkerBaselineService: bioSvc
            )
        }.value
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
