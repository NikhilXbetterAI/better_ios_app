import Foundation
import SwiftData

// MARK: - Versioned schema chain
//
// Schema V1 is the original 14 models that shipped before Protocol Formula Tracking.
// Schema V2 adds the four Protocol Formula models. V1 → V2 is purely additive (new
// tables only — no field changes), so the migration is `.lightweight`.
//
// Whenever you add or modify a `@Model` class you MUST add a new versioned schema
// here and append a stage to `BetterMigrationPlan`. Never mutate `BetterSchemaV1` /
// `BetterSchemaV2` after they ship.

nonisolated enum BetterSchemaV1: VersionedSchema {
    nonisolated static var versionIdentifier: Schema.Version { .init(1, 0, 0) }
    nonisolated static var models: [any PersistentModel.Type] {
        [
            StoredSleepSession.self,
            StoredNightlyBiometricSummary.self,
            StoredDailyActivitySummary.self,
            StoredBaseline.self,
            StoredProtocolAdherence.self,
            StoredActivityStatusLog.self,
            StoredAlert.self,
            StoredUserProfile.self,
            StoredSyncAnchor.self,
            StoredManualBiologyEntry.self,
            StoredSleepContextEntry.self,
            StoredSleepModeSettings.self,
            StoredSleepModeSchedule.self,
            StoredSleepModeSession.self
        ]
    }
}

nonisolated enum BetterSchemaV2: VersionedSchema {
    nonisolated static var versionIdentifier: Schema.Version { .init(2, 0, 0) }
    nonisolated static var models: [any PersistentModel.Type] {
        BetterSchemaV1.models + [
            StoredProtocolFormulaVersion.self,
            StoredProtocolNightLog.self,
            StoredProtocolLogEdit.self,
            StoredProtocolBaselineSnapshot.self
        ]
    }
}

nonisolated enum BetterMigrationPlan: SchemaMigrationPlan {
    nonisolated static var schemas: [any VersionedSchema.Type] {
        [BetterSchemaV1.self, BetterSchemaV2.self]
    }
    nonisolated static var stages: [MigrationStage] {
        [.lightweight(fromVersion: BetterSchemaV1.self, toVersion: BetterSchemaV2.self)]
    }
}

nonisolated enum BetterPersistenceContainerFactory {
    private static var currentSchema: Schema { Schema(versionedSchema: BetterSchemaV2.self) }

    /// Builds the live SwiftData container with `BetterMigrationPlan` wired in.
    ///
    /// Unlike the pre-V2 implementation, this no longer silently wipes the store on init
    /// failure. User-entered Protocol Formula data isn't recoverable from HealthKit, so a
    /// silent reset would destroy work. On migration failure the error propagates and the
    /// app surfaces a non-destructive blocking recovery state on next launch (the user
    /// must opt into "Reset all local data" from Settings).
    static func makeLiveContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: false)
        let container = try ModelContainer(
            for: currentSchema,
            migrationPlan: BetterMigrationPlan.self,
            configurations: config
        )
        applyFileProtection(to: container.configurations.first?.url)
        return container
    }

    static func makePreviewContainer() throws -> ModelContainer {
        try ModelContainer(
            for: currentSchema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    /// Upgrades SQLite store files to FileProtectionType.completeUnlessOpen.
    ///
    /// We intentionally use completeUnlessOpen (not .complete) because background tasks
    /// (BGAppRefreshTask) fire while the device is locked. With .complete the SQLite
    /// WAL files become inaccessible mid-write, corrupting them and crashing the next
    /// foreground open. completeUnlessOpen keeps already-open files accessible across
    /// a lock event while still protecting files that are closed at rest.
    private static func applyFileProtection(to storeURL: URL?) {
        guard let storeURL else { return }
        let fileManager = FileManager.default
        // SQLite stores consist of up to three files.
        let candidatePaths = [
            storeURL.path,
            storeURL.path + "-shm",
            storeURL.path + "-wal"
        ]
        for path in candidatePaths {
            guard fileManager.fileExists(atPath: path) else { continue }
            try? fileManager.setAttributes(
                [.protectionKey: FileProtectionType.completeUnlessOpen],
                ofItemAtPath: path
            )
        }
    }

}

enum PersistenceJSON {
    /// Encodes value to JSON then encrypts the bytes with AES-256-GCM.
    /// If encryption is unavailable (e.g. Keychain locked), the plain JSON is
    /// returned so writes never fail silently — the store's own file protection
    /// still applies.
    nonisolated static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let jsonData = try encoder.encode(value)
        return try EncryptionService.shared.encrypt(jsonData)
    }

    /// Decrypts the data and decodes it.  If decryption fails the data is
    /// treated as plain JSON — this provides transparent migration from the
    /// pre-encryption storage format without a schema change.
    nonisolated static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let decrypted = try? EncryptionService.shared.decrypt(data),
           let value = try? decoder.decode(type, from: decrypted) {
            return value
        }
        return try decoder.decode(type, from: data)
    }
}

