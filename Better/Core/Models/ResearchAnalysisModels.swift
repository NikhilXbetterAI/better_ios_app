import Foundation

nonisolated enum AnalysisConfidence: String, Codable, CaseIterable, Hashable, Sendable, Identifiable {
    case insufficient
    case low
    case moderate
    case strong

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .insufficient:
            "Insufficient"
        case .low:
            "Low"
        case .moderate:
            "Moderate"
        case .strong:
            "Strong"
        }
    }
}

nonisolated enum ComparisonConfidence: String, Codable, CaseIterable, Hashable, Sendable, Identifiable {
    case unavailable
    case low
    case medium
    case high

    var id: String { rawValue }

    var sortOrder: Int {
        switch self {
        case .unavailable: 0
        case .low:         1
        case .medium:      2
        case .high:        3
        }
    }
}

nonisolated enum ProtocolUsageStatus: String, Codable, CaseIterable, Hashable, Sendable, Identifiable {
    case taken
    case notTaken
    case unknown

    var id: String { rawValue }

    var protocolTaken: Bool? {
        switch self {
        case .taken: true
        case .notTaken: false
        case .unknown: nil
        }
    }
}

nonisolated struct DailyActivitySummary: Codable, Hashable, Sendable, Identifiable {
    var id: String { dateKey }
    var dateKey: String
    var steps: Double?
    var activeEnergy: Double?
    var exerciseMinutes: Double?
    var standHours: Double?
    var flights: Double?
    var distanceMeters: Double?
    var generatedAt: Date

    init(
        dateKey: String,
        steps: Double? = nil,
        activeEnergy: Double? = nil,
        exerciseMinutes: Double? = nil,
        standHours: Double? = nil,
        flights: Double? = nil,
        distanceMeters: Double? = nil,
        generatedAt: Date = Date()
    ) {
        self.dateKey = dateKey
        self.steps = steps
        self.activeEnergy = activeEnergy
        self.exerciseMinutes = exerciseMinutes
        self.standHours = standHours
        self.flights = flights
        self.distanceMeters = distanceMeters
        self.generatedAt = generatedAt
    }
}

