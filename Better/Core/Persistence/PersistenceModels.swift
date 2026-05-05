import Foundation
import SwiftData

nonisolated enum BetterPersistenceContainerFactory {
    private static let schema = Schema([
        StoredSleepSession.self,
        StoredNightlyBiometricSummary.self,
        StoredDailyActivitySummary.self,
        StoredBaseline.self,
        StoredProtocolAdherence.self,
        StoredActivityStatusLog.self,
        StoredAlert.self,
        StoredUserProfile.self,
        StoredSyncAnchor.self,
        StoredManualBiologyEntry.self
    ])

    static func makeLiveContainer() throws -> ModelContainer {
        try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: false)
        )
    }

    static func makePreviewContainer() throws -> ModelContainer {
        try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }
}

enum PersistenceJSON {
    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    static func encode<T: Encodable>(_ value: T) throws -> Data {
        try encoder.encode(value)
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try decoder.decode(type, from: data)
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
    var sleepAssessmentAnswersData: Data?
    var createdAt: Date
    var updatedAt: Date

    init(domain: UserProfile) {
        self.id = domain.id
        self.sleepGoalHours = domain.sleepGoalHours
        self.baselineWindowDays = domain.baselineWindowDays
        self.isResearchMode = domain.isResearchMode
        self.hasCompletedOnboarding = domain.hasCompletedOnboarding
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