@Model
final class StoredSleepSession {
    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var sleepDateKey: String
    var startDate: Date
    var endDate: Date
    var inBedStartDate: Date?
    var inBedEndDate: Date?
    var totalInBedTime: Double
    var totalSleepTime: Double
    var awakeDuration: Double
    var coreDuration: Double
    var deepDuration: Double
    var remDuration: Double
    var unspecifiedSleepDuration: Double
    var sleepLatency: Double
    var waso: Double
    var efficiency: Double
    var dataQualityRawValue: String
    var qualityScoreData: Data
    var stagesData: Data
    var sourcesData: Data
    var biometricsData: Data?

    init(
        id: UUID,
        sleepDateKey: String,
        startDate: Date,
        endDate: Date,
        inBedStartDate: Date?,
        inBedEndDate: Date?,
        totalInBedTime: Double,
        totalSleepTime: Double,
        awakeDuration: Double,
        coreDuration: Double,
        deepDuration: Double,
        remDuration: Double,
        unspecifiedSleepDuration: Double,
        sleepLatency: Double,
        waso: Double,
        efficiency: Double,
        dataQualityRawValue: String,
        qualityScoreData: Data,
        stagesData: Data,
        sourcesData: Data,
        biometricsData: Data?
    ) {
        self.id = id
        self.sleepDateKey = sleepDateKey
        self.startDate = startDate
        self.endDate = endDate
        self.inBedStartDate = inBedStartDate
        self.inBedEndDate = inBedEndDate
        self.totalInBedTime = totalInBedTime
        self.totalSleepTime = totalSleepTime
        self.awakeDuration = awakeDuration
        self.coreDuration = coreDuration
        self.deepDuration = deepDuration
        self.remDuration = remDuration
        self.unspecifiedSleepDuration = unspecifiedSleepDuration
        self.sleepLatency = sleepLatency
        self.waso = waso
        self.efficiency = efficiency
        self.dataQualityRawValue = dataQualityRawValue
        self.qualityScoreData = qualityScoreData
        self.stagesData = stagesData
        self.sourcesData = sourcesData
        self.biometricsData = biometricsData
    }

    convenience init(domain: SleepSession) throws {
        let biometricsData: Data?
        if let biometrics = domain.biometrics {
            biometricsData = try PersistenceJSON.encode(biometrics)
        } else {
            biometricsData = nil
        }

        self.init(
            id: domain.id,
            sleepDateKey: domain.sleepDateKey,
            startDate: domain.startDate,
            endDate: domain.endDate,
            inBedStartDate: domain.inBedStartDate,
            inBedEndDate: domain.inBedEndDate,
            totalInBedTime: domain.totalInBedTime,
            totalSleepTime: domain.totalSleepTime,
            awakeDuration: domain.awakeDuration,
            coreDuration: domain.coreDuration,
            deepDuration: domain.deepDuration,
            remDuration: domain.remDuration,
            unspecifiedSleepDuration: domain.unspecifiedSleepDuration,
            sleepLatency: domain.sleepLatency,
            waso: domain.waso,
            efficiency: domain.efficiency,
            dataQualityRawValue: domain.dataQuality.rawValue,
            qualityScoreData: try PersistenceJSON.encode(domain.qualityScore),
            stagesData: try PersistenceJSON.encode(domain.stages),
            sourcesData: try PersistenceJSON.encode(domain.sources),
            biometricsData: biometricsData
        )
    }

    func toDomain() throws -> SleepSession {
        let biometrics: NightlyBiometricSummary?
        if let biometricsData {
            biometrics = try PersistenceJSON.decode(NightlyBiometricSummary.self, from: biometricsData)
        } else {
            biometrics = nil
        }

        return SleepSession(
            id: id,
            sleepDateKey: sleepDateKey,
            startDate: startDate,
            endDate: endDate,
            inBedStartDate: inBedStartDate,
            inBedEndDate: inBedEndDate,
            stages: try PersistenceJSON.decode([SleepStage].self, from: stagesData),
            sources: try PersistenceJSON.decode([SleepSource].self, from: sourcesData),
            dataQuality: SleepDataQuality(rawValue: dataQualityRawValue) ?? .noData,
            totalInBedTime: totalInBedTime,
            totalSleepTime: totalSleepTime,
            awakeDuration: awakeDuration,
            coreDuration: coreDuration,
            deepDuration: deepDuration,
            remDuration: remDuration,
            unspecifiedSleepDuration: unspecifiedSleepDuration,
            sleepLatency: sleepLatency,
            waso: waso,
            efficiency: efficiency,
            qualityScore: try PersistenceJSON.decode(SleepQualityScore.self, from: qualityScoreData),
            biometrics: biometrics
        )
    }
}

