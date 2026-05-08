import Foundation
import HealthKit
import XCTest
@testable import Better

@MainActor
final class BiologyViewModelTests: XCTestCase {
    private static let start = Date(timeIntervalSince1970: 0)
    private static let end = Date(timeIntervalSince1970: 86_400)

    func testLoadFetchesAllSixHealthKitBiometricTypes() async {
        let repo = BiologyFakeHealthKitRepository()
        let vm = BiologyViewModel(
            localRepository: MockLocalDataRepository(),
            healthRepository: repo
        )

        await vm.load(now: Self.end)

        let queried = await repo.queriedTypes
        XCTAssertTrue(queried.contains(.vo2Max))
        XCTAssertTrue(queried.contains(.bodyMass))
        XCTAssertTrue(queried.contains(.leanBodyMass))
        XCTAssertTrue(queried.contains(.bodyFatPercentage))
        XCTAssertTrue(queried.contains(.bodyTemperature))
        XCTAssertTrue(queried.contains(.restingHeartRate))
    }

    func testRealHRVHistoryFlowsFromSessions() async {
        let session = makeSession(key: "1970-01-01", hrvAverage: 55)
        let repo = MockLocalDataRepository(sessions: [session])
        let vm = BiologyViewModel(
            localRepository: repo,
            healthRepository: BiologyFakeHealthKitRepository()
        )

        await vm.load(now: Self.end)

        let hrv = vm.metrics.first { $0.kind == .hrvBaseline }
        XCTAssertEqual(hrv?.history, [55])
    }

    func testHRVTrendIsComputedFromHistory() async {
        let sessions = [
            makeSession(key: "1970-01-01", hrvAverage: 50),
            makeSession(key: "1970-01-02", hrvAverage: 60)
        ]
        let repo = MockLocalDataRepository(sessions: sessions)
        let vm = BiologyViewModel(
            localRepository: repo,
            healthRepository: BiologyFakeHealthKitRepository()
        )

        await vm.load(now: Self.end)

        let hrv = vm.metrics.first { $0.kind == .hrvBaseline }
        XCTAssertEqual(hrv?.trend, "Increasing")
    }

    func testRHRUsesRestingHeartRateTypeNotSleepHR() async {
        let rhrSample = BiometricSample(
            type: .restingHeartRate,
            value: 56,
            unit: "count/min",
            startDate: Self.start,
            endDate: Self.end
        )
        let healthRepo = BiologyFakeHealthKitRepository(samples: [.restingHeartRate: [rhrSample]])
        let sessionWithHighSleepHR = makeSession(key: "1970-01-01", heartRateAverage: 72)
        let vm = BiologyViewModel(
            localRepository: MockLocalDataRepository(sessions: [sessionWithHighSleepHR]),
            healthRepository: healthRepo
        )

        await vm.load(now: Self.end)

        let rhr = vm.metrics.first { $0.kind == .restingHeartRateBaseline }
        XCTAssertEqual(rhr?.value, 56)
    }

    func testLoadBuildsBiomarkerSummaries() async {
        let session = makeSession(key: "1970-01-01", hrvAverage: 55)
        let repo = MockLocalDataRepository(sessions: [session])
        let vm = BiologyViewModel(
            localRepository: repo,
            healthRepository: BiologyFakeHealthKitRepository()
        )

        await vm.load(now: Self.end)

        XCTAssertEqual(vm.biomarkerSummaries[.hrv]?[.thirtyDays]?.currentValue, 55)
        XCTAssertEqual(vm.biomarkerSummaries[.hrv]?[.thirtyDays]?.validSampleCount, 1)
    }

    func testReloadRefreshesBiomarkerSummaries() async {
        let first = makeSession(key: "1970-01-01", hrvAverage: 45)
        let second = makeSession(key: "1970-01-02", hrvAverage: 65)
        let repo = MockLocalDataRepository(sessions: [first])
        let vm = BiologyViewModel(
            localRepository: repo,
            healthRepository: BiologyFakeHealthKitRepository()
        )

        await vm.load(now: Self.end)
        try? await repo.saveSessions([second])
        await vm.load(now: Self.end.addingTimeInterval(86_400))

        XCTAssertEqual(vm.biomarkerSummaries[.hrv]?[.thirtyDays]?.currentValue, 65)
        XCTAssertEqual(vm.biomarkerSummaries[.hrv]?[.thirtyDays]?.validSampleCount, 2)
    }

