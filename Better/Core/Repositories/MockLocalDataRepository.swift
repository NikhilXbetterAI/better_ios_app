import Foundation

actor MockLocalDataRepository: LocalDataRepositoryProtocol {
    private var sessionsBySleepDateKey: [String: SleepSession]
    private var summariesBySessionID: [UUID: NightlyBiometricSummary]
    private var baselines: [SleepBaseline]
    private var dailyActivitySummariesByDateKey: [String: DailyActivitySummary]
    private var alertsByID: [UUID: SleepAlert]
    private var adherenceByKey: [String: ProtocolAdherence]
    private var activityStatusLogsByDateKey: [String: ActivityStatusLog]
    private var profile: UserProfile?
    private var anchorsByTypeIdentifier: [String: Data?]
    private var manualBiologyEntriesByKind: [BiologyMetricKind: ManualBiologyEntry]
    private var contextEntriesByDateKey: [String: SleepContextEntry]

    init(
        sessions: [SleepSession] = [],
        summaries: [NightlyBiometricSummary] = [],
        dailyActivitySummaries: [DailyActivitySummary] = [],
        baselines: [SleepBaseline] = [],
        alerts: [SleepAlert] = [],
        adherence: [ProtocolAdherence] = [],
        activityStatusLogs: [ActivityStatusLog] = [],
        profile: UserProfile? = nil,
        anchors: [String: Data?] = [:],
        manualBiologyEntries: [ManualBiologyEntry] = [],
        contextEntries: [SleepContextEntry] = []
    ) {
        self.sessionsBySleepDateKey = Dictionary(sessions.map { ($0.sleepDateKey, $0) }, uniquingKeysWith: { _, new in new })
        self.summariesBySessionID = Dictionary(summaries.map { ($0.sleepSessionID, $0) }, uniquingKeysWith: { _, new in new })
        self.dailyActivitySummariesByDateKey = Dictionary(dailyActivitySummaries.map { ($0.dateKey, $0) }, uniquingKeysWith: { _, new in new })
        self.baselines = baselines
        self.alertsByID = Dictionary(uniqueKeysWithValues: alerts.map { ($0.id, $0) })
        self.adherenceByKey = Dictionary(uniqueKeysWithValues: adherence.map { (Self.adherenceKey($0), $0) })
        self.activityStatusLogsByDateKey = Dictionary(uniqueKeysWithValues: activityStatusLogs.map { ($0.dateKey, $0) })
        self.profile = profile
        self.anchorsByTypeIdentifier = anchors
        self.manualBiologyEntriesByKind = Dictionary(uniqueKeysWithValues: manualBiologyEntries.map { ($0.kind, $0) })
        self.contextEntriesByDateKey = Dictionary(uniqueKeysWithValues: contextEntries.map { ($0.sleepDateKey, $0) })
    }

    func saveSessions(_ sessions: [SleepSession]) async throws {
        for session in sessions {
            sessionsBySleepDateKey[session.sleepDateKey] = session
        }
    }

    func replaceSessions(_ sessions: [SleepSession], from: Date, to: Date) async throws {
        sessionsBySleepDateKey = sessionsBySleepDateKey.filter { _, session in
            !(session.endDate > from && session.startDate < to)
        }

        try await saveSessions(sessions)
    }

    func fetchCachedSessions(from: Date, to: Date) async throws -> [SleepSession] {
        sessionsBySleepDateKey.values
            .filter { $0.endDate > from && $0.startDate < to }
            .sorted { $0.startDate < $1.startDate }
    }

    func fetchSession(forSleepDateKey key: String) async throws -> SleepSession? {
        sessionsBySleepDateKey[key]
    }

    func fetchSessions(beforeSleepDateKey key: String, limit: Int) async throws -> [SleepSession] {
        Array(
            sessionsBySleepDateKey.values
                .filter { $0.sleepDateKey < key }
                .sorted { $0.sleepDateKey > $1.sleepDateKey }
                .prefix(max(0, limit))
        )
    }

    func fetchAvailableSleepDates(from startKey: String, to endKey: String) async throws -> [SleepDaySummary] {
        sessionsBySleepDateKey.values
            .filter { $0.sleepDateKey >= startKey && $0.sleepDateKey <= endKey }
            .sorted { $0.sleepDateKey < $1.sleepDateKey }
            .map {
                SleepDaySummary(
                    sleepDateKey: $0.sleepDateKey,
                    score: $0.qualityScore.overall,
                    totalSleepTime: $0.totalSleepTime,
                    dataQuality: $0.dataQuality,
                    hasSession: true
                )
            }
    }

    func fetchLatestSession() async throws -> SleepSession? {
        sessionsBySleepDateKey.values.max { $0.endDate < $1.endDate }
    }

    func saveBiometricSummary(_ summary: NightlyBiometricSummary) async throws {
        summariesBySessionID[summary.sleepSessionID] = summary
    }

    func saveDailyActivitySummary(_ summary: DailyActivitySummary) async throws {
        dailyActivitySummariesByDateKey[summary.dateKey] = summary
    }

    func fetchDailyActivitySummaries(from startKey: String, to endKey: String) async throws -> [DailyActivitySummary] {
        dailyActivitySummariesByDateKey.values
            .filter { $0.dateKey >= startKey && $0.dateKey <= endKey }
            .sorted { $0.dateKey < $1.dateKey }
    }

    func saveBaseline(_ baseline: SleepBaseline) async throws {
        baselines.removeAll { $0.id == baseline.id }
        baselines.append(baseline)
    }

    func fetchLatestBaseline(windowDays: Int) async throws -> SleepBaseline? {
        baselines
            .filter { $0.windowDays == windowDays }
            .max { $0.generatedAt < $1.generatedAt }
    }

    func saveAlerts(_ alerts: [SleepAlert]) async throws {
        for alert in alerts {
            alertsByID[alert.id] = alert
        }
    }

    func fetchAlerts(unreadOnly: Bool) async throws -> [SleepAlert] {
        try await fetchAlerts(unreadOnly: unreadOnly, fromSleepDateKey: nil, limit: nil)
    }

    func fetchAlerts(unreadOnly: Bool, fromSleepDateKey: String?, limit: Int?) async throws -> [SleepAlert] {
        let filtered = alertsByID.values
            .filter { unreadOnly ? !$0.isRead : true }
            .filter { alert in
                guard let startKey = fromSleepDateKey else { return true }
                guard let sleepDateKey = alert.sleepDateKey else { return false }
                return sleepDateKey >= startKey
            }
            .sorted { $0.createdAt > $1.createdAt }

        guard let limit else { return filtered }
        return Array(filtered.prefix(max(0, limit)))
    }

    func markAlertRead(id: UUID) async throws {
        guard var alert = alertsByID[id] else { return }
        alert.isRead = true
        alert.readAt = Date()
        alertsByID[id] = alert
    }

    func saveAdherence(_ adherence: ProtocolAdherence) async throws {
        adherenceByKey[Self.adherenceKey(adherence)] = adherence
    }

    func fetchAdherence(from: Date, to: Date) async throws -> [ProtocolAdherence] {
        let fromKey = Self.dateKey(for: from)
        let toKey = Self.dateKey(for: to)
        return adherenceByKey.values
            .filter { $0.dateKey >= fromKey && $0.dateKey <= toKey }
            .sorted { $0.dateKey < $1.dateKey }
    }

    func saveActivityStatusLog(_ log: ActivityStatusLog) async throws {
        activityStatusLogsByDateKey[log.dateKey] = log
    }

    func fetchActivityStatusLog(forDateKey key: String) async throws -> ActivityStatusLog? {
        activityStatusLogsByDateKey[key]
    }

    func fetchActivityStatusLogs(from startKey: String, to endKey: String) async throws -> [ActivityStatusLog] {
        activityStatusLogsByDateKey.values
            .filter { $0.dateKey >= startKey && $0.dateKey <= endKey }
            .sorted { $0.dateKey < $1.dateKey }
    }

    func saveProfile(_ profile: UserProfile) async throws {
        self.profile = profile
    }

    func fetchProfile() async throws -> UserProfile {
        if let profile {
            return profile
        }

        let profile = UserProfile()
        self.profile = profile
        return profile
    }

    func saveSyncAnchor(_ data: Data?, for typeIdentifier: String) async throws {
        anchorsByTypeIdentifier[typeIdentifier] = data
    }

    func fetchSyncAnchor(for typeIdentifier: String) async throws -> Data? {
        anchorsByTypeIdentifier[typeIdentifier] ?? nil
    }

    // MARK: - Manual Biology Entries

    func saveManualBiologyEntry(_ entry: ManualBiologyEntry) async throws {
        manualBiologyEntriesByKind[entry.kind] = entry
    }

    func fetchManualBiologyEntries() async throws -> [ManualBiologyEntry] {
        Array(manualBiologyEntriesByKind.values).sorted { $0.enteredAt > $1.enteredAt }
    }

    func deleteManualBiologyEntry(id: UUID) async throws {
        manualBiologyEntriesByKind = manualBiologyEntriesByKind.filter { $0.value.id != id }
    }

    // MARK: - Context entries

    func saveContextEntry(_ entry: SleepContextEntry) async throws {
        contextEntriesByDateKey[entry.sleepDateKey] = entry
    }

    func fetchContextEntry(forSleepDateKey key: String) async throws -> SleepContextEntry? {
        contextEntriesByDateKey[key]
    }

    func fetchContextEntries(from startKey: String, to endKey: String) async throws -> [SleepContextEntry] {
        contextEntriesByDateKey.values
            .filter { $0.sleepDateKey >= startKey && $0.sleepDateKey <= endKey }
            .sorted { $0.sleepDateKey < $1.sleepDateKey }
    }

    func deleteContextEntry(id: UUID) async throws {
        contextEntriesByDateKey = contextEntriesByDateKey.filter { $0.value.id != id }
    }

    func deleteAllContextEntries() async throws {
        contextEntriesByDateKey.removeAll()
    }

    func pruneDataOlderThan(days: Int) async throws {
        // No-op for mock: in-memory data pruning not required for basic testing.
    }

    // MARK: - Privacy & migration

    func deleteAllHealthData() async throws {
        sessionsBySleepDateKey.removeAll()
        summariesBySessionID.removeAll()
        dailyActivitySummariesByDateKey.removeAll()
        baselines.removeAll()
        alertsByID.removeAll()
        adherenceByKey.removeAll()
        activityStatusLogsByDateKey.removeAll()
        manualBiologyEntriesByKind.removeAll()
        contextEntriesByDateKey.removeAll()
        anchorsByTypeIdentifier.removeAll()
        if var current = profile {
            current.hasCompletedOnboarding = false
            current.sleepAssessmentAnswers = []
            profile = current
        }
    }

    func migrateToEncryptedStorage() async throws {
        // No-op for mock: in-memory data needs no migration.
    }

    func fetchDataInventory() async throws -> LocalDataInventory {
        let sortedSessions = sessionsBySleepDateKey.values.sorted { $0.startDate < $1.startDate }
        let lastContextDate = contextEntriesByDateKey.values.max { $0.updatedAt < $1.updatedAt }?.updatedAt
        return LocalDataInventory(
            sleepSessionCount: sessionsBySleepDateKey.count,
            baselineCount: baselines.count,
            alertCount: alertsByID.count,
            protocolAdherenceCount: adherenceByKey.count,
            activityLogCount: activityStatusLogsByDateKey.count,
            manualBiologyEntryCount: manualBiologyEntriesByKind.count,
            contextEntryCount: contextEntriesByDateKey.count,
            lastContextEntryDate: lastContextDate,
            oldestSessionDate: sortedSessions.first?.startDate,
            newestSessionDate: sortedSessions.last?.startDate
        )
    }
}

nonisolated private extension MockLocalDataRepository {
    static func adherenceKey(_ adherence: ProtocolAdherence) -> String {
        "\(adherence.protocolID)|\(adherence.dateKey)"
    }

    static func dateKey(for date: Date) -> String {
        SleepDateKey.calendarDateKey(for: date)
    }
}
