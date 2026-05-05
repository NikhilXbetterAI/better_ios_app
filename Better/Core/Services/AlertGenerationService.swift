import Foundation
@preconcurrency import UserNotifications

nonisolated struct AlertGenerationSettings: Sendable, Hashable {
    var lowScoreThreshold: Double
    var shortSleepGrace: TimeInterval
    var lowDeepAbsoluteMinimum: TimeInterval
    var lowRemAbsoluteMinimum: TimeInterval
    var highWASOThreshold: TimeInterval
    var lowHRVBaselineFraction: Double
    var oxygenSaturationAverageMinimum: Double
    var oxygenSaturationMinimumThreshold: Double
    var scheduleVariabilityThresholdMinutes: Double
    var protocolMissMonitoringEnabled: Bool
    var protocolMissCutoffHour: Int
    var localNotificationsEnabled: Bool
    var notificationEnabledKinds: Set<SleepAlertKind>

    static let `default` = AlertGenerationSettings(
        lowScoreThreshold: 70,
        shortSleepGrace: 60 * 60,
        lowDeepAbsoluteMinimum: 60 * 60,
        lowRemAbsoluteMinimum: 75 * 60,
        highWASOThreshold: 45 * 60,
        lowHRVBaselineFraction: 0.80,
        oxygenSaturationAverageMinimum: 0.94,
        oxygenSaturationMinimumThreshold: 0.90,
        scheduleVariabilityThresholdMinutes: 60,
        protocolMissMonitoringEnabled: false,
        protocolMissCutoffHour: 22,
        localNotificationsEnabled: false,
        notificationEnabledKinds: [.lowScore, .sleepDebt, .lowOxygenSaturation, .missedProtocol]
    )
}

nonisolated enum LocalNotificationAuthorizationState: Sendable, Hashable {
    case notDetermined
    case denied
    case authorized
}

nonisolated protocol LocalNotificationScheduling: Sendable {
    func authorizationState() async -> LocalNotificationAuthorizationState
    func scheduleNotification(identifier: String, title: String, body: String) async throws
}

nonisolated actor UserNotificationScheduler: LocalNotificationScheduling {
    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func authorizationState() async -> LocalNotificationAuthorizationState {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return .authorized
        case .denied:
            return .denied
        case .notDetermined:
            return .notDetermined
        @unknown default:
            return .denied
        }
    }

    func scheduleNotification(identifier: String, title: String, body: String) async throws {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        try await center.add(request)
    }
}

actor AlertGenerationService {
    private let calendar: Calendar
    private let notificationScheduler: LocalNotificationScheduling?

    init(
        calendar: Calendar = .current,
        notificationScheduler: LocalNotificationScheduling? = UserNotificationScheduler()
    ) {
        self.calendar = calendar
        self.notificationScheduler = notificationScheduler
    }

    @discardableResult
    func generateAlerts(
        latestSession: SleepSession,
        recentSessions: [SleepSession],
        baseline: SleepBaseline,
        profile: UserProfile,
        adherence: [ProtocolAdherence],
        settings: AlertGenerationSettings = .default,
        createdAt: Date = Date()
    ) async throws -> [SleepAlert] {
        let alerts = deduplicated(
            alerts: buildAlerts(
                latestSession: latestSession,
                recentSessions: recentSessions,
                baseline: baseline,
                profile: profile,
                adherence: adherence,
                settings: settings,
                createdAt: createdAt
            )
        )

        try await scheduleNotificationIfAllowed(for: alerts, settings: settings)
        return alerts
    }

    @discardableResult
    func generateAlerts(
        sessions: [SleepSession],
        recentSessions: [SleepSession],
        baseline: SleepBaseline,
        profile: UserProfile,
        adherence: [ProtocolAdherence],
        settings: AlertGenerationSettings = .default,
        createdAt: Date = Date()
    ) async throws -> [SleepAlert] {
        var allAlerts: [SleepAlert] = []
        for session in sessions {
            let sessionRecent = recentSessions.filter { $0.endDate <= session.endDate }
            let alerts = try await generateAlerts(
                latestSession: session,
                recentSessions: sessionRecent,
                baseline: baseline,
                profile: profile,
                adherence: adherence,
                settings: settings,
                createdAt: createdAt
            )
            allAlerts.append(contentsOf: alerts)
        }
        return deduplicated(alerts: allAlerts)
    }
}