nonisolated struct NightlyResearchRow: Codable, Hashable, Sendable, Identifiable {
    var id: String { sleepDateKey }
    var sleepDateKey: String
    var sleepStart: Date
    var sleepEnd: Date
    var dataQuality: SleepDataQuality
    var totalSleepHours: Double
    var inBedHours: Double
    var efficiencyPercent: Double
    var deepHours: Double?
    var remHours: Double?
    var coreHours: Double?
    var awakeHours: Double
    var wasoMinutes: Double
    var latencyMinutes: Double
    var sleepScore: Double
    var durationScore: Double
    var efficiencyScore: Double
    var remScore: Double
    var deepScore: Double
    var hrvAverage: Double?
    var hrvMedian: Double?
    var heartRateAverage: Double?
    var heartRateMinimum: Double?
    var heartRateMaximum: Double?
    var respiratoryRateAverage: Double?
    var oxygenSaturationAveragePercent: Double?
    var oxygenSaturationMinimumPercent: Double?
    var steps: Double?
    var activeEnergyKcal: Double?
    var exerciseMinutes: Double?
    var standHours: Double?
    var distanceMeters: Double?
    var activityStatus: UserActivityStatus?
    var isJetLagged: Bool
    var activityNote: String?
    var protocolTakenAny: Bool
    var protocolIDsTaken: [String]
    var protocolIDsNotTaken: [String]
    var protocolNamesTaken: [String]
    var protocolTakenAt: [Date]
    var minutesFromProtocolToSleep: [Double]
    var baselineTotalSleepDeltaHours: Double?
    var baselineEfficiencyDeltaPercent: Double?
    var baselineWASODeltaMinutes: Double?
    var baselineLatencyDeltaMinutes: Double?
    var baselineHRVDelta: Double?
    var sourceNames: [String]
    var baselineWindowUsed: Int?
    var baselineTotalSleepMinutes: Double?
    var durationVsBaselineMinutes: Double?
    var protocolUsageStatus: ProtocolUsageStatus
    var protocolTaken: Bool?
    var protocolName: String?
    var protocolTiming: String?
    var dataQualityStatus: String
    var comparisonConfidence: ComparisonConfidence

    // MARK: - Context fields (Phase 3 — appended at end for backward compatibility)
    var caffeineLate:            Bool?   // tristate: nil = unknown
    var alcohol:                 Bool?
    var workout:                 Bool?
    var lateMeal:                Bool?
    var highStress:              Bool?
    var screenTimeLate:          Bool?
    var nap:                     Bool?
    var travel:                  Bool?
    var perceivedSleepQuality:   String? // nil when no context entry
    var morningEnergy:           String?
    var contextNotesPresent:     Bool?   // true/false; nil = no entry
    var contextCompletionStatus: String? // notFilled / partial / complete / nil

    // MARK: - Sleep continuity fields (schema v2 — appended for backward compatibility)
    var restorativeSleepHours: Double?
    var longestRestorativeBlockHours: Double?
    var longestRestorativeBlockMinutes: Double?
    var sleepContinuityCategory: String?
    var sleepBlockCount: Int?
    var meaningfulAwakeCount: Int?
    var sleepBlockDurationsMinutes: [Double]?
    var sleepBlockStartDates: [Date]?
    var sleepBlockEndDates: [Date]?

    // MARK: - Protocol Formula fields (appended at end for backward compatibility)
    /// Resolved display label of the formula version logged for this night (empty if none).
    var formulaVersionLabel: String?
    /// UUID string of the formula version (empty if none).
    var formulaVersionID: String?
    /// taken / skipped / unknown (or empty if no log row).
    var formulaNightStatus: String?
    /// Restorative % of in-bed time — nil unless dataQuality is detailed or mixed.
    var restorativePctOfInBed: Double?

    init(
        sleepDateKey: String,
        sleepStart: Date,
        sleepEnd: Date,
        dataQuality: SleepDataQuality,
        totalSleepHours: Double,
        inBedHours: Double,
        efficiencyPercent: Double,
        deepHours: Double?,
        remHours: Double?,
        coreHours: Double?,
        awakeHours: Double,
        wasoMinutes: Double,
        latencyMinutes: Double,
        sleepScore: Double,
        durationScore: Double,
        efficiencyScore: Double,
        remScore: Double,
        deepScore: Double,
        hrvAverage: Double?,
        hrvMedian: Double?,
        heartRateAverage: Double?,
        heartRateMinimum: Double?,
        heartRateMaximum: Double?,
        respiratoryRateAverage: Double?,
        oxygenSaturationAveragePercent: Double?,
        oxygenSaturationMinimumPercent: Double?,
        steps: Double?,
        activeEnergyKcal: Double?,
        exerciseMinutes: Double?,
        standHours: Double?,
        distanceMeters: Double?,
        activityStatus: UserActivityStatus?,
        isJetLagged: Bool,
        activityNote: String?,
        protocolTakenAny: Bool = false,
        protocolIDsTaken: [String] = [],
        protocolIDsNotTaken: [String] = [],
        protocolNamesTaken: [String] = [],
        protocolTakenAt: [Date] = [],
        minutesFromProtocolToSleep: [Double] = [],
        baselineTotalSleepDeltaHours: Double?,
        baselineEfficiencyDeltaPercent: Double?,
        baselineWASODeltaMinutes: Double?,
        baselineLatencyDeltaMinutes: Double?,
        baselineHRVDelta: Double?,
        sourceNames: [String],
        baselineWindowUsed: Int? = nil,
        baselineTotalSleepMinutes: Double? = nil,
        durationVsBaselineMinutes: Double? = nil,
        protocolUsageStatus: ProtocolUsageStatus? = nil,
        protocolTaken: Bool? = nil,
        protocolName: String? = nil,
        protocolTiming: String? = nil,
        dataQualityStatus: String? = nil,
        comparisonConfidence: ComparisonConfidence = .unavailable,
        caffeineLate:            Bool? = nil,
        alcohol:                 Bool? = nil,
        workout:                 Bool? = nil,
        lateMeal:                Bool? = nil,
        highStress:              Bool? = nil,
        screenTimeLate:          Bool? = nil,
        nap:                     Bool? = nil,
        travel:                  Bool? = nil,
        perceivedSleepQuality:   String? = nil,
        morningEnergy:           String? = nil,
        contextNotesPresent:     Bool? = nil,
        contextCompletionStatus: String? = nil,
        restorativeSleepHours: Double? = nil,
        longestRestorativeBlockHours: Double? = nil,
        longestRestorativeBlockMinutes: Double? = nil,
        sleepContinuityCategory: String? = nil,
        sleepBlockCount: Int? = nil,
        meaningfulAwakeCount: Int? = nil,
        sleepBlockDurationsMinutes: [Double]? = nil,
        sleepBlockStartDates: [Date]? = nil,
        sleepBlockEndDates: [Date]? = nil,
        formulaVersionLabel: String? = nil,
        formulaVersionID: String? = nil,
        formulaNightStatus: String? = nil,
        restorativePctOfInBed: Double? = nil
    ) {
        self.sleepDateKey = sleepDateKey
        self.sleepStart = sleepStart
        self.sleepEnd = sleepEnd
        self.dataQuality = dataQuality
        self.totalSleepHours = totalSleepHours
        self.inBedHours = inBedHours
        self.efficiencyPercent = efficiencyPercent
        self.deepHours = deepHours
        self.remHours = remHours
        self.coreHours = coreHours
        self.awakeHours = awakeHours
        self.wasoMinutes = wasoMinutes
        self.latencyMinutes = latencyMinutes
        self.sleepScore = sleepScore
        self.durationScore = durationScore
        self.efficiencyScore = efficiencyScore
        self.remScore = remScore
        self.deepScore = deepScore
        self.hrvAverage = hrvAverage
        self.hrvMedian = hrvMedian
        self.heartRateAverage = heartRateAverage
        self.heartRateMinimum = heartRateMinimum
        self.heartRateMaximum = heartRateMaximum
        self.respiratoryRateAverage = respiratoryRateAverage
        self.oxygenSaturationAveragePercent = oxygenSaturationAveragePercent
        self.oxygenSaturationMinimumPercent = oxygenSaturationMinimumPercent
        self.steps = steps
        self.activeEnergyKcal = activeEnergyKcal
        self.exerciseMinutes = exerciseMinutes
        self.standHours = standHours
        self.distanceMeters = distanceMeters
        self.activityStatus = activityStatus
        self.isJetLagged = isJetLagged
        self.activityNote = activityNote
        self.protocolTakenAny = protocolTakenAny
        self.protocolIDsTaken = protocolIDsTaken
        self.protocolIDsNotTaken = protocolIDsNotTaken
        self.protocolNamesTaken = protocolNamesTaken
        self.protocolTakenAt = protocolTakenAt
        self.minutesFromProtocolToSleep = minutesFromProtocolToSleep
        self.baselineTotalSleepDeltaHours = baselineTotalSleepDeltaHours
        self.baselineEfficiencyDeltaPercent = baselineEfficiencyDeltaPercent
        self.baselineWASODeltaMinutes = baselineWASODeltaMinutes
        self.baselineLatencyDeltaMinutes = baselineLatencyDeltaMinutes
        self.baselineHRVDelta = baselineHRVDelta
        self.sourceNames = sourceNames
        self.baselineWindowUsed = baselineWindowUsed
        self.baselineTotalSleepMinutes = baselineTotalSleepMinutes
        self.durationVsBaselineMinutes = durationVsBaselineMinutes
        let resolvedStatus = protocolUsageStatus ?? (protocolTakenAny ? .taken : .unknown)
        self.protocolUsageStatus = resolvedStatus
        self.protocolTaken = protocolTaken ?? resolvedStatus.protocolTaken
        self.protocolName = protocolName
        self.protocolTiming = protocolTiming
        self.dataQualityStatus = dataQualityStatus ?? dataQuality.rawValue
        self.comparisonConfidence = comparisonConfidence
        self.caffeineLate            = caffeineLate
        self.alcohol                 = alcohol
        self.workout                 = workout
        self.lateMeal                = lateMeal
        self.highStress              = highStress
        self.screenTimeLate          = screenTimeLate
        self.nap                     = nap
        self.travel                  = travel
        self.perceivedSleepQuality   = perceivedSleepQuality
        self.morningEnergy           = morningEnergy
        self.contextNotesPresent     = contextNotesPresent
        self.contextCompletionStatus = contextCompletionStatus
        self.restorativeSleepHours = restorativeSleepHours
        self.longestRestorativeBlockHours = longestRestorativeBlockHours
        self.longestRestorativeBlockMinutes = longestRestorativeBlockMinutes
        self.sleepContinuityCategory = sleepContinuityCategory
        self.sleepBlockCount = sleepBlockCount
        self.meaningfulAwakeCount = meaningfulAwakeCount
        self.sleepBlockDurationsMinutes = sleepBlockDurationsMinutes
        self.sleepBlockStartDates = sleepBlockStartDates
        self.sleepBlockEndDates = sleepBlockEndDates
        self.formulaVersionLabel = formulaVersionLabel
        self.formulaVersionID = formulaVersionID
        self.formulaNightStatus = formulaNightStatus
        self.restorativePctOfInBed = restorativePctOfInBed
    }
}

