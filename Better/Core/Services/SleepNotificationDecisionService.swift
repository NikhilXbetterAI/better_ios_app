import Foundation

nonisolated enum SleepNotificationType: String, Codable, CaseIterable, Hashable, Sendable, Identifiable {
    case durationBelowBaseline
    case durationAboveBaseline
    case efficiencyDrop
    case poorSleepStreak
    case recovery
    case baselineAvailable

    var id: String { rawValue }

    var alertKind: SleepAlertKind {
        switch self {
        case .durationBelowBaseline:
            .sleepDurationBelowBaseline
        case .durationAboveBaseline:
            .sleepDurationAboveBaseline
        case .efficiencyDrop:
            .sleepEfficiencyDrop
        case .poorSleepStreak:
            .poorSleepStreak
        case .recovery:
            .recoveryTrend
        case .baselineAvailable:
            .baselineAvailable
        }
    }
}

nonisolated struct NotificationDecision: Codable, Hashable, Sendable, Identifiable {
    var id: String { "\(notificationType.rawValue)|\(createdAt.timeIntervalSince1970)" }
    var shouldNotify: Bool
    var notificationType: SleepNotificationType
    var title: String
    var body: String
    var reason: String
    var cooldownApplied: Bool
    var confidence: ComparisonConfidence
    var createdAt: Date
}

nonisolated struct SleepNotificationDecisionInput: Sendable {
    var latestSession: SleepSession
    var recentSessions: [SleepSession]
    var baseline: SleepBaseline
    var previousAlerts: [SleepAlert]
    var createdAt: Date
}

nonisolated struct SleepNotificationDecisionService: Sendable {
    private let calendar: Calendar

    init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    func decisions(input: SleepNotificationDecisionInput) -> [NotificationDecision] {
        let baselineConfidence = BaselineEngine.confidence(validNightCount: input.baseline.validNights)
        guard baselineConfidence != .unavailable else {
            return [
                suppressed(
                    .durationBelowBaseline,
                    title: "Sleep insight unavailable",
                    reason: "Baseline confidence is unavailable.",
                    confidence: baselineConfidence,
                    createdAt: input.createdAt
                )
            ]
        }

        var candidates: [NotificationDecision] = []
        candidates.append(contentsOf: baselineDurationCandidates(input: input, confidence: baselineConfidence))
        candidates.append(contentsOf: efficiencyCandidates(input: input, confidence: baselineConfidence))
        candidates.append(contentsOf: streakCandidates(input: input, confidence: baselineConfidence))
        candidates.append(contentsOf: baselineAvailableCandidates(input: input, confidence: baselineConfidence))

        let notifiable = candidates
            .filter(\.shouldNotify)
            .sorted { priority($0.notificationType) > priority($1.notificationType) }

        guard let selected = notifiable.first else {
            return candidates.isEmpty
                ? [suppressed(.durationBelowBaseline, title: "No sleep notification", reason: "No meaningful sleep change.", confidence: baselineConfidence, createdAt: input.createdAt)]
                : candidates
        }

        return candidates.map { decision in
            guard decision.notificationType != selected.notificationType, decision.shouldNotify else { return decision }
            var updated = decision
            updated.shouldNotify = false
            updated.reason = "Another sleep insight notification was selected for today."
            updated.cooldownApplied = true
            return updated
        }
    }
}

