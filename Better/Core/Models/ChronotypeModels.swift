import Foundation

nonisolated enum ChronotypeBucket: String, Codable, CaseIterable, Hashable, Sendable, Identifiable {
    case early
    case earlyIntermediate
    case intermediate
    case lateIntermediate
    case late

    var id: String { rawValue }
}

nonisolated enum ChronotypeExclusionReason: String, Codable, CaseIterable, Hashable, Sendable, Identifiable {
    case tooShort
    case tooLong
    case poorDataQuality
    case travelOrJetLag
    case invalidTiming

    var id: String { rawValue }
}

nonisolated enum ChronotypeDayType: String, Codable, CaseIterable, Hashable, Sendable, Identifiable {
    case workday
    case freeDay

    var id: String { rawValue }
}

nonisolated enum ChronotypeCalculationStatus: String, Codable, CaseIterable, Hashable, Sendable, Identifiable {
    case estimated
    case insufficientData

    var id: String { rawValue }
}

nonisolated enum BodyClockReadiness: String, Codable, CaseIterable, Hashable, Sendable, Identifiable {
    case preview
    case stable
    case highConfidence

    var id: String { rawValue }
}

nonisolated enum BodyClockCaveat: String, Codable, CaseIterable, Hashable, Sendable, Identifiable {
    case fewFreeDays = "few_free_days"
    case highExclusionRate = "high_exclusion_rate"
    case previewOnly = "preview_only"
    case travelRecentlyExcluded = "travel_recently_excluded"

    var id: String { rawValue }
}

nonisolated enum BodyClockAlignmentCategory: String, Codable, CaseIterable, Hashable, Sendable, Identifiable {
    case aligned
    case slightlyEarly
    case slightlyLate
    case early
    case late

    var id: String { rawValue }
}

nonisolated enum ChronotypeMinimumRequirement: String, Codable, CaseIterable, Hashable, Sendable, Identifiable {
    case totalNights
    case workdayNights
    case freeDayNights

    var id: String { rawValue }
}

nonisolated struct SleepWindowRecommendation: Codable, Hashable, Sendable {
    var startMinute: Int
    var endMinute: Int
    var duration: TimeInterval

    init(startMinute: Int, endMinute: Int, duration: TimeInterval) {
        self.startMinute = startMinute
        self.endMinute = endMinute
        self.duration = duration
    }
}

nonisolated struct BodyClockSleepAlignment: Codable, Hashable, Sendable {
    var actualMidpointMinute: Int
    var targetMidpointMinute: Int
    var signedDeltaMinutes: Int
    var category: BodyClockAlignmentCategory

    init(
        actualMidpointMinute: Int,
        targetMidpointMinute: Int,
        signedDeltaMinutes: Int,
        category: BodyClockAlignmentCategory
    ) {
        self.actualMidpointMinute = actualMidpointMinute
        self.targetMidpointMinute = targetMidpointMinute
        self.signedDeltaMinutes = signedDeltaMinutes
        self.category = category
    }
}

nonisolated struct ChronotypeNight: Codable, Hashable, Sendable, Identifiable {
    var id: String { sleepDateKey }
    var sleepDateKey: String
    var dayType: ChronotypeDayType
    var onset: Date
    var wake: Date
    var duration: TimeInterval
    var midpointMinute: Int

    init(
        sleepDateKey: String,
        dayType: ChronotypeDayType,
        onset: Date,
        wake: Date,
        duration: TimeInterval,
        midpointMinute: Int
    ) {
        self.sleepDateKey = sleepDateKey
        self.dayType = dayType
        self.onset = onset
        self.wake = wake
        self.duration = duration
        self.midpointMinute = midpointMinute
    }
}