nonisolated struct ProtocolEffectSummary: Codable, Hashable, Sendable, Identifiable {
    var id: String { protocolID }
    var protocolID: String
    var protocolName: String
    var takenNightCount: Int
    var missedNightCount: Int
    var sleepDifferenceHours: Double?
    var scoreDifference: Double?
    var efficiencyDifferencePercent: Double?
    var wasoDifferenceMinutes: Double?
    var latencyDifferenceMinutes: Double?
    var hrvDifference: Double?
    var jetLagAdjustedSleepDifferenceHours: Double?
    var earlyTimingSleepDelta: Double?
    var optimalTimingSleepDelta: Double?
    var lateTimingSleepDelta: Double?
    var confidence: AnalysisConfidence
    var caveats: [String]
}

nonisolated struct ResearchInsightSummary: Codable, Hashable, Sendable {
    var generatedAt: Date
    var validNightCount: Int
    var bestProtocolName: String?
    var bestProtocolSleepDifferenceHours: Double?
    var confidence: AnalysisConfidence
    var baselineSleepDifferenceHours: Double?
    var confounderNote: String?
    var summary: String

    init(
        generatedAt: Date,
        validNightCount: Int,
        bestProtocolName: String? = nil,
        bestProtocolSleepDifferenceHours: Double? = nil,
        confidence: AnalysisConfidence = .insufficient,
        baselineSleepDifferenceHours: Double?,
        confounderNote: String?,
        summary: String
    ) {
        self.generatedAt = generatedAt
        self.validNightCount = validNightCount
        self.bestProtocolName = bestProtocolName
        self.bestProtocolSleepDifferenceHours = bestProtocolSleepDifferenceHours
        self.confidence = confidence
        self.baselineSleepDifferenceHours = baselineSleepDifferenceHours
        self.confounderNote = confounderNote
        self.summary = summary
    }
}

