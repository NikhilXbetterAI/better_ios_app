import Foundation
import OSLog

// MARK: - ContextFactor

/// All lifestyle factors that can be compared against sleep metrics.
nonisolated enum ContextFactor: String, Codable, CaseIterable, Hashable, Sendable, Identifiable {
    case caffeineLate
    case alcohol
    case workout
    case lateMeal
    case highStress
    case screenTimeLate
    case nap
    case travel
    case protocolTaken

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .caffeineLate:   "Late Caffeine"
        case .alcohol:        "Alcohol"
        case .workout:        "Workout"
        case .lateMeal:       "Late Meal"
        case .highStress:     "High Stress"
        case .screenTimeLate: "Late Screen Time"
        case .nap:            "Nap"
        case .travel:         "Travel"
        case .protocolTaken:  "Protocol Taken"
        }
    }

    var systemImageName: String {
        switch self {
        case .caffeineLate:   "cup.and.saucer.fill"
        case .alcohol:        "wineglass.fill"
        case .workout:        "figure.run"
        case .lateMeal:       "fork.knife"
        case .highStress:     "brain.head.profile"
        case .screenTimeLate: "iphone"
        case .nap:            "zzz"
        case .travel:         "airplane"
        case .protocolTaken:  "pills.fill"
        }
    }
}

// MARK: - ContextComparisonResult

/// The result of comparing sleep metrics across nights where a single
/// context factor was yes, no, or unknown.
nonisolated struct ContextComparisonResult: Codable, Hashable, Sendable {
    var factor: ContextFactor
    var window: ProtocolComparisonWindow
    var yesNightCount: Int
    var noNightCount: Int
    var unknownNightCount: Int
    var confidence: ComparisonConfidence

    // Duration
    var averageSleepDurationYes: TimeInterval?
    var averageSleepDurationNo:  TimeInterval?
    var durationDelta: TimeInterval?

    // Efficiency
    var averageEfficiencyYes: Double?
    var averageEfficiencyNo:  Double?
    var efficiencyDelta: Double?

    // Deep sleep (nil when stage data unavailable)
    var averageDeepSleepYes: TimeInterval?
    var averageDeepSleepNo:  TimeInterval?
    var deepSleepDelta: TimeInterval?

    // REM sleep (nil when stage data unavailable)
    var averageREMSleepYes: TimeInterval?
    var averageREMSleepNo:  TimeInterval?
    var remSleepDelta: TimeInterval?

    // Awake time
    var averageAwakeTimeYes: TimeInterval?
    var averageAwakeTimeNo:  TimeInterval?
    var awakeTimeDelta: TimeInterval?

    /// `true` when at least one metric exceeds its meaningful threshold.
    var hasMeaningfulDifference: Bool
}

// MARK: - ContextComparisonService

