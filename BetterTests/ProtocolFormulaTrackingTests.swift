// ProtocolFormulaTrackingTests.swift
// Covers: SleepDateKey boundaries, baseline correctness, best-version gating,
// rollup exclusion of unknown/skipped, insights caveat, migration idempotency,
// and locale round-trip safety.
//
// Environment requirement: tests are pure in-memory (no SwiftData, no HK).
// Run via: xcodebuild -scheme Better test -only-testing:BetterTests/ProtocolFormulaTrackingTests

import XCTest
@testable import Better

// MARK: - In-memory repository for Protocol Formula tests

/// Fully self-contained in-memory actor implementing `LocalDataRepositoryProtocol`.
/// All non-formula methods are no-ops or return empty — only the Protocol Formula
/// and SleepSession paths have real storage (needed by the baseline/analysis services).
private actor ProtocolFormulaMemoryRepo: LocalDataRepositoryProtocol {
    enum TestError: Error {
        case forcedNightLogSaveFailure
    }

    // Session store (used by ProtocolBaselineService / ProtocolFormulaAnalysisService)
    private var sessionsByKey: [String: SleepSession]

    // Protocol formula store
    var formulaVersions: [UUID: ProtocolFormulaVersion] = [:]
    var nightLogs: [String: ProtocolNightLog] = [:]
    var logEdits: [String: [ProtocolLogEdit]] = [:]
    var baselines: [ProtocolBaselineSnapshot] = []
    var interventionWindows: [UUID: InterventionWindow] = [:]
    private var failingNightLogSaveCount: Int = 0

    // Legacy adherence (used by ProtocolAdherenceMigrationService.runIfNeeded)
    private var adherenceRows: [ProtocolAdherence] = []

    init(sessions: [SleepSession] = [], adherence: [ProtocolAdherence] = []) {
        self.sessionsByKey = Dictionary(sessions.map { ($0.sleepDateKey, $0) },
                                       uniquingKeysWith: { _, new in new })
        self.adherenceRows = adherence
    }

    // MARK: - Sessions
    func saveSessions(_ s: [SleepSession]) async throws {
        for session in s { sessionsByKey[session.sleepDateKey] = session }
    }
    func replaceSessions(_ s: [SleepSession], from: Date, to: Date) async throws {
        sessionsByKey = sessionsByKey.filter { $0.value.startDate < from || $0.value.endDate > to }
        try await saveSessions(s)
    }
    func fetchCachedSessions(from: Date, to: Date) async throws -> [SleepSession] {
        sessionsByKey.values.filter { $0.startDate >= from && $0.endDate <= to }
            .sorted { $0.startDate < $1.startDate }
    }
    func fetchSession(forSleepDateKey key: String) async throws -> SleepSession? { sessionsByKey[key] }
    func fetchSessions(beforeSleepDateKey key: String, limit: Int) async throws -> [SleepSession] {
        sessionsByKey.values.filter { $0.sleepDateKey < key }
            .sorted { $0.sleepDateKey > $1.sleepDateKey }
            .prefix(limit).map { $0 }
    }
    func fetchAvailableSleepDates(from startKey: String, to endKey: String) async throws -> [SleepDaySummary] { [] }
    func fetchLatestSession() async throws -> SleepSession? {
        sessionsByKey.values.max { $0.endDate < $1.endDate }
    }

    // MARK: - Protocol Formula
    func saveFormulaVersion(_ version: ProtocolFormulaVersion) async throws {
        if version.isActive {
            for key in formulaVersions.keys where formulaVersions[key]?.isActive == true && key != version.id {
                formulaVersions[key]?.isActive = false
            }
        }
        formulaVersions[version.id] = version
    }
    func fetchAllFormulaVersions() async throws -> [ProtocolFormulaVersion] {
        formulaVersions.values.sorted { $0.shippedOn < $1.shippedOn }
    }
    func fetchActiveFormulaVersion() async throws -> ProtocolFormulaVersion? {
        formulaVersions.values.first { $0.isActive }
    }
    func fetchFormulaVersion(id: UUID) async throws -> ProtocolFormulaVersion? { formulaVersions[id] }
    func archiveFormulaVersion(id: UUID) async throws {
        formulaVersions[id]?.archivedAt = Date()
        formulaVersions[id]?.isActive = false
    }
    func deleteFormulaVersion(id: UUID) async throws { formulaVersions[id] = nil }

    func failNextNightLogSave() {
        failingNightLogSaveCount += 1
    }

    func saveNightLog(_ log: ProtocolNightLog) async throws {
        if failingNightLogSaveCount > 0 {
            failingNightLogSaveCount -= 1
            throw TestError.forcedNightLogSaveFailure
        }
        nightLogs[log.sleepDateKey] = log
    }
    func fetchNightLog(forSleepDateKey key: String) async throws -> ProtocolNightLog? { nightLogs[key] }
    func fetchNightLogs(from startKey: String, to endKey: String) async throws -> [ProtocolNightLog] {
        nightLogs.values.filter { $0.sleepDateKey >= startKey && $0.sleepDateKey <= endKey }
            .sorted { $0.sleepDateKey < $1.sleepDateKey }
    }
    func deleteNightLog(forSleepDateKey key: String) async throws { nightLogs[key] = nil }
    func saveLogEdit(_ edit: ProtocolLogEdit) async throws {
        logEdits[edit.sleepDateKey, default: []].append(edit)
    }
    func fetchLogEdits(forSleepDateKey key: String) async throws -> [ProtocolLogEdit] { logEdits[key] ?? [] }

    func saveBaselineSnapshot(_ snapshot: ProtocolBaselineSnapshot) async throws {
        guard snapshot.validNightCount > 0 else { throw ProtocolFormulaRepositoryError.baselineSnapshotEmpty }
        // V3 upsert semantics: keyed by versionID (or the legacy nil slot)
        // AND by `id` (so legacy → versioned re-keys don't leave orphan rows).
        baselines.removeAll { $0.versionID == snapshot.versionID || $0.id == snapshot.id }
        baselines.append(snapshot)
    }
    func fetchBaselineSnapshot() async throws -> ProtocolBaselineSnapshot? {
        baselines.sorted { $0.frozenAt > $1.frozenAt }.first
    }
    func fetchBaselineSnapshot(versionID: UUID) async throws -> ProtocolBaselineSnapshot? {
        baselines.first { $0.versionID == versionID }
    }
    func fetchInterventionWindows() async throws -> [InterventionWindow] {
        interventionWindows.values.sorted { $0.startedAt < $1.startedAt }
    }
    func saveInterventionWindow(_ window: InterventionWindow) async throws {
        interventionWindows[window.id] = window
    }
    func deleteInterventionWindow(id: UUID) async throws {
        interventionWindows[id] = nil
    }

    // MARK: - Legacy adherence
    func saveAdherence(_ a: ProtocolAdherence) async throws { adherenceRows.append(a) }
    func fetchAdherence(from: Date, to: Date) async throws -> [ProtocolAdherence] {
        adherenceRows.filter { $0.takenAt ?? Date.distantPast >= from && $0.takenAt ?? Date.distantPast <= to }
    }

    // MARK: - Required stubs (not exercised by Protocol Formula tests)
    func saveBiometricSummary(_ s: NightlyBiometricSummary) async throws {}
    func saveDailyActivitySummary(_ s: DailyActivitySummary) async throws {}
    func fetchDailyActivitySummaries(from startKey: String, to endKey: String) async throws -> [DailyActivitySummary] { [] }
    func saveBaseline(_ b: SleepBaseline) async throws {}
    func fetchLatestBaseline(windowDays: Int) async throws -> SleepBaseline? { nil }
    func saveAlerts(_ alerts: [SleepAlert]) async throws {}
    func fetchAlerts(unreadOnly: Bool, fromSleepDateKey: String?, limit: Int?) async throws -> [SleepAlert] { [] }
    func markAlertRead(id: UUID) async throws {}
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
    func saveContextEntry(_ entry: SleepContextEntry) async throws {}
    func fetchContextEntry(forSleepDateKey key: String) async throws -> SleepContextEntry? { nil }
    func fetchContextEntries(from startKey: String, to endKey: String) async throws -> [SleepContextEntry] { [] }
    func deleteContextEntry(id: UUID) async throws {}
    func deleteAllContextEntries() async throws {}
    func deleteAllHealthData() async throws {}
    func migrateToEncryptedStorage() async throws {}
    func fetchDataInventory() async throws -> LocalDataInventory {
        LocalDataInventory(
            sleepSessionCount: sessionsByKey.count,
            baselineCount: baselines.count,
            alertCount: 0,
            protocolAdherenceCount: adherenceRows.count,
            activityLogCount: 0,
            manualBiologyEntryCount: 0,
            contextEntryCount: 0,
            protocolFormulaVersionCount: formulaVersions.count,
            protocolNightLogCount: nightLogs.count,
            protocolLogEditCount: logEdits.values.reduce(0) { $0 + $1.count },
            protocolBaselineSnapshotCount: baselines.count
        )
    }
}