private extension AlertGenerationService {
    func buildAlerts(
        latestSession session: SleepSession,
        recentSessions: [SleepSession],
        baseline: SleepBaseline,
        profile: UserProfile,
        adherence: [ProtocolAdherence],
        settings: AlertGenerationSettings,
        createdAt: Date
    ) -> [SleepAlert] {
        var alerts = [
            alert(
                .analysisReady,
                session: session,
                title: "Sleep analysis ready",
                body: "Your sleep dashboard has been updated.",
                severity: 0,
                createdAt: createdAt
            )
        ]

        if session.qualityScore.overall < settings.lowScoreThreshold {
            alerts.append(
                alert(
                    .lowScore,
                    session: session,
                    title: "Low sleep score",
                    body: "Your sleep score was \(Int(session.qualityScore.overall.rounded())), below your alert threshold.",
                    severity: 2,
                    createdAt: createdAt
                )
            )
        }

        let goalSeconds = profile.sleepGoalHours * 3_600
        if goalSeconds - session.totalSleepTime > settings.shortSleepGrace {
            alerts.append(
                alert(
                    .sleepDebt,
                    session: session,
                    title: "Short sleep detected",
                    body: "You slept \(formatDuration(session.totalSleepTime)), more than 1 hour below your \(formatHours(profile.sleepGoalHours)) goal.",
                    severity: 2,
                    createdAt: createdAt
                )
            )
        }

        if session.dataQuality == .detailedStages {
            if isBelowBaselineOrMinimum(
                value: session.deepDuration,
                average: baseline.deepAverage,
                standardDeviation: baseline.deepStandardDeviation,
                minimum: settings.lowDeepAbsoluteMinimum
            ) {
                alerts.append(
                    alert(
                        .lowDeepSleep,
                        session: session,
                        title: "Deep sleep below baseline",
                        body: "Deep sleep was \(formatDuration(session.deepDuration)), below your rolling baseline range.",
                        severity: 1,
                        createdAt: createdAt
                    )
                )
            }

            if isBelowBaselineOrMinimum(
                value: session.remDuration,
                average: baseline.remAverage,
                standardDeviation: baseline.remStandardDeviation,
                minimum: settings.lowRemAbsoluteMinimum
            ) {
                alerts.append(
                    alert(
                        .lowRemSleep,
                        session: session,
                        title: "REM sleep below baseline",
                        body: "REM sleep was \(formatDuration(session.remDuration)), below your rolling baseline range.",
                        severity: 1,
                        createdAt: createdAt
                    )
                )
            }
        }

        if session.waso > settings.highWASOThreshold {
            alerts.append(
                alert(
                    .highWASO,
                    session: session,
                    title: "More awake time overnight",
                    body: "Awake time after sleep onset was \(formatDuration(session.waso)), above your alert threshold.",
                    severity: 1,
                    createdAt: createdAt
                )
            )
        }

        if let hrv = session.biometrics?.hrvAverage,
           baseline.hrvAverage > 0,
           hrv < baseline.hrvAverage * settings.lowHRVBaselineFraction {
            alerts.append(
                alert(
                    .lowHRV,
                    session: session,
                    title: "HRV below baseline",
                    body: "Average HRV was \(Int(hrv.rounded())) ms, below 80% of your baseline.",
                    severity: 1,
                    createdAt: createdAt
                )
            )
        }

        if let oxygenAlert = oxygenSaturationAlert(
            for: session,
            settings: settings,
            createdAt: createdAt
        ) {
            alerts.append(oxygenAlert)
        }

        if baseline.bedtimeMinuteStandardDeviation > settings.scheduleVariabilityThresholdMinutes ||
            baseline.wakeMinuteStandardDeviation > settings.scheduleVariabilityThresholdMinutes {
            alerts.append(
                alert(
                    .irregularSchedule,
                    session: session,
                    title: "Schedule variability increased",
                    body: "Your bedtime or wake time varied by more than 60 minutes across the baseline window.",
                    severity: 1,
                    createdAt: createdAt
                )
            )
        }

        if let improvement = improvementAlert(
            for: session,
            recentSessions: recentSessions,
            createdAt: createdAt
        ) {
            alerts.append(improvement)
        }

        if settings.protocolMissMonitoringEnabled,
           hasPassedProtocolCutoff(on: createdAt, cutoffHour: settings.protocolMissCutoffHour),
           adherence.filter(\.taken).contains(where: { $0.dateKey == session.sleepDateKey }) == false {
            alerts.append(
                alert(
                    .missedProtocol,
                    session: session,
                    title: "Protocol not logged",
                    body: "No protocol adherence was logged by your cutoff time.",
                    severity: 0,
                    createdAt: createdAt
                )
            )
        }

        return alerts
    }