nonisolated struct ResearchExportPackage: Codable, Hashable, Sendable {
    static let schemaVersion = "4"

    var generatedAt: Date
    var rangeStart: Date
    var rangeEnd: Date
    var baselineWindowDays: Int
    var baselineValidNights: Int
    var isResearchMode: Bool
    var nightlyRows: [NightlyResearchRow]
    var protocolSummaries: [ProtocolEffectSummary]
    var insightSummary: ResearchInsightSummary
    var chronotypeResult: ChronotypeCalculationResult? = nil
    var baselineSelection: BaselineSelection? = nil
    var contextComparisonResults: [ContextComparisonResult] = []

    init(
        generatedAt: Date,
        rangeStart: Date,
        rangeEnd: Date,
        baselineWindowDays: Int,
        baselineValidNights: Int,
        isResearchMode: Bool,
        nightlyRows: [NightlyResearchRow],
        protocolSummaries: [ProtocolEffectSummary] = [],
        insightSummary: ResearchInsightSummary,
        chronotypeResult: ChronotypeCalculationResult? = nil,
        baselineSelection: BaselineSelection? = nil,
        contextComparisonResults: [ContextComparisonResult] = []
    ) {
        self.generatedAt = generatedAt
        self.rangeStart = rangeStart
        self.rangeEnd = rangeEnd
        self.baselineWindowDays = baselineWindowDays
        self.baselineValidNights = baselineValidNights
        self.isResearchMode = isResearchMode
        self.nightlyRows = nightlyRows
        self.protocolSummaries = protocolSummaries
        self.insightSummary = insightSummary
        self.chronotypeResult = chronotypeResult
        self.baselineSelection = baselineSelection
        self.contextComparisonResults = contextComparisonResults
    }
}