nonisolated private extension SleepNotificationDecisionService {
    func baselineDurationCandidates(input: SleepNotificationDecisionInput, confidence: ComparisonConfidence) -> [NotificationDecision] {
        let deltaMinutes = (input.latestSession.totalSleepTime - input.baseline.totalSleepAverage) / 60
        guard abs(deltaMinutes) >= 45 else {
            return [
                suppressed(
                    .durationBelowBaseline,
                    title: "Sleep duration change is small",
                    reason: "Duration delta is below the 45 minute threshold.",
                    confidence: confidence,
                    createdAt: input.createdAt
                )
            ]
        }

        let type: SleepNotificationType = deltaMinutes < 0 ? .durationBelowBaseline : .durationAboveBaseline
        guard !isCoolingDown(type.alertKind, previousAlerts: input.previousAlerts, createdAt: input.createdAt, days: 2) else {
            return [suppressed(type, title: "Duration cooldown", reason: "Duration notification cooldown is active.", confidence: confidence, createdAt: input.createdAt, cooldown: true)]
        }

        let minutes = Int(abs(deltaMinutes).rounded())
        let direction = deltaMinutes < 0 ? "below" : "above"
        return [
            NotificationDecision(
                shouldNotify: true,
                notificationType: type,
                title: deltaMinutes < 0 ? "Sleep was below baseline" : "Sleep was above baseline",
                body: "Your sleep duration was \(minutes) minutes \(direction) your baseline.",
                reason: "Duration delta exceeded the 45 minute threshold.",
                cooldownApplied: false,
                confidence: confidence,
                createdAt: input.createdAt
            )
        ]
    }

    func efficiencyCandidates(input: SleepNotificationDecisionInput, confidence: ComparisonConfidence) -> [NotificationDecision] {
        let delta = input.latestSession.efficiency - input.baseline.efficiencyAverage
        guard delta <= -0.05 else {
            return [
                suppressed(
                    .efficiencyDrop,
                    title: "Efficiency change is small",
                    reason: "Efficiency drop is below the 5 percentage point threshold.",
                    confidence: confidence,
                    createdAt: input.createdAt
                )
            ]
        }
        guard !isCoolingDown(.sleepEfficiencyDrop, previousAlerts: input.previousAlerts, createdAt: input.createdAt, days: 3) else {
            return [suppressed(.efficiencyDrop, title: "Efficiency cooldown", reason: "Efficiency notification cooldown is active.", confidence: confidence, createdAt: input.createdAt, cooldown: true)]
        }

        return [
            NotificationDecision(
                shouldNotify: true,
                notificationType: .efficiencyDrop,
                title: "Sleep efficiency dipped",
                body: "Sleep efficiency was meaningfully below your baseline.",
                reason: "Efficiency dropped by at least 5 percentage points.",
                cooldownApplied: false,
                confidence: confidence,
                createdAt: input.createdAt
            )
        ]
    }

    func streakCandidates(input: SleepNotificationDecisionInput, confidence: ComparisonConfidence) -> [NotificationDecision] {
        let ordered = input.recentSessions
            .filter { $0.sleepDateKey <= input.latestSession.sleepDateKey }
            .sorted { $0.sleepDateKey < $1.sleepDateKey }
            .suffix(3)
        guard ordered.count >= 3 else { return [] }

        let poorCount = ordered.filter { $0.qualityScore.overall < 70 || $0.totalSleepTime < input.baseline.totalSleepAverage - 45 * 60 }.count
        if poorCount >= 3 {
            guard !isCoolingDown(.poorSleepStreak, previousAlerts: input.previousAlerts, createdAt: input.createdAt, days: 3) else {
                return [suppressed(.poorSleepStreak, title: "Poor streak cooldown", reason: "Poor streak notification cooldown is active.", confidence: confidence, createdAt: input.createdAt, cooldown: true)]
            }
            return [
                NotificationDecision(
                    shouldNotify: true,
                    notificationType: .poorSleepStreak,
                    title: "Sleep has been lower recently",
                    body: "The last few nights have been below your usual range.",
                    reason: "Three recent nights were below the poor-night threshold.",
                    cooldownApplied: false,
                    confidence: confidence,
                    createdAt: input.createdAt
                )
            ]
        }

        let previousTwo = ordered.dropLast()
        if previousTwo.count == 2,
           previousTwo.allSatisfy({ $0.qualityScore.overall < 70 }),
           input.latestSession.qualityScore.overall >= 75 {
            guard !isCoolingDown(.recoveryTrend, previousAlerts: input.previousAlerts, createdAt: input.createdAt, days: 2) else {
                return [suppressed(.recovery, title: "Recovery cooldown", reason: "Recovery notification cooldown is active.", confidence: confidence, createdAt: input.createdAt, cooldown: true)]
            }
            return [
                NotificationDecision(
                    shouldNotify: true,
                    notificationType: .recovery,
                    title: "Sleep moved back toward normal",
                    body: "After a lower stretch, last night moved back into your usual range.",
                    reason: "Latest night recovered after two lower-scoring nights.",
                    cooldownApplied: false,
                    confidence: confidence,
                    createdAt: input.createdAt
                )
            ]
        }

        return []
    }

    func baselineAvailableCandidates(input: SleepNotificationDecisionInput, confidence: ComparisonConfidence) -> [NotificationDecision] {
        guard confidence == .medium || confidence == .high else { return [] }
        guard !input.previousAlerts.contains(where: { $0.kind == .baselineAvailable }) else { return [] }
        return [
            NotificationDecision(
                shouldNotify: true,
                notificationType: .baselineAvailable,
                title: "Your sleep baseline is ready",
                body: "Your recent nights now support more useful baseline comparisons.",
                reason: "Baseline confidence became available.",
                cooldownApplied: false,
                confidence: confidence,
                createdAt: input.createdAt
            )
        ]
    }

    func suppressed(
        _ type: SleepNotificationType,
        title: String,
        reason: String,
        confidence: ComparisonConfidence,
        createdAt: Date,
        cooldown: Bool = false
    ) -> NotificationDecision {
        NotificationDecision(
            shouldNotify: false,
            notificationType: type,
            title: title,
            body: "",
            reason: reason,
            cooldownApplied: cooldown,
            confidence: confidence,
            createdAt: createdAt
        )
    }

    func isCoolingDown(_ kind: SleepAlertKind, previousAlerts: [SleepAlert], createdAt: Date, days: Int) -> Bool {
        let interval = TimeInterval(days * 86_400)
        return previousAlerts.contains { alert in
            alert.kind == kind && createdAt.timeIntervalSince(alert.createdAt) >= 0 && createdAt.timeIntervalSince(alert.createdAt) < interval
        }
    }

    func priority(_ type: SleepNotificationType) -> Int {
        switch type {
        case .recovery:
            100
        case .baselineAvailable:
            95
        case .poorSleepStreak:
            90
        case .durationBelowBaseline, .durationAboveBaseline:
            70
        case .efficiencyDrop:
            60
        }
    }
}
