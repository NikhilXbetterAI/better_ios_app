import Foundation
import HealthKit
import XCTest
@testable import Better

final class BiomarkerSummaryServiceTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)

    func testComputesTimelineAveragesIndependently() async throws {
        let now = date("2026-01-31")
        let sessions = (0..<60).map { offset in
            makeSession(date: dateByAdding(-offset, to: now), hrv: Double(offset + 1))
        }
        let service = BiomarkerSummaryService(
            localRepository: MockLocalDataRepository(sessions: sessions),
            healthRepository: BiologyFakeHealthKitRepository(),
            calendar: calendar
        )

        let summaries = try await service.summaries(now: now)

        XCTAssertEqual(summaries[.hrv]?[.sevenDays]?.average, 4)
        XCTAssertEqual(summaries[.hrv]?[.thirtyDays]?.average, 15.5)
        XCTAssertEqual(summaries[.hrv]?[.sixtyDays]?.average, 30.5)
    }

    func testBestValueRulesForAllBiomarkers() async throws {
        let now = date("2026-01-31")
        let sessions = [
            makeSession(date: now, hrv: 45, spo2: 0.96, breath: 11),
            makeSession(date: dateByAdding(-1, to: now), hrv: 72, spo2: 0.98, breath: 14),
            makeSession(date: dateByAdding(-2, to: now), hrv: 54, spo2: 0.94, breath: 19)
        ]
        let rhrSamples = [
            rhrSample(value: 62, date: now),
            rhrSample(value: 55, date: dateByAdding(-1, to: now)),
            rhrSample(value: 70, date: dateByAdding(-2, to: now))
        ]
        let service = BiomarkerSummaryService(
            localRepository: MockLocalDataRepository(sessions: sessions),
            healthRepository: BiologyFakeHealthKitRepository(samples: [.restingHeartRate: rhrSamples]),
            calendar: calendar
        )

        let summaries = try await service.summaries(now: now)

        XCTAssertEqual(summaries[.hrv]?[.sevenDays]?.bestValue, 72)
        XCTAssertEqual(summaries[.spo2]?[.sevenDays]?.bestValue, 98)
        XCTAssertEqual(summaries[.restingHeartRate]?[.sevenDays]?.bestValue, 55)
        XCTAssertEqual(summaries[.respiratoryRate]?[.sevenDays]?.bestValue, 14)
    }

    func testRangeUsesValidPointsAndSpO2DisplaysPercent() async throws {
        let now = date("2026-01-31")
        let invalid = makeSession(date: dateByAdding(-1, to: now), hrv: 20, spo2: 0.90, breath: 22, totalSleep: 60)
        let sessions = [
            makeSession(date: now, hrv: 40, spo2: 0.965, breath: 13),
            makeSession(date: dateByAdding(-2, to: now), hrv: 80, spo2: 0.985, breath: 15),
            invalid
        ]
        let service = BiomarkerSummaryService(
            localRepository: MockLocalDataRepository(sessions: sessions),
            healthRepository: BiologyFakeHealthKitRepository(),
            calendar: calendar
        )

        let summaries = try await service.summaries(now: now)
        let hrv = summaries[.hrv]?[.sevenDays]
        let spo2 = summaries[.spo2]?[.sevenDays]

        XCTAssertEqual(hrv?.minValue, 40)
        XCTAssertEqual(hrv?.maxValue, 80)
        XCTAssertEqual(hrv?.validSampleCount, 2)
        XCTAssertEqual(spo2?.average, 97.5)
        XCTAssertEqual(spo2?.points.map(\.value), [98.5, 96.5])
    }

    func testRHRUsesHealthKitRestingHeartRateInsteadOfSleepHeartRate() async throws {
        let now = date("2026-01-31")
        let sessions = [
            makeSession(date: now, hrv: 50, sleepHeartRateMinimum: 44),
            makeSession(date: dateByAdding(-1, to: now), hrv: 52, sleepHeartRateMinimum: 45)
        ]
        let rhrSamples = [
            rhrSample(value: 61, date: now),
            rhrSample(value: 63, date: dateByAdding(-1, to: now))
        ]
        let service = BiomarkerSummaryService(
            localRepository: MockLocalDataRepository(sessions: sessions),
            healthRepository: BiologyFakeHealthKitRepository(samples: [.restingHeartRate: rhrSamples]),
            calendar: calendar
        )

        let summaries = try await service.summaries(now: now)
        let rhr = summaries[.restingHeartRate]?[.sevenDays]

        XCTAssertEqual(rhr?.average, 62)
        XCTAssertEqual(rhr?.minValue, 61)
        XCTAssertFalse(rhr?.points.map(\.value).contains(44) ?? true)
    }

    func testMissingNightsDoNotZeroFillAndCoverageReflectsExpectedWindow() async throws {
        let now = date("2026-01-31")
        let sessions = [
            makeSession(date: now, hrv: 50),
            makeSession(date: dateByAdding(-6, to: now), hrv: 70)
        ]
        let service = BiomarkerSummaryService(
            localRepository: MockLocalDataRepository(sessions: sessions),
            healthRepository: BiologyFakeHealthKitRepository(),
            calendar: calendar
        )

        let summaries = try await service.summaries(now: now)
        let hrv = summaries[.hrv]?[.sevenDays]

        XCTAssertEqual(hrv?.average, 60)
        XCTAssertEqual(hrv?.validSampleCount, 2)
        XCTAssertEqual(hrv?.expectedDayCount, 7)
        XCTAssertEqual(hrv?.points.count, 2)
    }
}

private extension BiomarkerSummaryServiceTests {
    func date(_ key: String) -> Date {
        SleepDateKey.date(from: key, calendar: calendar) ?? Date(timeIntervalSince1970: 0)
    }

    func dateByAdding(_ days: Int, to date: Date) -> Date {
        calendar.date(byAdding: .day, value: days, to: date) ?? date
    }

    func makeSession(
        date: Date,
        hrv: Double? = nil,
        spo2: Double? = nil,
        breath: Double? = nil,
        sleepHeartRateMinimum: Double? = nil,
        totalSleep: TimeInterval = 7 * 3_600
    ) -> SleepSession {
        let start = calendar.date(byAdding: .hour, value: -8, to: date) ?? date.addingTimeInterval(-8 * 3_600)
        let end = calendar.date(byAdding: .hour, value: -1, to: date) ?? date.addingTimeInterval(-3_600)
        let dateKey = SleepDateKey.calendarDateKey(for: date, calendar: calendar)
        let id = UUID()
        return SleepSession(
            id: id,
            sleepDateKey: dateKey,
            startDate: start,
            endDate: end,
            dataQuality: .detailedStages,
            totalInBedTime: totalSleep + 900,
            totalSleepTime: totalSleep,
            efficiency: 0.9,
            biometrics: NightlyBiometricSummary(
                sleepSessionID: id,
                sleepDateKey: dateKey,
                heartRateMinimum: sleepHeartRateMinimum,
                hrvAverage: hrv,
                oxygenSaturationAverage: spo2,
                respiratoryRateAverage: breath
            )
        )
    }

    func rhrSample(value: Double, date: Date) -> BiometricSample {
        let start = calendar.date(byAdding: .hour, value: 10, to: date) ?? date
        let end = calendar.date(byAdding: .minute, value: 5, to: start) ?? start.addingTimeInterval(300)
        return BiometricSample(
            type: .restingHeartRate,
            value: value,
            unit: "count/min",
            startDate: start,
            endDate: end
        )
    }
}
