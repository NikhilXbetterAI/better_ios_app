import XCTest
@testable import Better

/// Tests for the Phase 4 chronotype snapshot cache added to `ChronotypeCalculationService`.
///
/// These tests use an in-memory `SpyLocalDataRepository` that records every
/// `fetchCachedSessions` call so we can assert whether the 90-day session
/// fetch was skipped on a cache hit.
final class ChronotypeSnapshotCacheTests: XCTestCase {

    // MARK: - Helpers

    private static let calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal
    }()

    private var service: ChronotypeCalculationService { ChronotypeCalculationService() }

    private func date(_ string: String) -> Date {
        ISO8601DateFormatter().date(from: string)!
    }

    /// Builds a minimal ChronotypeEstimate suitable for round-trip encoding tests.
    private func makeEstimate() -> ChronotypeEstimate {
        ChronotypeEstimate(
            bucket: .intermediate,
            correctedMidpointMinute: 240,
            workdayMidpointMinute: 240,
            freeDayMidpointMinute: 270,
            workdayMedianDuration: 7 * 3_600,
            freeDayMedianDuration: 7.5 * 3_600,
            weeklyAverageDuration: 7.1 * 3_600,
            validNightCount: 14,
            workdayNightCount: 10,
            freeDayNightCount: 4,
            excludedNightCount: 2,
            excludedCountsByReason: [.travelOrJetLag: 2],
            confidence: .medium,
            bodyClockReadiness: .goodEstimate,
            optimalSleepWindow: SleepWindowRecommendation(startMinute: 22 * 60, endMinute: 5 * 60, duration: 7 * 3_600),
            socialJetlagMinutes: 30,
            nightsUntilNextTier: 16,
            nextTierName: "Stable"
        )
    }

    // MARK: - Test 1: Cache hit — no session fetch on second load

    func testCacheHitSkipsSessionFetch() async throws {
        let spy = SpyLocalDataRepository()
        let svc = service

        // Pre-populate the snapshot with a fresh estimate.
        let estimate = makeEstimate()
        let estimateData = try PersistenceJSON.encode(estimate)
        let snapshot = StoredChronotypeSnapshot(
            windowEndSleepDateKey: "2026-05-02",
            generatedAt: Date(), // now → within 7-day TTL
            estimateData: estimateData,
            coverageNightCount: 16,
            windowDays: 90
        )
        try await spy.saveChronotypeSnapshot(snapshot)

        // Reset the fetch counter after setup.
        spy.resetFetchCounters()

        let result = await svc.cachedEstimate(
            windowEndSleepDateKey: "2026-05-02",
            localRepository: spy
        )

        XCTAssertNotNil(result, "Should return a result on cache hit")
        XCTAssertEqual(result?.status, .estimated)
        XCTAssertEqual(result?.estimate?.correctedMidpointMinute, estimate.correctedMidpointMinute)
        XCTAssertEqual(result?.estimate?.bucket, estimate.bucket)
        // The session fetch is skipped — the calling path never calls fetchCachedSessions.
        XCTAssertEqual(spy.sessionFetchCount, 0, "Cache hit must not trigger a session fetch")
    }

    // MARK: - Test 2: Cache TTL — 8-day-old snapshot is a miss

    func testCacheMissOnStaleTTL() async throws {
        let spy = SpyLocalDataRepository()
        let svc = service

        let staleDate = Date().addingTimeInterval(-8 * 86_400)  // 8 days ago → past 7-day TTL
        let estimate = makeEstimate()
        let estimateData = try PersistenceJSON.encode(estimate)
        let snapshot = StoredChronotypeSnapshot(
            windowEndSleepDateKey: "2026-05-02",
            generatedAt: staleDate,
            estimateData: estimateData,
            coverageNightCount: 16,
            windowDays: 90
        )
        try await spy.saveChronotypeSnapshot(snapshot)

        let result = await svc.cachedEstimate(
            windowEndSleepDateKey: "2026-05-02",
            localRepository: spy
        )

        XCTAssertNil(result, "8-day-old snapshot must be treated as a cache miss")
    }

    // MARK: - Test 3: Snapshot absent → miss

    func testCacheMissWhenNoSnapshot() async {
        let spy = SpyLocalDataRepository()
        let result = await service.cachedEstimate(
            windowEndSleepDateKey: "2026-06-01",
            localRepository: spy
        )
        XCTAssertNil(result, "Missing snapshot must return nil")
    }

    // MARK: - Test 4: saveSnapshot / cachedEstimate round-trip parity

    func testSaveAndRetrieveParity() async throws {
        let spy = SpyLocalDataRepository()
        let svc = service

        // Build a full ChronotypeCalculationResult the same way the service does.
        let estimate = makeEstimate()
        let freshResult = ChronotypeCalculationResult(
            status: .estimated,
            estimate: estimate,
            includedNights: [],
            excludedCountsByReason: estimate.excludedCountsByReason,
            totalCandidateNightCount: 18,
            validNightCount: estimate.validNightCount,
            workdayNightCount: estimate.workdayNightCount,
            freeDayNightCount: estimate.freeDayNightCount,
            missingRequirements: [],
            windowDays: 90,
            windowStart: date("2026-02-01T00:00:00Z"),
            windowEnd: date("2026-05-02T00:00:00Z")
        )

        await svc.saveSnapshot(
            result: freshResult,
            windowEndSleepDateKey: "2026-05-02",
            localRepository: spy
        )

        let cached = await svc.cachedEstimate(
            windowEndSleepDateKey: "2026-05-02",
            localRepository: spy
        )

        XCTAssertNotNil(cached)
        XCTAssertEqual(cached?.estimate?.correctedMidpointMinute, estimate.correctedMidpointMinute)
        XCTAssertEqual(cached?.estimate?.bucket, estimate.bucket)
        XCTAssertEqual(cached?.estimate?.workdayMidpointMinute, estimate.workdayMidpointMinute)
        XCTAssertEqual(cached?.estimate?.freeDayMidpointMinute, estimate.freeDayMidpointMinute)
        XCTAssertEqual(cached?.estimate?.validNightCount, estimate.validNightCount)
        XCTAssertEqual(cached?.estimate?.workdayNightCount, estimate.workdayNightCount)
        XCTAssertEqual(cached?.estimate?.freeDayNightCount, estimate.freeDayNightCount)
        XCTAssertEqual(cached?.estimate?.confidence, estimate.confidence)
        XCTAssertEqual(cached?.estimate?.bodyClockReadiness, estimate.bodyClockReadiness)
        XCTAssertEqual(cached?.estimate?.socialJetlagMinutes, estimate.socialJetlagMinutes)
        XCTAssertEqual(cached?.estimate?.nightsUntilNextTier, estimate.nightsUntilNextTier)
        // Numeric parity on durations (floating-point round-trip).
        let tolerance: Double = 1.0
        XCTAssertEqual(
            cached?.estimate?.workdayMedianDuration ?? 0,
            estimate.workdayMedianDuration,
            accuracy: tolerance
        )
        XCTAssertEqual(
            cached?.estimate?.weeklyAverageDuration ?? 0,
            estimate.weeklyAverageDuration,
            accuracy: tolerance
        )
    }

    // MARK: - Test 5: Invalidation — stale marker written by sync engine expires immediately

    func testInvalidationViaStaleMarker() async throws {
        let spy = SpyLocalDataRepository()
        let svc = service

        // First write a valid snapshot.
        let estimate = makeEstimate()
        let estimateData = try PersistenceJSON.encode(estimate)
        let validSnapshot = StoredChronotypeSnapshot(
            windowEndSleepDateKey: "2026-05-29",
            generatedAt: Date(),
            estimateData: estimateData,
            coverageNightCount: 14,
            windowDays: 90
        )
        try await spy.saveChronotypeSnapshot(validSnapshot)

        // Simulate what HealthSyncEngine.invalidateChronotypeSnapshot does —
        // overwrite with a generatedAt of epoch (far past the 7-day TTL).
        let staleMarker = StoredChronotypeSnapshot(
            windowEndSleepDateKey: "2026-05-29",
            generatedAt: Date(timeIntervalSince1970: 0),
            estimateData: nil,
            coverageNightCount: 0,
            windowDays: 90
        )
        try await spy.saveChronotypeSnapshot(staleMarker)

        let result = await svc.cachedEstimate(
            windowEndSleepDateKey: "2026-05-29",
            localRepository: spy
        )

        XCTAssertNil(result, "Stale-marker snapshot (epoch generatedAt) must be treated as a miss")
    }

    // MARK: - Test 6: Insufficient-data snapshot round-trip

    func testInsufficientDataSnapshotRoundTrip() async {
        let spy = SpyLocalDataRepository()
        let svc = service

        // A snapshot with nil estimateData represents an insufficient-data result.
        let snapshot = StoredChronotypeSnapshot(
            windowEndSleepDateKey: "2026-05-29",
            generatedAt: Date(),
            estimateData: nil,
            coverageNightCount: 3,
            windowDays: 90
        )
        try? await spy.saveChronotypeSnapshot(snapshot)

        let result = await svc.cachedEstimate(
            windowEndSleepDateKey: "2026-05-29",
            localRepository: spy
        )

        XCTAssertNotNil(result, "Nil estimateData snapshot should still produce a result")
        XCTAssertEqual(result?.status, .insufficientData)
        XCTAssertNil(result?.estimate, "Insufficient-data result must have no estimate")
    }
}

