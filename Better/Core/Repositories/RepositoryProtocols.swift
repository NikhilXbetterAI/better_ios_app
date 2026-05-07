import Foundation
@preconcurrency import HealthKit

nonisolated protocol HealthKitRepositoryProtocol: Sendable {
    func isHealthDataAvailable() -> Bool
    func requestAuthorization() async throws -> HealthAuthorizationResult
    func fetchSleepSamples(from: Date, to: Date) async throws -> [HKCategorySample]
    func fetchSleepSessions(from: Date, to: Date) async throws -> [SleepSession]
    func fetchBiometrics(for type: BiometricType, from: Date, to: Date) async throws -> [BiometricSample]
    func fetchSourceSummaries(from: Date, to: Date) async throws -> [SleepSource]
    func startObservingSleepChanges() async throws -> AsyncStream<HealthKitChangeEvent>
    func fetchIncrementalSleepChanges(anchor: Data?) async throws -> HealthKitAnchoredResult
}

nonisolated protocol LocalDataRepositoryProtocol: Sendable {
    func saveSessions(_ sessions: [SleepSession]) async throws
    func replaceSessions(_ sessions: [SleepSession], from: Date, to: Date) async throws
    func fetchCachedSessions(from: Date, to: Date) async throws -> [SleepSession]
    func fetchSession(forSleepDateKey key: String) async throws -> SleepSession?
    func fetchSessions(beforeSleepDateKey key: String, limit: Int) async throws -> [SleepSession]
    func fetchAvailableSleepDates(from startKey: String, to endKey: String) async throws -> [SleepDaySummary]
    func fetchLatestSession() async throws -> SleepSession?
    func saveBiometricSummary(_ summary: NightlyBiometricSummary) async throws
    func saveDailyActivitySummary(_ summary: DailyActivitySummary) async throws
    func fetchDailyActivitySummaries(from startKey: String, to endKey: String) async throws -> [DailyActivitySummary]
    func saveBaseline(_ baseline: SleepBaseline) async throws
    func fetchLatestBaseline(windowDays: Int) async throws -> SleepBaseline?
    func saveAlerts(_ alerts: [SleepAlert]) async throws
    func fetchAlerts(unreadOnly: Bool) async throws -> [SleepAlert]
    func fetchAlerts(unreadOnly: Bool, fromSleepDateKey: String?, limit: Int?) async throws -> [SleepAlert]
    func markAlertRead(id: UUID) async throws
    func saveAdherence(_ adherence: ProtocolAdherence) async throws
    func fetchAdherence(from: Date, to: Date) async throws -> [ProtocolAdherence]
    func saveActivityStatusLog(_ log: ActivityStatusLog) async throws
    func fetchActivityStatusLog(forDateKey key: String) async throws -> ActivityStatusLog?
    func fetchActivityStatusLogs(from startKey: String, to endKey: String) async throws -> [ActivityStatusLog]
    func saveProfile(_ profile: UserProfile) async throws
    func fetchProfile() async throws -> UserProfile
    func saveSyncAnchor(_ data: Data?, for typeIdentifier: String) async throws
    func fetchSyncAnchor(for typeIdentifier: String) async throws -> Data?
    func saveManualBiologyEntry(_ entry: ManualBiologyEntry) async throws
    func fetchManualBiologyEntries() async throws -> [ManualBiologyEntry]
    func deleteManualBiologyEntry(id: UUID) async throws
    /// Prunes all health-derived data older than the specified number of days.
    func pruneDataOlderThan(days: Int) async throws


    // MARK: - Context entries

    /// Saves (or replaces) the context entry for the given sleep date.
    func saveContextEntry(_ entry: SleepContextEntry) async throws
    /// Fetches the context entry for the given sleep date key, or nil if not found.
    func fetchContextEntry(forSleepDateKey key: String) async throws -> SleepContextEntry?
    /// Fetches all context entries whose sleep date key falls in [startKey, endKey].
    func fetchContextEntries(from startKey: String, to endKey: String) async throws -> [SleepContextEntry]
    /// Deletes the context entry with the given id.
    func deleteContextEntry(id: UUID) async throws
    /// Deletes all context entries. Called as part of the full local-data delete flow.
    func deleteAllContextEntries() async throws

    // MARK: - Privacy & migration

    /// Deletes all health-derived records.  User preferences (sleep goal, baseline
    /// window, onboarding completion flag) are retained; only health data is removed.
    /// Sets hasCompletedOnboarding = false so the app returns to onboarding state.
    func deleteAllHealthData() async throws

    /// Re-saves every stored record so that transparent encryption in
    /// PersistenceJSON.encode is applied to any legacy plain-JSON blobs.
    /// Safe to call multiple times (idempotent).
    func migrateToEncryptedStorage() async throws

    /// Returns a snapshot of how many records are stored locally.
    func fetchDataInventory() async throws -> LocalDataInventory
}

