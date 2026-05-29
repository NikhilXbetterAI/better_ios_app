import XCTest
@testable import Better

final class AlertGenerationServiceTests: XCTestCase {
    func testGeneratesDeterministicAlertsAndDeduplicatesSameSessionRule() async throws {
        let service = AlertGenerationService(calendar: Self.utcCalendar, notificationScheduler: nil)
        let session = Self.session(
            score: 62,
            totalSleep: 5.5 * 3_600,
            deep: 30 * 60,
            rem: 50 * 60,
            waso: 50 * 60,
            hrv: 40,
            oxygenAverage: 0.93,
            oxygenMinimum: 0.89
        )
        var settings = AlertGenerationSettings.default
        settings.protocolMissMonitoringEnabled = true

        let first = try await service.generateAlerts(
            sessions: [session, session],
            recentSessions: [session],
            baseline: Self.baseline,
            profile: UserProfile(sleepGoalHours: 8),
            settings: settings,
            createdAt: Self.date("2026-05-04T23:30:00Z")
        )
        let second = try await service.generateAlerts(
            latestSession: session,
            recentSessions: [session],
            baseline: Self.baseline,
            profile: UserProfile(sleepGoalHours: 8),
            settings: settings,
            createdAt: Self.date("2026-05-04T23:30:00Z")
        )

        XCTAssertEqual(first.map(\.id), second.map(\.id))
        XCTAssertEqual(Set(first.map(\.id)).count, first.count)
        XCTAssertEqual(
            Set(first.map(\.kind)),
            [
                .analysisReady,
                .lowScore,
                .sleepDebt,
                .lowDeepSleep,
                .lowRemSleep,
                .highWASO,
                .lowHRV,
                .lowOxygenSaturation,
                .irregularSchedule
            ]
        )
    }

    func testOxygenAlertRequiresReliableSummary() async throws {
        let service = AlertGenerationService(calendar: Self.utcCalendar, notificationScheduler: nil)
        let session = Self.session(
            score: 82,
            totalSleep: 8 * 3_600,
            deep: 90 * 60,
            rem: 120 * 60,
            waso: 10 * 60,
            hrv: 58,
            oxygenAverage: 0.92,
            oxygenMinimum: nil
        )

        let alerts = try await service.generateAlerts(
            latestSession: session,
            recentSessions: [session],
            baseline: Self.stableBaseline,
            profile: UserProfile(sleepGoalHours: 8),
            createdAt: Self.date("2026-05-04T08:00:00Z")
        )

        XCTAssertFalse(alerts.map(\.kind).contains(.lowOxygenSaturation))
    }

    func testImprovementTrendUsesSevenNightTrend() async throws {
        let service = AlertGenerationService(calendar: Self.utcCalendar, notificationScheduler: nil)
        let sessions = (0..<7).map { index in
            Self.session(
                key: "2026-05-\(String(format: "%02d", index + 1))",
                start: Self.date("2026-05-\(String(format: "%02d", index + 1))T22:00:00Z"),
                end: Self.date("2026-05-\(String(format: "%02d", index + 2))T06:00:00Z"),
                score: 70 + Double(index),
                totalSleep: 8 * 3_600,
                deep: Double(70 + index * 4) * 60,
                rem: 120 * 60,
                waso: 10 * 60,
                hrv: 58,
                oxygenAverage: 0.97,
                oxygenMinimum: 0.95
            )
        }

        let alerts = try await service.generateAlerts(
            latestSession: sessions[6],
            recentSessions: sessions,
            baseline: Self.stableBaseline,
            profile: UserProfile(sleepGoalHours: 8),
            createdAt: Self.date("2026-05-08T08:00:00Z")
        )

        XCTAssertTrue(alerts.map(\.kind).contains(.improvementTrend))
    }

    func testNotificationPolicyGroupsMultipleEnabledSmartAlerts() async throws {
        let scheduler = CapturingNotificationScheduler(state: .authorized)
        let service = AlertGenerationService(calendar: Self.utcCalendar, notificationScheduler: scheduler)
        var settings = AlertGenerationSettings.default
        settings.localNotificationsEnabled = true
        settings.notificationEnabledKinds = [.lowScore, .sleepDebt]
        let session = Self.session(
            score: 55,
            totalSleep: 4.5 * 3_600,
            deep: 90 * 60,
            rem: 120 * 60,
            waso: 10 * 60,
            hrv: 58,
            oxygenAverage: 0.97,
            oxygenMinimum: 0.95
        )

        _ = try await service.generateAlerts(
            latestSession: session,
            recentSessions: [session],
            baseline: Self.stableBaseline,
            profile: UserProfile(sleepGoalHours: 8),
            settings: settings,
            createdAt: Self.date("2026-05-04T08:00:00Z")
        )

        let requests = await scheduler.requests()
        XCTAssertEqual(requests.count, 1)
        // The morning digest now uses a score-bucketed title and an alert-count body.
        // Session score 66 falls into the "Fair night" bucket, with two notifiable insights.
        XCTAssertEqual(requests[0].title, "Fair night — score 66")
        XCTAssertTrue(requests[0].body.contains("2 insights are ready"))
    }

