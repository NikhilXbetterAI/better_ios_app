import Foundation

enum SleepStageType: String, Codable, CaseIterable, Hashable, Sendable, Identifiable {
    case inBed
    case unspecified
    case awake
    case core
    case deep
    case rem

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .inBed:
            "In Bed"
        case .unspecified:
            "Unspecified"
        case .awake:
            "Awake"
        case .core:
            "Core"
        case .deep:
            "Deep"
        case .rem:
            "REM"
        }
    }

    var isSleep: Bool {
        switch self {
        case .inBed, .awake:
            false
        case .unspecified, .core, .deep, .rem:
            true
        }
    }
}

enum SleepDataQuality: String, Codable, CaseIterable, Hashable, Sendable, Identifiable {
    case detailedStages
    case unspecifiedSleepOnly
    case inBedOnly
    case mixedSources
    case noData

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .detailedStages:
            "Detailed stages"
        case .unspecifiedSleepOnly:
            "Unspecified sleep only"
        case .inBedOnly:
            "In bed only"
        case .mixedSources:
            "Mixed sources"
        case .noData:
            "No data"
        }
    }
}

struct SleepSource: Codable, Hashable, Sendable, Identifiable {
    var id: UUID = UUID()
    var name: String
    var bundleIdentifier: String?
    var productType: String?
    var operatingSystemVersion: String?
    var isManualEntry: Bool

    init(
        id: UUID = UUID(),
        name: String,
        bundleIdentifier: String? = nil,
        productType: String? = nil,
        operatingSystemVersion: String? = nil,
        isManualEntry: Bool = false
    ) {
        self.id = id
        self.name = name
        self.bundleIdentifier = bundleIdentifier
        self.productType = productType
        self.operatingSystemVersion = operatingSystemVersion
        self.isManualEntry = isManualEntry
    }
}

struct SleepStage: Codable, Hashable, Sendable, Identifiable {
    var id: UUID = UUID()
    var type: SleepStageType
    var startDate: Date
    var endDate: Date
    var source: SleepSource?

    init(
        id: UUID = UUID(),
        type: SleepStageType,
        startDate: Date,
        endDate: Date,
        source: SleepSource? = nil
    ) {
        self.id = id
        self.type = type
        self.startDate = startDate
        self.endDate = endDate
        self.source = source
    }
}

struct SleepQualityScore: Codable, Hashable, Sendable {
    var overall: Double
    var durationScore: Double
    var efficiencyScore: Double
    var remScore: Double
    var deepScore: Double
    var isPartial: Bool

    static let zero = SleepQualityScore(
        overall: 0,
        durationScore: 0,
        efficiencyScore: 0,
        remScore: 0,
        deepScore: 0,
        isPartial: false
    )
}

struct SleepSession: Codable, Hashable, Sendable, Identifiable {
    var id: UUID
    var sleepDateKey: String
    var startDate: Date
    var endDate: Date
    var inBedStartDate: Date?
    var inBedEndDate: Date?
    var stages: [SleepStage]
    var sources: [SleepSource]
    var dataQuality: SleepDataQuality
    var totalInBedTime: TimeInterval
    var totalSleepTime: TimeInterval
    var awakeDuration: TimeInterval
    var coreDuration: TimeInterval
    var deepDuration: TimeInterval
    var remDuration: TimeInterval
    var unspecifiedSleepDuration: TimeInterval
    var sleepLatency: TimeInterval
    var waso: TimeInterval
    var efficiency: Double
    var qualityScore: SleepQualityScore
    var biometrics: NightlyBiometricSummary?

