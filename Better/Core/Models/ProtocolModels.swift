import Foundation

nonisolated enum SleepAlertKind: String, Codable, CaseIterable, Hashable, Sendable, Identifiable {
    case analysisReady
    case lowScore
    case lowDeepSleep
    case lowRemSleep
    case sleepDebt
    case highWASO
    case lowHRV
    case lowOxygenSaturation
    case irregularSchedule
    case improvementTrend
    case missedProtocol
    case sleepDurationBelowBaseline
    case sleepDurationAboveBaseline
    case sleepEfficiencyDrop
    case poorSleepStreak
    case recoveryTrend
    case baselineAvailable
    case protocolPattern

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .analysisReady:
            "Analysis Ready"
        case .lowScore:
            "Low Score"
        case .lowDeepSleep:
            "Low Deep Sleep"
        case .lowRemSleep:
            "Low REM"
        case .sleepDebt:
            "Sleep Debt"
        case .highWASO:
            "High WASO"
        case .lowHRV:
            "Low HRV"
        case .lowOxygenSaturation:
            "Low SpO2"
        case .irregularSchedule:
            "Irregular Schedule"
        case .improvementTrend:
            "Improvement Trend"
        case .missedProtocol:
            "Missed Protocol"
        case .sleepDurationBelowBaseline:
            "Below Baseline"
        case .sleepDurationAboveBaseline:
            "Above Baseline"
        case .sleepEfficiencyDrop:
            "Efficiency Drop"
        case .poorSleepStreak:
            "Poor Sleep Streak"
        case .recoveryTrend:
            "Recovery Trend"
        case .baselineAvailable:
            "Baseline Available"
        case .protocolPattern:
            "Protocol Pattern"
        }
    }
}

nonisolated struct SleepAlert: Codable, Hashable, Sendable, Identifiable {
    var id: UUID
    var kind: SleepAlertKind
    var title: String
    var body: String
    var sleepDateKey: String?
    var severity: Int
    var isRead: Bool
    var createdAt: Date
    var readAt: Date?

    init(
        id: UUID = UUID(),
        kind: SleepAlertKind,
        title: String,
        body: String,
        sleepDateKey: String? = nil,
        severity: Int = 0,
        isRead: Bool = false,
        createdAt: Date = Date(),
        readAt: Date? = nil
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.body = body
        self.sleepDateKey = sleepDateKey
        self.severity = severity
        self.isRead = isRead
        self.createdAt = createdAt
        self.readAt = readAt
    }
}

nonisolated struct ProtocolItem: Codable, Hashable, Sendable, Identifiable {
    var id: UUID
    var name: String
    var dose: String
    var benefit: String
    var instructions: String
    var isActive: Bool
    var sortOrder: Int
    var colorHex: String?

    init(
        id: UUID = UUID(),
        name: String,
        dose: String,
        benefit: String,
        instructions: String,
        isActive: Bool = true,
        sortOrder: Int = 0,
        colorHex: String? = nil
    ) {
        self.id = id
        self.name = name
        self.dose = dose
        self.benefit = benefit
        self.instructions = instructions
        self.isActive = isActive
        self.sortOrder = sortOrder
        self.colorHex = colorHex
    }
}

nonisolated struct ProtocolAdherence: Codable, Hashable, Sendable, Identifiable {
    var id: UUID
    var protocolID: String
    var dateKey: String
    var taken: Bool
    var takenAt: Date?
    var note: String?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        protocolID: String,
        dateKey: String,
        taken: Bool,
        takenAt: Date? = nil,
        note: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.protocolID = protocolID
        self.dateKey = dateKey
        self.taken = taken
        self.takenAt = takenAt
        self.note = note
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

nonisolated struct UserProfile: Codable, Hashable, Sendable, Identifiable {
    var id: UUID
    var sleepGoalHours: Double
    var baselineWindowDays: Int
    var isResearchMode: Bool
    var hasCompletedOnboarding: Bool
    var displayName: String?
    var sleepAssessmentAnswers: [SleepAssessmentAnswer]
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        sleepGoalHours: Double = 8,
        baselineWindowDays: Int = 30,
        isResearchMode: Bool = false,
        hasCompletedOnboarding: Bool = false,
        displayName: String? = nil,
        sleepAssessmentAnswers: [SleepAssessmentAnswer] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.sleepGoalHours = sleepGoalHours
        self.baselineWindowDays = baselineWindowDays
        self.isResearchMode = isResearchMode
        self.hasCompletedOnboarding = hasCompletedOnboarding
        self.displayName = displayName
        self.sleepAssessmentAnswers = sleepAssessmentAnswers
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

nonisolated extension UserProfile {
    mutating func normalizeForStorage() {
        displayName = displayName?.trimmedNonEmpty
    }
}

nonisolated extension String {
    var trimmedNonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
