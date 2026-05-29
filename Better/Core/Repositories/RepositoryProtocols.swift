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

    // MARK: - Sleep Mode

    func saveSleepModeSettings(_ settings: SleepModeSettings) async throws
    func fetchSleepModeSettings() async throws -> SleepModeSettings?
    func saveSleepModeSchedule(_ schedule: SleepModeSchedule) async throws
    func fetchSleepModeSchedule() async throws -> SleepModeSchedule?
    func saveSleepModeSession(_ session: SleepModeSession) async throws
    func fetchSleepModeSessions(from: Date, to: Date) async throws -> [SleepModeSession]
    func deleteAllSleepModeData() async throws


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

    // MARK: - Protocol Formula Tracking

    /// Save (insert or update) a formula version. Enforces:
    ///   - `isActive` singleton (clears the flag on any other row when this one is active),
    ///   - immutability of `formulaText` / `components` once any `ProtocolNightLog`
    ///     references this version (except for `isImportedPlaceholder` rows whose first
    ///     non-empty save atomically clears the placeholder flag).
    /// Throws `ProtocolFormulaRepositoryError.formulaTextLocked` if the immutability rule fires.
    func saveFormulaVersion(_ version: ProtocolFormulaVersion) async throws
    func fetchAllFormulaVersions() async throws -> [ProtocolFormulaVersion]
    func fetchActiveFormulaVersion() async throws -> ProtocolFormulaVersion?
    func fetchFormulaVersion(id: UUID) async throws -> ProtocolFormulaVersion?
    func archiveFormulaVersion(id: UUID) async throws
    func deleteFormulaVersion(id: UUID) async throws

    func saveNightLog(_ log: ProtocolNightLog) async throws
    func fetchNightLog(forSleepDateKey key: String) async throws -> ProtocolNightLog?
    func fetchNightLogs(from startKey: String, to endKey: String) async throws -> [ProtocolNightLog]
    func deleteNightLog(forSleepDateKey key: String) async throws
    func hasNightLogs(forVersionID id: UUID) async throws -> Bool


    func saveLogEdit(_ edit: ProtocolLogEdit) async throws
    func fetchLogEdits(forSleepDateKey key: String) async throws -> [ProtocolLogEdit]

    func saveBaselineSnapshot(_ snapshot: ProtocolBaselineSnapshot) async throws
    func fetchBaselineSnapshot() async throws -> ProtocolBaselineSnapshot?
    func fetchBaselineSnapshot(versionID: UUID) async throws -> ProtocolBaselineSnapshot?
    func fetchInterventionWindows() async throws -> [InterventionWindow]
    func saveInterventionWindow(_ window: InterventionWindow) async throws
    func deleteInterventionWindow(id: UUID) async throws
    func deleteBaselineSnapshot() async throws

    // MARK: - Dashboard baseline snapshot cache (V4)

    func saveBaselineSnapshot(_ snapshot: DashboardBaselineSnapshotRecord) async throws
    func fetchBaselineSnapshot(asOfSleepDateKey: String, windowKind: String) async throws -> DashboardBaselineSnapshotRecord?
    func deleteBaselineSnapshots(containingSleepDateKey: String) async throws

    // MARK: - Chronotype snapshot cache (V4)

    func saveChronotypeSnapshot(_ snapshot: ChronotypeSnapshotRecord) async throws
    func fetchChronotypeSnapshot(windowEndSleepDateKey: String) async throws -> ChronotypeSnapshotRecord?

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
    var sleepModeSettingsCount: Int
    var sleepModeScheduleCount: Int
    var sleepModeSessionCount: Int
    var contextEntryCount: Int
    var lastContextEntryDate: Date?
    var lastSleepModeSessionDate: Date?
    var oldestSessionDate: Date?
    var newestSessionDate: Date?
    var protocolFormulaVersionCount: Int
    var protocolNightLogCount: Int
    var protocolLogEditCount: Int
    var protocolBaselineSnapshotCount: Int
    var protocolBaselineValidNightCount: Int?
    var protocolBaselineIsInsufficient: Bool?

    init(
        sleepSessionCount: Int,
        baselineCount: Int,
        alertCount: Int,
        protocolAdherenceCount: Int,
        activityLogCount: Int,
        manualBiologyEntryCount: Int,
        sleepModeSettingsCount: Int = 0,
        sleepModeScheduleCount: Int = 0,
        sleepModeSessionCount: Int = 0,
        contextEntryCount: Int,
        lastContextEntryDate: Date? = nil,
        lastSleepModeSessionDate: Date? = nil,
        oldestSessionDate: Date? = nil,
        newestSessionDate: Date? = nil,
        protocolFormulaVersionCount: Int = 0,
        protocolNightLogCount: Int = 0,
        protocolLogEditCount: Int = 0,
        protocolBaselineSnapshotCount: Int = 0,
        protocolBaselineValidNightCount: Int? = nil,
        protocolBaselineIsInsufficient: Bool? = nil
    ) {
        self.sleepSessionCount = sleepSessionCount
        self.baselineCount = baselineCount
        self.alertCount = alertCount
        self.protocolAdherenceCount = protocolAdherenceCount
        self.activityLogCount = activityLogCount
        self.manualBiologyEntryCount = manualBiologyEntryCount
        self.sleepModeSettingsCount = sleepModeSettingsCount
        self.sleepModeScheduleCount = sleepModeScheduleCount
        self.sleepModeSessionCount = sleepModeSessionCount
        self.contextEntryCount = contextEntryCount
        self.lastContextEntryDate = lastContextEntryDate
        self.lastSleepModeSessionDate = lastSleepModeSessionDate
        self.oldestSessionDate = oldestSessionDate
        self.newestSessionDate = newestSessionDate
        self.protocolFormulaVersionCount = protocolFormulaVersionCount
        self.protocolNightLogCount = protocolNightLogCount
        self.protocolLogEditCount = protocolLogEditCount
        self.protocolBaselineSnapshotCount = protocolBaselineSnapshotCount
        self.protocolBaselineValidNightCount = protocolBaselineValidNightCount
        self.protocolBaselineIsInsufficient = protocolBaselineIsInsufficient
    }
}