// MARK: - Spy repository

/// In-memory `LocalDataRepositoryProtocol` that stores one chronotype snapshot
/// and counts `fetchCachedSessions` calls to assert skipped fetches on cache hits.
private final class SpyLocalDataRepository: LocalDataRepositoryProtocol {

    // MARK: Tracking
    private(set) var sessionFetchCount = 0

    func resetFetchCounters() {
        sessionFetchCount = 0
    }

    // MARK: Chronotype snapshot storage
    private var storedSnapshot: StoredChronotypeSnapshot?

    func saveChronotypeSnapshot(_ snapshot: StoredChronotypeSnapshot) async throws {
        storedSnapshot = snapshot
    }

    func fetchChronotypeSnapshot(windowEndSleepDateKey: String) async throws -> StoredChronotypeSnapshot? {
        guard let snap = storedSnapshot, snap.windowEndSleepDateKey == windowEndSleepDateKey else { return nil }
        return snap
    }

    // MARK: Session fetch (tracked)
    func fetchCachedSessions(from: Date, to: Date) async throws -> [SleepSession] {
        sessionFetchCount += 1
        return []
    }

    // MARK: - Default no-op implementations required by the protocol

    func saveSessions(_ sessions: [SleepSession]) async throws {}
    func replaceSessions(_ sessions: [SleepSession], from: Date, to: Date) async throws {}
    func fetchSession(forSleepDateKey key: String) async throws -> SleepSession? { nil }
    func fetchSessions(beforeSleepDateKey key: String, limit: Int) async throws -> [SleepSession] { [] }
    func fetchAvailableSleepDates(from startKey: String, to endKey: String) async throws -> [SleepDaySummary] { [] }
    func fetchLatestSession() async throws -> SleepSession? { nil }
    func saveBiometricSummary(_ summary: NightlyBiometricSummary) async throws {}
    func saveDailyActivitySummary(_ summary: DailyActivitySummary) async throws {}
    func fetchDailyActivitySummaries(from startKey: String, to endKey: String) async throws -> [DailyActivitySummary] { [] }
    func saveBaseline(_ baseline: SleepBaseline) async throws {}
    func fetchLatestBaseline(windowDays: Int) async throws -> SleepBaseline? { nil }
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
    func fetchProfile() async throws -> UserProfile { UserProfile() }
    func saveSyncAnchor(_ data: Data?, for typeIdentifier: String) async throws {}
    func fetchSyncAnchor(for typeIdentifier: String) async throws -> Data? { nil }
    func saveManualBiologyEntry(_ entry: ManualBiologyEntry) async throws {}
    func fetchManualBiologyEntries() async throws -> [ManualBiologyEntry] { [] }
    func deleteManualBiologyEntry(id: UUID) async throws {}
    func pruneDataOlderThan(days: Int) async throws {}
    func saveSleepModeSettings(_ settings: SleepModeSettings) async throws {}
    func fetchSleepModeSettings() async throws -> SleepModeSettings? { nil }
    func saveSleepModeSchedule(_ schedule: SleepModeSchedule) async throws {}
    func fetchSleepModeSchedule() async throws -> SleepModeSchedule? { nil }
    func saveSleepModeSession(_ session: SleepModeSession) async throws {}
    func fetchSleepModeSessions(from: Date, to: Date) async throws -> [SleepModeSession] { [] }
    func deleteAllSleepModeData() async throws {}
    func saveContextEntry(_ entry: SleepContextEntry) async throws {}
    func fetchContextEntry(forSleepDateKey key: String) async throws -> SleepContextEntry? { nil }
    func fetchContextEntries(from startKey: String, to endKey: String) async throws -> [SleepContextEntry] { [] }
    func deleteContextEntry(id: UUID) async throws {}
    func deleteAllContextEntries() async throws {}
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
    func saveBaselineSnapshot(_ snapshot: StoredDashboardBaselineSnapshot) async throws {}
    func fetchBaselineSnapshot(asOfSleepDateKey: String, windowKind: String) async throws -> StoredDashboardBaselineSnapshot? { nil }
    func deleteBaselineSnapshots(containingSleepDateKey: String) async throws {}
    func deleteAllHealthData() async throws {}
    func migrateToEncryptedStorage() async throws {}
    func fetchDataInventory() async throws -> LocalDataInventory {
        LocalDataInventory(
            sleepSessionCount: 0, baselineCount: 0, alertCount: 0,
            protocolAdherenceCount: 0, activityLogCount: 0,
            manualBiologyEntryCount: 0, contextEntryCount: 0
        )
    }
}
