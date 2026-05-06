import Foundation

// MARK: - Supporting Enums

nonisolated enum PerceivedSleepQuality: Int, Codable, CaseIterable, Hashable, Sendable, Identifiable {
    case poor = 1
    case fair = 2
    case good = 3
    case great = 4

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .poor:  "Poor"
        case .fair:  "Fair"
        case .good:  "Good"
        case .great: "Great"
        }
    }

    var emoji: String {
        switch self {
        case .poor:  "😞"
        case .fair:  "😐"
        case .good:  "🙂"
        case .great: "😄"
        }
    }
}

nonisolated enum MorningEnergy: Int, Codable, CaseIterable, Hashable, Sendable, Identifiable {
    case low    = 1
    case fair   = 2
    case good   = 3
    case high   = 4

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .low:  "Low"
        case .fair: "Fair"
        case .good: "Good"
        case .high: "High"
        }
    }

    var emoji: String {
        switch self {
        case .low:  "🪫"
        case .fair: "😴"
        case .good: "⚡"
        case .high: "🔋"
        }
    }
}

nonisolated enum ContextCompletionStatus: String, Codable, Hashable, Sendable {
    /// No fields have been filled in.
    case notFilled
    /// At least one field filled, but not all behavioural Bool? fields.
    case partial
    /// All eight behavioural Bool? fields have an explicit yes/no answer.
    case complete

    var displayName: String {
        switch self {
        case .notFilled: "Not filled"
        case .partial:   "Partial"
        case .complete:  "Complete"
        }
    }
}

// MARK: - Domain Model

/// Records nightly lifestyle context factors for one sleep date.
///
/// All `Bool?` fields use tristate semantics:
/// - `true`  = yes, this happened
/// - `false` = no, this did not happen
/// - `nil`   = unknown / not answered
///
/// Unknown is **never** treated as false in comparisons.
nonisolated struct SleepContextEntry: Codable, Hashable, Sendable, Identifiable {
    var id: UUID
    /// The sleep date this entry belongs to, formatted as `"YYYY-MM-DD"`.
    var sleepDateKey: String

    // MARK: Evening / before-sleep factors
    var caffeineLate:    Bool?
    var alcohol:         Bool?
    var workout:         Bool?
    var lateMeal:        Bool?
    var highStress:      Bool?
    var screenTimeLate:  Bool?
    var nap:             Bool?
    var travel:          Bool?

    // MARK: Morning self-report
    var perceivedSleepQuality: PerceivedSleepQuality?
    var morningEnergy:         MorningEnergy?

    // MARK: Free text (optional)
    var notes: String?

    // MARK: Timestamps
    var createdAt:  Date
    var updatedAt:  Date

    init(
        id: UUID = UUID(),
        sleepDateKey: String,
        caffeineLate:   Bool? = nil,
        alcohol:        Bool? = nil,
        workout:        Bool? = nil,
        lateMeal:       Bool? = nil,
        highStress:     Bool? = nil,
        screenTimeLate: Bool? = nil,
        nap:            Bool? = nil,
        travel:         Bool? = nil,
        perceivedSleepQuality: PerceivedSleepQuality? = nil,
        morningEnergy:         MorningEnergy? = nil,
        notes:    String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id              = id
        self.sleepDateKey    = sleepDateKey
        self.caffeineLate    = caffeineLate
        self.alcohol         = alcohol
        self.workout         = workout
        self.lateMeal        = lateMeal
        self.highStress      = highStress
        self.screenTimeLate  = screenTimeLate
        self.nap             = nap
        self.travel          = travel
        self.perceivedSleepQuality = perceivedSleepQuality
        self.morningEnergy   = morningEnergy
        self.notes           = notes
        self.createdAt       = createdAt
        self.updatedAt       = updatedAt
    }

    // MARK: - Derived

    /// All eight behavioural `Bool?` fields.
    var behaviouralFields: [Bool?] { [caffeineLate, alcohol, workout, lateMeal, highStress, screenTimeLate, nap, travel] }

    /// How completely this entry has been filled in.
    var completionStatus: ContextCompletionStatus {
        let answeredCount = behaviouralFields.filter { $0 != nil }.count
        if answeredCount == 0 && perceivedSleepQuality == nil && morningEnergy == nil && notes == nil {
            return .notFilled
        }
        if answeredCount == behaviouralFields.count {
            return .complete
        }
        return .partial
    }

    var hasNotes: Bool { !(notes?.isEmpty ?? true) }
}