// MARK: - Helpers

private func gregorian() -> Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
}

private func date(_ y: Int, _ m: Int, _ d: Int, hour: Int = 12, tz: TimeZone = .current) -> Date {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = tz
    return cal.date(from: DateComponents(year: y, month: m, day: d, hour: hour))!
}

/// Builds a SleepSession whose mutable stored properties match the requested metric values.
/// `restorativeSleepDuration` is computed as `deepDuration + remDuration` — so pass half
/// each into `deepSeconds`/`remSeconds` to get the desired restorative total.
private func makeSession(
    dateKey: String,
    quality: SleepDataQuality = .detailedStages,
    deepSeconds: Double = 2400,   // restorative = deep + rem; default → 4800 total
    remSeconds: Double = 2400,
    awakeSeconds: Double = 600,
    totalSleepSeconds: Double = 25200,
    latencySeconds: Double = 900,
    score: Double = 75.0
) -> SleepSession {
    // Parse YYYY-MM-DD → a fixed 23:00 start / 07:00 wake so the dateKey is correct.
    let parts = dateKey.split(separator: "-").compactMap { Int($0) }
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = .current
    let wake = cal.date(from: DateComponents(
        year: parts[0], month: parts[1], day: parts[2], hour: 7))!
    let start = wake.addingTimeInterval(-8 * 3600)

    return SleepSession(
        sleepDateKey: dateKey,
        startDate: start,
        endDate: wake,
        dataQuality: quality,
        totalInBedTime: totalSleepSeconds + awakeSeconds,
        totalSleepTime: totalSleepSeconds,
        awakeDuration: awakeSeconds,
        deepDuration: deepSeconds,
        remDuration: remSeconds,
        sleepLatency: latencySeconds,
        qualityScore: SleepQualityScore(
            overall: score, durationScore: 0.75, efficiencyScore: 0.88,
            remScore: 0.75, deepScore: 0.75, isPartial: false)
    )
}

private func makeVersion(id: UUID = UUID(), label: String, shippedOn: Date = Date(), active: Bool = false) -> ProtocolFormulaVersion {
    ProtocolFormulaVersion(
        id: id,
        displayLabel: label,
        ordinalLabel: label,
        formulaText: "Magnesium 400mg",
        shippedOn: shippedOn,
        isActive: active
    )
}

private func makeLog(dateKey: String, versionID: UUID, status: ProtocolFormulaNightStatus) -> ProtocolNightLog {
    ProtocolNightLog(
        sleepDateKey: dateKey,
        versionID: versionID,
        status: status,
        formulaSnapshotHash: ProtocolNightLog.importedPlaceholderHash
    )
}

private func makeBaseline(nights: Int = 14, isInsufficient: Bool = false) -> ProtocolBaselineSnapshot {
    ProtocolBaselineSnapshot(
        frozenAt: Date(),
        windowStart: Date(timeIntervalSinceNow: -90 * 86400),
        windowEnd: Date(timeIntervalSinceNow: -30 * 86400),
        validNightCount: nights,
        meanRestorativeMin: 80.0,
        stdRestorativeMin: 10.0,
        meanRestorativePctOfInBed: 62.0,
        stdRestorativePctOfInBed: 5.0,
        meanLongestRestorativeBlockMin: 60.0,
        stdLongestRestorativeBlockMin: 8.0,
        continuityCategoryDistribution: [.good: 0.7, .moderatelyFragmented: 0.3],
        isInsufficient: isInsufficient,
        meanDeepMin: 60.0, stdDeepMin: 8.0,
        meanRemMin: 60.0, stdRemMin: 8.0,
        meanAwakeMin: 10.0, stdAwakeMin: 3.0,
        meanTotalSleepMin: 420.0, stdTotalSleepMin: 30.0,
        meanLatencyMin: 15.0, stdLatencyMin: 5.0,
        meanSleepScore: 75.0, stdSleepScore: 5.0
    )
}

// MARK: - 1. SleepDateKey boundary tests

@MainActor
final class SleepDateKeyTests: XCTestCase {

    func testCalendarDateKeyIsGregorianUnderBuddhistLocale() {
        // Buddhist calendar year for 2026 would be 2569 if we used locale's preferred calendar.
        // We must always return the Gregorian key.
        var buddhistCal = Calendar(identifier: .buddhist)
        buddhistCal.locale = Locale(identifier: "th_TH")
        buddhistCal.timeZone = TimeZone(identifier: "Asia/Bangkok")!

        let d = date(2026, 5, 21, hour: 12, tz: TimeZone(identifier: "Asia/Bangkok")!)
        let key = SleepDateKey.calendarDateKey(for: d, calendar: buddhistCal)
        XCTAssertEqual(key, "2026-05-21", "Buddhist calendar locale must not affect date key year")
    }

