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

    func testDiagnosticReportKeepsAvailableBiomarkersWhenOneTypeIsMissing() async throws {
        let now = date("2026-01-31")
        let session = makeSession(date: now, hrv: nil, spo2: nil, breath: nil)
        let samples: [BiometricType: [BiometricSample]] = [
            .heartRate: [
                biometricSample(.heartRate, value: 58, start: session.startDate.addingTimeInterval(600), end: session.startDate.addingTimeInterval(660))
            ],
            .respiratoryRate: [
                biometricSample(.respiratoryRate, value: 14.2, start: session.startDate.addingTimeInterval(900), end: session.startDate.addingTimeInterval(960))
            ]
        ]
        let service = BiomarkerDiagnosticService(
            localRepository: MockLocalDataRepository(sessions: [session]),
            healthRepository: BiologyFakeHealthKitRepository(samples: samples),
            calendar: calendar
        )

        let report = try await service.latestNightReport(now: now)

        XCTAssertEqual(report.metric(for: .heartRate)?.sleepWindow.count, 1)
        XCTAssertEqual(report.metric(for: .heartRateVariabilitySDNN)?.sleepWindow.count, 0)
        XCTAssertEqual(report.metric(for: .respiratoryRate)?.sleepWindow.count, 1)
        XCTAssertTrue(report.plainText.contains("Heart Rate"))
        XCTAssertTrue(report.plainText.contains("HRV"))
    }

    func testDiagnosticReportFlagsSamplesOutsideSleepWindow() async throws {
        let now = date("2026-01-31")
        let session = makeSession(date: now)
        let lateSample = biometricSample(
            .oxygenSaturation,
            value: 0.97,
            start: session.endDate.addingTimeInterval(3_600),
            end: session.endDate.addingTimeInterval(3_660)
        )
        let service = BiomarkerDiagnosticService(
            localRepository: MockLocalDataRepository(sessions: [session]),
            healthRepository: BiologyFakeHealthKitRepository(samples: [.oxygenSaturation: [lateSample]]),
            calendar: calendar
        )

        let report = try await service.latestNightReport(now: now)
        let oxygen = try XCTUnwrap(report.metric(for: .oxygenSaturation))

        XCTAssertEqual(oxygen.sleepWindow.count, 0)
        XCTAssertEqual(oxygen.expandedWindow.count, 1)
        XCTAssertEqual(oxygen.outsideSleepWindowCount, 1)
    }

    func testDiagnosticReportDocumentsSleepTabRHRUsesOvernightLowHeartRate() async throws {
        let now = date("2026-01-31")
        let session = makeSession(date: now, sleepHeartRateMinimum: 44)
        let rhrSample = biometricSample(
            .restingHeartRate,
            value: 62,
            start: now.addingTimeInterval(10 * 3_600),
            end: now.addingTimeInterval(10 * 3_600 + 300)
        )
        let service = BiomarkerDiagnosticService(
            localRepository: MockLocalDataRepository(sessions: [session]),
            healthRepository: BiologyFakeHealthKitRepository(samples: [.restingHeartRate: [rhrSample]]),
            calendar: calendar
        )

        let report = try await service.latestNightReport(now: now)

        XCTAssertTrue(report.plainText.contains("Resting heart rate used by Sleep tab RHR: 44 bpm"))
        XCTAssertTrue(report.plainText.contains("not HealthKit restingHeartRate"))
        XCTAssertEqual(report.metric(for: .restingHeartRate)?.expandedWindow.count, 1)
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

    func biometricSample(_ type: BiometricType, value: Double, start: Date, end: Date) -> BiometricSample {
        BiometricSample(
            type: type,
            value: value,
            unit: type.unitSymbol,
            startDate: start,
            endDate: end,
            source: SleepSource(name: "Oura", bundleIdentifier: "com.ouraring.oura")
        )
    }
}

private extension BiomarkerDiagnosticReport {
    func metric(for type: BiometricType) -> BiomarkerDiagnosticMetricReport? {
        metricReports.first { $0.type == type }
    }
}
