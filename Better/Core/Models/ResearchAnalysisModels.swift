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
    var protocolNamesTaken: [String]
    var protocolTakenAt: [Date]
    var minutesFromProtocolToSleep: [Double]
    var baselineTotalSleepDeltaHours: Double?
    var baselineEfficiencyDeltaPercent: Double?
    var baselineWASODeltaMinutes: Double?
    var baselineLatencyDeltaMinutes: Double?
    var baselineHRVDelta: Double?
    var sourceNames: [String]
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
    var earlyTimingSleepDelta: Double?   // >3h before sleep onset (≥5 nights each, else nil)
    var optimalTimingSleepDelta: Double? // 1–3h before sleep onset
    var lateTimingSleepDelta: Double?    // <1h before sleep onset
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
}

nonisolated struct ResearchExportPackage: Codable, Hashable, Sendable {
    static let schemaVersion = "1"

    var generatedAt: Date
    var rangeStart: Date
    var rangeEnd: Date
    var baselineWindowDays: Int
    var baselineValidNights: Int
    var isResearchMode: Bool
    var nightlyRows: [NightlyResearchRow]
    var protocolSummaries: [ProtocolEffectSummary]
    var insightSummary: ResearchInsightSummary
}