    func testSleepDateKeySessionStartNoon_mapsToNextDay() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let noon = date(2026, 5, 21, hour: 12, tz: cal.timeZone)
        let key = SleepDateKey.sleepDateKey(forSessionStart: noon, calendar: cal)
        XCTAssertEqual(key, "2026-05-22", "Session starting at noon → next day's key")
    }

    func testSleepDateKeySessionStartEarlyMorning_mapsToSameDay() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let earlyMorning = date(2026, 5, 21, hour: 3, tz: cal.timeZone)
        let key = SleepDateKey.sleepDateKey(forSessionStart: earlyMorning, calendar: cal)
        XCTAssertEqual(key, "2026-05-21", "Session starting before noon → same day's key")
    }

    func testTonightKeyBefore4am_returnsToday() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let twoAM = date(2026, 5, 21, hour: 2, tz: cal.timeZone)
        let key = ProtocolFormulaHomeViewModel.tonightSleepDateKey(calendar: cal, now: twoAM)
        XCTAssertEqual(key, "2026-05-21", "Before 4am → tonight is today's key (night-in-progress)")
    }

    func testTonightKeyBetween4amAnd12pm_routesToTomorrow() {
        // Regression for B3: before this fix, 9am returned today's key,
        // overwriting last night's log when "Mark Tonight Taken" was tapped.
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        for hour in [4, 7, 9, 11] {
            let t = date(2026, 5, 21, hour: hour, tz: cal.timeZone)
            let key = ProtocolFormulaHomeViewModel.tonightSleepDateKey(calendar: cal, now: t)
            XCTAssertEqual(key, "2026-05-22",
                "At \(hour):00 'tonight' must route to tomorrow, not overwrite last night (hour=\(hour))")
        }
    }

    func testTonightKeyAfter12pm_returnsNextDay() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let eve = date(2026, 5, 21, hour: 21, tz: cal.timeZone)
        let key = ProtocolFormulaHomeViewModel.tonightSleepDateKey(calendar: cal, now: eve)
        XCTAssertEqual(key, "2026-05-22", "After 12pm → upcoming sleep night = tomorrow's key")
    }

    func testTonightKeyNoCollisionWithLastNightKey() {
        // The tonight key should never equal the most-recent historical session key
        // during the "morning overlap" window (4–12h).
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        // Simulate: last night's session has sleepDateKey = "2026-05-21"
        let lastNightKey = "2026-05-21"
        let nineAM = date(2026, 5, 21, hour: 9, tz: cal.timeZone)
        let tonightKey = ProtocolFormulaHomeViewModel.tonightSleepDateKey(calendar: cal, now: nineAM)
        XCTAssertNotEqual(tonightKey, lastNightKey, "Tonight key must not collide with last night at 9am")
    }

    func testDateKeyRoundTrip() {
        let d = date(2026, 12, 31, hour: 12, tz: TimeZone(identifier: "UTC")!)
        let key = SleepDateKey.calendarDateKey(for: d)
        let reconstructed = SleepDateKey.date(from: key)
        XCTAssertNotNil(reconstructed)
        // Reconstructed date should represent the same calendar day (y/m/d)
        let cal = Calendar(identifier: .gregorian)
        XCTAssertEqual(cal.component(.year, from: reconstructed!), 2026)
        XCTAssertEqual(cal.component(.month, from: reconstructed!), 12)
        XCTAssertEqual(cal.component(.day, from: reconstructed!), 31)
    }
}

// MARK: - 1b. ProtocolFormulaHomeViewModel tonight save-state tests

@MainActor
final class ProtocolFormulaHomeViewModelTests: XCTestCase {

    private func makeHomeViewModel(
        repo: ProtocolFormulaMemoryRepo,
        now: Date,
        calendar: Calendar,
        userDefaults: UserDefaults
    ) -> ProtocolFormulaHomeViewModel {
        ProtocolFormulaHomeViewModel(
            localRepository: repo,
            userDefaults: userDefaults,
            calendar: calendar,
            nowProvider: { now }
        )
    }

    private func makeIsolatedDefaults(name: String = UUID().uuidString) -> UserDefaults {
        let defaults = UserDefaults(suiteName: "ProtocolFormulaHomeViewModelTests.\(name)")!
        defaults.removePersistentDomain(forName: "ProtocolFormulaHomeViewModelTests.\(name)")
        return defaults
    }

    func testRefreshDerivesTonightSavedStatusFromPersistedLog() async throws {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let now = date(2026, 5, 21, hour: 21, tz: cal.timeZone)
        let version = makeVersion(label: "V1", shippedOn: date(2026, 5, 1, tz: cal.timeZone), active: true)
        let tonightKey = ProtocolFormulaHomeViewModel.tonightSleepDateKey(calendar: cal, now: now)
        let repo = ProtocolFormulaMemoryRepo()
        try await repo.saveFormulaVersion(version)
        try await repo.saveNightLog(makeLog(dateKey: tonightKey, versionID: version.id, status: .skipped))

        let viewModel = makeHomeViewModel(
            repo: repo,
            now: now,
            calendar: cal,
            userDefaults: makeIsolatedDefaults()
        )

        await viewModel.refresh()

        XCTAssertEqual(viewModel.tonightLogSaveState, .saved(status: .skipped))
        XCTAssertEqual(viewModel.selectedTonightVersionID, version.id)
    }

    func testRetryRepeatsFailedSkippedAction() async throws {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let now = date(2026, 5, 21, hour: 21, tz: cal.timeZone)
        let version = makeVersion(label: "V1", shippedOn: date(2026, 5, 1, tz: cal.timeZone), active: true)
        let tonightKey = ProtocolFormulaHomeViewModel.tonightSleepDateKey(calendar: cal, now: now)
        let repo = ProtocolFormulaMemoryRepo()
        try await repo.saveFormulaVersion(version)

        let viewModel = makeHomeViewModel(
            repo: repo,
            now: now,
            calendar: cal,
            userDefaults: makeIsolatedDefaults()
        )
        await viewModel.refresh()

        await repo.failNextNightLogSave()
        await viewModel.markTonightSkipped()

        XCTAssertEqual(viewModel.tonightLogSaveState, .error(retryStatus: .skipped))
        let missingLog = try await repo.fetchNightLog(forSleepDateKey: tonightKey)
        XCTAssertNil(missingLog)

        await viewModel.retryTonightLogSave()

        let saved = try await repo.fetchNightLog(forSleepDateKey: tonightKey)
        XCTAssertEqual(saved?.status, .skipped)
        XCTAssertEqual(viewModel.tonightLogSaveState, .saved(status: .skipped))
    }

    func testMarkTakenShowsSavedStateAndPersistsTonightLog() async throws {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let now = date(2026, 5, 21, hour: 21, tz: cal.timeZone)
        let version = makeVersion(label: "V1", shippedOn: date(2026, 5, 1, tz: cal.timeZone), active: true)
        let tonightKey = ProtocolFormulaHomeViewModel.tonightSleepDateKey(calendar: cal, now: now)
        let repo = ProtocolFormulaMemoryRepo()
        try await repo.saveFormulaVersion(version)

        let viewModel = makeHomeViewModel(
            repo: repo,
            now: now,
            calendar: cal,
            userDefaults: makeIsolatedDefaults()
        )
        await viewModel.refresh()

        await viewModel.markTonightTaken()

        let saved = try await repo.fetchNightLog(forSleepDateKey: tonightKey)
        XCTAssertEqual(saved?.status, .taken)
        XCTAssertEqual(saved?.takenAt, now)
        XCTAssertEqual(viewModel.tonightLogSaveState, .saved(status: .taken))
    }
}

// MARK: - 2. ProtocolBaselineService tests

final class ProtocolBaselineServiceTests: XCTestCase {

    func testFreezeBaseline_sufficiencyThreshold() async throws {
        // < 14 qualifying nights → no persisted Protocol baseline.
        let sessions = (0..<5).map { i -> SleepSession in
            makeSession(dateKey: "2026-0\(3)-\(String(format: "%02d", i + 1))")
        }
        let repo = ProtocolFormulaMemoryRepo(sessions: sessions)
        let svc = ProtocolBaselineService(repository: repo, calendar: gregorian())
        let snap = try await svc.freezeBaseline(beforeSleepDateKey: "2026-04-01")
        let readiness = try await svc.readiness(beforeSleepDateKey: "2026-04-01")
        XCTAssertNil(snap)
        XCTAssertEqual(readiness?.validNightCount, 5)
        XCTAssertEqual(readiness?.requiredNightCount, 14)
        XCTAssertEqual(readiness?.totalCachedNightCount, 5)
    }

    func testFreezeBaseline_sufficientData() async throws {
        let sessions = (1...14).map { i -> SleepSession in
            makeSession(dateKey: "2026-03-\(String(format: "%02d", i))")
        }
        let repo = ProtocolFormulaMemoryRepo(sessions: sessions)
        let svc = ProtocolBaselineService(repository: repo, calendar: gregorian())
        let snap = try await svc.freezeBaseline(beforeSleepDateKey: "2026-04-01")
        XCTAssertNotNil(snap)
        XCTAssertFalse(snap!.isInsufficient, "14 nights meets Protocol baseline threshold")
        XCTAssertEqual(snap!.validNightCount, 14)
    }

