import Foundation
@preconcurrency import HealthKit

protocol HealthKitRepositoryProtocol: Sendable {
    func isHealthDataAvailable() -> Bool
    func requestAuthorization() async throws -> HealthAuthorizationResult
    func fetchSleepSamples(from: Date, to: Date) async throws -> [HKCategorySample]
    func fetchSleepSessions(from: Date, to: Date) async throws -> [SleepSession]
    func fetchBiometrics(for type: BiometricType, from: Date, to: Date) async throws -> [BiometricSample]
    func fetchSourceSummaries(from: Date, to: Date) async throws -> [SleepSource]
    func startObservingSleepChanges() async throws -> AsyncStream<HealthKitChangeEvent>
    func fetchIncrementalSleepChanges(anchor: Data?) async throws -> HealthKitAnchoredResult
}

protocol LocalDataRepositoryProtocol: Sendable {
    func saveSessions(_ sessions: [SleepSession]) async throws
    func replaceSessions(_ sessions: [SleepSession], from: Date, to: Date) async throws
    func fetchCachedSessions(from: Date, to: Date) async throws -> [SleepSession]
    func fetchSession(forSleepDateKey key: String) async throws -> SleepSession?
    func fetchSessions(beforeSleepDateKey key: String, limit: Int) async throws -> [SleepSession]
    func fetchAvailableSleepDates(from startKey: String, to endKey: String) async throws -> [SleepDaySummary]
    func fetchLatestSession() async throws -> SleepSession?
    func saveBiometricSummary(_ summary: NightlyBiometricSummary) async throws
    func saveBaseline(_ baseline: SleepBaseline) async throws
    func fetchLatestBaseline(windowDays: Int) async throws -> SleepBaseline?
    func saveAlerts(_ alerts: [SleepAlert]) async throws
    func fetchAlerts(unreadOnly: Bool) async throws -> [SleepAlert]
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
}

struct HealthAuthorizationResult: Sendable, Hashable {
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

enum HealthAuthorizationPresentationState: Sendable, Hashable {
    case notRequested
    case healthDataUnavailable
    case requestCompleted
    case canQueryHealthData
    case noReadableSleepData
    case failed(String)
}

struct HealthKitChangeEvent: @unchecked Sendable {
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

struct HealthKitAnchoredResult: @unchecked Sendable {
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