nonisolated enum ProtocolFormulaRepositoryError: Error, Equatable, Sendable {
    /// Raised when a save would edit `formulaText` or `components` of a version that
    /// already has at least one ProtocolNightLog referencing it (and is not an
    /// imported-placeholder still awaiting backfill).
    case formulaTextLocked(versionID: UUID)
    /// Raised by `saveBaselineSnapshot` when the snapshot would be persisted with
    /// zero valid nights — explicitly disallowed.
    case baselineSnapshotEmpty
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

    func saveSleepModeSettings(_ settings: SleepModeSettings) async throws {}
    func fetchSleepModeSettings() async throws -> SleepModeSettings? { nil }
    func saveSleepModeSchedule(_ schedule: SleepModeSchedule) async throws {}
    func fetchSleepModeSchedule() async throws -> SleepModeSchedule? { nil }
    func saveSleepModeSession(_ session: SleepModeSession) async throws {}
    func fetchSleepModeSessions(from: Date, to: Date) async throws -> [SleepModeSession] { [] }
    func deleteAllSleepModeData() async throws {}

    // Default no-op implementations so mocks (e.g. MockLocalDataRepository) don't have
    // to grow new in-memory state for every consumer that doesn't exercise Protocol
    // Formula Tracking. Live `LocalDataRepository` overrides all of these.
    func saveFormulaVersion(_ version: ProtocolFormulaVersion) async throws {}
    func fetchAllFormulaVersions() async throws -> [ProtocolFormulaVersion] { [] }
    func fetchActiveFormulaVersion() async throws -> ProtocolFormulaVersion? { nil }
    func fetchFormulaVersion(id: UUID) async throws -> ProtocolFormulaVersion? { nil }
    func archiveFormulaVersion(id: UUID) async throws {}
    func deleteFormulaVersion(id: UUID) async throws {}
    func saveNightLog(_ log: ProtocolNightLog) async throws {}
    func fetchNightLog(forSleepDateKey key: String) async throws -> ProtocolNightLog? { nil }
    func fetchNightLogs(from startKey: String, to endKey: String) async throws -> [ProtocolNightLog] { [] }
    func deleteNightLog(forSleepDateKey key: String) async throws {}
    func hasNightLogs(forVersionID id: UUID) async throws -> Bool { false }

    func saveLogEdit(_ edit: ProtocolLogEdit) async throws {}
    func fetchLogEdits(forSleepDateKey key: String) async throws -> [ProtocolLogEdit] { [] }
    func saveBaselineSnapshot(_ snapshot: ProtocolBaselineSnapshot) async throws {}
    func fetchBaselineSnapshot() async throws -> ProtocolBaselineSnapshot? { nil }
    func fetchBaselineSnapshot(versionID: UUID) async throws -> ProtocolBaselineSnapshot? { nil }
    func fetchInterventionWindows() async throws -> [InterventionWindow] { [] }
    func saveInterventionWindow(_ window: InterventionWindow) async throws {}
    func deleteInterventionWindow(id: UUID) async throws {}
    func deleteBaselineSnapshot() async throws {}

    // Default no-op implementations for V4 cache tables so mocks don't need
    // to track dashboard baseline / chronotype snapshot state.
    func saveBaselineSnapshot(_ snapshot: DashboardBaselineSnapshotRecord) async throws {}
    func fetchBaselineSnapshot(asOfSleepDateKey: String, windowKind: String) async throws -> DashboardBaselineSnapshotRecord? { nil }
    func deleteBaselineSnapshots(containingSleepDateKey: String) async throws {}
    func saveChronotypeSnapshot(_ snapshot: ChronotypeSnapshotRecord) async throws {}
    func fetchChronotypeSnapshot(windowEndSleepDateKey: String) async throws -> ChronotypeSnapshotRecord? { nil }
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