    func testFreezeBaseline_excludesSessionsOnOrAfterCutoff() async throws {
        // Sessions on 2026-04-01 and later must NOT contribute to the baseline
        let beforeCutoff = (1...14).map { i -> SleepSession in
            makeSession(dateKey: "2026-03-\(String(format: "%02d", i))")
        }
        let onCutoff = [makeSession(dateKey: "2026-04-01")]
        let repo = ProtocolFormulaMemoryRepo(sessions: beforeCutoff + onCutoff)
        let svc = ProtocolBaselineService(repository: repo, calendar: gregorian())
        let snap = try await svc.freezeBaseline(beforeSleepDateKey: "2026-04-01")
        XCTAssertEqual(snap?.validNightCount, 14, "Cutoff day itself must be excluded from baseline")
    }

    func testFreezeBaseline_zeroQualifyingNights_returnsNil() async throws {
        let noDataSessions = (1...5).map { i -> SleepSession in
            makeSession(dateKey: "2026-03-\(String(format: "%02d", i))", quality: .noData)
        }
        let repo = ProtocolFormulaMemoryRepo(sessions: noDataSessions)
        let svc = ProtocolBaselineService(repository: repo, calendar: gregorian())
        let snap = try await svc.freezeBaseline(beforeSleepDateKey: "2026-04-01")
        XCTAssertNil(snap, "No qualifying nights → nil baseline (not a crash)")
    }

    func testFreezeBaseline_idempotent_doesNotOverwriteExisting() async throws {
        let sessions = (1...14).map { makeSession(dateKey: "2026-03-\(String(format: "%02d", $0))") }
        let repo = ProtocolFormulaMemoryRepo(sessions: sessions)
        let svc = ProtocolBaselineService(repository: repo, calendar: gregorian())

        let first = try await svc.freezeBaseline(beforeSleepDateKey: "2026-04-01")
        let firstID = first?.id

        // Add more sessions — should NOT affect the already-frozen baseline
        let more = (11...15).map { makeSession(dateKey: "2026-03-\(String(format: "%02d", $0))") }
        try await repo.saveSessions(more)
        let second = try await svc.freezeBaseline(beforeSleepDateKey: "2026-04-01")

        XCTAssertEqual(firstID, second?.id, "Second freeze call must return the existing snapshot (idempotent)")
    }

    func testAugmentBaselineWithExtendedMetrics_preservesExistingBaselineFields() async throws {
        let sessions = [
            makeSession(
                dateKey: "2026-03-01",
                deepSeconds: 60 * 60,
                remSeconds: 30 * 60,
                awakeSeconds: 10 * 60,
                totalSleepSeconds: 400 * 60,
                latencySeconds: 15 * 60,
                score: 70
            ),
            makeSession(
                dateKey: "2026-03-02",
                deepSeconds: 90 * 60,
                remSeconds: 60 * 60,
                awakeSeconds: 20 * 60,
                totalSleepSeconds: 440 * 60,
                latencySeconds: 25 * 60,
                score: 80
            )
        ]
        let repo = ProtocolFormulaMemoryRepo(sessions: sessions)
        let oldBaseline = ProtocolBaselineSnapshot(
            frozenAt: date(2026, 4, 1, tz: TimeZone(identifier: "UTC")!),
            windowStart: date(2026, 1, 1, tz: TimeZone(identifier: "UTC")!),
            windowEnd: date(2026, 4, 1, tz: TimeZone(identifier: "UTC")!),
            validNightCount: 2,
            meanRestorativeMin: 123.0,
            stdRestorativeMin: 11.0,
            meanRestorativePctOfInBed: 44.0,
            stdRestorativePctOfInBed: 3.0,
            meanLongestRestorativeBlockMin: 55.0,
            stdLongestRestorativeBlockMin: 4.0,
            continuityCategoryDistribution: [.good: 1.0],
            isInsufficient: true
        )
        try await repo.saveBaselineSnapshot(oldBaseline)
        let svc = ProtocolBaselineService(repository: repo, calendar: gregorian())

        let didAugment = try await svc.augmentBaselineWithExtendedMetricsIfNeeded()
        let augmented = try await repo.fetchBaselineSnapshot()

        XCTAssertTrue(didAugment)
        XCTAssertEqual(augmented?.meanRestorativeMin, 123.0)
        XCTAssertEqual(augmented?.stdRestorativeMin, 11.0)
        XCTAssertEqual(augmented?.meanRestorativePctOfInBed, 44.0)
        XCTAssertEqual(augmented?.meanLongestRestorativeBlockMin, 55.0)
        XCTAssertEqual(augmented?.meanDeepMin ?? 0, 75.0, accuracy: 0.001)
        XCTAssertEqual(augmented?.stdDeepMin ?? 0, 21.213, accuracy: 0.001)
        XCTAssertEqual(augmented?.meanRemMin ?? 0, 45.0, accuracy: 0.001)
        XCTAssertEqual(augmented?.meanAwakeMin ?? 0, 15.0, accuracy: 0.001)
        XCTAssertEqual(augmented?.meanTotalSleepMin ?? 0, 420.0, accuracy: 0.001)
        XCTAssertEqual(augmented?.meanLatencyMin ?? 0, 20.0, accuracy: 0.001)
        XCTAssertEqual(augmented?.meanSleepScore ?? 0, 75.0, accuracy: 0.001)
    }

    func testFreezeBaseline_force_recomputesSnapshot() async throws {
        let sessions = (1...14).map { makeSession(dateKey: "2026-03-\(String(format: "%02d", $0))") }
        let repo = ProtocolFormulaMemoryRepo(sessions: sessions)
        let svc = ProtocolBaselineService(repository: repo, calendar: gregorian())
        let first = try await svc.freezeBaseline(beforeSleepDateKey: "2026-04-01")
        let second = try await svc.freezeBaseline(beforeSleepDateKey: "2026-04-01", force: true)
        XCTAssertNotEqual(first?.id, second?.id, "force=true must produce a new snapshot with a new ID")
    }

    func testReadiness_countsCachedAndQualifyingNightsInNinetyDayWindow() async throws {
        let qualifying = (1...6).map { makeSession(dateKey: "2026-03-\(String(format: "%02d", $0))") }
        let excluded = (7...10).map {
            makeSession(dateKey: "2026-03-\(String(format: "%02d", $0))", quality: .noData)
        }
        let repo = ProtocolFormulaMemoryRepo(sessions: qualifying + excluded)
        let svc = ProtocolBaselineService(repository: repo, calendar: gregorian())

        let readiness = try await svc.readiness(beforeSleepDateKey: "2026-04-01")

        XCTAssertEqual(readiness?.validNightCount, 6)
        XCTAssertEqual(readiness?.qualifyingNightCount, 6)
        XCTAssertEqual(readiness?.totalCachedNightCount, 10)
        XCTAssertEqual(readiness?.excludedNightCount, 4)
        XCTAssertFalse(readiness?.isReady ?? true)
    }

    func testStdDev_singleValue_returnsNil() {
        XCTAssertNil(ProtocolBaselineService.standardDeviation([42.0]), "Std dev undefined for n=1 → nil")
    }

    func testMean_empty_returnsNil() {
        XCTAssertNil(ProtocolBaselineService.mean([]), "Mean of empty array → nil")
    }
}

// MARK: - 3. ProtocolFormulaAnalysisService rollup tests

final class ProtocolFormulaAnalysisRollupTests: XCTestCase {