    func testAnalysisReadyNotificationSchedulesWhenEnabled() async throws {
        let scheduler = CapturingNotificationScheduler(state: .authorized)
        let service = AlertGenerationService(calendar: Self.utcCalendar, notificationScheduler: scheduler)
        var settings = AlertGenerationSettings.default
        settings.localNotificationsEnabled = true
        settings.notificationEnabledKinds = [.analysisReady]
        var baseline = Self.baseline
        baseline.validNights = 0
        let session = Self.session(
            score: 88,
            totalSleep: 8 * 3_600,
            deep: 90 * 60,
            rem: 120 * 60,
            waso: 10 * 60,
            hrv: 58,
            oxygenAverage: 0.97,
            oxygenMinimum: 0.95
        )

        _ = try await service.generateAlerts(
            latestSession: session,
            recentSessions: [session],
            baseline: baseline,
            profile: UserProfile(sleepGoalHours: 8),
            settings: settings,
            createdAt: Self.date("2026-05-04T08:00:00Z")
        )

        let requests = await scheduler.requests()
        XCTAssertEqual(requests.count, 1)
        // Score 98 lands in the "Great night" bucket; only one notifiable alert (analysis ready)
        // so the digest body uses the single-alert "Tap to see your analysis." copy.
        XCTAssertEqual(requests[0].title, "Great night — score 98")
        XCTAssertEqual(requests[0].body, "You slept 8h 0m. Tap to see your analysis.")
    }
}

private actor CapturingNotificationScheduler: LocalNotificationScheduling {
    private let state: LocalNotificationAuthorizationState
    private var scheduledRequests: [(identifier: String, title: String, body: String)] = []

    init(state: LocalNotificationAuthorizationState) {
        self.state = state
    }

    func authorizationState() async -> LocalNotificationAuthorizationState {
        state
    }

    func scheduleNotification(identifier: String, title: String, body: String) async throws {
        scheduledRequests.append((identifier, title, body))
    }

    func isAlreadyDelivered(identifier: String) async -> Bool { false }

    func cancelPending(identifier: String) async {}

    func requests() -> [(identifier: String, title: String, body: String)] {
        scheduledRequests
    }
}

private extension AlertGenerationServiceTests {
    static let utcCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    static var baseline: SleepBaseline {
        SleepBaseline(
            windowDays: 30,
            validNights: 21,
            totalSleepAverage: 8 * 3_600,
            totalSleepStandardDeviation: 20 * 60,
            remAverage: 120 * 60,
            remStandardDeviation: 20 * 60,
            deepAverage: 90 * 60,
            deepStandardDeviation: 15 * 60,
            efficiencyAverage: 0.9,
            efficiencyStandardDeviation: 0.05,
            wasoAverage: 20 * 60,
            wasoStandardDeviation: 10 * 60,
            latencyAverage: 15 * 60,
            latencyStandardDeviation: 5 * 60,
            hrvAverage: 60,
            hrvStandardDeviation: 8,
            respiratoryRateAverage: 14,
            respiratoryRateStandardDeviation: 1,
            oxygenSaturationAverage: 0.97,
            oxygenSaturationStandardDeviation: 0.01,
            bedtimeMinuteAverage: 23 * 60,
            bedtimeMinuteStandardDeviation: 70,
            wakeMinuteAverage: 7 * 60,
            wakeMinuteStandardDeviation: 20
        )
    }

    static var stableBaseline: SleepBaseline {
        var baseline = Self.baseline
        baseline.bedtimeMinuteStandardDeviation = 20
        baseline.wakeMinuteStandardDeviation = 20
        return baseline
    }

    static func session(
        key: String = "2026-05-04",
        start: Date = date("2026-05-03T22:00:00Z"),
        end: Date = date("2026-05-04T06:00:00Z"),
        score: Double,
        totalSleep: TimeInterval,
        deep: TimeInterval,
        rem: TimeInterval,
        waso: TimeInterval,
        hrv: Double?,
        oxygenAverage: Double?,
        oxygenMinimum: Double?
    ) -> SleepSession {
        SleepSession(
            sleepDateKey: key,
            startDate: start,
            endDate: end,
            dataQuality: .detailedStages,
            totalInBedTime: end.timeIntervalSince(start),
            totalSleepTime: totalSleep,
            awakeDuration: waso,
            coreDuration: max(0, totalSleep - deep - rem),
            deepDuration: deep,
            remDuration: rem,
            waso: waso,
            efficiency: totalSleep / end.timeIntervalSince(start),
            qualityScore: SleepQualityScore(
                overall: score,
                durationScore: score,
                efficiencyScore: score,
                remScore: score,
                deepScore: score,
                isPartial: false
            ),
            biometrics: NightlyBiometricSummary(
                sleepSessionID: UUID(),
                sleepDateKey: key,
                hrvAverage: hrv,
                oxygenSaturationAverage: oxygenAverage,
                oxygenSaturationMinimum: oxygenMinimum
            )
        )
    }

    static func date(_ string: String) -> Date {
        ISO8601DateFormatter().date(from: string)!
    }
}