nonisolated struct ChronotypeEstimate: Codable, Hashable, Sendable {
    var bucket: ChronotypeBucket
    var correctedMidpointMinute: Int
    var workdayMidpointMinute: Int
    var freeDayMidpointMinute: Int
    var workdayMedianDuration: TimeInterval
    var freeDayMedianDuration: TimeInterval
    var weeklyAverageDuration: TimeInterval
    var validNightCount: Int
    var workdayNightCount: Int
    var freeDayNightCount: Int
    var excludedNightCount: Int
    var excludedCountsByReason: [ChronotypeExclusionReason: Int]
    var confidence: ComparisonConfidence
    var bodyClockReadiness: BodyClockReadiness
    var bodyClockCaveats: [BodyClockCaveat]
    var optimalSleepWindow: SleepWindowRecommendation

    init(
        bucket: ChronotypeBucket,
        correctedMidpointMinute: Int,
        workdayMidpointMinute: Int,
        freeDayMidpointMinute: Int,
        workdayMedianDuration: TimeInterval,
        freeDayMedianDuration: TimeInterval,
        weeklyAverageDuration: TimeInterval,
        validNightCount: Int,
        workdayNightCount: Int,
        freeDayNightCount: Int,
        excludedNightCount: Int,
        excludedCountsByReason: [ChronotypeExclusionReason: Int],
        confidence: ComparisonConfidence,
        bodyClockReadiness: BodyClockReadiness,
        bodyClockCaveats: [BodyClockCaveat] = [],
        optimalSleepWindow: SleepWindowRecommendation
    ) {
        self.bucket = bucket
        self.correctedMidpointMinute = correctedMidpointMinute
        self.workdayMidpointMinute = workdayMidpointMinute
        self.freeDayMidpointMinute = freeDayMidpointMinute
        self.workdayMedianDuration = workdayMedianDuration
        self.freeDayMedianDuration = freeDayMedianDuration
        self.weeklyAverageDuration = weeklyAverageDuration
        self.validNightCount = validNightCount
        self.workdayNightCount = workdayNightCount
        self.freeDayNightCount = freeDayNightCount
        self.excludedNightCount = excludedNightCount
        self.excludedCountsByReason = excludedCountsByReason
        self.confidence = confidence
        self.bodyClockReadiness = bodyClockReadiness
        self.bodyClockCaveats = bodyClockCaveats
        self.optimalSleepWindow = optimalSleepWindow
    }
}

nonisolated struct ChronotypeCalculationResult: Codable, Hashable, Sendable {
    var status: ChronotypeCalculationStatus
    var estimate: ChronotypeEstimate?
    var includedNights: [ChronotypeNight]
    var excludedCountsByReason: [ChronotypeExclusionReason: Int]
    var totalCandidateNightCount: Int
    var validNightCount: Int
    var workdayNightCount: Int
    var freeDayNightCount: Int
    var missingRequirements: [ChronotypeMinimumRequirement]
    var windowDays: Int
    var windowStart: Date
    var windowEnd: Date

    init(
        status: ChronotypeCalculationStatus,
        estimate: ChronotypeEstimate?,
        includedNights: [ChronotypeNight],
        excludedCountsByReason: [ChronotypeExclusionReason: Int],
        totalCandidateNightCount: Int,
        validNightCount: Int,
        workdayNightCount: Int,
        freeDayNightCount: Int,
        missingRequirements: [ChronotypeMinimumRequirement],
        windowDays: Int,
        windowStart: Date,
        windowEnd: Date
    ) {
        self.status = status
        self.estimate = estimate
        self.includedNights = includedNights
        self.excludedCountsByReason = excludedCountsByReason
        self.totalCandidateNightCount = totalCandidateNightCount
        self.validNightCount = validNightCount
        self.workdayNightCount = workdayNightCount
        self.freeDayNightCount = freeDayNightCount
        self.missingRequirements = missingRequirements
        self.windowDays = windowDays
        self.windowStart = windowStart
        self.windowEnd = windowEnd
    }
}

extension ChronotypeBucket {
    var bodyClockDisplayName: String {
        switch self {
        case .early:
            "Early Body Clock"
        case .earlyIntermediate:
            "Early-intermediate Body Clock"
        case .intermediate:
            "Intermediate Body Clock"
        case .lateIntermediate:
            "Late-intermediate Body Clock"
        case .late:
            "Late Body Clock"
        }
    }
}