/// Deterministic, association-only comparison of sleep metrics by context factor.
/// Uses the same confidence thresholds and stage-suppression logic as
/// `ProtocolComparisonService` so behaviour is consistent and easy to test.
nonisolated struct ContextComparisonService: Sendable {

    // MARK: - Thresholds (centralised — used by tests)
    static let meaningfulDurationDelta:  TimeInterval = 20 * 60   // 20 min
    static let meaningfulEfficiencyDelta: Double      = 0.03      // 3 pp
    static let meaningfulStageDelta:     TimeInterval = 10 * 60   // 10 min
    static let meaningfulAwakeDelta:     TimeInterval = 10 * 60   // 10 min

    private let calendar: Calendar
    private let logger = Logger(subsystem: "Better", category: "ContextComparison")

    init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    /// Compare sessions for a single factor.
    ///
    /// - Parameters:
    ///   - sessions:       All available sleep sessions.
    ///   - contextEntries: Context entries keyed by sleep date.
    ///   - adherence:      Protocol adherence records (needed for `.protocolTaken` factor).
    ///   - factor:         The factor to compare.
    ///   - window:         Date window to restrict sessions.
    ///   - endDate:        The end of the date window.
    func compare(
        sessions: [SleepSession],
        contextEntries: [SleepContextEntry],
        adherence: [ProtocolAdherence],
        factor: ContextFactor,
        window: ProtocolComparisonWindow = .last30Days,
        endingAt endDate: Date = Date()
    ) -> ContextComparisonResult {
        let eligible = sessions
            .filter { BaselineEngine.isValidNight($0, calendar: calendar) }
            .filter { session in
                guard let days = window.dayCount else { return true }
                guard let sleepDate = SleepDateKey.date(from: session.sleepDateKey, calendar: calendar) else { return false }
                let start = calendar.date(byAdding: .day, value: -days + 1, to: calendar.startOfDay(for: endDate))
                    ?? endDate.addingTimeInterval(Double(-days + 1) * 86_400)
                return sleepDate >= calendar.startOfDay(for: start) && sleepDate <= calendar.startOfDay(for: endDate)
            }
            .sorted { $0.sleepDateKey < $1.sleepDateKey }

        let contextByDate = Dictionary(grouping: contextEntries, by: \.sleepDateKey).mapValues { $0.first! }
        let adherenceByDate = Dictionary(grouping: adherence, by: \.dateKey)

        let grouped = Dictionary(grouping: eligible) { session -> Bool? in
            factorValue(
                for: session.sleepDateKey,
                factor: factor,
                context: contextByDate[session.sleepDateKey],
                adherence: adherenceByDate[session.sleepDateKey]
            )
        }

        // Bool? keys: true = yes, false = no, nil = unknown
        let yesNights     = grouped[true,  default: []]
        let noNights      = grouped[false, default: []]
        let unknownNights = grouped[nil,   default: []]
        let confidence    = ProtocolComparisonService.confidence(takenCount: yesNights.count, notTakenCount: noNights.count)

        logger.debug(
            "Context compare factor=\(factor.rawValue, privacy: .public) yes=\(yesNights.count, privacy: .public) no=\(noNights.count, privacy: .public) unknown=\(unknownNights.count, privacy: .public)"
        )

        let durationDelta   = difference(yesNights.map(\.totalSleepTime), noNights.map(\.totalSleepTime))
        let efficiencyDelta = difference(yesNights.map(\.efficiency), noNights.map(\.efficiency))
        let deepDelta       = stageDifference(yesNights, noNights, value: \.deepDuration)
        let remDelta        = stageDifference(yesNights, noNights, value: \.remDuration)
        let awakeDelta      = difference(yesNights.map(\.awakeDuration), noNights.map(\.awakeDuration))

        let meaningful = hasMeaningfulDifference(
            durationDelta: durationDelta,
            efficiencyDelta: efficiencyDelta,
            deepDelta: deepDelta,
            remDelta: remDelta,
            awakeDelta: awakeDelta
        )

        return ContextComparisonResult(
            factor: factor,
            window: window,
            yesNightCount:     yesNights.count,
            noNightCount:      noNights.count,
            unknownNightCount: unknownNights.count,
            confidence: confidence,
            averageSleepDurationYes: average(yesNights.map(\.totalSleepTime)),
            averageSleepDurationNo:  average(noNights.map(\.totalSleepTime)),
            durationDelta: durationDelta,
            averageEfficiencyYes: average(yesNights.map(\.efficiency)),
            averageEfficiencyNo:  average(noNights.map(\.efficiency)),
            efficiencyDelta: efficiencyDelta,
            averageDeepSleepYes: stageAverage(yesNights, value: \.deepDuration),
            averageDeepSleepNo:  stageAverage(noNights,  value: \.deepDuration),
            deepSleepDelta: deepDelta,
            averageREMSleepYes: stageAverage(yesNights, value: \.remDuration),
            averageREMSleepNo:  stageAverage(noNights,  value: \.remDuration),
            remSleepDelta: remDelta,
            averageAwakeTimeYes: average(yesNights.map(\.awakeDuration)),
            averageAwakeTimeNo:  average(noNights.map(\.awakeDuration)),
            awakeTimeDelta: awakeDelta,
            hasMeaningfulDifference: meaningful
        )
    }

    /// Compare all factors and return results sorted by meaningful difference first,
    /// then by confidence descending.
    func compareAll(
        sessions: [SleepSession],
        contextEntries: [SleepContextEntry],
        adherence: [ProtocolAdherence],
        window: ProtocolComparisonWindow = .last30Days,
        endingAt endDate: Date = Date()
    ) -> [ContextComparisonResult] {
        ContextFactor.allCases.map { factor in
            compare(
                sessions: sessions,
                contextEntries: contextEntries,
                adherence: adherence,
                factor: factor,
                window: window,
                endingAt: endDate
            )
        }
        .sorted { lhs, rhs in
            if lhs.hasMeaningfulDifference != rhs.hasMeaningfulDifference {
                return lhs.hasMeaningfulDifference
            }
            return lhs.confidence.sortOrder > rhs.confidence.sortOrder
        }
    }
}