@Model
final class StoredNightlyBiometricSummary {
    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var sleepSessionID: UUID
    var sleepDateKey: String
    var samplesData: Data
    var heartRateAverage: Double?
    var heartRateMinimum: Double?
    var heartRateMaximum: Double?
    var hrvAverage: Double?
    var hrvMedian: Double?
    var oxygenSaturationAverage: Double?
    var oxygenSaturationMinimum: Double?
    var respiratoryRateAverage: Double?

    init(
        id: UUID,
        sleepSessionID: UUID,
        sleepDateKey: String,
        samplesData: Data,
        heartRateAverage: Double?,
        heartRateMinimum: Double?,
        heartRateMaximum: Double?,
        hrvAverage: Double?,
        hrvMedian: Double?,
        oxygenSaturationAverage: Double?,
        oxygenSaturationMinimum: Double?,
        respiratoryRateAverage: Double?
    ) {
        self.id = id
        self.sleepSessionID = sleepSessionID
        self.sleepDateKey = sleepDateKey
        self.samplesData = samplesData
        self.heartRateAverage = heartRateAverage
        self.heartRateMinimum = heartRateMinimum
        self.heartRateMaximum = heartRateMaximum
        self.hrvAverage = hrvAverage
        self.hrvMedian = hrvMedian
        self.oxygenSaturationAverage = oxygenSaturationAverage
        self.oxygenSaturationMinimum = oxygenSaturationMinimum
        self.respiratoryRateAverage = respiratoryRateAverage
    }

    convenience init(domain: NightlyBiometricSummary) throws {
        self.init(
            id: domain.id,
            sleepSessionID: domain.sleepSessionID,
            sleepDateKey: domain.sleepDateKey,
            samplesData: try PersistenceJSON.encode(domain.samples),
            heartRateAverage: domain.heartRateAverage,
            heartRateMinimum: domain.heartRateMinimum,
            heartRateMaximum: domain.heartRateMaximum,
            hrvAverage: domain.hrvAverage,
            hrvMedian: domain.hrvMedian,
            oxygenSaturationAverage: domain.oxygenSaturationAverage,
            oxygenSaturationMinimum: domain.oxygenSaturationMinimum,
            respiratoryRateAverage: domain.respiratoryRateAverage
        )
    }

    func toDomain() throws -> NightlyBiometricSummary {
        NightlyBiometricSummary(
            id: id,
            sleepSessionID: sleepSessionID,
            sleepDateKey: sleepDateKey,
            samples: try PersistenceJSON.decode([BiometricSample].self, from: samplesData),
            heartRateAverage: heartRateAverage,
            heartRateMinimum: heartRateMinimum,
            heartRateMaximum: heartRateMaximum,
            hrvAverage: hrvAverage,
            hrvMedian: hrvMedian,
            oxygenSaturationAverage: oxygenSaturationAverage,
            oxygenSaturationMinimum: oxygenSaturationMinimum,
            respiratoryRateAverage: respiratoryRateAverage
        )
    }
}

@Model
final class StoredDailyActivitySummary {
    @Attribute(.unique) var dateKey: String
    var steps: Double?
    var activeEnergy: Double?
    var exerciseMinutes: Double?
    var standHours: Double?
    var flights: Double?
    var distanceMeters: Double?
    var generatedAt: Date

    init(domain: DailyActivitySummary) {
        self.dateKey = domain.dateKey
        self.steps = domain.steps
        self.activeEnergy = domain.activeEnergy
        self.exerciseMinutes = domain.exerciseMinutes
        self.standHours = domain.standHours
        self.flights = domain.flights
        self.distanceMeters = domain.distanceMeters
        self.generatedAt = domain.generatedAt
    }

    func toDomain() -> DailyActivitySummary {
        DailyActivitySummary(
            dateKey: dateKey,
            steps: steps,
            activeEnergy: activeEnergy,
            exerciseMinutes: exerciseMinutes,
            standHours: standHours,
            flights: flights,
            distanceMeters: distanceMeters,
            generatedAt: generatedAt
        )
    }
}

