import XCTest
@testable import Better

final class SleepInsightServiceTests: XCTestCase {
    func testSleepInsightCategorySelection() {
        let service = SleepInsightService()
        let session = Self.session(totalSleep: 7 * 3_600, efficiency: 0.84)
        let baseline = Self.baseline(validNights: 14, totalSleepAverage: 8 * 3_600, efficiencyAverage: 0.90)

        let insights = service.insights(session: session, baseline: baseline, recentSessions: [session])
        let categories = Set(insights.map(\.category))

        XCTAssertTrue(categories.contains(.duration))
        XCTAssertTrue(categories.contains(.efficiency))
    }

    func testBaselineBuildingInsightWhenBaselineIsNotReady() {
        let service = SleepInsightService()
        let session = Self.session(totalSleep: 7.5 * 3_600, efficiency: 0.90)
        let baseline = Self.baseline(validNights: 3)

        let insights = service.insights(session: session, baseline: baseline, recentSessions: [session])

        let baselineInsight = insights.first { $0.category == .baselineBuilding }
        XCTAssertEqual(baselineInsight?.body, "Log 2 more valid nights to unlock baseline comparisons.")
        XCTAssertEqual(baselineInsight?.metricDelta?.value, 3.0)
    }

    func testFiveValidNightsUnlockBaselineInsights() {
        let service = SleepInsightService()
        let session = Self.session(totalSleep: 7 * 3_600, efficiency: 0.84)
        let baseline = Self.baseline(validNights: 5, totalSleepAverage: 8 * 3_600, efficiencyAverage: 0.90)

        let insights = service.insights(session: session, baseline: baseline, recentSessions: [session])

        XCTAssertFalse(insights.contains { $0.category == .baselineBuilding })
        XCTAssertTrue(insights.contains { $0.category == .duration })
    }

    func testNonCausalLanguage() {
        let service = SleepInsightService()
        let session = Self.session(totalSleep: 9 * 3_600, efficiency: 0.95)
        let baseline = Self.baseline(validNights: 14, totalSleepAverage: 7 * 3_600, efficiencyAverage: 0.80)

        let insights = service.insights(session: session, baseline: baseline, recentSessions: [session])
        for insight in insights {
            let lowerBody = insight.body.lowercased()
            XCTAssertFalse(lowerBody.contains("caused"), "Insight body contains causal language: \(insight.body)")
            XCTAssertFalse(lowerBody.contains("improves"), "Insight body contains causal language: \(insight.body)")
            XCTAssertFalse(lowerBody.contains("leads to"), "Insight body contains causal language: \(insight.body)")
            XCTAssertFalse(lowerBody.contains("due to"), "Insight body contains causal language: \(insight.body)")
        }
    }
}

extension SleepInsightServiceTests {
    static func session(
        key: String = "2026-05-01",
        totalSleep: TimeInterval,
        efficiency: Double,
        score: Double = 80,
        quality: SleepDataQuality = .detailedStages
    ) -> SleepSession {
        let start = ISO8601DateFormatter().date(from: "\(key)T22:00:00Z")!
        let totalInBed = totalSleep / efficiency
        return SleepSession(
            sleepDateKey: key,
            startDate: start,
            endDate: start.addingTimeInterval(totalInBed),
            dataQuality: quality,
            totalInBedTime: totalInBed,
            totalSleepTime: totalSleep,
            awakeDuration: totalInBed - totalSleep,
            coreDuration: max(0, totalSleep - 180 * 60),
            deepDuration: 90 * 60,
            remDuration: 90 * 60,
            waso: totalInBed - totalSleep,
            efficiency: efficiency,
            qualityScore: SleepQualityScore(
                overall: score,
                durationScore: score,
                efficiencyScore: score,
                remScore: score,
                deepScore: score,
                isPartial: false
            )
        )
    }

    static func baseline(
        validNights: Int,
        totalSleepAverage: TimeInterval = 8 * 3_600,
        efficiencyAverage: Double = 0.90
    ) -> SleepBaseline {
        SleepBaseline(
            windowDays: validNights >= 14 ? 14 : 7,
            validNights: validNights,
            totalSleepAverage: totalSleepAverage,
            totalSleepStandardDeviation: 20 * 60,
            remAverage: 100 * 60,
            remStandardDeviation: 15 * 60,
            deepAverage: 90 * 60,
            deepStandardDeviation: 15 * 60,
            efficiencyAverage: efficiencyAverage,
            efficiencyStandardDeviation: 0.03,
            wasoAverage: 20 * 60,
            wasoStandardDeviation: 10 * 60,
            latencyAverage: 10 * 60,
            latencyStandardDeviation: 5 * 60,
            hrvAverage: 50,
            hrvStandardDeviation: 8,
            respiratoryRateAverage: 14,
            respiratoryRateStandardDeviation: 1,
            oxygenSaturationAverage: 0.97,
            oxygenSaturationStandardDeviation: 0.01,
            bedtimeMinuteAverage: 23 * 60,
            bedtimeMinuteStandardDeviation: 20,
            wakeMinuteAverage: 7 * 60,
            wakeMinuteStandardDeviation: 20
        )
    }
}