    func testRollup_excludesSkippedAndUnknownNights() async throws {
        let vID = UUID()
        // restorative = deep + rem; 4800 → 2400/2400, 3600 → 1800/1800, 6000 → 3000/3000
        let sessions = [
            makeSession(dateKey: "2026-05-01", deepSeconds: 2400, remSeconds: 2400),
            makeSession(dateKey: "2026-05-02", deepSeconds: 1800, remSeconds: 1800),
            makeSession(dateKey: "2026-05-03", deepSeconds: 3000, remSeconds: 3000),
        ]
        let logs = [
            makeLog(dateKey: "2026-05-01", versionID: vID, status: .taken),
            makeLog(dateKey: "2026-05-02", versionID: vID, status: .skipped),  // must be excluded
            // 2026-05-03 has no log → .unknown → must be excluded
        ]
        let repo = ProtocolFormulaMemoryRepo(sessions: sessions)
        for log in logs { try await repo.saveNightLog(log) }
        let svc = ProtocolFormulaAnalysisService(repository: repo)
        let rollups = try await svc.allRollups()
        let rollup = rollups.first { $0.versionID == vID }
        XCTAssertNotNil(rollup)
        XCTAssertEqual(rollup!.nightCount, 1, "Only the .taken night contributes to rollup")
        // May-01: deep=2400s + rem=2400s = 4800s restorative → 80 min
        XCTAssertEqual(rollup!.meanRestorativeMin ?? 0, 80.0, accuracy: 0.01)
    }

    func testRollup_awakeHigherMeansBetter_lowerIsBetter() {
        // Regression guard: ProtocolFormulaMetric.awake.betterIsLower == true
        XCTAssertTrue(ProtocolFormulaMetric.awake.betterIsLower)
        XCTAssertTrue(ProtocolFormulaMetric.latency.betterIsLower)
        XCTAssertEqual(ProtocolFormulaMetric.restorativePct.deltaUnit, "pp")
        // All others should be higher-is-better
        let higherBetter: [ProtocolFormulaMetric] = [.restorativeMin, .restorativePct, .longestBlock, .deep, .rem, .duration, .score]
        for m in higherBetter {
            XCTAssertFalse(m.betterIsLower, "\(m) should be higher-is-better")
        }
    }

    func testRollup_noStagesQuality_suppressesStageMetrics() async throws {
        let vID = UUID()
        let sessions = [makeSession(dateKey: "2026-05-01", quality: .unspecifiedSleepOnly)]
        let logs = [makeLog(dateKey: "2026-05-01", versionID: vID, status: .taken)]
        let repo = ProtocolFormulaMemoryRepo(sessions: sessions)
        for log in logs { try await repo.saveNightLog(log) }
        let svc = ProtocolFormulaAnalysisService(repository: repo)
        let snapshot = ProtocolFormulaAnalysisService.snapshot(for: sessions[0], log: logs[0])
        XCTAssertNil(snapshot.restorativeSleepMinutes, "noStages quality → restorativeMin suppressed")
        XCTAssertNil(snapshot.deepMinutes, "noStages quality → deepMin suppressed")
        // Total sleep is still available for noStages
        XCTAssertNotNil(snapshot.totalSleepMinutes, "noStages → total sleep still available")
    }

    func testRollup_multipleVersions_separatedCorrectly() async throws {
        let v1 = UUID(); let v2 = UUID()
        // 3600 → 1800/1800, 7200 → 3600/3600
        let sessions = [
            makeSession(dateKey: "2026-05-01", deepSeconds: 1800, remSeconds: 1800),
            makeSession(dateKey: "2026-05-02", deepSeconds: 3600, remSeconds: 3600),
        ]
        let repo = ProtocolFormulaMemoryRepo(sessions: sessions)
        try await repo.saveNightLog(makeLog(dateKey: "2026-05-01", versionID: v1, status: .taken))
        try await repo.saveNightLog(makeLog(dateKey: "2026-05-02", versionID: v2, status: .taken))
        let svc = ProtocolFormulaAnalysisService(repository: repo)
        let rollups = try await svc.allRollups()
        let r1 = rollups.first { $0.versionID == v1 }!
        let r2 = rollups.first { $0.versionID == v2 }!
        // May-01: 1800+1800=3600s → 60 min; May-02: 3600+3600=7200s → 120 min
        XCTAssertEqual(r1.meanRestorativeMin ?? 0, 60.0, accuracy: 0.01)
        XCTAssertEqual(r2.meanRestorativeMin ?? 0, 120.0, accuracy: 0.01)
    }
}

// MARK: - 4. ProtocolTimelineViewModel tests

@MainActor
final class ProtocolTimelineViewModelTests: XCTestCase {

    func testTimelineBuildsCardsFromLogsBeforeSessionsMatch() async throws {
        let spec = ProtocolFormulaCatalog.specs[0]
        let version = makeVersion(
            id: spec.id,
            label: spec.label,
            shippedOn: SleepDateKey.date(from: "2026-05-18")!,
            active: true
        )
        let repo = ProtocolFormulaMemoryRepo()
        try await repo.saveFormulaVersion(version)
        try await repo.saveNightLog(makeLog(dateKey: "2026-05-18", versionID: version.id, status: .taken))
        try await repo.saveNightLog(makeLog(dateKey: "2026-05-19", versionID: version.id, status: .skipped))

        let viewModel = ProtocolTimelineViewModel(repository: repo)
        await viewModel.reload()

        XCTAssertEqual(viewModel.totalNights, 2, "Timeline summary counts logged taken + skipped nights, not only measured sessions")
        XCTAssertEqual(viewModel.cards.count, 1, "A logged version should render even before sleep sessions match")
        let card = try XCTUnwrap(viewModel.cards.first)
        XCTAssertEqual(card.firstDateKey, "2026-05-18")
        XCTAssertEqual(card.lastDateKey, "2026-05-19")
        XCTAssertEqual(card.takenLogCount, 1)
        XCTAssertEqual(card.skippedLogCount, 1)
        XCTAssertNil(card.rollup, "No matching sleep sessions means no measured rollup attached yet")
        XCTAssertFalse(card.hasMeasuredSleepData)
    }

    func testTimelineAttachesRollupOnlyForTakenSessionsAndKeepsSkippedAsLogOnly() async throws {
        let spec = ProtocolFormulaCatalog.specs[1]
        let version = makeVersion(
            id: spec.id,
            label: spec.label,
            shippedOn: SleepDateKey.date(from: "2026-05-01")!,
            active: true
        )
        let sessions = [
            makeSession(dateKey: "2026-05-01", deepSeconds: 2400, remSeconds: 2400),
            makeSession(dateKey: "2026-05-02", deepSeconds: 3600, remSeconds: 3600)
        ]
        let repo = ProtocolFormulaMemoryRepo(sessions: sessions)
        try await repo.saveFormulaVersion(version)
        try await repo.saveBaselineSnapshot(makeBaseline())
        try await repo.saveNightLog(makeLog(dateKey: "2026-05-01", versionID: version.id, status: .taken))
        try await repo.saveNightLog(makeLog(dateKey: "2026-05-02", versionID: version.id, status: .skipped))

        let viewModel = ProtocolTimelineViewModel(repository: repo)
        await viewModel.reload()

        let card = try XCTUnwrap(viewModel.cards.first)
        XCTAssertEqual(card.loggedNightCount, 2, "Skipped logs stay visible in timeline log counts")
        XCTAssertEqual(card.rollup?.nightCount, 1, "Skipped sessions must not contribute to measured rollups")
        XCTAssertEqual(card.rollup?.meanRestorativeMin ?? 0, 80.0, accuracy: 0.01)
        XCTAssertEqual(card.restorativeDeltaMin ?? 0, 0.0, accuracy: 0.01)
        XCTAssertNotNil(viewModel.baseline)
        XCTAssertEqual(viewModel.baseline?.validNightCount, 14)
    }

