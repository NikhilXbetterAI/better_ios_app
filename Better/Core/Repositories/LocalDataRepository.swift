import Foundation
import SwiftData

@ModelActor
actor LocalDataRepository: LocalDataRepositoryProtocol {
    func saveSessions(_ sessions: [SleepSession]) async throws {
        for session in sessions {
            try deleteExistingSession(matching: session)
            modelContext.insert(try StoredSleepSession(domain: session))
        }

        try modelContext.save()
    }

    func replaceSessions(_ sessions: [SleepSession], from: Date, to: Date) async throws {
        let descriptor = FetchDescriptor<StoredSleepSession>(
            predicate: #Predicate { session in
                session.endDate > from && session.startDate < to
            }
        )

        for storedSession in try modelContext.fetch(descriptor) {
            modelContext.delete(storedSession)
        }

        for session in sessions {
            modelContext.insert(try StoredSleepSession(domain: session))
        }

        try modelContext.save()
    }

    func fetchCachedSessions(from: Date, to: Date) async throws -> [SleepSession] {
        var descriptor = FetchDescriptor<StoredSleepSession>(
            predicate: #Predicate { session in
                session.endDate > from && session.startDate < to
            },
            sortBy: [SortDescriptor(\.startDate)]
        )
        descriptor.includePendingChanges = true

        return try modelContext.fetch(descriptor).map { try $0.toDomain() }
    }

    func fetchSession(forSleepDateKey key: String) async throws -> SleepSession? {
        var descriptor = FetchDescriptor<StoredSleepSession>(
            predicate: #Predicate { session in
                session.sleepDateKey == key
            }
        )
        descriptor.fetchLimit = 1

        return try modelContext.fetch(descriptor).first?.toDomain()
    }

    func fetchSessions(beforeSleepDateKey key: String, limit: Int) async throws -> [SleepSession] {
        var descriptor = FetchDescriptor<StoredSleepSession>(
            predicate: #Predicate { session in
                session.sleepDateKey < key
            },
            sortBy: [SortDescriptor(\.sleepDateKey, order: .reverse)]
        )
        descriptor.fetchLimit = max(0, limit)

        return try modelContext.fetch(descriptor).map { try $0.toDomain() }
    }

    func fetchAvailableSleepDates(from startKey: String, to endKey: String) async throws -> [SleepDaySummary] {
        let descriptor = FetchDescriptor<StoredSleepSession>(
            predicate: #Predicate { session in
                session.sleepDateKey >= startKey && session.sleepDateKey <= endKey
            },
            sortBy: [SortDescriptor(\.sleepDateKey)]
        )

        return try modelContext.fetch(descriptor).map { stored in
            SleepDaySummary(
                sleepDateKey: stored.sleepDateKey,
                score: try stored.toDomain().qualityScore.overall,
                totalSleepTime: stored.totalSleepTime,
                dataQuality: SleepDataQuality(rawValue: stored.dataQualityRawValue) ?? .noData,
                hasSession: true
            )
        }
    }

    func fetchLatestSession() async throws -> SleepSession? {
        var descriptor = FetchDescriptor<StoredSleepSession>(
            sortBy: [SortDescriptor(\.endDate, order: .reverse)]
        )
        descriptor.fetchLimit = 1

        return try modelContext.fetch(descriptor).first?.toDomain()
    }

    func saveBiometricSummary(_ summary: NightlyBiometricSummary) async throws {
        let id = summary.id
        let sessionID = summary.sleepSessionID
        let descriptor = FetchDescriptor<StoredNightlyBiometricSummary>(
            predicate: #Predicate { stored in
                stored.id == id || stored.sleepSessionID == sessionID
            }
        )

        for storedSummary in try modelContext.fetch(descriptor) {
            modelContext.delete(storedSummary)
        }

        modelContext.insert(try StoredNightlyBiometricSummary(domain: summary))
        try modelContext.save()
    }

    func saveDailyActivitySummary(_ summary: DailyActivitySummary) async throws {
        let dateKey = summary.dateKey
        let descriptor = FetchDescriptor<StoredDailyActivitySummary>(
            predicate: #Predicate { stored in
                stored.dateKey == dateKey
            }
        )

        for storedSummary in try modelContext.fetch(descriptor) {
            modelContext.delete(storedSummary)
        }

        modelContext.insert(StoredDailyActivitySummary(domain: summary))
        try modelContext.save()
    }

    func fetchDailyActivitySummaries(from startKey: String, to endKey: String) async throws -> [DailyActivitySummary] {
        let descriptor = FetchDescriptor<StoredDailyActivitySummary>(
            predicate: #Predicate { summary in
                summary.dateKey >= startKey && summary.dateKey <= endKey
            },
            sortBy: [SortDescriptor(\.dateKey)]
        )

        return try modelContext.fetch(descriptor).map { $0.toDomain() }
    }

    func saveBaseline(_ baseline: SleepBaseline) async throws {
        let id = baseline.id
        let descriptor = FetchDescriptor<StoredBaseline>(
            predicate: #Predicate { stored in
                stored.id == id
            }
        )

        for storedBaseline in try modelContext.fetch(descriptor) {
            modelContext.delete(storedBaseline)
        }

        modelContext.insert(StoredBaseline(domain: baseline))
        try modelContext.save()
    }

    func fetchLatestBaseline(windowDays: Int) async throws -> SleepBaseline? {
        var descriptor = FetchDescriptor<StoredBaseline>(
            predicate: #Predicate { baseline in
                baseline.windowDays == windowDays
            },
            sortBy: [SortDescriptor(\.generatedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1

        return try modelContext.fetch(descriptor).first?.toDomain()
    }

    func saveAlerts(_ alerts: [SleepAlert]) async throws {
        for alert in alerts {
            let id = alert.id
            let descriptor = FetchDescriptor<StoredAlert>(
                predicate: #Predicate { stored in
                    stored.id == id
                }
            )

            for storedAlert in try modelContext.fetch(descriptor) {
                modelContext.delete(storedAlert)
            }

            modelContext.insert(StoredAlert(domain: alert))
        }

        try modelContext.save()
    }

    func fetchAlerts(unreadOnly: Bool) async throws -> [SleepAlert] {
        try await fetchAlerts(unreadOnly: unreadOnly, fromSleepDateKey: nil, limit: nil)
    }

    func fetchAlerts(unreadOnly: Bool, fromSleepDateKey: String?, limit: Int?) async throws -> [SleepAlert] {
        let descriptor: FetchDescriptor<StoredAlert>
        if unreadOnly {
            descriptor = FetchDescriptor<StoredAlert>(
                predicate: #Predicate { alert in
                    !alert.isRead
                },
                sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
            )
        } else {
            descriptor = FetchDescriptor<StoredAlert>(
                sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
            )
        }

        var limitedDescriptor = descriptor
        if fromSleepDateKey == nil, let limit {
            limitedDescriptor.fetchLimit = max(0, limit)
        }

        let alerts = try modelContext.fetch(limitedDescriptor).map { $0.toDomain() }
        let filteredAlerts = alerts.filter { alert in
            guard let fromSleepDateKey else { return true }
            guard let sleepDateKey = alert.sleepDateKey else { return false }
            return sleepDateKey >= fromSleepDateKey
        }

        guard let limit else { return filteredAlerts }
        return Array(filteredAlerts.prefix(max(0, limit)))
    }

    func markAlertRead(id: UUID) async throws {
        let descriptor = FetchDescriptor<StoredAlert>(
            predicate: #Predicate { alert in
                alert.id == id
            }
        )

        for alert in try modelContext.fetch(descriptor) {
            alert.isRead = true
            alert.readAt = Date()
        }

        try modelContext.save()
    }

    func saveAdherence(_ adherence: ProtocolAdherence) async throws {
        let id = adherence.id
        let uniqueKey = "\(adherence.protocolID)|\(adherence.dateKey)"
        let descriptor = FetchDescriptor<StoredProtocolAdherence>(
            predicate: #Predicate { stored in
                stored.id == id || stored.uniqueKey == uniqueKey
            }
        )

        for storedAdherence in try modelContext.fetch(descriptor) {
            modelContext.delete(storedAdherence)
        }

        modelContext.insert(StoredProtocolAdherence(domain: adherence))
        try modelContext.save()
    }

    func fetchAdherence(from: Date, to: Date) async throws -> [ProtocolAdherence] {
        let fromKey = Self.dateKey(for: from)
        let toKey = Self.dateKey(for: to)
        let descriptor = FetchDescriptor<StoredProtocolAdherence>(
            predicate: #Predicate { adherence in
                adherence.dateKey >= fromKey && adherence.dateKey <= toKey
            },
            sortBy: [SortDescriptor(\.dateKey)]
        )

        return try modelContext.fetch(descriptor).map { $0.toDomain() }
    }

    func saveActivityStatusLog(_ log: ActivityStatusLog) async throws {
        let id = log.id
        let dateKey = log.dateKey
        let descriptor = FetchDescriptor<StoredActivityStatusLog>(
            predicate: #Predicate { stored in
                stored.id == id || stored.dateKey == dateKey
            }
        )

        for storedLog in try modelContext.fetch(descriptor) {
            modelContext.delete(storedLog)
        }

        modelContext.insert(StoredActivityStatusLog(domain: log))
        try modelContext.save()
    }

    func fetchActivityStatusLog(forDateKey key: String) async throws -> ActivityStatusLog? {
        var descriptor = FetchDescriptor<StoredActivityStatusLog>(
            predicate: #Predicate { log in
                log.dateKey == key
            }
        )
        descriptor.fetchLimit = 1

        return try modelContext.fetch(descriptor).first?.toDomain()
    }

    func fetchActivityStatusLogs(from startKey: String, to endKey: String) async throws -> [ActivityStatusLog] {
        let descriptor = FetchDescriptor<StoredActivityStatusLog>(
            predicate: #Predicate { log in
                log.dateKey >= startKey && log.dateKey <= endKey
            },
            sortBy: [SortDescriptor(\.dateKey)]
        )

        return try modelContext.fetch(descriptor).map { $0.toDomain() }
    }

    func saveProfile(_ profile: UserProfile) async throws {
        let descriptor = FetchDescriptor<StoredUserProfile>()
        for storedProfile in try modelContext.fetch(descriptor) {
            modelContext.delete(storedProfile)
        }

        modelContext.insert(StoredUserProfile(domain: profile))
        try modelContext.save()
    }

    func fetchProfile() async throws -> UserProfile {
        var descriptor = FetchDescriptor<StoredUserProfile>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1

        if let profile = try modelContext.fetch(descriptor).first {
            return profile.toDomain()
        }

        let profile = UserProfile()
        modelContext.insert(StoredUserProfile(domain: profile))
        try modelContext.save()
        return profile
    }

    func saveSyncAnchor(_ data: Data?, for typeIdentifier: String) async throws {
        let descriptor = FetchDescriptor<StoredSyncAnchor>(
            predicate: #Predicate { anchor in
                anchor.typeIdentifier == typeIdentifier
            }
        )

        let existingAnchors = try modelContext.fetch(descriptor)
        if let anchor = existingAnchors.first {
            anchor.anchorData = data
            anchor.updatedAt = Date()
            for duplicate in existingAnchors.dropFirst() {
                modelContext.delete(duplicate)
            }
        } else {
            modelContext.insert(StoredSyncAnchor(typeIdentifier: typeIdentifier, anchorData: data))
        }

        try modelContext.save()
    }

    func fetchSyncAnchor(for typeIdentifier: String) async throws -> Data? {
        var descriptor = FetchDescriptor<StoredSyncAnchor>(
            predicate: #Predicate { anchor in
                anchor.typeIdentifier == typeIdentifier
            },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1

        return try modelContext.fetch(descriptor).first?.anchorData
    }

    // MARK: - Manual Biology Entries

    func saveManualBiologyEntry(_ entry: ManualBiologyEntry) async throws {
        let kindRaw = entry.kind.rawValue
        let descriptor = FetchDescriptor<StoredManualBiologyEntry>(
            predicate: #Predicate { stored in
                stored.kindRawValue == kindRaw
            }
        )
        for existing in try modelContext.fetch(descriptor) {
            modelContext.delete(existing)
        }
        modelContext.insert(StoredManualBiologyEntry(domain: entry))
        try modelContext.save()
    }

    func fetchManualBiologyEntries() async throws -> [ManualBiologyEntry] {
        let descriptor = FetchDescriptor<StoredManualBiologyEntry>(
            sortBy: [SortDescriptor(\.enteredAt, order: .reverse)]
        )
        return try modelContext.fetch(descriptor).compactMap { $0.toDomain() }
    }

    func deleteManualBiologyEntry(id: UUID) async throws {
        let descriptor = FetchDescriptor<StoredManualBiologyEntry>(
            predicate: #Predicate { stored in
                stored.id == id
            }
        )
        for existing in try modelContext.fetch(descriptor) {
            modelContext.delete(existing)
        }
        try modelContext.save()
    }

    // MARK: - Context entries

    func saveContextEntry(_ entry: SleepContextEntry) async throws {
        // Replace any existing entry for this sleep date (one entry per night).
        let sleepDateKey = entry.sleepDateKey
        let id = entry.id
        let descriptor = FetchDescriptor<StoredSleepContextEntry>(
            predicate: #Predicate { stored in
                stored.id == id || stored.sleepDateKey == sleepDateKey
            }
        )
        for existing in try modelContext.fetch(descriptor) {
            modelContext.delete(existing)
        }
        modelContext.insert(try StoredSleepContextEntry(domain: entry))
        try modelContext.save()
    }

    func fetchContextEntry(forSleepDateKey key: String) async throws -> SleepContextEntry? {
        var descriptor = FetchDescriptor<StoredSleepContextEntry>(
            predicate: #Predicate { stored in
                stored.sleepDateKey == key
            }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first.flatMap { try? $0.toDomain() }
    }

    func fetchContextEntries(from startKey: String, to endKey: String) async throws -> [SleepContextEntry] {
        let descriptor = FetchDescriptor<StoredSleepContextEntry>(
            predicate: #Predicate { stored in
                stored.sleepDateKey >= startKey && stored.sleepDateKey <= endKey
            },
            sortBy: [SortDescriptor(\.sleepDateKey)]
        )
        return try modelContext.fetch(descriptor).compactMap { try? $0.toDomain() }
    }

    func deleteContextEntry(id: UUID) async throws {
        let descriptor = FetchDescriptor<StoredSleepContextEntry>(
            predicate: #Predicate { stored in
                stored.id == id
            }
        )
        for stored in try modelContext.fetch(descriptor) {
            modelContext.delete(stored)
        }
        try modelContext.save()
    }

    func deleteAllContextEntries() async throws {
        try modelContext.delete(model: StoredSleepContextEntry.self)
        try modelContext.save()
    }

    func pruneDataOlderThan(days: Int) async throws {
        let cutoff = Date.now.addingTimeInterval(Double(-days) * 86_400)
        let cutoffKey = Self.dateKey(for: cutoff)

        // 1. Sessions & Biometrics
        try modelContext.delete(model: StoredSleepSession.self, where: #Predicate { session in
            session.endDate < cutoff
        })
        try modelContext.delete(model: StoredNightlyBiometricSummary.self, where: #Predicate { summary in
            summary.sleepDateKey < cutoffKey
        })

        // 2. Activity & Status
        try modelContext.delete(model: StoredDailyActivitySummary.self, where: #Predicate { summary in
            summary.dateKey < cutoffKey
        })
        try modelContext.delete(model: StoredActivityStatusLog.self, where: #Predicate { log in
            log.dateKey < cutoffKey
        })

        // 3. Protocols & Context
        try modelContext.delete(model: StoredProtocolAdherence.self, where: #Predicate { adherence in
            adherence.dateKey < cutoffKey
        })
        try modelContext.delete(model: StoredSleepContextEntry.self, where: #Predicate { entry in
            entry.sleepDateKey < cutoffKey
        })

        // 4. Baselines
        try modelContext.delete(model: StoredBaseline.self, where: #Predicate { baseline in
            baseline.generatedAt < cutoff
        })

        try modelContext.save()
    }

    // MARK: - Privacy & migration

    func deleteAllHealthData() async throws {
        try modelContext.delete(model: StoredSleepSession.self)
        try modelContext.delete(model: StoredNightlyBiometricSummary.self)
        try modelContext.delete(model: StoredDailyActivitySummary.self)
        try modelContext.delete(model: StoredBaseline.self)
        try modelContext.delete(model: StoredProtocolAdherence.self)
        try modelContext.delete(model: StoredActivityStatusLog.self)
        try modelContext.delete(model: StoredAlert.self)
        try modelContext.delete(model: StoredManualBiologyEntry.self)
        try modelContext.delete(model: StoredSyncAnchor.self)
        try modelContext.delete(model: StoredSleepContextEntry.self)

        // Clear health-sensitive profile fields; keep non-sensitive preferences.
        for profile in try modelContext.fetch(FetchDescriptor<StoredUserProfile>()) {
            profile.sleepAssessmentAnswersData = nil
            profile.hasCompletedOnboarding = false
            profile.updatedAt = Date()
        }

        try modelContext.save()
    }

    func migrateToEncryptedStorage() async throws {
        // Sleep sessions — re-encode all JSON blob fields via PersistenceJSON (which now encrypts).
        for session in try modelContext.fetch(FetchDescriptor<StoredSleepSession>()) {
            await Task.yield()
            guard let domain = try? session.toDomain() else { continue }
            session.qualityScoreData = try PersistenceJSON.encode(domain.qualityScore)
            session.stagesData = try PersistenceJSON.encode(domain.stages)
            session.sourcesData = try PersistenceJSON.encode(domain.sources)
            if let biometrics = domain.biometrics {
                session.biometricsData = try PersistenceJSON.encode(biometrics)
            }
        }

        // Nightly biometric summaries.
        for summary in try modelContext.fetch(FetchDescriptor<StoredNightlyBiometricSummary>()) {
            await Task.yield()
            guard let domain = try? summary.toDomain() else { continue }
            summary.samplesData = try PersistenceJSON.encode(domain.samples)
        }

        // User profile — onboarding assessment answers.
        for profile in try modelContext.fetch(FetchDescriptor<StoredUserProfile>()) {
            guard
                let raw = profile.sleepAssessmentAnswersData,
                let answers = try? PersistenceJSON.decode([SleepAssessmentAnswer].self, from: raw)
            else { continue }
            profile.sleepAssessmentAnswersData = try PersistenceJSON.encode(answers)
        }

        try modelContext.save()
    }

    func fetchDataInventory() async throws -> LocalDataInventory {
        let sessionDescriptor = FetchDescriptor<StoredSleepSession>(
            sortBy: [SortDescriptor(\.startDate)]
        )
        let sessions = try modelContext.fetch(sessionDescriptor)

        var contextDescriptor = FetchDescriptor<StoredSleepContextEntry>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        contextDescriptor.fetchLimit = 1
        let latestContextEntry = try modelContext.fetch(contextDescriptor).first
        let contextCount = try modelContext.fetchCount(FetchDescriptor<StoredSleepContextEntry>())

        return LocalDataInventory(
            sleepSessionCount: sessions.count,
            baselineCount: try modelContext.fetchCount(FetchDescriptor<StoredBaseline>()),
            alertCount: try modelContext.fetchCount(FetchDescriptor<StoredAlert>()),
            protocolAdherenceCount: try modelContext.fetchCount(FetchDescriptor<StoredProtocolAdherence>()),
            activityLogCount: try modelContext.fetchCount(FetchDescriptor<StoredActivityStatusLog>()),
            manualBiologyEntryCount: try modelContext.fetchCount(FetchDescriptor<StoredManualBiologyEntry>()),
            contextEntryCount: contextCount,
            lastContextEntryDate: latestContextEntry?.updatedAt,
            oldestSessionDate: sessions.first?.startDate,
            newestSessionDate: sessions.last?.startDate
        )
    }
}

private extension LocalDataRepository {
    func deleteExistingSession(matching session: SleepSession) throws {
        let id = session.id
        let sleepDateKey = session.sleepDateKey
        let descriptor = FetchDescriptor<StoredSleepSession>(
            predicate: #Predicate { storedSession in
                storedSession.id == id || storedSession.sleepDateKey == sleepDateKey
            }
        )

        for storedSession in try modelContext.fetch(descriptor) {
            modelContext.delete(storedSession)
        }
    }

    nonisolated static func dateKey(for date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }
}