    func testAllMetricsNilWhenNoData() async {
        let vm = BiologyViewModel(
            localRepository: MockLocalDataRepository(),
            healthRepository: BiologyFakeHealthKitRepository()
        )

        await vm.load(now: Self.end)

        XCTAssertFalse(vm.metrics.isEmpty)
        XCTAssertTrue(vm.metrics.allSatisfy { $0.value == nil })
    }

    func testOnAppearRetriesWhenAllMetricValuesAreNil() async {
        // Use a stub local repo that can be told to throw — if onAppear retries,
        // the second load() call throws, setting vm.errorMessage.
        let throwRepo = OnRetryThrowingLocalRepository()
        let vm = BiologyViewModel(
            localRepository: throwRepo,
            healthRepository: BiologyFakeHealthKitRepository()
        )

        // First load: succeeds, all metrics nil (no HealthKit data)
        await vm.load(now: Self.end)
        XCTAssertNil(vm.errorMessage, "first load should succeed")
        XCTAssertTrue(vm.metrics.allSatisfy { $0.value == nil }, "all metrics nil after empty first load")

        // Arm the throw for the next load
        throwRepo.shouldThrow = true

        // onAppear should retry (hasData is false) → second load throws → errorMessage set
        await vm.onAppear(now: Self.end)
        XCTAssertNotNil(vm.errorMessage, "onAppear should have retried and triggered the throw")
    }

    func testOnAppearDoesNotRetryWhenDataIsPresent() async {
        let rhrSample = BiometricSample(
            type: .restingHeartRate,
            value: 58,
            unit: "count/min",
            startDate: Self.start,
            endDate: Self.end
        )
        let healthRepo = BiologyFakeHealthKitRepository(samples: [.restingHeartRate: [rhrSample]])
        let vm = BiologyViewModel(
            localRepository: MockLocalDataRepository(),
            healthRepository: healthRepo
        )

        await vm.onAppear(now: Self.end)
        let countAfterFirst = await healthRepo.fetchCallCount

        await vm.onAppear(now: Self.end)
        let countAfterSecond = await healthRepo.fetchCallCount
        XCTAssertEqual(countAfterSecond, countAfterFirst)
    }
}

private extension BiologyViewModelTests {
    func makeSession(key: String, hrvAverage: Double? = nil, heartRateAverage: Double? = nil) -> SleepSession {
        // Derive unique dates from the key so multi-session sorts are stable
        let midnight = ISO8601DateFormatter().date(from: key + "T00:00:00Z") ?? Self.start
        let sessionStart = midnight.addingTimeInterval(-2 * 3_600)
        let sessionEnd = midnight.addingTimeInterval(6 * 3_600)
        let biometrics: NightlyBiometricSummary? = (hrvAverage != nil || heartRateAverage != nil) ? NightlyBiometricSummary(
            sleepSessionID: UUID(),
            sleepDateKey: key,
            heartRateAverage: heartRateAverage,
            heartRateMinimum: nil,
            heartRateMaximum: nil,
            hrvAverage: hrvAverage,
            hrvMedian: nil,
            oxygenSaturationAverage: nil,
            oxygenSaturationMinimum: nil,
            respiratoryRateAverage: nil
        ) : nil
        return SleepSession(
            sleepDateKey: key,
            startDate: sessionStart,
            endDate: sessionEnd,
            dataQuality: .detailedStages,
            totalInBedTime: 7 * 3_600,
            totalSleepTime: 7 * 3_600,
            biometrics: biometrics
        )
    }
}

/// Minimal local repository stub that throws on `fetchCachedSessions` once `shouldThrow`
/// is set. Non-isolated `@unchecked Sendable` so calls hop off the main actor to the
/// cooperative pool (genuine suspension), matching `MockLocalDataRepository` behaviour.
/// `shouldThrow` is written on `@MainActor` before each `await` that reads it, so the
/// `await` boundary guarantees the write is visible.
final class OnRetryThrowingLocalRepository: LocalDataRepositoryProtocol, @unchecked Sendable {
    var shouldThrow = false

    func fetchCachedSessions(from: Date, to: Date) async throws -> [SleepSession] {
        if shouldThrow { throw NSError(domain: "BiologyViewModelTests", code: 1) }
        return []
    }
    func fetchLatestSession() async throws -> SleepSession? { nil }
    func fetchProfile() async throws -> UserProfile { UserProfile() }
    func fetchLatestBaseline(windowDays: Int) async throws -> SleepBaseline? { nil }