    func testTimelineIgnoresUnknownRowsForCardsAndTotals() async throws {
        let spec = ProtocolFormulaCatalog.specs[2]
        let version = makeVersion(
            id: spec.id,
            label: spec.label,
            shippedOn: SleepDateKey.date(from: "2026-05-03")!,
            active: true
        )
        let repo = ProtocolFormulaMemoryRepo()
        try await repo.saveFormulaVersion(version)
        try await repo.saveNightLog(makeLog(dateKey: "2026-05-03", versionID: version.id, status: .unknown))

        let viewModel = ProtocolTimelineViewModel(repository: repo)
        await viewModel.reload()

        XCTAssertEqual(viewModel.totalNights, 0)
        XCTAssertTrue(viewModel.cards.isEmpty, "Unknown means no stored adherence state and should not create timeline cards")
    }
}

// MARK: - 4. ProtocolFormulaCatalogService.bestVersion tests

final class BestVersionTests: XCTestCase {

    func testBestVersion_insufficientBaseline_returnsNil() {
        let v = makeVersion(label: "V1")
        let rollup = ProtocolVersionRollup(
            versionID: v.id, nightCount: 10,
            meanRestorativeMin: 90, stdRestorativeMin: 5,
            meanRestorativePctOfInBed: 70, stdRestorativePctOfInBed: 3,
            meanLongestRestorativeBlockMin: 65, stdLongestRestorativeBlockMin: 6,
            continuityDistribution: [:],
            meanDeepMin: 70, stdDeepMin: 5,
            meanRemMin: 70, stdRemMin: 5,
            meanAwakeMin: 8, stdAwakeMin: 2,
            meanTotalSleepMin: 430, stdTotalSleepMin: 20,
            meanLatencyMin: 12, stdLatencyMin: 4,
            meanSleepScore: 80, stdSleepScore: 4
        )
        let baseline = makeBaseline(nights: 4, isInsufficient: true)
        let result = ProtocolFormulaCatalogService.bestVersion(
            versions: [v], rollups: [rollup], baseline: baseline
        )
        XCTAssertNil(result, "Insufficient baseline → bestVersion must return nil")
    }

    func testBestVersion_fewerThanMinimumNights_excluded() {
        let v = makeVersion(label: "V1")
        // minimumRankedNights = 5; give it only 4
        let rollup = ProtocolVersionRollup(
            versionID: v.id, nightCount: 4,
            meanRestorativeMin: 90, stdRestorativeMin: 5,
            meanRestorativePctOfInBed: 80, stdRestorativePctOfInBed: 3,
            meanLongestRestorativeBlockMin: 65, stdLongestRestorativeBlockMin: 6,
            continuityDistribution: [:],
            meanDeepMin: nil, stdDeepMin: nil,
            meanRemMin: nil, stdRemMin: nil,
            meanAwakeMin: nil, stdAwakeMin: nil,
            meanTotalSleepMin: nil, stdTotalSleepMin: nil,
            meanLatencyMin: nil, stdLatencyMin: nil,
            meanSleepScore: nil, stdSleepScore: nil
        )
        let baseline = makeBaseline(nights: 14, isInsufficient: false)
        let result = ProtocolFormulaCatalogService.bestVersion(
            versions: [v], rollups: [rollup], baseline: baseline
        )
        XCTAssertNil(result, "< \(ProtocolFormulaCatalog.minimumRankedNights) nights → excluded from ranking")
    }

    func testBestVersion_minimumRankedNightsIs5() {
        XCTAssertEqual(ProtocolFormulaCatalog.minimumRankedNights, 5,
                       "minimumRankedNights was raised to 5 to reduce misleading 'best' labels on thin data")
    }

    func testBestVersion_deterministic_tiebreakByNightCount() {
        // Two versions with identical restorativePctDelta → higher nightCount wins
        let v1 = makeVersion(label: "V1"); let v2 = makeVersion(label: "V2")
        let baseline = makeBaseline(nights: 14)

        func rollup(_ vID: UUID, nights: Int) -> ProtocolVersionRollup {
            ProtocolVersionRollup(
                versionID: vID, nightCount: nights,
                meanRestorativeMin: 90, stdRestorativeMin: nil,
                meanRestorativePctOfInBed: 72, stdRestorativePctOfInBed: nil,  // baseline is 62 → delta = +10 for both
                meanLongestRestorativeBlockMin: nil, stdLongestRestorativeBlockMin: nil,
                continuityDistribution: [:],
                meanDeepMin: nil, stdDeepMin: nil,
                meanRemMin: nil, stdRemMin: nil,
                meanAwakeMin: nil, stdAwakeMin: nil,
                meanTotalSleepMin: nil, stdTotalSleepMin: nil,
                meanLatencyMin: nil, stdLatencyMin: nil,
                meanSleepScore: nil, stdSleepScore: nil
            )
        }

        let r1 = rollup(v1.id, nights: 5)
        let r2 = rollup(v2.id, nights: 12)

        let result = ProtocolFormulaCatalogService.bestVersion(
            versions: [v1, v2], rollups: [r1, r2], baseline: baseline
        )
        XCTAssertEqual(result?.version.id, v2.id, "Tie on delta → more nights wins")
    }

    func testBestVersion_picksHighestRestorativeDelta() {
        let v1 = makeVersion(label: "V1"); let v2 = makeVersion(label: "V2")
        let baseline = makeBaseline(nights: 14)   // meanRestorativePctOfInBed = 62

        let r1 = ProtocolVersionRollup(
            versionID: v1.id, nightCount: 7,
            meanRestorativeMin: nil, stdRestorativeMin: nil,
            meanRestorativePctOfInBed: 68, stdRestorativePctOfInBed: nil,   // delta = +6
            meanLongestRestorativeBlockMin: nil, stdLongestRestorativeBlockMin: nil,
            continuityDistribution: [:],
            meanDeepMin: nil, stdDeepMin: nil,
            meanRemMin: nil, stdRemMin: nil,
            meanAwakeMin: nil, stdAwakeMin: nil,
            meanTotalSleepMin: nil, stdTotalSleepMin: nil,
            meanLatencyMin: nil, stdLatencyMin: nil,
            meanSleepScore: nil, stdSleepScore: nil
        )
        let r2 = ProtocolVersionRollup(
            versionID: v2.id, nightCount: 7,
            meanRestorativeMin: nil, stdRestorativeMin: nil,
            meanRestorativePctOfInBed: 75, stdRestorativePctOfInBed: nil,   // delta = +13
            meanLongestRestorativeBlockMin: nil, stdLongestRestorativeBlockMin: nil,
            continuityDistribution: [:],
            meanDeepMin: nil, stdDeepMin: nil,
            meanRemMin: nil, stdRemMin: nil,
            meanAwakeMin: nil, stdAwakeMin: nil,
            meanTotalSleepMin: nil, stdTotalSleepMin: nil,
            meanLatencyMin: nil, stdLatencyMin: nil,
            meanSleepScore: nil, stdSleepScore: nil
        )

        let result = ProtocolFormulaCatalogService.bestVersion(
            versions: [v1, v2], rollups: [r1, r2], baseline: baseline
        )
        XCTAssertEqual(result?.version.id, v2.id, "V2 has higher delta → wins")
        XCTAssertEqual(result?.restorativePctDelta ?? 0, 13.0, accuracy: 0.01)
    }

    func testBestVersion_noBaseline_returnsNil() {
        let v = makeVersion(label: "V1")
        let result = ProtocolFormulaCatalogService.bestVersion(versions: [v], rollups: [], baseline: nil)
        XCTAssertNil(result, "No baseline → bestVersion must return nil")
    }
}

// MARK: - 5. ProtocolAdherenceMigrationService idempotency