    init(
        id: UUID = UUID(),
        sleepDateKey: String,
        startDate: Date,
        endDate: Date,
        inBedStartDate: Date? = nil,
        inBedEndDate: Date? = nil,
        stages: [SleepStage] = [],
        sources: [SleepSource] = [],
        dataQuality: SleepDataQuality = .noData,
        totalInBedTime: TimeInterval = 0,
        totalSleepTime: TimeInterval = 0,
        awakeDuration: TimeInterval = 0,
        coreDuration: TimeInterval = 0,
        deepDuration: TimeInterval = 0,
        remDuration: TimeInterval = 0,
        unspecifiedSleepDuration: TimeInterval = 0,
        sleepLatency: TimeInterval = 0,
        waso: TimeInterval = 0,
        efficiency: Double = 0,
        qualityScore: SleepQualityScore = .zero,
        biometrics: NightlyBiometricSummary? = nil
    ) {
        self.id = id
        self.sleepDateKey = sleepDateKey
        self.startDate = startDate
        self.endDate = endDate
        self.inBedStartDate = inBedStartDate
        self.inBedEndDate = inBedEndDate
        self.stages = stages
        self.sources = sources
        self.dataQuality = dataQuality
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
        self.qualityScore = qualityScore
        self.biometrics = biometrics
    }
}

struct SleepDaySummary: Codable, Hashable, Sendable, Identifiable {
    var id: String { sleepDateKey }
    var sleepDateKey: String
    var score: Double?
    var totalSleepTime: TimeInterval?
    var dataQuality: SleepDataQuality
    var hasSession: Bool

    init(
        sleepDateKey: String,
        score: Double? = nil,
        totalSleepTime: TimeInterval? = nil,
        dataQuality: SleepDataQuality = .noData,
        hasSession: Bool = false
    ) {
        self.sleepDateKey = sleepDateKey
        self.score = score
        self.totalSleepTime = totalSleepTime
        self.dataQuality = dataQuality
        self.hasSession = hasSession
    }
}

struct SleepBaseline: Codable, Hashable, Sendable, Identifiable {
    var id: UUID
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

    init(
        id: UUID = UUID(),
        windowDays: Int,
        generatedAt: Date = Date(),
        validNights: Int,
        totalSleepAverage: Double,
        totalSleepStandardDeviation: Double,
        remAverage: Double,
        remStandardDeviation: Double,
        deepAverage: Double,
        deepStandardDeviation: Double,
        efficiencyAverage: Double,
        efficiencyStandardDeviation: Double,
        wasoAverage: Double,
        wasoStandardDeviation: Double,
        latencyAverage: Double,
        latencyStandardDeviation: Double,
        hrvAverage: Double,
        hrvStandardDeviation: Double,
        respiratoryRateAverage: Double,
        respiratoryRateStandardDeviation: Double,
        oxygenSaturationAverage: Double,
        oxygenSaturationStandardDeviation: Double,
        bedtimeMinuteAverage: Double,
        bedtimeMinuteStandardDeviation: Double,
        wakeMinuteAverage: Double,
        wakeMinuteStandardDeviation: Double
    ) {
        self.id = id
        self.windowDays = windowDays
        self.generatedAt = generatedAt
        self.validNights = validNights
        self.totalSleepAverage = totalSleepAverage
        self.totalSleepStandardDeviation = totalSleepStandardDeviation
        self.remAverage = remAverage
        self.remStandardDeviation = remStandardDeviation
        self.deepAverage = deepAverage
        self.deepStandardDeviation = deepStandardDeviation
        self.efficiencyAverage = efficiencyAverage
        self.efficiencyStandardDeviation = efficiencyStandardDeviation
        self.wasoAverage = wasoAverage
        self.wasoStandardDeviation = wasoStandardDeviation
        self.latencyAverage = latencyAverage
        self.latencyStandardDeviation = latencyStandardDeviation
        self.hrvAverage = hrvAverage
        self.hrvStandardDeviation = hrvStandardDeviation
        self.respiratoryRateAverage = respiratoryRateAverage
        self.respiratoryRateStandardDeviation = respiratoryRateStandardDeviation
        self.oxygenSaturationAverage = oxygenSaturationAverage
        self.oxygenSaturationStandardDeviation = oxygenSaturationStandardDeviation
        self.bedtimeMinuteAverage = bedtimeMinuteAverage
        self.bedtimeMinuteStandardDeviation = bedtimeMinuteStandardDeviation
        self.wakeMinuteAverage = wakeMinuteAverage
        self.wakeMinuteStandardDeviation = wakeMinuteStandardDeviation
    }
}