@Model
final class StoredBaseline {
    @Attribute(.unique) var id: UUID
    var windowDays: Int
    var generatedAt: Date
    var validNights: Int
    var totalSleepAverage: Double
    var totalSleepStandardDeviation: Double
    var remAverage: Double
    var remStandardDeviation: Double
    var deepAverage: Double
    var deepStandardDeviation: Double
    var efficiencyAverage: Double
    var efficiencyStandardDeviation: Double
    var wasoAverage: Double
    var wasoStandardDeviation: Double
    var latencyAverage: Double
    var latencyStandardDeviation: Double
    var hrvAverage: Double
    var hrvStandardDeviation: Double
    var respiratoryRateAverage: Double
    var respiratoryRateStandardDeviation: Double
    var oxygenSaturationAverage: Double
    var oxygenSaturationStandardDeviation: Double
    var bedtimeMinuteAverage: Double
    var bedtimeMinuteStandardDeviation: Double
    var wakeMinuteAverage: Double
    var wakeMinuteStandardDeviation: Double

    init(domain: SleepBaseline) {
        self.id = domain.id
        self.windowDays = domain.windowDays
        self.generatedAt = domain.generatedAt
        self.validNights = domain.validNights
        self.totalSleepAverage = domain.totalSleepAverage
        self.totalSleepStandardDeviation = domain.totalSleepStandardDeviation
        self.remAverage = domain.remAverage
        self.remStandardDeviation = domain.remStandardDeviation
        self.deepAverage = domain.deepAverage
        self.deepStandardDeviation = domain.deepStandardDeviation
        self.efficiencyAverage = domain.efficiencyAverage
        self.efficiencyStandardDeviation = domain.efficiencyStandardDeviation
        self.wasoAverage = domain.wasoAverage
        self.wasoStandardDeviation = domain.wasoStandardDeviation
        self.latencyAverage = domain.latencyAverage
        self.latencyStandardDeviation = domain.latencyStandardDeviation
        self.hrvAverage = domain.hrvAverage
        self.hrvStandardDeviation = domain.hrvStandardDeviation
        self.respiratoryRateAverage = domain.respiratoryRateAverage
        self.respiratoryRateStandardDeviation = domain.respiratoryRateStandardDeviation
        self.oxygenSaturationAverage = domain.oxygenSaturationAverage
        self.oxygenSaturationStandardDeviation = domain.oxygenSaturationStandardDeviation
        self.bedtimeMinuteAverage = domain.bedtimeMinuteAverage
        self.bedtimeMinuteStandardDeviation = domain.bedtimeMinuteStandardDeviation
        self.wakeMinuteAverage = domain.wakeMinuteAverage
        self.wakeMinuteStandardDeviation = domain.wakeMinuteStandardDeviation
    }

    func toDomain() -> SleepBaseline {
        SleepBaseline(
            id: id,
            windowDays: windowDays,
            generatedAt: generatedAt,
            validNights: validNights,
            totalSleepAverage: totalSleepAverage,
            totalSleepStandardDeviation: totalSleepStandardDeviation,
            remAverage: remAverage,
            remStandardDeviation: remStandardDeviation,
            deepAverage: deepAverage,
            deepStandardDeviation: deepStandardDeviation,
            efficiencyAverage: efficiencyAverage,
            efficiencyStandardDeviation: efficiencyStandardDeviation,
            wasoAverage: wasoAverage,
            wasoStandardDeviation: wasoStandardDeviation,
            latencyAverage: latencyAverage,
            latencyStandardDeviation: latencyStandardDeviation,
            hrvAverage: hrvAverage,
            hrvStandardDeviation: hrvStandardDeviation,
            respiratoryRateAverage: respiratoryRateAverage,
            respiratoryRateStandardDeviation: respiratoryRateStandardDeviation,
            oxygenSaturationAverage: oxygenSaturationAverage,
            oxygenSaturationStandardDeviation: oxygenSaturationStandardDeviation,
            bedtimeMinuteAverage: bedtimeMinuteAverage,
            bedtimeMinuteStandardDeviation: bedtimeMinuteStandardDeviation,
            wakeMinuteAverage: wakeMinuteAverage,
            wakeMinuteStandardDeviation: wakeMinuteStandardDeviation
        )
    }
}

@Model
final class StoredProtocolAdherence {
    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var uniqueKey: String
    var protocolID: String
    var dateKey: String
    var taken: Bool
    var takenAt: Date?
    var note: String?
    var createdAt: Date
    var updatedAt: Date

    init(domain: ProtocolAdherence) {
        self.id = domain.id
        self.uniqueKey = "\(domain.protocolID)|\(domain.dateKey)"
        self.protocolID = domain.protocolID
        self.dateKey = domain.dateKey
        self.taken = domain.taken
        self.takenAt = domain.takenAt
        self.note = domain.note
        self.createdAt = domain.createdAt
        self.updatedAt = domain.updatedAt
    }