@MainActor
final class ProtocolAdherenceMigrationTests: XCTestCase {

    func testRunIfNeeded_idempotencyFlag_preventsSecondRun() async throws {
        let suiteName = "test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let repo = ProtocolFormulaMemoryRepo()
        let svc = ProtocolAdherenceMigrationService(repository: repo, userDefaults: defaults)
        defaults.set(true, forKey: ProtocolAdherenceMigrationService.idempotencyKey)
        let ran = try await svc.runIfNeeded()
        XCTAssertFalse(ran, "Idempotency flag set → migration must not run")
        defaults.removeSuite(named: suiteName)
    }

    func testRunIfNeeded_noLegacyRows_setsFlag() async throws {
        let suiteName = "test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let repo = ProtocolFormulaMemoryRepo()
        let svc = ProtocolAdherenceMigrationService(repository: repo, userDefaults: defaults)
        let ran = try await svc.runIfNeeded()
        XCTAssertFalse(ran, "No legacy data → migration skips but sets idempotency flag")
        XCTAssertTrue(defaults.bool(forKey: ProtocolAdherenceMigrationService.idempotencyKey),
                      "Idempotency flag must be set even when nothing to migrate")
        defaults.removeSuite(named: suiteName)
    }
}

// MARK: - 6. ProtocolFormulaInsightsService tests

final class ProtocolFormulaInsightsTests: XCTestCase {

    func testInsights_noBaseline_returnsBaselineUnavailable() async throws {
        let repo = ProtocolFormulaMemoryRepo()
        let svc = ProtocolFormulaInsightsService(repository: repo)
        let v = makeVersion(label: "V1")
        let insights = try await svc.insights(for: [v])
        XCTAssertEqual(insights.count, 1)
        XCTAssertEqual(insights[0].kind, .baselineUnavailable)
        XCTAssertFalse(insights[0].isPositive)
    }

    func testInsights_lowData_returnsLowDataKind() async throws {
        let v = makeVersion(label: "V1")
        let sessions = (1...2).map { makeSession(dateKey: "2026-05-0\($0)") }
        let repo = ProtocolFormulaMemoryRepo(sessions: sessions)
        for s in sessions {
            try await repo.saveNightLog(makeLog(dateKey: s.sleepDateKey, versionID: v.id, status: .taken))
        }
        try await repo.saveBaselineSnapshot(makeBaseline(nights: 14))
        let svc = ProtocolFormulaInsightsService(repository: repo)
        let insights = try await svc.insights(for: [v])
        XCTAssertTrue(insights.contains { $0.kind == .lowData },
                      "2 nights < 3 minimum → lowData insight")
    }

    func testInsights_causalityCaveat_presentInBody() async throws {
        // Every non-lowData insight body must include the causality caveat.
        let v = makeVersion(label: "V1")
        // Give it 5 nights with +20min restorative over baseline (baseline = 80min mean)
        let sessions = (1...5).map { makeSession(dateKey: "2026-05-0\($0)", deepSeconds: 3000, remSeconds: 3000) }
        let repo = ProtocolFormulaMemoryRepo(sessions: sessions)
        for s in sessions {
            try await repo.saveNightLog(makeLog(dateKey: s.sleepDateKey, versionID: v.id, status: .taken))
        }
        try await repo.saveBaselineSnapshot(makeBaseline(nights: 14))
        let svc = ProtocolFormulaInsightsService(repository: repo)
        let insights = try await svc.insights(for: [v])
        let dataInsights = insights.filter { $0.kind != .lowData && $0.kind != .baselineUnavailable }
        for insight in dataInsights {
            XCTAssertTrue(insight.body.contains(ProtocolImpactSummary.causalityCaveat),
                          "Insight '\(insight.headline)' body must contain the causality caveat")
        }
    }

    func testInsights_noMedicalLanguage() async throws {
        // Guard against causal / medical language creeping into insight text.
        let v = makeVersion(label: "V1")
        let sessions = (1...5).map { makeSession(dateKey: "2026-05-0\($0)", deepSeconds: 3600, remSeconds: 3600) }
        let repo = ProtocolFormulaMemoryRepo(sessions: sessions)
        for s in sessions {
            try await repo.saveNightLog(makeLog(dateKey: s.sleepDateKey, versionID: v.id, status: .taken))
        }
        try await repo.saveBaselineSnapshot(makeBaseline(nights: 14))
        let svc = ProtocolFormulaInsightsService(repository: repo)
        let insights = try await svc.insights(for: [v])
        let forbidden = ["causes", "cures", "treats", "diagnoses", "improves your sleep",
                         "clinically proven", "guaranteed", "scientifically"]
        for insight in insights {
            for word in forbidden {
                let combined = "\(insight.headline) \(insight.body)".lowercased()
                XCTAssertFalse(combined.contains(word),
                               "Insight must not use medical claim language '\(word)'")
            }
        }
    }
}

// MARK: - 7. ProtocolNightLog one-per-date invariant

final class NightLogInvariantTests: XCTestCase {

    func testSaveNightLog_overwritesSameDateKey() async throws {
        let repo = ProtocolFormulaMemoryRepo()
        let vID = UUID()
        let log1 = makeLog(dateKey: "2026-05-01", versionID: vID, status: .taken)
        try await repo.saveNightLog(log1)

        let log2 = makeLog(dateKey: "2026-05-01", versionID: vID, status: .skipped)
        try await repo.saveNightLog(log2)

        let fetched = try await repo.fetchNightLog(forSleepDateKey: "2026-05-01")
        XCTAssertEqual(fetched?.status, .skipped, "Second save for same date key overwrites first")
    }

    func testDeleteNightLog_removesLogAndLeavesUnknown() async throws {
        let repo = ProtocolFormulaMemoryRepo()
        let vID = UUID()
        try await repo.saveNightLog(makeLog(dateKey: "2026-05-01", versionID: vID, status: .taken))
        try await repo.deleteNightLog(forSleepDateKey: "2026-05-01")
        let fetched = try await repo.fetchNightLog(forSleepDateKey: "2026-05-01")
        XCTAssertNil(fetched, "Deleted log → nil (= .unknown, matching invariant #2)")
    }
}

// MARK: - 8. ProtocolBaselineService stats helpers

final class BaselineStatHelperTests: XCTestCase {

    func testMean_correctValue() {
        let m = ProtocolBaselineService.mean([10, 20, 30])
        XCTAssertEqual(m ?? 0, 20.0, accuracy: 0.001)
    }

    func testStdDev_knownValues() {
        // [2, 4, 4, 4, 5, 5, 7, 9] → sample std ≈ 2.0
        let std = ProtocolBaselineService.standardDeviation([2, 4, 4, 4, 5, 5, 7, 9])
        XCTAssertEqual(std ?? 0, 2.0, accuracy: 0.001)
    }

    func testStdDev_twoIdentical_zero() {
        let std = ProtocolBaselineService.standardDeviation([5.0, 5.0])
        XCTAssertEqual(std ?? -1, 0.0, accuracy: 0.001)
    }

    func testContinuityDistribution_sumsToOne() {
        let sessions = (1...6).map { _ in makeSession(dateKey: "2026-01-01") }
        let dist = ProtocolBaselineService.continuityDistribution(for: sessions)
        let total = dist.values.reduce(0, +)
        XCTAssertEqual(total, 1.0, accuracy: 0.001, "Continuity distribution must sum to 1.0")
    }

    func testRestorativePct_rejectsImplausibleHundredPercent() {
        let impossible = makeSession(
            dateKey: "2026-01-02",
            deepSeconds: 30 * 60,
            remSeconds: 30 * 60,
            awakeSeconds: 0,
            totalSleepSeconds: 60 * 60
        )

        XCTAssertNil(
            ProtocolFormulaMetricMath.restorativePctOfInBed(for: impossible),
            "100% restorative sleep is treated as suspect source data, not a real protocol result"
        )
    }
}