// MARK: - Supporting types

/// A snapshot of locally-stored health data record counts.
nonisolated struct LocalDataInventory: Sendable {
    var sleepSessionCount: Int
    var baselineCount: Int
    var alertCount: Int
    var protocolAdherenceCount: Int
    var activityLogCount: Int
    var manualBiologyEntryCount: Int
    var contextEntryCount: Int
    var lastContextEntryDate: Date?
    var oldestSessionDate: Date?
    var newestSessionDate: Date?
}

// MARK: - HealthKit fallback states

/// Richer data-quality states shown in the Sleep tab, distinct from
/// HealthAuthorizationPresentationState (which covers permissions only).
enum HealthKitFallbackState: Sendable, Equatable {
    case permissionDenied
    case baselineBuilding(nightsLogged: Int, nightsNeeded: Int)
    case noSleepStages
    case missingNights(count: Int)
    case watchNotWorn
    case insufficientHistory
}

extension LocalDataRepositoryProtocol {
    func fetchAlerts(unreadOnly: Bool) async throws -> [SleepAlert] {
        try await fetchAlerts(unreadOnly: unreadOnly, fromSleepDateKey: nil, limit: nil)
    }
}


nonisolated struct HealthAuthorizationResult: Sendable, Hashable {
    var requestCompleted: Bool
    var healthDataAvailable: Bool
    var canQuerySleep: Bool
    var lastQueryReturnedSamples: Bool?

    init(
        requestCompleted: Bool,
        healthDataAvailable: Bool,
        canQuerySleep: Bool,
        lastQueryReturnedSamples: Bool? = nil
    ) {
        self.requestCompleted = requestCompleted
        self.healthDataAvailable = healthDataAvailable
        self.canQuerySleep = canQuerySleep
        self.lastQueryReturnedSamples = lastQueryReturnedSamples
    }
}

nonisolated enum HealthAuthorizationPresentationState: Sendable, Hashable {
    case notRequested
    case healthDataUnavailable
    case requestCompleted
    case canQueryHealthData
    case noReadableSleepData
    case failed(String)
}

nonisolated struct HealthKitChangeEvent: @unchecked Sendable {
    var typeIdentifier: String
    var occurredAt: Date
    var acknowledge: () -> Void

    init(
        typeIdentifier: String,
        occurredAt: Date = Date(),
        acknowledge: @escaping () -> Void
    ) {
        self.typeIdentifier = typeIdentifier
        self.occurredAt = occurredAt
        self.acknowledge = acknowledge
    }
}

nonisolated struct HealthKitAnchoredResult: @unchecked Sendable {
    var samples: [HKCategorySample]
    var deletedObjects: [HKDeletedObject]
    var newAnchor: Data?

    init(
        samples: [HKCategorySample],
        deletedObjects: [HKDeletedObject],
        newAnchor: Data?
    ) {
        self.samples = samples
        self.deletedObjects = deletedObjects
        self.newAnchor = newAnchor
    }
}