    func oxygenSaturationAlert(
        for session: SleepSession,
        settings: AlertGenerationSettings,
        createdAt: Date
    ) -> SleepAlert? {
        guard
            let average = session.biometrics?.oxygenSaturationAverage,
            let minimum = session.biometrics?.oxygenSaturationMinimum
        else {
            return nil
        }

        guard average < settings.oxygenSaturationAverageMinimum ||
            minimum < settings.oxygenSaturationMinimumThreshold
        else {
            return nil
        }

        return alert(
            .lowOxygenSaturation,
            session: session,
            title: "Oxygen saturation dipped",
            body: "Average SpO2 was \(Int((average * 100).rounded()))%, with a minimum of \(Int((minimum * 100).rounded()))%.",
            severity: 2,
            createdAt: createdAt
        )
    }

    func improvementAlert(
        for session: SleepSession,
        recentSessions: [SleepSession],
        createdAt: Date
    ) -> SleepAlert? {
        let ordered = recentSessions
            .filter { $0.endDate <= session.endDate }
            .sorted { $0.endDate < $1.endDate }
            .suffix(7)

        guard ordered.count == 7, let first = ordered.first else { return nil }

        let scoreImproved = session.qualityScore.overall - first.qualityScore.overall >= 5
        let deepImproved = session.dataQuality == .detailedStages &&
            first.dataQuality == .detailedStages &&
            session.deepDuration - first.deepDuration >= 15 * 60

        guard scoreImproved || deepImproved else { return nil }

        let body = scoreImproved
            ? "Your sleep score has trended upward over the last 7 nights."
            : "Deep sleep has trended upward over the last 7 nights."

        return alert(
            .improvementTrend,
            session: session,
            title: "Sleep trend improved",
            body: body,
            severity: 0,
            createdAt: createdAt
        )
    }

    func hasPassedProtocolCutoff(on date: Date, cutoffHour: Int) -> Bool {
        let hour = calendar.component(.hour, from: date)
        return hour >= cutoffHour
    }

    func isBelowBaselineOrMinimum(
        value: TimeInterval,
        average: TimeInterval,
        standardDeviation: TimeInterval,
        minimum: TimeInterval
    ) -> Bool {
        if value < minimum {
            return true
        }

        guard average > 0 else { return false }
        return value < average - max(standardDeviation, 0)
    }

    func alert(
        _ kind: SleepAlertKind,
        session: SleepSession,
        title: String,
        body: String,
        severity: Int,
        createdAt: Date
    ) -> SleepAlert {
        SleepAlert(
            id: Self.deterministicUUID("\(kind.rawValue)|\(session.sleepDateKey)"),
            kind: kind,
            title: title,
            body: body,
            sleepDateKey: session.sleepDateKey,
            severity: severity,
            createdAt: createdAt
        )
    }

    func deduplicated(alerts: [SleepAlert]) -> [SleepAlert] {
        var seenIDs = Set<UUID>()
        return alerts.filter { alert in
            seenIDs.insert(alert.id).inserted
        }
    }

    func scheduleNotificationIfAllowed(
        for alerts: [SleepAlert],
        settings: AlertGenerationSettings
    ) async throws {
        guard settings.localNotificationsEnabled, let notificationScheduler else { return }

        let notifiableAlerts = alerts.filter { settings.notificationEnabledKinds.contains($0.kind) }
        guard !notifiableAlerts.isEmpty else { return }
        guard await notificationScheduler.authorizationState() == .authorized else { return }

        if notifiableAlerts.count > 1, let analysisAlert = alerts.first(where: { $0.kind == .analysisReady }) {
            try await notificationScheduler.scheduleNotification(
                identifier: "notification|\(analysisAlert.id.uuidString)",
                title: "Sleep analysis ready",
                body: "\(notifiableAlerts.count) sleep insights are ready to review."
            )
        } else if let alert = notifiableAlerts.first {
            try await notificationScheduler.scheduleNotification(
                identifier: "notification|\(alert.id.uuidString)",
                title: alert.title,
                body: alert.body
            )
        }
    }

    func formatDuration(_ duration: TimeInterval) -> String {
        let totalMinutes = max(0, Int((duration / 60).rounded()))
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours == 0 {
            return "\(minutes)m"
        }
        return "\(hours)h \(minutes)m"
    }

    func formatHours(_ hours: Double) -> String {
        if hours.rounded() == hours {
            return "\(Int(hours))h"
        }
        return String(format: "%.1fh", hours)
    }

    static func deterministicUUID(_ key: String) -> UUID {
        var bytes = [UInt8](repeating: 0, count: 16)
        for (index, byte) in key.utf8.enumerated() {
            bytes[index % 16] = bytes[index % 16] &+ byte &+ UInt8(truncatingIfNeeded: index)
        }
        bytes[6] = (bytes[6] & 0x0F) | 0x40
        bytes[8] = (bytes[8] & 0x3F) | 0x80

        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}