// MARK: - V3: Versioned baseline + InterventionWindow

final class ProtocolFormulaSchemaV3Tests: XCTestCase {

    func testBaselineUpsertByVersionID_isolatesPerVersionRows() async throws {
        let repo = ProtocolFormulaMemoryRepo()
        let v1 = UUID(), v2 = UUID()

        var b1 = makeBaseline(nights: 10)
        b1.versionID = v1
        var b2 = makeBaseline(nights: 12)
        b2.versionID = v2

        try await repo.saveBaselineSnapshot(b1)
        try await repo.saveBaselineSnapshot(b2)

        let fetchedV1 = try await repo.fetchBaselineSnapshot(versionID: v1)
        let fetchedV2 = try await repo.fetchBaselineSnapshot(versionID: v2)
        XCTAssertEqual(fetchedV1?.validNightCount, 10)
        XCTAssertEqual(fetchedV2?.validNightCount, 12)

        // Re-saving for v1 should replace, not duplicate.
        var b1Updated = makeBaseline(nights: 14)
        b1Updated.versionID = v1
        try await repo.saveBaselineSnapshot(b1Updated)

        let all = await repo.baselines
        XCTAssertEqual(all.count, 2, "Upsert must replace by versionID, not append")
        let v1Refetched = try await repo.fetchBaselineSnapshot(versionID: v1)
        XCTAssertEqual(v1Refetched?.validNightCount, 14)
    }

    func testInterventionWindowUpsertAndDelete() async throws {
        let repo = ProtocolFormulaMemoryRepo()
        let id = UUID()
        let window = InterventionWindow(
            id: id,
            versionID: UUID(),
            startedAt: Date(timeIntervalSince1970: 1000),
            phase: .active
        )
        try await repo.saveInterventionWindow(window)
        let initial = try await repo.fetchInterventionWindows()
        XCTAssertEqual(initial.count, 1)

        var updated = window
        updated.endedAt = Date(timeIntervalSince1970: 2000)
        updated.phase = .superseded
        try await repo.saveInterventionWindow(updated)
        let fetched = try await repo.fetchInterventionWindows()
        XCTAssertEqual(fetched.count, 1, "Save by id must upsert, not append")
        XCTAssertEqual(fetched.first?.phase, .superseded)

        try await repo.deleteInterventionWindow(id: id)
        let afterDelete = try await repo.fetchInterventionWindows()
        XCTAssertEqual(afterDelete.count, 0)
    }

    func testCatalogUpsertVersionEmitsActiveWindowAndClosesPredecessor() async throws {
        let repo = ProtocolFormulaMemoryRepo()
        let service = ProtocolFormulaCatalogService(repository: repo)

        let spec1 = ProtocolFormulaCatalog.specs[0]
        let spec2 = ProtocolFormulaCatalog.specs[2] // V2
        let shipped1 = Date(timeIntervalSince1970: 10_000)
        let shipped2 = Date(timeIntervalSince1970: 20_000)

        _ = try await service.upsertVersion(for: spec1, shippedOn: shipped1, currentVersionID: spec1.id)
        let afterFirst = try await repo.fetchInterventionWindows()
        XCTAssertEqual(afterFirst.count, 1)
        XCTAssertEqual(afterFirst.first?.phase, .active)
        XCTAssertNil(afterFirst.first?.endedAt)
        XCTAssertEqual(afterFirst.first?.versionID, spec1.id)

        _ = try await service.upsertVersion(for: spec2, shippedOn: shipped2, currentVersionID: spec2.id)
        let afterSecond = try await repo.fetchInterventionWindows().sorted { $0.startedAt < $1.startedAt }
        XCTAssertEqual(afterSecond.count, 2)
        XCTAssertEqual(afterSecond[0].phase, .superseded)
        XCTAssertEqual(afterSecond[0].endedAt, shipped2)
        XCTAssertEqual(afterSecond[1].phase, .active)
        XCTAssertNil(afterSecond[1].endedAt)
    }

    func testCatalogArchiveVersionClosesWindowAsArchived() async throws {
        let repo = ProtocolFormulaMemoryRepo()
        let service = ProtocolFormulaCatalogService(repository: repo)
        let spec = ProtocolFormulaCatalog.specs[0]
        let shipped = Date(timeIntervalSince1970: 10_000)
        let version = try await service.upsertVersion(for: spec, shippedOn: shipped, currentVersionID: spec.id)

        try await service.archiveVersion(id: version.id)

        let windows = try await repo.fetchInterventionWindows()
        XCTAssertEqual(windows.count, 1)
        XCTAssertEqual(windows.first?.phase, .archived)
        XCTAssertNotNil(windows.first?.endedAt)
        if let ended = windows.first?.endedAt {
            XCTAssertGreaterThanOrEqual(ended, shipped, "endedAt must be clamped to >= startedAt")
        }
    }

    func testV3BackfillIsIdempotentAndAssignsVersionIDToLegacyBaseline() async throws {
        let repo = ProtocolFormulaMemoryRepo()
        let suiteName = "BackfillCoordinatorTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let v1 = makeVersion(label: "V1", shippedOn: Date(timeIntervalSince1970: 10_000), active: false)
        let v2 = makeVersion(label: "V2", shippedOn: Date(timeIntervalSince1970: 20_000), active: true)
        try await repo.saveFormulaVersion(v1)
        try await repo.saveFormulaVersion(v2)

        // Legacy singleton baseline (no versionID).
        let legacy = makeBaseline(nights: 14)
        try await repo.saveBaselineSnapshot(legacy)

        await BackfillCoordinator.runV3Backfill(repository: repo, userDefaults: defaults)

        let windows = try await repo.fetchInterventionWindows().sorted { $0.startedAt < $1.startedAt }
        XCTAssertEqual(windows.count, 2)
        XCTAssertEqual(windows[0].versionID, v1.id)
        XCTAssertEqual(windows[0].phase, .superseded)
        XCTAssertEqual(windows[0].endedAt, v2.shippedOn)
        XCTAssertEqual(windows[1].versionID, v2.id)
        XCTAssertEqual(windows[1].phase, .active)
        XCTAssertNil(windows[1].endedAt)

        // Legacy baseline got versionID = active version id.
        let migrated = try await repo.fetchBaselineSnapshot()
        XCTAssertEqual(migrated?.versionID, v2.id)

        // Idempotency: a second run must be a no-op.
        let countBefore = try await repo.fetchInterventionWindows().count
        await BackfillCoordinator.runV3Backfill(repository: repo, userDefaults: defaults)
        let countAfter = try await repo.fetchInterventionWindows().count
        XCTAssertEqual(countAfter, countBefore)
    }

    func testV3BackfillArchivedVersionWithoutSuccessorBecomesArchivedPhase() async throws {
        let repo = ProtocolFormulaMemoryRepo()
        let suiteName = "BackfillCoordinatorTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        var v1 = makeVersion(label: "V1", shippedOn: Date(timeIntervalSince1970: 10_000), active: false)
        v1.archivedAt = Date(timeIntervalSince1970: 15_000)
        try await repo.saveFormulaVersion(v1)

        await BackfillCoordinator.runV3Backfill(repository: repo, userDefaults: defaults)

        let windows = try await repo.fetchInterventionWindows()
        XCTAssertEqual(windows.count, 1)
        XCTAssertEqual(windows.first?.phase, .archived)
        XCTAssertEqual(windows.first?.endedAt, v1.archivedAt)
    }
}
