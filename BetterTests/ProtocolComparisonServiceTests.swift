import XCTest
@testable import Better

final class ProtocolComparisonServiceTests: XCTestCase {
    func testProtocolUsageStatusMappingDistinguishesUnknownNotTakenAndTaken() {
        XCTAssertEqual(ProtocolComparisonService.status(for: nil), .unknown)
        XCTAssertEqual(ProtocolComparisonService.status(for: []), .unknown)
        XCTAssertEqual(ProtocolComparisonService.status(for: [
            ProtocolAdherence(protocolID: "p1", dateKey: "2026-05-01", taken: false)
        ]), .notTaken)
        XCTAssertEqual(ProtocolComparisonService.status(for: [
            ProtocolAdherence(protocolID: "p1", dateKey: "2026-05-01", taken: false),
            ProtocolAdherence(protocolID: "p2", dateKey: "2026-05-01", taken: true)
        ]), .taken)
    }

    func testComparisonExcludesUnknownNightsFromAverages() {
        let sessions = [
            Self.session(day: 1, hours: 8),
            Self.session(day: 2, hours: 6),
            Self.session(day: 3, hours: 12)
        ]
        let adherence = [
            ProtocolAdherence(protocolID: "p1", dateKey: "2026-05-01", taken: true),
            ProtocolAdherence(protocolID: "p1", dateKey: "2026-05-02", taken: false)
        ]

        let result = ProtocolComparisonService(calendar: Self.calendar).compare(
            sessions: sessions,
            adherence: adherence,
            window: .all,
            endingAt: Self.date("2026-05-03T12:00:00Z")
        )

        XCTAssertEqual(result.takenNightCount, 1)
        XCTAssertEqual(result.notTakenNightCount, 1)
        XCTAssertEqual(result.unknownNightCount, 1)
        XCTAssertEqual(result.deltaTotalSleep ?? 0, 2 * 3_600, accuracy: 0.001)
    }

    func testComparisonWithEnoughDataProducesHighConfidenceDeltas() {
        let sessions = (1...14).map { day in
            Self.session(day: day, hours: day <= 7 ? 8 : 6)
        }
        let adherence = (1...14).map { day in
            ProtocolAdherence(
                protocolID: "p1",
                dateKey: String(format: "2026-05-%02d", day),
                taken: day <= 7
            )
        }

        let result = ProtocolComparisonService(calendar: Self.calendar).compare(
            sessions: sessions,
            adherence: adherence,
            window: .all,
            endingAt: Self.date("2026-05-14T12:00:00Z")
        )

        XCTAssertEqual(result.confidence, .high)
        XCTAssertEqual(result.takenNightCount, 7)
        XCTAssertEqual(result.notTakenNightCount, 7)
        XCTAssertEqual(result.unknownNightCount, 0)
        XCTAssertEqual(result.averageTotalSleepTaken ?? 0, 8 * 3_600, accuracy: 0.001)
        XCTAssertEqual(result.averageTotalSleepNotTaken ?? 0, 6 * 3_600, accuracy: 0.001)
        XCTAssertEqual(result.deltaTotalSleep ?? 0, 2 * 3_600, accuracy: 0.001)
    }

    func testComparisonConfidenceLevels() {
        XCTAssertEqual(ProtocolComparisonService.confidence(takenCount: 7, notTakenCount: 7), .high)
        XCTAssertEqual(ProtocolComparisonService.confidence(takenCount: 4, notTakenCount: 6), .medium)
        XCTAssertEqual(ProtocolComparisonService.confidence(takenCount: 2, notTakenCount: 3), .low)
        XCTAssertEqual(ProtocolComparisonService.confidence(takenCount: 1, notTakenCount: 7), .unavailable)
    }

    func testMissingStageDataOmitsStageDeltas() {
        let sessions = [
            Self.session(day: 1, hours: 8, quality: .unspecifiedSleepOnly, deep: 0, rem: 0),
            Self.session(day: 2, hours: 6, quality: .unspecifiedSleepOnly, deep: 0, rem: 0)
        ]
        let adherence = [
            ProtocolAdherence(protocolID: "p1", dateKey: "2026-05-01", taken: true),
            ProtocolAdherence(protocolID: "p1", dateKey: "2026-05-02", taken: false)
        ]

        let result = ProtocolComparisonService(calendar: Self.calendar).compare(
            sessions: sessions,
            adherence: adherence,
            window: .all,
            endingAt: Self.date("2026-05-02T12:00:00Z")
        )

        XCTAssertNil(result.deltaDeepSleep)
        XCTAssertNil(result.deltaREMSleep)
        XCTAssertEqual(result.deltaAwakeTime ?? 0, 0, accuracy: 0.001)
    }
}

private extension ProtocolComparisonServiceTests {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    static func session(
        day: Int,
        hours: Double,
        quality: SleepDataQuality = .detailedStages,
        deep: TimeInterval = 90 * 60,
        rem: TimeInterval = 90 * 60
    ) -> SleepSession {
        let key = String(format: "2026-05-%02d", day)
        let start = date(String(format: "2026-05-%02dT22:00:00Z", day))
        let end = start.addingTimeInterval((hours + 0.5) * 3_600)
        let totalSleep = hours * 3_600
        let totalInBed = totalSleep + 30 * 60
        return SleepSession(
            sleepDateKey: key,
            startDate: start,
            endDate: end,
            dataQuality: quality,
            totalInBedTime: totalInBed,
            totalSleepTime: totalSleep,
            awakeDuration: 30 * 60,
            coreDuration: max(0, totalSleep - deep - rem),
            deepDuration: deep,
            remDuration: rem,
            efficiency: totalSleep / totalInBed
        )
    }

    static func date(_ string: String) -> Date {
        ISO8601DateFormatter().date(from: string)!
    }
}
