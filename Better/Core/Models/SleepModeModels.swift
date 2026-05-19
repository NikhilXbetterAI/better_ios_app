import Foundation

nonisolated struct SleepModeSettings: Codable, Hashable, Sendable, Identifiable {
    var id: UUID
    var breathingRounds: Int
    var blackoutAfterBreathing: Bool
    var dimScreenDuringBlackout: Bool
    var playAudioDuringBlackout: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        breathingRounds: Int = 4,
        blackoutAfterBreathing: Bool = true,
        dimScreenDuringBlackout: Bool = true,
        playAudioDuringBlackout: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.breathingRounds = max(1, breathingRounds)
        self.blackoutAfterBreathing = blackoutAfterBreathing
        self.dimScreenDuringBlackout = dimScreenDuringBlackout
        self.playAudioDuringBlackout = playAudioDuringBlackout
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

nonisolated struct SleepModeSchedule: Codable, Hashable, Sendable, Identifiable {
    var id: UUID
    var isEnabled: Bool
    var startHour: Int
    var startMinute: Int
    var endHour: Int
    var endMinute: Int
    /// Calendar weekday values: 1 = Sunday ... 7 = Saturday.
    var activeWeekdays: Set<Int>
    var remindersEnabled: Bool
    var reminderLeadMinutes: Int
    var autoEnterWhenForeground: Bool
    var useFocusChecklist: Bool
    var useScreenTimeShields: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        isEnabled: Bool = false,
        startHour: Int = 22,
        startMinute: Int = 30,
        endHour: Int = 6,
        endMinute: Int = 30,
        activeWeekdays: Set<Int> = Set(1...7),
        remindersEnabled: Bool = true,
        reminderLeadMinutes: Int = 10,
        autoEnterWhenForeground: Bool = true,
        useFocusChecklist: Bool = true,
        useScreenTimeShields: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.isEnabled = isEnabled
        self.startHour = Self.clamped(startHour, lower: 0, upper: 23)
        self.startMinute = Self.clamped(startMinute, lower: 0, upper: 59)
        self.endHour = Self.clamped(endHour, lower: 0, upper: 23)
        self.endMinute = Self.clamped(endMinute, lower: 0, upper: 59)
        self.activeWeekdays = Set(activeWeekdays.filter { (1...7).contains($0) })
        self.remindersEnabled = remindersEnabled
        self.reminderLeadMinutes = max(0, reminderLeadMinutes)
        self.autoEnterWhenForeground = autoEnterWhenForeground
        self.useFocusChecklist = useFocusChecklist
        self.useScreenTimeShields = useScreenTimeShields
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var isOvernight: Bool {
        endMinuteOfDay <= startMinuteOfDay
    }

    var startMinuteOfDay: Int {
        startHour * 60 + startMinute
    }

    var endMinuteOfDay: Int {
        endHour * 60 + endMinute
    }

    var startTimeLabel: String {
        Self.timeLabel(hour: startHour, minute: startMinute)
    }

    var endTimeLabel: String {
        Self.timeLabel(hour: endHour, minute: endMinute)
    }

    private static func clamped(_ value: Int, lower: Int, upper: Int) -> Int {
        min(max(value, lower), upper)
    }

    private static func timeLabel(hour: Int, minute: Int) -> String {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.hour = hour
        components.minute = minute
        let date = components.date ?? Date(timeIntervalSince1970: 0)

        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case isEnabled
        case startHour
        case startMinute
        case endHour
        case endMinute
        case activeWeekdays
        case remindersEnabled
        case reminderLeadMinutes
        case autoEnterWhenForeground
        case useFocusChecklist
        case useScreenTimeShields
        case createdAt
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID(),
            isEnabled: try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? false,
            startHour: try container.decodeIfPresent(Int.self, forKey: .startHour) ?? 22,
            startMinute: try container.decodeIfPresent(Int.self, forKey: .startMinute) ?? 30,
            endHour: try container.decodeIfPresent(Int.self, forKey: .endHour) ?? 6,
            endMinute: try container.decodeIfPresent(Int.self, forKey: .endMinute) ?? 30,
            activeWeekdays: try container.decodeIfPresent(Set<Int>.self, forKey: .activeWeekdays) ?? Set(1...7),
            remindersEnabled: try container.decodeIfPresent(Bool.self, forKey: .remindersEnabled) ?? true,
            reminderLeadMinutes: try container.decodeIfPresent(Int.self, forKey: .reminderLeadMinutes) ?? 10,
            autoEnterWhenForeground: try container.decodeIfPresent(Bool.self, forKey: .autoEnterWhenForeground) ?? true,
            useFocusChecklist: try container.decodeIfPresent(Bool.self, forKey: .useFocusChecklist) ?? true,
            useScreenTimeShields: try container.decodeIfPresent(Bool.self, forKey: .useScreenTimeShields) ?? false,
            createdAt: try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date(),
            updatedAt: try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
        )
    }
}

nonisolated enum SleepModeSessionStartReason: String, Codable, CaseIterable, Hashable, Sendable, Identifiable {
    case manual
    case scheduledForeground
    case notification

    var id: String { rawValue }
}

nonisolated struct SleepModeSession: Codable, Hashable, Sendable, Identifiable {
    var id: UUID
    var sleepDateKey: String
    var startedAt: Date
    var endedAt: Date?
    var startReason: SleepModeSessionStartReason
    var breathingRoundsCompleted: Int
    var blackoutStartedAt: Date?
    var blackoutEndedAt: Date?
    var audioStartedAt: Date?
    var audioEndedAt: Date?
    var screenTimeShieldsEnabled: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        sleepDateKey: String? = nil,
        startedAt: Date,
        endedAt: Date? = nil,
        startReason: SleepModeSessionStartReason = .manual,
        breathingRoundsCompleted: Int = 0,
        blackoutStartedAt: Date? = nil,
        blackoutEndedAt: Date? = nil,
        audioStartedAt: Date? = nil,
        audioEndedAt: Date? = nil,
        screenTimeShieldsEnabled: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        calendar: Calendar = .current
    ) {
        self.id = id
        self.sleepDateKey = sleepDateKey ?? SleepDateKey.sleepDateKey(forSessionStart: startedAt, calendar: calendar)
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.startReason = startReason
        self.breathingRoundsCompleted = max(0, breathingRoundsCompleted)
        self.blackoutStartedAt = blackoutStartedAt
        self.blackoutEndedAt = blackoutEndedAt
        self.audioStartedAt = audioStartedAt
        self.audioEndedAt = audioEndedAt
        self.screenTimeShieldsEnabled = screenTimeShieldsEnabled
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var duration: TimeInterval? {
        endedAt?.timeIntervalSince(startedAt)
    }

    var blackoutDuration: TimeInterval {
        guard let blackoutStartedAt else { return 0 }
        return (blackoutEndedAt ?? endedAt ?? Date()).timeIntervalSince(blackoutStartedAt)
    }

    var audioDuration: TimeInterval {
        guard let audioStartedAt else { return 0 }
        return (audioEndedAt ?? endedAt ?? Date()).timeIntervalSince(audioStartedAt)
    }

    var isActive: Bool {
        endedAt == nil
    }
}
