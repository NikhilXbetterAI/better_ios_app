import Foundation

nonisolated enum SleepStageType: String, Codable, CaseIterable, Hashable, Sendable, Identifiable {
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

nonisolated enum SleepDataQuality: String, Codable, CaseIterable, Hashable, Sendable, Identifiable {
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

nonisolated struct SleepSource: Codable, Hashable, Sendable, Identifiable {
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

nonisolated struct SleepStage: Codable, Hashable, Sendable, Identifiable {
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

nonisolated struct SleepQualityScore: Codable, Hashable, Sendable {
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

nonisolated struct SleepSession: Codable, Hashable, Sendable, Identifiable {
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

    /// Apple-formula score using only duration + interruptions (no baseline needed).
    /// Normalized to 0–100 so it's on the same scale as the full hero score.
    /// Services (alerts, insights) use this instead of the old qualityScore.overall.
    var appleScorePartial: Int {
        let duration = min(totalSleepTime / (8.0 * 3_600), 1.0) * 50.0
        let wasoMin = waso / 60.0
        let interruptions = max(0.0, (1.0 - wasoMin / 120.0) * 20.0)
        return Int(((duration + interruptions) / 70.0 * 100.0).rounded())
    }

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

extension SleepSession {
    /// Canonical wake time for display.
    /// Prefer `inBedEndDate` (the moment the user got out of bed) over
    /// `endDate` (last detected sleep sample). Using `endDate` can produce
    /// an earlier timestamp when the last stage ends before the user
    /// physically woke up, causing inconsistencies between cards. (Bug A2)
    nonisolated var displayWakeDate: Date { inBedEndDate ?? endDate }
}

nonisolated struct SleepDaySummary: Codable, Hashable, Sendable, Identifiable {
    var id: String { sleepDateKey }
    var sleepDateKey: String
    var score: Double?
    var totalSleepTime: TimeInterval?
    var waso: TimeInterval          // needed to recompute Apple score in ViewModel
    var inBedStartDate: Date?       // needed for bedtime component
    var dataQuality: SleepDataQuality
    var hasSession: Bool

    init(
        sleepDateKey: String,
        score: Double? = nil,
        totalSleepTime: TimeInterval? = nil,
        waso: TimeInterval = 0,
        inBedStartDate: Date? = nil,
        dataQuality: SleepDataQuality = .noData,
        hasSession: Bool = false
    ) {
        self.sleepDateKey = sleepDateKey
        self.score = score
        self.totalSleepTime = totalSleepTime
        self.waso = waso
        self.inBedStartDate = inBedStartDate
        self.dataQuality = dataQuality
        self.hasSession = hasSession
    }
}

nonisolated struct HealthSleepScoreEstimate: Codable, Hashable, Sendable {
    var overall: Int
    var duration: Int       // 0-50 pts — actual sleep vs goal
    var bedtime: Int        // 0-30 pts; 0 when baseline not ready or travel suppressed
    var interruptions: Int  // 0-20 pts — WASO penalty
}

nonisolated enum HealthSleepScoreEstimator {
    /// Apple-style formula (same weights as Apple Health Sleep Score):
    ///   Duration      50 pts  — actual sleep / goal (linear, capped at 1.0)
    ///   Bedtime       30 pts  — deviation from personal baseline; 0 if baseline not ready
    ///   Interruptions 20 pts  — WASO penalty (0 pts at ≥120 min wake time)
    ///   Total = 100
    static func estimate(
        session: SleepSession,
        baseline: SleepBaseline?,
        sleepGoalHours: Double = 8.0,
        contextEntry: SleepContextEntry? = nil,
        calendar: Calendar = .current
    ) -> HealthSleepScoreEstimate {
        let duration = durationComponent(
            totalSleepTime: session.totalSleepTime,
            sleepGoalHours: sleepGoalHours
        )
        let bedtime = bedtimeComponent(
            session: session,
            baseline: baseline,
            contextEntry: contextEntry,
            calendar: calendar
        )
        let interruptions = interruptionsComponent(session: session)

        return HealthSleepScoreEstimate(
            overall: duration + bedtime + interruptions,
            duration: duration,
            bedtime: bedtime,
            interruptions: interruptions
        )
    }

    // Duration: 0-50 pts — proportional to sleep/goal, capped.
    private static func durationComponent(totalSleepTime: TimeInterval, sleepGoalHours: Double) -> Int {
        let ratio = totalSleepTime / (sleepGoalHours * 3_600)
        return clamp(Int((min(ratio, 1.0) * 50).rounded()), lower: 0, upper: 50)
    }

    // Bedtime: 0-30 pts — linear decay, 0 pts at ≥3h deviation from baseline.
    private static func bedtimeComponent(
        session: SleepSession,
        baseline: SleepBaseline?,
        contextEntry: SleepContextEntry?,
        calendar: Calendar
    ) -> Int {
        // Invariant #2: travel == true (not != false) — nil means unknown, not safe-to-penalize.
        if contextEntry?.travel == true { return 30 }
        guard let baseline, baseline.validNights >= 5 else { return 0 }

        let bedMinute = minuteOfDay(for: session.inBedStartDate ?? session.startDate, calendar: calendar)
        let deviation = circularMinuteDistance(bedMinute, baseline.bedtimeMinuteAverage)
        return clamp(Int(((1.0 - deviation / 180.0) * 30.0).rounded()), lower: 0, upper: 30)
    }

    // Interruptions: 0-20 pts — linear decay, 0 pts at ≥120 min WASO.
    private static func interruptionsComponent(session: SleepSession) -> Int {
        let wasoMinutes = session.waso / 60.0
        return clamp(Int(((1.0 - wasoMinutes / 120.0) * 20.0).rounded()), lower: 0, upper: 20)
    }

    private static func minuteOfDay(for date: Date, calendar: Calendar) -> Double {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return Double((components.hour ?? 0) * 60 + (components.minute ?? 0))
    }

    private static func circularMinuteDistance(_ lhs: Double, _ rhs: Double) -> Double {
        let rawDifference = abs(lhs - rhs).truncatingRemainder(dividingBy: 1_440)
        return min(rawDifference, 1_440 - rawDifference)
    }

    private static func clamp(_ value: Int, lower: Int, upper: Int) -> Int {
        min(upper, max(lower, value))
    }
}

nonisolated struct SleepBaseline: Codable, Hashable, Sendable, Identifiable {
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
