import XCTest
@testable import Better

final class SleepNotificationDecisionServiceTests: XCTestCase {
    private var service: SleepNotificationDecisionService {
        SleepNotificationDecisionService(calendar: Self.calendar)
    }

    func testNotificationSuppressedForUnavailableConfidence() {
        let decisions = service.decisions(input: input(baseline: SleepInsightServiceTests.baseline(validNights: 1)))

        XCTAssertFalse(decisions.contains(where: \.shouldNotify))
        XCTAssertEqual(decisions.first?.confidence, .unavailable)
    }

    func testNotificationSuppressedForSmallDelta() {
        let baseline = SleepInsightServiceTests.baseline(validNights: 14, totalSleepAverage: 8 * 3_600)
        let session = SleepInsightServiceTests.session(totalSleep: 7.75 * 3_600, efficiency: 0.90)

        let decisions = service.decisions(input: input(session: session, baseline: baseline))

        XCTAssertFalse(decisions.contains { $0.notificationType == .durationBelowBaseline && $0.shouldNotify })
    }

    func testNotificationTriggeredForMeaningfulDelta() {
        let baseline = SleepInsightServiceTests.baseline(validNights: 14, totalSleepAverage: 8 * 3_600)
        let session = SleepInsightServiceTests.session(totalSleep: 7 * 3_600, efficiency: 0.90)

        let decisions = service.decisions(input: input(session: session, baseline: baseline))

        XCTAssertTrue(decisions.contains { $0.notificationType == .durationBelowBaseline && $0.shouldNotify })
    }

    func testNotificationCooldownBehavior() {
        let baseline = SleepInsightServiceTests.baseline(validNights: 14, totalSleepAverage: 8 * 3_600)
        let session = SleepInsightServiceTests.session(totalSleep: 7 * 3_600, efficiency: 0.90)
        let previous = SleepAlert(
            kind: .sleepDurationBelowBaseline,
            title: "Sleep was below baseline",
            body: "",
            sleepDateKey: session.sleepDateKey,
            createdAt: Self.date("2026-05-01T08:00:00Z")
        )

        let decisions = service.decisions(input: input(
            session: session,
            baseline: baseline,
            previousAlerts: [previous],
            createdAt: Self.date("2026-05-02T08:00:00Z")
        ))

        let duration = decisions.first { $0.notificationType == .durationBelowBaseline }
        XCTAssertEqual(duration?.shouldNotify, false)
        XCTAssertEqual(duration?.cooldownApplied, true)
    }

    func testProtocolNotificationWeeklyCooldown() {
        let previous = SleepAlert(
            kind: .protocolPattern,
            title: "Protocol sleep pattern",
            body: "",
            sleepDateKey: "2026-05-01",
            createdAt: Self.date("2026-05-01T08:00:00Z")
        )
        let comparison = ProtocolComparisonResult(
            window: .last30Days,
            takenNightCount: 7,
            notTakenNightCount: 7,
            unknownNightCount: 0,
            confidence: .medium,
            averageTotalSleepTaken: 8 * 3_600,
            averageTotalSleepNotTaken: 7.4 * 3_600,
            deltaTotalSleep: 36 * 60,
            averageEfficiencyTaken: nil,
            averageEfficiencyNotTaken: nil,
            deltaEfficiency: nil,
            averageDeepSleepTaken: nil,
            averageDeepSleepNotTaken: nil,
            deltaDeepSleep: nil,
            averageREMSleepTaken: nil,
            averageREMSleepNotTaken: nil,
            deltaREMSleep: nil,
            averageAwakeTimeTaken: nil,
            averageAwakeTimeNotTaken: nil,
            deltaAwakeTime: nil
        )

        let decisions = service.decisions(input: input(
            protocolComparison: comparison,
            previousAlerts: [previous],
            createdAt: Self.date("2026-05-05T08:00:00Z")
        ))

        let protocolDecision = decisions.first { $0.notificationType == .protocolDurationPattern }
        XCTAssertEqual(protocolDecision?.shouldNotify, false)
        XCTAssertEqual(protocolDecision?.cooldownApplied, true)
    }
}

private extension SleepNotificationDecisionServiceTests {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    func input(
        session: SleepSession = SleepInsightServiceTests.session(totalSleep: 7 * 3_600, efficiency: 0.90),
        baseline: SleepBaseline = SleepInsightServiceTests.baseline(validNights: 14),
        protocolComparison: ProtocolComparisonResult? = nil,
        previousAlerts: [SleepAlert] = [],
        createdAt: Date = date("2026-05-03T08:00:00Z")
    ) -> SleepNotificationDecisionInput {
        let history = previousAlerts.isEmpty
            ? [
                SleepAlert(
                    kind: .baselineAvailable,
                    title: "Your sleep baseline is ready",
                    body: "",
                    sleepDateKey: session.sleepDateKey,
                    createdAt: date("2026-04-20T08:00:00Z")
                )
            ]
            : previousAlerts
        return SleepNotificationDecisionInput(
            latestSession: session,
            recentSessions: [session],
            baseline: baseline,
            protocolComparison: protocolComparison,
            previousAlerts: history,
            createdAt: createdAt
        )
    }

    static func date(_ string: String) -> Date {
        ISO8601DateFormatter().date(from: string)!
    }

    func date(_ string: String) -> Date {
        Self.date(string)
    }
}
