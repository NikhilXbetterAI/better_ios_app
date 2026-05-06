import Foundation
import OSLog

nonisolated enum ProtocolComparisonWindow: String, Codable, CaseIterable, Hashable, Sendable, Identifiable {
    case last7Days
    case last15Days
    case last30Days
    case all

    var id: String { rawValue }

    var dayCount: Int? {
        switch self {
        case .last7Days:
            7
        case .last15Days:
            15
        case .last30Days:
            30
        case .all:
            nil
        }
    }
}

nonisolated struct ProtocolComparisonResult: Codable, Hashable, Sendable {
    var window: ProtocolComparisonWindow
    var takenNightCount: Int
    var notTakenNightCount: Int
    var unknownNightCount: Int
    var confidence: ComparisonConfidence
    var averageTotalSleepTaken: TimeInterval?
    var averageTotalSleepNotTaken: TimeInterval?
    var deltaTotalSleep: TimeInterval?
    var averageEfficiencyTaken: Double?
    var averageEfficiencyNotTaken: Double?
    var deltaEfficiency: Double?
    var averageDeepSleepTaken: TimeInterval?
    var averageDeepSleepNotTaken: TimeInterval?
    var deltaDeepSleep: TimeInterval?
    var averageREMSleepTaken: TimeInterval?
    var averageREMSleepNotTaken: TimeInterval?
    var deltaREMSleep: TimeInterval?
    var averageAwakeTimeTaken: TimeInterval?
    var averageAwakeTimeNotTaken: TimeInterval?
    var deltaAwakeTime: TimeInterval?
}

nonisolated struct ProtocolComparisonService: Sendable {
    private let calendar: Calendar
    private let logger = Logger(subsystem: "Better", category: "ProtocolComparison")

    init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    func compare(
        sessions: [SleepSession],
        adherence: [ProtocolAdherence],
        window: ProtocolComparisonWindow = .last30Days,
        endingAt endDate: Date = Date()
    ) -> ProtocolComparisonResult {
        let eligibleSessions = sessions
            .filter { BaselineEngine.isValidNight($0, calendar: calendar) }
            .filter { session in
                guard let days = window.dayCount else { return true }
                guard let sleepDate = SleepDateKey.date(from: session.sleepDateKey, calendar: calendar) else { return false }
                let start = calendar.date(byAdding: .day, value: -days + 1, to: calendar.startOfDay(for: endDate))
                    ?? endDate.addingTimeInterval(Double(-days + 1) * 86_400)
                return sleepDate >= calendar.startOfDay(for: start) && sleepDate <= calendar.startOfDay(for: endDate)
            }
            .sorted { $0.sleepDateKey < $1.sleepDateKey }

        let adherenceByDate = Dictionary(grouping: adherence, by: \.dateKey)
        let grouped = Dictionary(grouping: eligibleSessions) { session in
            Self.status(for: adherenceByDate[session.sleepDateKey])
        }
        let taken = grouped[.taken, default: []]
        let notTaken = grouped[.notTaken, default: []]
        let unknown = grouped[.unknown, default: []]
        let confidence = Self.confidence(takenCount: taken.count, notTakenCount: notTaken.count)

        logger.debug(
            "Protocol comparison counts taken=\(taken.count, privacy: .public) notTaken=\(notTaken.count, privacy: .public) unknown=\(unknown.count, privacy: .public)"
        )

        return ProtocolComparisonResult(
            window: window,
            takenNightCount: taken.count,
            notTakenNightCount: notTaken.count,
            unknownNightCount: unknown.count,
            confidence: confidence,
            averageTotalSleepTaken: Self.average(taken.map(\.totalSleepTime)),
            averageTotalSleepNotTaken: Self.average(notTaken.map(\.totalSleepTime)),
            deltaTotalSleep: Self.difference(taken.map(\.totalSleepTime), notTaken.map(\.totalSleepTime)),
            averageEfficiencyTaken: Self.average(taken.map(\.efficiency)),
            averageEfficiencyNotTaken: Self.average(notTaken.map(\.efficiency)),
            deltaEfficiency: Self.difference(taken.map(\.efficiency), notTaken.map(\.efficiency)),
            averageDeepSleepTaken: Self.stageAverage(taken, value: \.deepDuration),
            averageDeepSleepNotTaken: Self.stageAverage(notTaken, value: \.deepDuration),
            deltaDeepSleep: Self.stageDifference(taken, notTaken, value: \.deepDuration),
            averageREMSleepTaken: Self.stageAverage(taken, value: \.remDuration),
            averageREMSleepNotTaken: Self.stageAverage(notTaken, value: \.remDuration),
            deltaREMSleep: Self.stageDifference(taken, notTaken, value: \.remDuration),
            averageAwakeTimeTaken: Self.average(taken.map(\.awakeDuration)),
            averageAwakeTimeNotTaken: Self.average(notTaken.map(\.awakeDuration)),
            deltaAwakeTime: Self.difference(taken.map(\.awakeDuration), notTaken.map(\.awakeDuration))
        )
    }

    static func status(for adherence: [ProtocolAdherence]?) -> ProtocolUsageStatus {
        guard let adherence, !adherence.isEmpty else { return .unknown }
        return adherence.contains(where: \.taken) ? .taken : .notTaken
    }

    static func confidence(takenCount: Int, notTakenCount: Int) -> ComparisonConfidence {
        let minimum = min(takenCount, notTakenCount)
        switch minimum {
        case 7...:
            return .high
        case 4...6:
            return .medium
        case 2...3:
            return .low
        default:
            return .unavailable
        }
    }

    private static func stageAverage(_ sessions: [SleepSession], value: KeyPath<SleepSession, TimeInterval>) -> TimeInterval? {
        average(sessions.compactMap { session in
            guard session.dataQuality == .detailedStages || session.dataQuality == .mixedSources else { return nil }
            let metric = session[keyPath: value]
            return metric > 0 ? metric : nil
        })
    }

    private static func stageDifference(
        _ taken: [SleepSession],
        _ notTaken: [SleepSession],
        value: KeyPath<SleepSession, TimeInterval>
    ) -> TimeInterval? {
        guard let takenAverage = stageAverage(taken, value: value),
              let notTakenAverage = stageAverage(notTaken, value: value)
        else { return nil }
        return takenAverage - notTakenAverage
    }

    private static func difference(_ takenValues: [Double], _ notTakenValues: [Double]) -> Double? {
        guard let takenAverage = average(takenValues),
              let notTakenAverage = average(notTakenValues)
        else { return nil }
        return takenAverage - notTakenAverage
    }

    private static func average(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }
}
