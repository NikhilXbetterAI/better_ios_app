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

        return try modelContext.fetch(descriptor).compactMap { try? $0.toDomain() }
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

        // compactMap: skip any record whose JSON blob is corrupted (e.g. from a
        // failed background write) rather than crashing the whole fetch.
        return try modelContext.fetch(descriptor).compactMap { try? $0.toDomain() }
    }

    func fetchAvailableSleepDates(from startKey: String, to endKey: String) async throws -> [SleepDaySummary] {
        let descriptor = FetchDescriptor<StoredSleepSession>(
            predicate: #Predicate { session in
                session.sleepDateKey >= startKey && session.sleepDateKey <= endKey
            },
            sortBy: [SortDescriptor(\.sleepDateKey)]
        )

        return try modelContext.fetch(descriptor).compactMap { stored in
            // Store raw scalars needed for the ViewModel to recompute the full
            // Apple score (with bedtime) once the baseline is available.
            return SleepDaySummary(
                sleepDateKey: stored.sleepDateKey,
                score: stored.qualityScoreOverall,
                totalSleepTime: stored.totalSleepTime,
                waso: stored.waso,
                inBedStartDate: stored.inBedStartDate ?? stored.startDate,
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
        let descriptor = FetchDescriptor<StoredBaseline>(
            sortBy: [SortDescriptor(\.generatedAt, order: .reverse)]
        )
        let storedBaselines = try modelContext.fetch(descriptor)
        let baselines = storedBaselines.map { $0.toDomain() }

        if let exactMatch = baselines.first(where: { $0.windowDays == windowDays }) {
            return exactMatch
        }

        return baselines.first(where: { $0.windowDays <= windowDays })
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

    // MARK: - Sleep Mode

    func saveSleepModeSettings(_ settings: SleepModeSettings) async throws {
        for existing in try modelContext.fetch(FetchDescriptor<StoredSleepModeSettings>()) {
            modelContext.delete(existing)
        }
        modelContext.insert(try StoredSleepModeSettings(domain: settings))
        try modelContext.save()
    }

    func fetchSleepModeSettings() async throws -> SleepModeSettings? {
        var descriptor = FetchDescriptor<StoredSleepModeSettings>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first.flatMap { try? $0.toDomain() }
    }

    func saveSleepModeSchedule(_ schedule: SleepModeSchedule) async throws {
        for existing in try modelContext.fetch(FetchDescriptor<StoredSleepModeSchedule>()) {
            modelContext.delete(existing)
        }
        modelContext.insert(try StoredSleepModeSchedule(domain: schedule))
        try modelContext.save()
    }

    func fetchSleepModeSchedule() async throws -> SleepModeSchedule? {
        var descriptor = FetchDescriptor<StoredSleepModeSchedule>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first.flatMap { try? $0.toDomain() }
    }

    func saveSleepModeSession(_ session: SleepModeSession) async throws {
        let id = session.id
        let descriptor = FetchDescriptor<StoredSleepModeSession>(
            predicate: #Predicate { stored in
                stored.id == id
            }
        )
        for existing in try modelContext.fetch(descriptor) {
            modelContext.delete(existing)
        }
        modelContext.insert(try StoredSleepModeSession(domain: session))
        try modelContext.save()
    }

    func fetchSleepModeSessions(from: Date, to: Date) async throws -> [SleepModeSession] {
        let descriptor = FetchDescriptor<StoredSleepModeSession>(
            sortBy: [SortDescriptor(\.startedAt)]
        )
        return try modelContext.fetch(descriptor)
            .filter { ($0.endedAt ?? $0.startedAt) > from && $0.startedAt < to }
            .compactMap { try? $0.toDomain() }
    }

    func deleteAllSleepModeData() async throws {
        try modelContext.delete(model: StoredSleepModeSettings.self)
        try modelContext.delete(model: StoredSleepModeSchedule.self)
        try modelContext.delete(model: StoredSleepModeSession.self)
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

    // MARK: - Protocol Formula Tracking

    func saveFormulaVersion(_ version: ProtocolFormulaVersion) async throws {
        let id = version.id
        let descriptor = FetchDescriptor<StoredProtocolFormulaVersion>(
            predicate: #Predicate { row in row.id == id }
        )
        let existing = try modelContext.fetch(descriptor).first

        // Compute ordinal index — count of existing rows with an earlier `shippedOn`, or
        // keep the existing index if the row already exists.
        let ordinalIndex: Int
        if let existing {
            ordinalIndex = existing.ordinalIndex
        } else {
            let allDescriptor = FetchDescriptor<StoredProtocolFormulaVersion>(
                sortBy: [SortDescriptor(\.shippedOn)]
            )
            let all = try modelContext.fetch(allDescriptor)
            ordinalIndex = all.filter { $0.shippedOn <= version.shippedOn }.count + 1
        }

        // Immutability rule: if this version has any logs and `formulaText`/`components`
        // changed, reject the write — UNLESS the existing row is still an imported
        // placeholder with empty text and the incoming text is non-empty (the one
        // permitted backfill, which atomically clears the placeholder flag).
        var versionToWrite = version
        if let existing {
            let logCount = try modelContext.fetchCount(FetchDescriptor<StoredProtocolNightLog>(
                predicate: #Predicate { log in log.versionIDString == id.uuidString }
            ))
            if logCount > 0 {
                let existingDomain = try existing.toDomain(ordinalLabel: "")
                let textChanged = existingDomain.formulaText != version.formulaText
                let componentsChanged = existingDomain.components != version.components
                let placeholderBackfill = existing.isImportedPlaceholder &&
                    existingDomain.formulaText.isEmpty &&
                    !version.formulaText.isEmpty
                if (textChanged || componentsChanged) && !placeholderBackfill {
                    throw ProtocolFormulaRepositoryError.formulaTextLocked(versionID: id)
                }
                if placeholderBackfill {
                    versionToWrite.isImportedPlaceholder = false
                }
            }
        }

        // Active-singleton enforcement: clear `isActive` on any other row when this row is active.
        if versionToWrite.isActive {
            let othersDescriptor = FetchDescriptor<StoredProtocolFormulaVersion>(
                predicate: #Predicate { row in row.id != id && row.isActive }
            )
            for other in try modelContext.fetch(othersDescriptor) {
                other.isActive = false
                other.updatedAt = Date()
            }
        }

        if let existing {
            modelContext.delete(existing)
        }
        let stored = try StoredProtocolFormulaVersion(domain: versionToWrite, ordinalIndex: ordinalIndex)
        modelContext.insert(stored)
        try modelContext.save()
    }

    func fetchAllFormulaVersions() async throws -> [ProtocolFormulaVersion] {
        let descriptor = FetchDescriptor<StoredProtocolFormulaVersion>(
            sortBy: [SortDescriptor(\.shippedOn), SortDescriptor(\.createdAt)]
        )
        let rows = try modelContext.fetch(descriptor)
        return rows.enumerated().compactMap { idx, row in
            try? row.toDomain(ordinalLabel: "V\(idx + 1)")
        }
    }

    func fetchActiveFormulaVersion() async throws -> ProtocolFormulaVersion? {
        // Resolve the ordinal label by reading all versions so the active row's label
        // is correct relative to its peers.
        let all = try await fetchAllFormulaVersions()
        return all.first(where: { $0.isActive })
    }

    func fetchFormulaVersion(id: UUID) async throws -> ProtocolFormulaVersion? {
        let all = try await fetchAllFormulaVersions()
        return all.first(where: { $0.id == id })
    }

    func archiveFormulaVersion(id: UUID) async throws {
        let descriptor = FetchDescriptor<StoredProtocolFormulaVersion>(
            predicate: #Predicate { row in row.id == id }
        )
        for row in try modelContext.fetch(descriptor) {
            row.archivedAt = Date()
            row.isActive = false
            row.updatedAt = Date()
        }
        try modelContext.save()
    }

    func deleteFormulaVersion(id: UUID) async throws {
        let descriptor = FetchDescriptor<StoredProtocolFormulaVersion>(
            predicate: #Predicate { row in row.id == id }
        )
        for row in try modelContext.fetch(descriptor) {
            modelContext.delete(row)
        }
        try modelContext.save()
    }

    func saveNightLog(_ log: ProtocolNightLog) async throws {
        let id = log.id
        let sleepDateKey = log.sleepDateKey
        let descriptor = FetchDescriptor<StoredProtocolNightLog>(
            predicate: #Predicate { row in row.id == id || row.sleepDateKey == sleepDateKey }
        )
        for existing in try modelContext.fetch(descriptor) {
            modelContext.delete(existing)
        }
        modelContext.insert(try StoredProtocolNightLog(domain: log))
        try modelContext.save()
    }

    func fetchNightLog(forSleepDateKey key: String) async throws -> ProtocolNightLog? {
        var descriptor = FetchDescriptor<StoredProtocolNightLog>(
            predicate: #Predicate { row in row.sleepDateKey == key }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first.flatMap { try? $0.toDomain() }
    }

    func fetchNightLogs(from startKey: String, to endKey: String) async throws -> [ProtocolNightLog] {
        let descriptor = FetchDescriptor<StoredProtocolNightLog>(
            predicate: #Predicate { row in row.sleepDateKey >= startKey && row.sleepDateKey <= endKey },
            sortBy: [SortDescriptor(\.sleepDateKey)]
        )
        return try modelContext.fetch(descriptor).compactMap { try? $0.toDomain() }
    }

    func deleteNightLog(forSleepDateKey key: String) async throws {
        let descriptor = FetchDescriptor<StoredProtocolNightLog>(
            predicate: #Predicate { row in row.sleepDateKey == key }
        )
        for row in try modelContext.fetch(descriptor) {
            modelContext.delete(row)
        }
        try modelContext.save()
    }

    func hasNightLogs(forVersionID id: UUID) async throws -> Bool {
        let idString = id.uuidString
        let descriptor = FetchDescriptor<StoredProtocolNightLog>(
            predicate: #Predicate { log in log.versionIDString == idString }
        )
        let count = try modelContext.fetchCount(descriptor)
        return count > 0
    }


    func saveLogEdit(_ edit: ProtocolLogEdit) async throws {
        modelContext.insert(StoredProtocolLogEdit(domain: edit))
        try modelContext.save()
    }

    func fetchLogEdits(forSleepDateKey key: String) async throws -> [ProtocolLogEdit] {
        let descriptor = FetchDescriptor<StoredProtocolLogEdit>(
            predicate: #Predicate { row in row.sleepDateKey == key },
            sortBy: [SortDescriptor(\.editedAt)]
        )
        return try modelContext.fetch(descriptor).map { $0.toDomain() }
    }

    func saveBaselineSnapshot(_ snapshot: ProtocolBaselineSnapshot) async throws {
        guard snapshot.validNightCount > 0 else {
            throw ProtocolFormulaRepositoryError.baselineSnapshotEmpty
        }
        // V3: per-version baselines. Upsert keyed by `versionID` when present;
        // legacy nil-keyed rows upsert within their own slot. Additionally,
        // any row sharing the same `id` is removed — handles the V3 backfill
        // case where the legacy singleton row is re-keyed to the active version.
        let snapshotID = snapshot.id
        let idDescriptor = FetchDescriptor<StoredProtocolBaselineSnapshot>(
            predicate: #Predicate { row in row.id == snapshotID }
        )
        for existing in try modelContext.fetch(idDescriptor) {
            modelContext.delete(existing)
        }
        if let versionID = snapshot.versionID {
            let descriptor = FetchDescriptor<StoredProtocolBaselineSnapshot>(
                predicate: #Predicate { row in row.versionID == versionID }
            )
            for existing in try modelContext.fetch(descriptor) {
                modelContext.delete(existing)
            }
        } else {
            let descriptor = FetchDescriptor<StoredProtocolBaselineSnapshot>(
                predicate: #Predicate { row in row.versionID == nil }
            )
            for existing in try modelContext.fetch(descriptor) {
                modelContext.delete(existing)
            }
        }
        modelContext.insert(try StoredProtocolBaselineSnapshot(domain: snapshot))
        try modelContext.save()
    }

    func fetchBaselineSnapshot() async throws -> ProtocolBaselineSnapshot? {
        var descriptor = FetchDescriptor<StoredProtocolBaselineSnapshot>(
            sortBy: [SortDescriptor(\.frozenAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first.flatMap { try? $0.toDomain() }
    }

    func fetchBaselineSnapshot(versionID: UUID) async throws -> ProtocolBaselineSnapshot? {
        var descriptor = FetchDescriptor<StoredProtocolBaselineSnapshot>(
            predicate: #Predicate { row in row.versionID == versionID },
            sortBy: [SortDescriptor(\.frozenAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first.flatMap { try? $0.toDomain() }
    }

    func deleteBaselineSnapshot() async throws {
        for existing in try modelContext.fetch(FetchDescriptor<StoredProtocolBaselineSnapshot>()) {
            modelContext.delete(existing)
        }
        try modelContext.save()
    }

    // MARK: - Intervention windows (V3)

    func fetchInterventionWindows() async throws -> [InterventionWindow] {
        let descriptor = FetchDescriptor<StoredInterventionWindow>(
            sortBy: [SortDescriptor(\.startedAt)]
        )
        return try modelContext.fetch(descriptor).map { $0.toDomain() }
    }

    func saveInterventionWindow(_ window: InterventionWindow) async throws {
        let id = window.id
        let descriptor = FetchDescriptor<StoredInterventionWindow>(
            predicate: #Predicate { row in row.id == id }
        )
        if let existing = try modelContext.fetch(descriptor).first {
            existing.versionID = window.versionID
            existing.startedAt = window.startedAt
            existing.endedAt = window.endedAt
            existing.phaseRaw = window.phase.rawValue
            existing.updatedAt = window.updatedAt
        } else {
            modelContext.insert(StoredInterventionWindow(domain: window))
        }
        try modelContext.save()
    }

    func deleteInterventionWindow(id: UUID) async throws {
        let descriptor = FetchDescriptor<StoredInterventionWindow>(
            predicate: #Predicate { row in row.id == id }
        )
        for row in try modelContext.fetch(descriptor) {
            modelContext.delete(row)
        }
        try modelContext.save()
    }

    // MARK: - Dashboard baseline snapshot cache (V4)

    func saveBaselineSnapshot(_ snapshot: DashboardBaselineSnapshotRecord) async throws {
        let compositeID = "\(snapshot.asOfSleepDateKey)_\(snapshot.windowKind)"
        let descriptor = FetchDescriptor<StoredDashboardBaselineSnapshot>(
            predicate: #Predicate { row in row.id == compositeID }
        )
        if let existing = try modelContext.fetch(descriptor).first {
            existing.generatedAt = snapshot.generatedAt
            existing.validNightCount = snapshot.validNightCount
            existing.sourceWindowStart = snapshot.sourceWindowStart
            existing.sourceWindowEnd = snapshot.sourceWindowEnd
            existing.durationMean = snapshot.durationMean
            existing.durationStdDev = snapshot.durationStdDev
            existing.bedtimeMeanHour = snapshot.bedtimeMeanHour
            existing.bedtimeStdDev = snapshot.bedtimeStdDev
            existing.remRatioMean = snapshot.remRatioMean
            existing.deepRatioMean = snapshot.deepRatioMean
            existing.baselineData = snapshot.baselineData
        } else {
            modelContext.insert(StoredDashboardBaselineSnapshot(domain: snapshot))
        }
        try modelContext.save()
    }

    func fetchBaselineSnapshot(asOfSleepDateKey: String, windowKind: String) async throws -> DashboardBaselineSnapshotRecord? {
        let compositeID = "\(asOfSleepDateKey)_\(windowKind)"
        var descriptor = FetchDescriptor<StoredDashboardBaselineSnapshot>(
            predicate: #Predicate { row in row.id == compositeID }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first?.toDomain()
    }

    func deleteBaselineSnapshots(containingSleepDateKey: String) async throws {
        let key = containingSleepDateKey
        let descriptor = FetchDescriptor<StoredDashboardBaselineSnapshot>(
            predicate: #Predicate { row in row.asOfSleepDateKey == key }
        )
        for row in try modelContext.fetch(descriptor) {
            modelContext.delete(row)
        }
        try modelContext.save()
    }

    // MARK: - Chronotype snapshot cache (V4)

    func saveChronotypeSnapshot(_ snapshot: ChronotypeSnapshotRecord) async throws {
        let key = snapshot.windowEndSleepDateKey
        let descriptor = FetchDescriptor<StoredChronotypeSnapshot>(
            predicate: #Predicate { row in row.windowEndSleepDateKey == key }
        )
        if let existing = try modelContext.fetch(descriptor).first {
            existing.generatedAt = snapshot.generatedAt
            existing.estimateData = snapshot.estimateData
            existing.coverageNightCount = snapshot.coverageNightCount
            existing.windowDays = snapshot.windowDays
        } else {
            modelContext.insert(StoredChronotypeSnapshot(domain: snapshot))
        }
        try modelContext.save()
    }

    func fetchChronotypeSnapshot(windowEndSleepDateKey: String) async throws -> ChronotypeSnapshotRecord? {
        let key = windowEndSleepDateKey
        var descriptor = FetchDescriptor<StoredChronotypeSnapshot>(
            predicate: #Predicate { row in row.windowEndSleepDateKey == key }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first?.toDomain()
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
        try modelContext.delete(model: StoredProtocolNightLog.self, where: #Predicate { log in
            log.sleepDateKey < cutoffKey
        })
        try modelContext.delete(model: StoredProtocolLogEdit.self, where: #Predicate { edit in
            edit.sleepDateKey < cutoffKey
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
        try modelContext.delete(model: StoredSleepModeSession.self)
        try modelContext.delete(model: StoredProtocolFormulaVersion.self)
        try modelContext.delete(model: StoredProtocolNightLog.self)
        try modelContext.delete(model: StoredProtocolLogEdit.self)
        try modelContext.delete(model: StoredProtocolBaselineSnapshot.self)
        try modelContext.delete(model: StoredInterventionWindow.self)
        try modelContext.delete(model: StoredDashboardBaselineSnapshot.self)
        try modelContext.delete(model: StoredChronotypeSnapshot.self)

        // Clear health-sensitive profile fields; keep non-sensitive preferences.
        for profile in try modelContext.fetch(FetchDescriptor<StoredUserProfile>()) {
            profile.sleepAssessmentAnswersData = nil
            profile.hasCompletedOnboarding = false
            profile.updatedAt = Date()
        }

        try modelContext.save()
    }

    func migrateToEncryptedStorage() async throws {
        let batchSize = 100

        // Sleep sessions — re-encode all JSON blob fields via PersistenceJSON (which now encrypts).
        var sessionOffset = 0
        while true {
            var descriptor = FetchDescriptor<StoredSleepSession>()
            descriptor.fetchLimit = batchSize
            descriptor.fetchOffset = sessionOffset
            let sessions = try modelContext.fetch(descriptor)
            if sessions.isEmpty { break }
            for session in sessions {
                await Task.yield()
                guard let domain = try? session.toDomain() else { continue }
                session.qualityScoreData = try PersistenceJSON.encode(domain.qualityScore)
                session.stagesData = try PersistenceJSON.encode(domain.stages)
                session.sourcesData = try PersistenceJSON.encode(domain.sources)
                if let biometrics = domain.biometrics {
                    session.biometricsData = try PersistenceJSON.encode(biometrics)
                }
            }
            try modelContext.save()
            sessionOffset += sessions.count
        }

        // Sleep Mode blobs.
        for settings in try modelContext.fetch(FetchDescriptor<StoredSleepModeSettings>()) {
            guard let domain = try? settings.toDomain() else { continue }
            settings.settingsData = try PersistenceJSON.encode(domain)
        }
        for schedule in try modelContext.fetch(FetchDescriptor<StoredSleepModeSchedule>()) {
            guard let domain = try? schedule.toDomain() else { continue }
            schedule.scheduleData = try PersistenceJSON.encode(domain)
        }

        var sleepModeOffset = 0
        while true {
            var descriptor = FetchDescriptor<StoredSleepModeSession>()
            descriptor.fetchLimit = batchSize
            descriptor.fetchOffset = sleepModeOffset
            let sessions = try modelContext.fetch(descriptor)
            if sessions.isEmpty { break }
            for session in sessions {
                await Task.yield()
                guard let domain = try? session.toDomain() else { continue }
                session.sessionData = try PersistenceJSON.encode(domain)
            }
            try modelContext.save()
            sleepModeOffset += sessions.count
        }

        // Nightly biometric summaries.
        var biometricOffset = 0
        while true {
            var descriptor = FetchDescriptor<StoredNightlyBiometricSummary>()
            descriptor.fetchLimit = batchSize
            descriptor.fetchOffset = biometricOffset
            let summaries = try modelContext.fetch(descriptor)
            if summaries.isEmpty { break }
            for summary in summaries {
                await Task.yield()
                guard let domain = try? summary.toDomain() else { continue }
                summary.samplesData = try PersistenceJSON.encode(domain.samples)
            }
            try modelContext.save()
            biometricOffset += summaries.count
        }

        // User profile — onboarding assessment answers.
        for profile in try modelContext.fetch(FetchDescriptor<StoredUserProfile>()) {
            guard
                let raw = profile.sleepAssessmentAnswersData,
                let answers = try? PersistenceJSON.decode([SleepAssessmentAnswer].self, from: raw)
            else { continue }
            profile.sleepAssessmentAnswersData = try PersistenceJSON.encode(answers)
        }

        // Protocol Formula blobs — re-encode through the convenience initializers so the
        // bytes are routed through `PersistenceJSON.encode` (which now encrypts). The
        // freshly-constructed @Model instances are never inserted into the context;
        // they're only used as a transport for the re-encoded bodyData bytes.
        for row in try modelContext.fetch(FetchDescriptor<StoredProtocolFormulaVersion>()) {
            guard let domain = try? row.toDomain(ordinalLabel: "") else { continue }
            let rewritten = try StoredProtocolFormulaVersion(domain: domain, ordinalIndex: row.ordinalIndex)
            row.bodyData = rewritten.bodyData
        }

        var nightLogOffset = 0
        while true {
            var descriptor = FetchDescriptor<StoredProtocolNightLog>()
            descriptor.fetchLimit = batchSize
            descriptor.fetchOffset = nightLogOffset
            let rows = try modelContext.fetch(descriptor)
            if rows.isEmpty { break }
            for row in rows {
                await Task.yield()
                guard let domain = try? row.toDomain() else { continue }
                let rewritten = try StoredProtocolNightLog(domain: domain)
                row.bodyData = rewritten.bodyData
            }
            try modelContext.save()
            nightLogOffset += rows.count
        }

        for row in try modelContext.fetch(FetchDescriptor<StoredProtocolBaselineSnapshot>()) {
            guard let domain = try? row.toDomain() else { continue }
            let rewritten = try StoredProtocolBaselineSnapshot(domain: domain)
            row.bodyData = rewritten.bodyData
        }

        try modelContext.save()
    }


    func fetchDataInventory() async throws -> LocalDataInventory {
        let sleepSessionCount = try modelContext.fetchCount(FetchDescriptor<StoredSleepSession>())

        var oldestDescriptor = FetchDescriptor<StoredSleepSession>(
            sortBy: [SortDescriptor(\.startDate)]
        )
        oldestDescriptor.fetchLimit = 1
        let oldestSession = try modelContext.fetch(oldestDescriptor).first

        var newestDescriptor = FetchDescriptor<StoredSleepSession>(
            sortBy: [SortDescriptor(\.startDate, order: .reverse)]
        )
        newestDescriptor.fetchLimit = 1
        let newestSession = try modelContext.fetch(newestDescriptor).first

        var contextDescriptor = FetchDescriptor<StoredSleepContextEntry>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        contextDescriptor.fetchLimit = 1
        let latestContextEntry = try modelContext.fetch(contextDescriptor).first
        let contextCount = try modelContext.fetchCount(FetchDescriptor<StoredSleepContextEntry>())
        var sleepModeSessionDescriptor = FetchDescriptor<StoredSleepModeSession>(
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        sleepModeSessionDescriptor.fetchLimit = 1
        let latestSleepModeSession = try modelContext.fetch(sleepModeSessionDescriptor).first
        let protocolBaseline = try? await fetchBaselineSnapshot()

        return LocalDataInventory(
            sleepSessionCount: sleepSessionCount,
            baselineCount: try modelContext.fetchCount(FetchDescriptor<StoredBaseline>()),
            alertCount: try modelContext.fetchCount(FetchDescriptor<StoredAlert>()),
            protocolAdherenceCount: try modelContext.fetchCount(FetchDescriptor<StoredProtocolAdherence>()),
            activityLogCount: try modelContext.fetchCount(FetchDescriptor<StoredActivityStatusLog>()),
            manualBiologyEntryCount: try modelContext.fetchCount(FetchDescriptor<StoredManualBiologyEntry>()),
            sleepModeSettingsCount: try modelContext.fetchCount(FetchDescriptor<StoredSleepModeSettings>()),
            sleepModeScheduleCount: try modelContext.fetchCount(FetchDescriptor<StoredSleepModeSchedule>()),
            sleepModeSessionCount: try modelContext.fetchCount(FetchDescriptor<StoredSleepModeSession>()),
            contextEntryCount: contextCount,
            lastContextEntryDate: latestContextEntry?.updatedAt,
            lastSleepModeSessionDate: latestSleepModeSession?.startedAt,
            oldestSessionDate: oldestSession?.startDate,
            newestSessionDate: newestSession?.startDate,
            protocolFormulaVersionCount: try modelContext.fetchCount(FetchDescriptor<StoredProtocolFormulaVersion>()),
            protocolNightLogCount: try modelContext.fetchCount(FetchDescriptor<StoredProtocolNightLog>()),
            protocolLogEditCount: try modelContext.fetchCount(FetchDescriptor<StoredProtocolLogEdit>()),
            protocolBaselineSnapshotCount: try modelContext.fetchCount(FetchDescriptor<StoredProtocolBaselineSnapshot>()),
            protocolBaselineValidNightCount: protocolBaseline?.validNightCount,
            protocolBaselineIsInsufficient: protocolBaseline?.isInsufficient
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