    func saveSessions(_ sessions: [SleepSession]) async throws {}
    func replaceSessions(_ sessions: [SleepSession], from: Date, to: Date) async throws {}
    func fetchSession(forSleepDateKey key: String) async throws -> SleepSession? { nil }
    func fetchSessions(beforeSleepDateKey key: String, limit: Int) async throws -> [SleepSession] { [] }
    func fetchAvailableSleepDates(from startKey: String, to endKey: String) async throws -> [SleepDaySummary] { [] }
    func saveBiometricSummary(_ summary: NightlyBiometricSummary) async throws {}
    func saveDailyActivitySummary(_ summary: DailyActivitySummary) async throws {}
    func fetchDailyActivitySummaries(from startKey: String, to endKey: String) async throws -> [DailyActivitySummary] { [] }
    func saveBaseline(_ baseline: SleepBaseline) async throws {}
    func saveAlerts(_ alerts: [SleepAlert]) async throws {}
    func fetchAlerts(unreadOnly: Bool) async throws -> [SleepAlert] { [] }
    func fetchAlerts(unreadOnly: Bool, fromSleepDateKey: String?, limit: Int?) async throws -> [SleepAlert] { [] }
    func markAlertRead(id: UUID) async throws {}
    func saveAdherence(_ adherence: ProtocolAdherence) async throws {}
    func fetchAdherence(from: Date, to: Date) async throws -> [ProtocolAdherence] { [] }
    func saveActivityStatusLog(_ log: ActivityStatusLog) async throws {}
    func fetchActivityStatusLog(forDateKey key: String) async throws -> ActivityStatusLog? { nil }
    func fetchActivityStatusLogs(from startKey: String, to endKey: String) async throws -> [ActivityStatusLog] { [] }
    func saveProfile(_ profile: UserProfile) async throws {}
    func saveSyncAnchor(_ data: Data?, for typeIdentifier: String) async throws {}
    func fetchSyncAnchor(for typeIdentifier: String) async throws -> Data? { nil }
    func saveManualBiologyEntry(_ entry: ManualBiologyEntry) async throws {}
    func fetchManualBiologyEntries() async throws -> [ManualBiologyEntry] { [] }
    func deleteManualBiologyEntry(id: UUID) async throws {}
    func saveContextEntry(_ entry: SleepContextEntry) async throws {}
    func fetchContextEntry(forSleepDateKey key: String) async throws -> SleepContextEntry? { nil }
    func fetchContextEntries(from startKey: String, to endKey: String) async throws -> [SleepContextEntry] { [] }
    func deleteContextEntry(id: UUID) async throws {}
    func deleteAllContextEntries() async throws {}
    func pruneDataOlderThan(days: Int) async throws {}
    func deleteAllHealthData() async throws {}
    func migrateToEncryptedStorage() async throws {}
    func fetchDataInventory() async throws -> LocalDataInventory {
        LocalDataInventory(
            sleepSessionCount: 0,
            baselineCount: 0,
            alertCount: 0,
            protocolAdherenceCount: 0,
            activityLogCount: 0,
            manualBiologyEntryCount: 0,
            contextEntryCount: 0
        )
    }
}

actor BiologyFakeHealthKitRepository: HealthKitRepositoryProtocol {
    var samples: [BiometricType: [BiometricSample]]
    private(set) var queriedTypes: Set<BiometricType> = []
    private(set) var fetchCallCount = 0

    init(samples: [BiometricType: [BiometricSample]] = [:]) {
        self.samples = samples
    }

    nonisolated func isHealthDataAvailable() -> Bool { true }

    func requestAuthorization() async throws -> HealthAuthorizationResult {
        HealthAuthorizationResult(requestCompleted: true, healthDataAvailable: true, canQuerySleep: true)
    }

    func fetchSleepSamples(from: Date, to: Date) async throws -> [HKCategorySample] { [] }

    func fetchSleepSessions(from: Date, to: Date) async throws -> [SleepSession] { [] }

    func fetchBiometrics(for type: BiometricType, from: Date, to: Date) async throws -> [BiometricSample] {
        queriedTypes.insert(type)
        fetchCallCount += 1
        return samples[type, default: []].filter { $0.endDate > from && $0.startDate < to }
    }

    func fetchSourceSummaries(from: Date, to: Date) async throws -> [SleepSource] { [] }

    func startObservingSleepChanges() async throws -> AsyncStream<HealthKitChangeEvent> {
        AsyncStream { continuation in continuation.finish() }
    }

    func fetchIncrementalSleepChanges(anchor: Data?) async throws -> HealthKitAnchoredResult {
        HealthKitAnchoredResult(samples: [], deletedObjects: [], newAnchor: anchor)
    }
}
