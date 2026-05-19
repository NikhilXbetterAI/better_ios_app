import Foundation

nonisolated enum SleepContinuityCategory: String, Codable, CaseIterable, Hashable, Sendable, Identifiable {
    case unavailable
    case exceptional
    case strong
    case good
    case moderatelyFragmented
    case highlyFragmented

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .unavailable:
            "Not enough data"
        case .exceptional:
            "Exceptional continuity"
        case .strong:
            "Strong continuity"
        case .good:
            "Good continuity"
        case .moderatelyFragmented:
            "Moderately fragmented"
        case .highlyFragmented:
            "Highly fragmented"
        }
    }

    var userMessage: String {
        switch self {
        case .unavailable:
            "Not enough sleep-stage data to calculate continuity."
        case .exceptional:
            "Your body maintained an exceptional uninterrupted recovery stretch."
        case .strong:
            "Your body maintained one strong recovery period."
        case .good:
            "Your body maintained one solid recovery period before interruptions."
        case .moderatelyFragmented:
            "Your sleep had moderate fragmentation overnight."
        case .highlyFragmented:
            "Your recovery was highly fragmented overnight."
        }
    }
}

nonisolated struct SleepContinuityBlock: Codable, Hashable, Sendable, Identifiable {
    var id: UUID
    var index: Int
    var startDate: Date
    var endDate: Date
    var sleepDuration: TimeInterval
    var includedShortAwakeDuration: TimeInterval
    var shortAwakeningCount: Int

    init(
        id: UUID = UUID(),
        index: Int,
        startDate: Date,
        endDate: Date,
        sleepDuration: TimeInterval,
        includedShortAwakeDuration: TimeInterval = 0,
        shortAwakeningCount: Int = 0
    ) {
        self.id = id
        self.index = index
        self.startDate = startDate
        self.endDate = endDate
        self.sleepDuration = sleepDuration
        self.includedShortAwakeDuration = includedShortAwakeDuration
        self.shortAwakeningCount = shortAwakeningCount
    }
}

nonisolated struct SleepContinuitySummary: Codable, Hashable, Sendable {
    var blocks: [SleepContinuityBlock]
    var longestBlockDuration: TimeInterval
    var longestBlockIndex: Int?
    var meaningfulAwakeningCount: Int
    var continuityCategory: SleepContinuityCategory

    static let unavailable = SleepContinuitySummary(
        blocks: [],
        longestBlockDuration: 0,
        longestBlockIndex: nil,
        meaningfulAwakeningCount: 0,
        continuityCategory: .unavailable
    )
}

nonisolated extension SleepSession {
    var restorativeSleepDuration: TimeInterval {
        deepDuration + remDuration
    }

    var continuitySummary: SleepContinuitySummary {
        SleepContinuityCalculator.summary(for: stages)
    }
}
