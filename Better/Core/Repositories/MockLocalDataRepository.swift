import Foundation

actor MockLocalDataRepository: LocalDataRepositoryProtocol {
    private var sessionsBySleepDateKey: [String: SleepSession]
    private var summariesBySessionID: [UUID: NightlyBiometricSummary]
    private var baselines: [SleepBaseline]
    private var alertsByID: [UUID: SleepAlert]
    private var adherenceByKey: [String: ProtocolAdherence]
    private var activityStatusLogsByDateKey: [String: ActivityStatusLog]
    private var profile: UserProfile?
    private var anchorsByTypeIdentifier: [String: Data?]

    init(
        sessions: [SleepSession] = [],
        summaries: [NightlyBiometricSummary] = [],
        baselines: [SleepBaseline] = [],
        alerts: [SleepAlert] = [],
        adherence: [ProtocolAdherence] = [],
        activityStatusLogs: [ActivityStatusLog] = [],
        profile: UserProfile? = nil,
        anchors: [String: Data?] = [:]
    ) {
        self.sessionsBySleepDateKey = Dictionary(sessions.map { ($0.sleepDateKey, $0) }, uniquingKeysWith: { _, new in new })
        self.summariesBySessionID = Dictionary(summaries.map { ($0.sleepSessionID, $0) }, uniquingKeysWith: { _, new in new })
        self.baselines = baselines
        self.alertsByID = Dictionary(uniqueKeysWithValues: alerts.map { ($0.id, $0) })
        self.adherenceByKey = Dictionary(uniqueKeysWithValues: adherence.map { (Self.adherenceKey($0), $0) })
        self.activityStatusLogsByDateKey = Dictionary(uniqueKeysWithValues: activityStatusLogs.map { ($0.dateKey, $0) })
        self.profile = profile
        self.anchorsByTypeIdentifier = anchors
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
        alertsByID.values
            .filter { unreadOnly ? !$0.isRead : true }
            .sorted { $0.createdAt > $1.createdAt }
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
}

private extension MockLocalDataRepository {
    static func adherenceKey(_ adherence: ProtocolAdherence) -> String {
        "\(adherence.protocolID)|\(adherence.dateKey)"
    }

    static func dateKey(for date: Date) -> String {
        SleepDateKey.calendarDateKey(for: date)
    }
}