// MARK: - Private helpers

nonisolated private extension ContextComparisonService {
    /// Returns the Bool? value of `factor` for the given sleep date.
    /// `nil` = unknown (tristate — must NOT be treated as false).
    func factorValue(
        for sleepDateKey: String,
        factor: ContextFactor,
        context: SleepContextEntry?,
        adherence: [ProtocolAdherence]?
    ) -> Bool? {
        switch factor {
        case .caffeineLate:   return context?.caffeineLate
        case .alcohol:        return context?.alcohol
        case .workout:        return context?.workout
        case .lateMeal:       return context?.lateMeal
        case .highStress:     return context?.highStress
        case .screenTimeLate: return context?.screenTimeLate
        case .nap:            return context?.nap
        case .travel:         return context?.travel
        case .protocolTaken:
            return ProtocolComparisonService.status(for: adherence).protocolTaken
        }
    }

    func stageAverage(_ sessions: [SleepSession], value: KeyPath<SleepSession, TimeInterval>) -> TimeInterval? {
        average(sessions.compactMap { session in
            guard session.dataQuality == .detailedStages || session.dataQuality == .mixedSources else { return nil }
            let metric = session[keyPath: value]
            return metric > 0 ? metric : nil
        })
    }

    func stageDifference(
        _ yes: [SleepSession],
        _ no: [SleepSession],
        value: KeyPath<SleepSession, TimeInterval>
    ) -> TimeInterval? {
        guard let yesAvg = stageAverage(yes, value: value),
              let noAvg  = stageAverage(no,  value: value)
        else { return nil }
        return yesAvg - noAvg
    }

    func difference(_ yesValues: [Double], _ noValues: [Double]) -> Double? {
        guard let yesAvg = average(yesValues),
              let noAvg  = average(noValues)
        else { return nil }
        return yesAvg - noAvg
    }

    func average(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    func hasMeaningfulDifference(
        durationDelta:   TimeInterval?,
        efficiencyDelta: Double?,
        deepDelta:       TimeInterval?,
        remDelta:        TimeInterval?,
        awakeDelta:      TimeInterval?
    ) -> Bool {
        if let d = durationDelta,   abs(d) >= Self.meaningfulDurationDelta   { return true }
        if let e = efficiencyDelta, abs(e) >= Self.meaningfulEfficiencyDelta { return true }
        if let d = deepDelta,       abs(d) >= Self.meaningfulStageDelta       { return true }
        if let r = remDelta,        abs(r) >= Self.meaningfulStageDelta       { return true }
        if let a = awakeDelta,      abs(a) >= Self.meaningfulAwakeDelta       { return true }
        return false
    }
}

// MARK: - ComparisonConfidence sort order

nonisolated private extension ComparisonConfidence {
    var sortOrder: Int {
        switch self {
        case .unavailable: 0
        case .low:         1
        case .medium:      2
        case .high:        3
        }
    }
}