    func toDomain() -> ProtocolAdherence {
        ProtocolAdherence(
            id: id,
            protocolID: protocolID,
            dateKey: dateKey,
            taken: taken,
            takenAt: takenAt,
            note: note,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

@Model
final class StoredActivityStatusLog {
    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var dateKey: String
    var statusRawValue: String
    var note: String?
    var createdAt: Date
    var updatedAt: Date

    init(domain: ActivityStatusLog) {
        self.id = domain.id
        self.dateKey = domain.dateKey
        self.statusRawValue = domain.status.rawValue
        self.note = domain.note
        self.createdAt = domain.createdAt
        self.updatedAt = domain.updatedAt
    }

    func toDomain() -> ActivityStatusLog {
        ActivityStatusLog(
            id: id,
            dateKey: dateKey,
            status: UserActivityStatus(rawValue: statusRawValue) ?? .active,
            note: note,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

@Model
final class StoredAlert {
    @Attribute(.unique) var id: UUID
    var kindRawValue: String
    var title: String
    var body: String
    var sleepDateKey: String?
    var severity: Int
    var isRead: Bool
    var createdAt: Date
    var readAt: Date?

    init(domain: SleepAlert) {
        self.id = domain.id
        self.kindRawValue = domain.kind.rawValue
        self.title = domain.title
        self.body = domain.body
        self.sleepDateKey = domain.sleepDateKey
        self.severity = domain.severity
        self.isRead = domain.isRead
        self.createdAt = domain.createdAt
        self.readAt = domain.readAt
    }

    func toDomain() -> SleepAlert {
        SleepAlert(
            id: id,
            kind: SleepAlertKind(rawValue: kindRawValue) ?? .analysisReady,
            title: title,
            body: body,
            sleepDateKey: sleepDateKey,
            severity: severity,
            isRead: isRead,
            createdAt: createdAt,
            readAt: readAt
        )
    }
}

@Model
final class StoredUserProfile {
    @Attribute(.unique) var id: UUID
    var sleepGoalHours: Double
    var baselineWindowDays: Int
    var isResearchMode: Bool
    var hasCompletedOnboarding: Bool
    var displayName: String?
    var sleepAssessmentAnswersData: Data?
    var createdAt: Date
    var updatedAt: Date

    init(domain: UserProfile) {
        self.id = domain.id
        self.sleepGoalHours = domain.sleepGoalHours
        self.baselineWindowDays = domain.baselineWindowDays
        self.isResearchMode = domain.isResearchMode
        self.hasCompletedOnboarding = domain.hasCompletedOnboarding
        self.displayName = domain.displayName
        self.sleepAssessmentAnswersData = try? PersistenceJSON.encode(domain.sleepAssessmentAnswers)
        self.createdAt = domain.createdAt
        self.updatedAt = domain.updatedAt
    }

    func toDomain() -> UserProfile {
        let answers = sleepAssessmentAnswersData
            .flatMap { try? PersistenceJSON.decode([SleepAssessmentAnswer].self, from: $0) } ?? []
        return UserProfile(
            id: id,
            sleepGoalHours: sleepGoalHours,
            baselineWindowDays: baselineWindowDays,
            isResearchMode: isResearchMode,
            hasCompletedOnboarding: hasCompletedOnboarding,
            displayName: displayName,
            sleepAssessmentAnswers: answers,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

@Model
final class StoredSyncAnchor {
    @Attribute(.unique) var typeIdentifier: String
    var anchorData: Data?
    var updatedAt: Date

    init(typeIdentifier: String, anchorData: Data?, updatedAt: Date = Date()) {
        self.typeIdentifier = typeIdentifier
        self.anchorData = anchorData
        self.updatedAt = updatedAt
    }
}

@Model
final class StoredManualBiologyEntry {
    @Attribute(.unique) var id: UUID
    /// One entry per metric kind — stores only the most-recent manual value.
    @Attribute(.unique) var kindRawValue: String
    var value: Double
    var enteredAt: Date

    init(domain: ManualBiologyEntry) {
        self.id = domain.id
        self.kindRawValue = domain.kind.rawValue
        self.value = domain.value
        self.enteredAt = domain.enteredAt
    }

    func toDomain() -> ManualBiologyEntry? {
        guard let kind = BiologyMetricKind(rawValue: kindRawValue) else { return nil }
        return ManualBiologyEntry(id: id, kind: kind, value: value, enteredAt: enteredAt)
    }
}

/// Stores one nightly sleep context entry.
/// The entire `SleepContextEntry` value (including all Bool? fields) is
/// encoded as an encrypted JSON blob so the tristate semantics are preserved.
@Model
final class StoredSleepContextEntry {
    @Attribute(.unique) var id: UUID
    /// Formatted as `"YYYY-MM-DD"` — one entry per sleep date.
    @Attribute(.unique) var sleepDateKey: String
    var entryData: Data
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID,
        sleepDateKey: String,
        entryData: Data,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id          = id
        self.sleepDateKey = sleepDateKey
        self.entryData   = entryData
        self.createdAt   = createdAt
        self.updatedAt   = updatedAt
    }

    convenience init(domain: SleepContextEntry) throws {
        self.init(
            id: domain.id,
            sleepDateKey: domain.sleepDateKey,
            entryData: try PersistenceJSON.encode(domain),
            createdAt: domain.createdAt,
            updatedAt: domain.updatedAt
        )
    }

    func toDomain() throws -> SleepContextEntry {
        try PersistenceJSON.decode(SleepContextEntry.self, from: entryData)
    }
}

@Model
final class StoredSleepModeSettings {
    @Attribute(.unique) var id: UUID
    var settingsData: Data
    var updatedAt: Date

    init(id: UUID, settingsData: Data, updatedAt: Date) {
        self.id = id
        self.settingsData = settingsData
        self.updatedAt = updatedAt
    }

    convenience init(domain: SleepModeSettings) throws {
        self.init(
            id: domain.id,
            settingsData: try PersistenceJSON.encode(domain),
            updatedAt: domain.updatedAt
        )
    }

    func toDomain() throws -> SleepModeSettings {
        try PersistenceJSON.decode(SleepModeSettings.self, from: settingsData)
    }
}

@Model
final class StoredSleepModeSchedule {
    @Attribute(.unique) var id: UUID
    var isEnabled: Bool
    var scheduleData: Data
    var updatedAt: Date

    init(id: UUID, isEnabled: Bool, scheduleData: Data, updatedAt: Date) {
        self.id = id
        self.isEnabled = isEnabled
        self.scheduleData = scheduleData
        self.updatedAt = updatedAt
    }

    convenience init(domain: SleepModeSchedule) throws {
        self.init(
            id: domain.id,
            isEnabled: domain.isEnabled,
            scheduleData: try PersistenceJSON.encode(domain),
            updatedAt: domain.updatedAt
        )
    }

    func toDomain() throws -> SleepModeSchedule {
        try PersistenceJSON.decode(SleepModeSchedule.self, from: scheduleData)
    }
}

@Model
final class StoredSleepModeSession {
    @Attribute(.unique) var id: UUID
    var sleepDateKey: String
    var startedAt: Date
    var endedAt: Date?
    var sessionData: Data
    var updatedAt: Date

    init(
        id: UUID,
        sleepDateKey: String,
        startedAt: Date,
        endedAt: Date?,
        sessionData: Data,
        updatedAt: Date
    ) {
        self.id = id
        self.sleepDateKey = sleepDateKey
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.sessionData = sessionData
        self.updatedAt = updatedAt
    }

    convenience init(domain: SleepModeSession) throws {
        self.init(
            id: domain.id,
            sleepDateKey: domain.sleepDateKey,
            startedAt: domain.startedAt,
            endedAt: domain.endedAt,
            sessionData: try PersistenceJSON.encode(domain),
            updatedAt: domain.updatedAt
        )
    }

    func toDomain() throws -> SleepModeSession {
        try PersistenceJSON.decode(SleepModeSession.self, from: sessionData)
    }
}

// MARK: - Protocol Formula Tracking (schema V2)

@Model
final class StoredProtocolFormulaVersion {
    @Attribute(.unique) var id: UUID
    var displayLabel: String
    /// Always indexed (sortable) — derived ordinal value computed by the repository
    /// on read. Stored so SQLite-side sorts remain cheap.
    var ordinalIndex: Int
    var shippedOn: Date
    var colorHex: String
    var isActive: Bool
    var isImportedPlaceholder: Bool
    var archivedAt: Date?
    /// Encrypted JSON blob containing `formulaText` + `components` + timestamps.
    var bodyData: Data
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID,
        displayLabel: String,
        ordinalIndex: Int,
        shippedOn: Date,
        colorHex: String,
        isActive: Bool,
        isImportedPlaceholder: Bool,
        archivedAt: Date?,
        bodyData: Data,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.displayLabel = displayLabel
        self.ordinalIndex = ordinalIndex
        self.shippedOn = shippedOn
        self.colorHex = colorHex
        self.isActive = isActive
        self.isImportedPlaceholder = isImportedPlaceholder
        self.archivedAt = archivedAt
        self.bodyData = bodyData
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    convenience init(domain: ProtocolFormulaVersion, ordinalIndex: Int) throws {
        // The blob stores the version-detail fields that may evolve over time so we don't
        // need a schema migration every time we add an optional field to the domain type.
        let body = ProtocolFormulaVersionBody(
            formulaText: domain.formulaText,
            components: domain.components
        )
        self.init(
            id: domain.id,
            displayLabel: domain.displayLabel,
            ordinalIndex: ordinalIndex,
            shippedOn: domain.shippedOn,
            colorHex: domain.colorHex,
            isActive: domain.isActive,
            isImportedPlaceholder: domain.isImportedPlaceholder,
            archivedAt: domain.archivedAt,
            bodyData: try PersistenceJSON.encode(body),
            createdAt: domain.createdAt,
            updatedAt: domain.updatedAt
        )
    }

    func toDomain(ordinalLabel: String) throws -> ProtocolFormulaVersion {
        let body = try PersistenceJSON.decode(ProtocolFormulaVersionBody.self, from: bodyData)
        return ProtocolFormulaVersion(
            id: id,
            displayLabel: displayLabel,
            ordinalLabel: ordinalLabel,
            formulaText: body.formulaText,
            components: body.components,
            shippedOn: shippedOn,
            colorHex: colorHex,
            isActive: isActive,
            isImportedPlaceholder: isImportedPlaceholder,
            archivedAt: archivedAt,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

/// Encrypted blob layout for the parts of `ProtocolFormulaVersion` that don't need their
/// own SQLite columns. Schema-stable — adding a field here is a JSON migration, not a
/// SwiftData migration, thanks to `PersistenceJSON.decode`'s plain-JSON fallback.
nonisolated private struct ProtocolFormulaVersionBody: Codable, Hashable, Sendable {
    var formulaText: String
    var components: [ProtocolFormulaComponent]
}

@Model
final class StoredProtocolNightLog {
    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var sleepDateKey: String
    /// Stringified UUID — SwiftData predicates can't compare UUIDs across `@Model` boundaries
    /// without a lot of friction, so we index the string form.
    var versionIDString: String
    var statusRawValue: String
    var takenAt: Date?
    var note: String?
    var formulaSnapshotHash: String
    /// Encrypted JSON blob containing `addins`.
    var bodyData: Data
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID,
        sleepDateKey: String,
        versionIDString: String,
        statusRawValue: String,
        takenAt: Date?,
        note: String?,
        formulaSnapshotHash: String,
        bodyData: Data,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.sleepDateKey = sleepDateKey
        self.versionIDString = versionIDString
        self.statusRawValue = statusRawValue
        self.takenAt = takenAt
        self.note = note
        self.formulaSnapshotHash = formulaSnapshotHash
        self.bodyData = bodyData
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    convenience init(domain: ProtocolNightLog) throws {
        let body = ProtocolNightLogBody(addins: domain.addins)
        self.init(
            id: domain.id,
            sleepDateKey: domain.sleepDateKey,
            versionIDString: domain.versionID.uuidString,
            statusRawValue: domain.status.rawValue,
            takenAt: domain.takenAt,
            note: domain.note,
            formulaSnapshotHash: domain.formulaSnapshotHash,
            bodyData: try PersistenceJSON.encode(body),
            createdAt: domain.createdAt,
            updatedAt: domain.updatedAt
        )
    }

    func toDomain() throws -> ProtocolNightLog {
        let body = try PersistenceJSON.decode(ProtocolNightLogBody.self, from: bodyData)
        return ProtocolNightLog(
            id: id,
            sleepDateKey: sleepDateKey,
            versionID: UUID(uuidString: versionIDString) ?? UUID(),
            status: ProtocolFormulaNightStatus(rawValue: statusRawValue) ?? .unknown,
            addins: body.addins,
            takenAt: takenAt,
            note: note,
            formulaSnapshotHash: formulaSnapshotHash,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

nonisolated private struct ProtocolNightLogBody: Codable, Hashable, Sendable {
    var addins: [ProtocolFormulaComponent]
}

@Model
final class StoredProtocolLogEdit {
    @Attribute(.unique) var id: UUID
    var nightLogID: UUID
    var sleepDateKey: String
    var beforeData: Data?
    var afterData: Data
    var editedAt: Date
    var reason: String?

    init(domain: ProtocolLogEdit) {
        self.id = domain.id
        self.nightLogID = domain.nightLogID
        self.sleepDateKey = domain.sleepDateKey
        self.beforeData = domain.beforeData
        self.afterData = domain.afterData
        self.editedAt = domain.editedAt
        self.reason = domain.reason
    }

    func toDomain() -> ProtocolLogEdit {
        ProtocolLogEdit(
            id: id,
            nightLogID: nightLogID,
            sleepDateKey: sleepDateKey,
            beforeData: beforeData,
            afterData: afterData,
            editedAt: editedAt,
            reason: reason
        )
    }
}

@Model
final class StoredProtocolBaselineSnapshot {
    @Attribute(.unique) var id: UUID
    var frozenAt: Date
    var windowStart: Date
    var windowEnd: Date
    var validNightCount: Int
    var isInsufficient: Bool
    /// Encrypted JSON blob with the means, stds and continuity distribution.
    var bodyData: Data

    init(
        id: UUID,
        frozenAt: Date,
        windowStart: Date,
        windowEnd: Date,
        validNightCount: Int,
        isInsufficient: Bool,
        bodyData: Data
    ) {
        self.id = id
        self.frozenAt = frozenAt
        self.windowStart = windowStart
        self.windowEnd = windowEnd
        self.validNightCount = validNightCount
        self.isInsufficient = isInsufficient
        self.bodyData = bodyData
    }

    convenience init(domain: ProtocolBaselineSnapshot) throws {
        let body = ProtocolBaselineSnapshotBody(
            meanRestorativeMin: domain.meanRestorativeMin,
            stdRestorativeMin: domain.stdRestorativeMin,
            meanRestorativePctOfInBed: domain.meanRestorativePctOfInBed,
            stdRestorativePctOfInBed: domain.stdRestorativePctOfInBed,
            meanLongestRestorativeBlockMin: domain.meanLongestRestorativeBlockMin,
            stdLongestRestorativeBlockMin: domain.stdLongestRestorativeBlockMin,
            continuityCategoryDistribution: domain.continuityCategoryDistribution,
            meanDeepMin: domain.meanDeepMin,
            stdDeepMin: domain.stdDeepMin,
            meanRemMin: domain.meanRemMin,
            stdRemMin: domain.stdRemMin,
            meanAwakeMin: domain.meanAwakeMin,
            stdAwakeMin: domain.stdAwakeMin,
            meanTotalSleepMin: domain.meanTotalSleepMin,
            stdTotalSleepMin: domain.stdTotalSleepMin,
            meanLatencyMin: domain.meanLatencyMin,
            stdLatencyMin: domain.stdLatencyMin,
            meanSleepScore: domain.meanSleepScore,
            stdSleepScore: domain.stdSleepScore
        )
        self.init(
            id: domain.id,
            frozenAt: domain.frozenAt,
            windowStart: domain.windowStart,
            windowEnd: domain.windowEnd,
            validNightCount: domain.validNightCount,
            isInsufficient: domain.isInsufficient,
            bodyData: try PersistenceJSON.encode(body)
        )
    }

    func toDomain() throws -> ProtocolBaselineSnapshot {
        let body = try PersistenceJSON.decode(ProtocolBaselineSnapshotBody.self, from: bodyData)
        return ProtocolBaselineSnapshot(
            id: id,
            frozenAt: frozenAt,
            windowStart: windowStart,
            windowEnd: windowEnd,
            validNightCount: validNightCount,
            meanRestorativeMin: body.meanRestorativeMin,
            stdRestorativeMin: body.stdRestorativeMin,
            meanRestorativePctOfInBed: body.meanRestorativePctOfInBed,
            stdRestorativePctOfInBed: body.stdRestorativePctOfInBed,
            meanLongestRestorativeBlockMin: body.meanLongestRestorativeBlockMin,
            stdLongestRestorativeBlockMin: body.stdLongestRestorativeBlockMin,
            continuityCategoryDistribution: body.continuityCategoryDistribution,
            isInsufficient: isInsufficient,
            meanDeepMin: body.meanDeepMin,
            stdDeepMin: body.stdDeepMin,
            meanRemMin: body.meanRemMin,
            stdRemMin: body.stdRemMin,
            meanAwakeMin: body.meanAwakeMin,
            stdAwakeMin: body.stdAwakeMin,
            meanTotalSleepMin: body.meanTotalSleepMin,
            stdTotalSleepMin: body.stdTotalSleepMin,
            meanLatencyMin: body.meanLatencyMin,
            stdLatencyMin: body.stdLatencyMin,
            meanSleepScore: body.meanSleepScore,
            stdSleepScore: body.stdSleepScore
        )
    }
}

nonisolated private struct ProtocolBaselineSnapshotBody: Codable, Hashable, Sendable {
    var meanRestorativeMin: Double?
    var stdRestorativeMin: Double?
    var meanRestorativePctOfInBed: Double?
    var stdRestorativePctOfInBed: Double?
    var meanLongestRestorativeBlockMin: Double?
    var stdLongestRestorativeBlockMin: Double?
    var continuityCategoryDistribution: [SleepContinuityCategory: Double]
    var meanDeepMin: Double?
    var stdDeepMin: Double?
    var meanRemMin: Double?
    var stdRemMin: Double?
    var meanAwakeMin: Double?
    var stdAwakeMin: Double?
    var meanTotalSleepMin: Double?
    var stdTotalSleepMin: Double?
    var meanLatencyMin: Double?
    var stdLatencyMin: Double?
    var meanSleepScore: Double?
    var stdSleepScore: Double?
}
