import XCTest
@testable import Better

final class ChronotypeCalculationServiceTests: XCTestCase {
    func testCalculatesCorrectedMidpointWithSecondsToMinutesCorrection() {
        let sessions = [
            makeSession(onset: "2026-04-05T00:30:00Z", durationHours: 7, midpointMinute: 240),
            makeSession(onset: "2026-04-06T00:30:00Z", durationHours: 7, midpointMinute: 240),
            makeSession(onset: "2026-04-07T00:30:00Z", durationHours: 7, midpointMinute: 240),
            makeSession(onset: "2026-04-08T00:30:00Z", durationHours: 7, midpointMinute: 240),
            makeSession(onset: "2026-04-09T00:30:00Z", durationHours: 7, midpointMinute: 240),
            makeSession(onset: "2026-04-12T00:30:00Z", durationHours: 7, midpointMinute: 240),
            makeSession(onset: "2026-04-13T00:30:00Z", durationHours: 7, midpointMinute: 240),
            makeSession(onset: "2026-04-14T00:30:00Z", durationHours: 7, midpointMinute: 240),
            makeSession(onset: "2026-04-15T00:30:00Z", durationHours: 7, midpointMinute: 240),
            makeSession(onset: "2026-04-16T00:30:00Z", durationHours: 7, midpointMinute: 240),
            makeSession(onset: "2026-04-10T01:00:00Z", durationHours: 8, midpointMinute: 300),
            makeSession(onset: "2026-04-11T01:00:00Z", durationHours: 8, midpointMinute: 300),
            makeSession(onset: "2026-04-17T01:00:00Z", durationHours: 8, midpointMinute: 300),
            makeSession(onset: "2026-04-18T01:00:00Z", durationHours: 8, midpointMinute: 300)
        ]

        let result = service.estimate(
            sessions: sessions,
            contextEntries: [],
            activityLogs: [],
            endingAt: date("2026-05-01T00:00:00Z"),
            calendar: Self.calendar
        )

        XCTAssertEqual(result.status, .estimated)
        XCTAssertEqual(result.estimate?.workdayMidpointMinute, 240)
        XCTAssertEqual(result.estimate?.freeDayMidpointMinute, 300)
        XCTAssertEqual(result.estimate?.correctedMidpointMinute, 279)
        XCTAssertEqual(result.estimate?.bucket, .intermediate)
    }

    func testHandlesCircularMedianAcrossMidnight() {
        let sessions = [
            makeSession(onset: "2026-04-05T20:20:00Z", durationHours: 7, midpointMinute: 1_430),
            makeSession(onset: "2026-04-06T20:40:00Z", durationHours: 7, midpointMinute: 10),
            makeSession(onset: "2026-04-07T20:30:00Z", durationHours: 7, midpointMinute: 0),
            makeSession(onset: "2026-04-08T20:30:00Z", durationHours: 7, midpointMinute: 0),
            makeSession(onset: "2026-04-09T20:30:00Z", durationHours: 7, midpointMinute: 0),
            makeSession(onset: "2026-04-12T20:30:00Z", durationHours: 7, midpointMinute: 0),
            makeSession(onset: "2026-04-10T21:30:00Z", durationHours: 7, midpointMinute: 60),
            makeSession(onset: "2026-04-11T21:30:00Z", durationHours: 7, midpointMinute: 60),
            makeSession(onset: "2026-04-17T21:30:00Z", durationHours: 7, midpointMinute: 60),
            makeSession(onset: "2026-04-18T21:30:00Z", durationHours: 7, midpointMinute: 60),
            makeSession(onset: "2026-04-19T20:30:00Z", durationHours: 7, midpointMinute: 0),
            makeSession(onset: "2026-04-20T20:30:00Z", durationHours: 7, midpointMinute: 0),
            makeSession(onset: "2026-04-21T20:30:00Z", durationHours: 7, midpointMinute: 0),
            makeSession(onset: "2026-04-22T20:30:00Z", durationHours: 7, midpointMinute: 0)
        ]

        let result = service.estimate(
            sessions: sessions,
            contextEntries: [],
            activityLogs: [],
            endingAt: date("2026-05-01T00:00:00Z"),
            calendar: Self.calendar
        )

        XCTAssertEqual(result.status, .estimated)
        XCTAssertEqual(result.estimate?.workdayMidpointMinute, 0)
    }

    func testClassifiesDayTypeFromLocalOnsetWeekdayInsteadOfSleepDateKey() {
        let fridayOnsetSaturdaySleepKey = makeSession(
            sleepDateKey: "2026-04-11",
            onset: "2026-04-10T23:00:00Z",
            durationHours: 8,
            midpointMinute: 180
        )
        let sundayOnsetMondaySleepKey = makeSession(
            sleepDateKey: "2026-04-13",
            onset: "2026-04-12T23:00:00Z",
            durationHours: 8,
            midpointMinute: 180
        )

        let result = service.estimate(
            sessions: fillerSessions + [fridayOnsetSaturdaySleepKey, sundayOnsetMondaySleepKey],
            contextEntries: [],
            activityLogs: [],
            endingAt: date("2026-05-01T00:00:00Z"),
            calendar: Self.calendar
        )

        let fridayNight = result.includedNights.first { $0.sleepDateKey == "2026-04-11" }
        let sundayNight = result.includedNights.first { $0.sleepDateKey == "2026-04-13" }
        XCTAssertEqual(fridayNight?.dayType, .freeDay)
        XCTAssertEqual(sundayNight?.dayType, .workday)
    }

    func testExcludesDurationQualityTravelAndJetLagNights() {
        let short = makeSession(onset: "2026-04-01T23:00:00Z", durationHours: 2.5, midpointMinute: 15)
        let long = makeSession(onset: "2026-04-02T20:00:00Z", durationHours: 12.5, midpointMinute: 135)
        let inBedOnly = makeSession(onset: "2026-04-03T23:00:00Z", durationHours: 8, midpointMinute: 180, quality: .inBedOnly)
        let noData = makeSession(onset: "2026-04-04T23:00:00Z", durationHours: 8, midpointMinute: 180, quality: .noData)
        let travel = makeSession(sleepDateKey: "2026-04-05", onset: "2026-04-05T23:00:00Z", durationHours: 8, midpointMinute: 180)
        let traveling = makeSession(sleepDateKey: "2026-04-06", onset: "2026-04-06T23:00:00Z", durationHours: 8, midpointMinute: 180)
        let jetLagged = makeSession(sleepDateKey: "2026-04-07", onset: "2026-04-07T23:00:00Z", durationHours: 8, midpointMinute: 180)
        let manualUnspecified = makeSession(
            onset: "2026-04-08T23:00:00Z",
            durationHours: 8,
            midpointMinute: 180,
            quality: .unspecifiedSleepOnly,
            sources: [SleepSource(name: "Manual", isManualEntry: true)]
        )

        let result = service.estimate(
            sessions: fillerSessions + [short, long, inBedOnly, noData, travel, traveling, jetLagged, manualUnspecified],
            contextEntries: [SleepContextEntry(sleepDateKey: "2026-04-05", travel: true)],
            activityLogs: [
                ActivityStatusLog(dateKey: "2026-04-06", status: .traveling),
                ActivityStatusLog(dateKey: "2026-04-07", status: .jetLagged)
            ],
            endingAt: date("2026-05-01T00:00:00Z"),
            calendar: Self.calendar
        )

        XCTAssertEqual(result.excludedCountsByReason[.tooShort], 1)
        XCTAssertEqual(result.excludedCountsByReason[.tooLong], 1)
        XCTAssertEqual(result.excludedCountsByReason[.poorDataQuality], 3)
        XCTAssertEqual(result.excludedCountsByReason[.travelOrJetLag], 3)
    }

    func testReturnsInsufficientDataWhenFreeDayNightsAreMissing() {
        let result = service.estimate(
            sessions: (0..<14).map { index in
                makeSession(onset: "2026-04-\(String(format: "%02d", 5 + index))T00:30:00Z", durationHours: 7, midpointMinute: 240)
            }.filter { session in
                Self.calendar.component(.weekday, from: session.startDate) <= 5
            },
            contextEntries: [],
            activityLogs: [],
            endingAt: date("2026-05-01T00:00:00Z"),
            calendar: Self.calendar
        )

        XCTAssertEqual(result.status, .insufficientData)
        XCTAssertTrue(result.missingRequirements.contains(.freeDayNights))
    }

    func testDoesNotApplyCatchUpCorrectionWhenFreeDaySleepIsNotLonger() {
        let sessions = [
            makeSession(onset: "2026-04-05T00:00:00Z", durationHours: 8, midpointMinute: 240),
            makeSession(onset: "2026-04-06T00:00:00Z", durationHours: 8, midpointMinute: 240),
            makeSession(onset: "2026-04-07T00:00:00Z", durationHours: 8, midpointMinute: 240),
            makeSession(onset: "2026-04-08T00:00:00Z", durationHours: 8, midpointMinute: 240),
            makeSession(onset: "2026-04-09T00:00:00Z", durationHours: 8, midpointMinute: 240),
            makeSession(onset: "2026-04-12T00:00:00Z", durationHours: 8, midpointMinute: 240),
            makeSession(onset: "2026-04-13T00:00:00Z", durationHours: 8, midpointMinute: 240),
            makeSession(onset: "2026-04-14T00:00:00Z", durationHours: 8, midpointMinute: 240),
            makeSession(onset: "2026-04-15T00:00:00Z", durationHours: 8, midpointMinute: 240),
            makeSession(onset: "2026-04-16T00:00:00Z", durationHours: 8, midpointMinute: 240),
            makeSession(onset: "2026-04-10T01:00:00Z", durationHours: 6, midpointMinute: 240),
            makeSession(onset: "2026-04-11T01:00:00Z", durationHours: 6, midpointMinute: 240),
            makeSession(onset: "2026-04-17T01:00:00Z", durationHours: 6, midpointMinute: 240),
            makeSession(onset: "2026-04-18T01:00:00Z", durationHours: 6, midpointMinute: 240)
        ]

        let result = service.estimate(
            sessions: sessions,
            contextEntries: [],
            activityLogs: [],
            endingAt: date("2026-05-01T00:00:00Z"),
            calendar: Self.calendar
        )

        XCTAssertEqual(result.status, .estimated)
        XCTAssertEqual(result.estimate?.freeDayMidpointMinute, 240)
        XCTAssertEqual(result.estimate?.correctedMidpointMinute, 240)
    }

    func testSleepWindowWrapsAroundMidnight() {
        let sessions = [
            makeSession(onset: "2026-04-05T20:00:00Z", durationHours: 8, midpointMinute: 0),
            makeSession(onset: "2026-04-06T20:00:00Z", durationHours: 8, midpointMinute: 0),
            makeSession(onset: "2026-04-07T20:00:00Z", durationHours: 8, midpointMinute: 0),
            makeSession(onset: "2026-04-08T20:00:00Z", durationHours: 8, midpointMinute: 0),
            makeSession(onset: "2026-04-09T20:00:00Z", durationHours: 8, midpointMinute: 0),
            makeSession(onset: "2026-04-12T20:00:00Z", durationHours: 8, midpointMinute: 0),
            makeSession(onset: "2026-04-13T20:00:00Z", durationHours: 8, midpointMinute: 0),
            makeSession(onset: "2026-04-14T20:00:00Z", durationHours: 8, midpointMinute: 0),
            makeSession(onset: "2026-04-15T20:00:00Z", durationHours: 8, midpointMinute: 0),
            makeSession(onset: "2026-04-16T20:00:00Z", durationHours: 8, midpointMinute: 0),
            makeSession(onset: "2026-04-10T20:00:00Z", durationHours: 8, midpointMinute: 0),
            makeSession(onset: "2026-04-11T20:00:00Z", durationHours: 8, midpointMinute: 0),
            makeSession(onset: "2026-04-17T20:00:00Z", durationHours: 8, midpointMinute: 0),
            makeSession(onset: "2026-04-18T20:00:00Z", durationHours: 8, midpointMinute: 0)
        ]

        let result = service.estimate(
            sessions: sessions,
            contextEntries: [],
            activityLogs: [],
            endingAt: date("2026-05-01T00:00:00Z"),
            calendar: Self.calendar
        )

        XCTAssertEqual(result.estimate?.optimalSleepWindow.startMinute, 20 * 60)
        XCTAssertEqual(result.estimate?.optimalSleepWindow.endMinute, 4 * 60)
    }

    func testIncludesAfterMidnightOnsetBeforeWindowEnd() {
        let afterMidnight = makeSession(
            sleepDateKey: "2026-05-01",
            onset: "2026-05-01T00:30:00Z",
            durationHours: 7,
            midpointMinute: 240
        )

        let result = service.estimate(
            sessions: fillerSessions + [afterMidnight],
            contextEntries: [],
            activityLogs: [],
            endingAt: date("2026-05-02T00:00:00Z"),
            calendar: Self.calendar
        )

        XCTAssertTrue(result.includedNights.contains { $0.sleepDateKey == "2026-05-01" })
    }

    func testConfidenceThresholds() {
        let result = service.estimate(
            sessions: highConfidenceSessions,
            contextEntries: [],
            activityLogs: [],
            endingAt: date("2026-05-01T00:00:00Z"),
            calendar: Self.calendar
        )

        XCTAssertEqual(result.estimate?.confidence, .high)
    }
}

private extension ChronotypeCalculationServiceTests {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    var service: ChronotypeCalculationService {
        ChronotypeCalculationService()
    }

    var fillerSessions: [SleepSession] {
        [
            makeSession(onset: "2026-04-19T00:30:00Z", durationHours: 7, midpointMinute: 240),
            makeSession(onset: "2026-04-20T00:30:00Z", durationHours: 7, midpointMinute: 240),
            makeSession(onset: "2026-04-21T00:30:00Z", durationHours: 7, midpointMinute: 240),
            makeSession(onset: "2026-04-22T00:30:00Z", durationHours: 7, midpointMinute: 240),
            makeSession(onset: "2026-04-23T00:30:00Z", durationHours: 7, midpointMinute: 240),
            makeSession(onset: "2026-04-26T00:30:00Z", durationHours: 7, midpointMinute: 240),
            makeSession(onset: "2026-04-24T01:00:00Z", durationHours: 8, midpointMinute: 300),
            makeSession(onset: "2026-04-25T01:00:00Z", durationHours: 8, midpointMinute: 300),
            makeSession(onset: "2026-04-17T01:00:00Z", durationHours: 8, midpointMinute: 300),
            makeSession(onset: "2026-04-18T01:00:00Z", durationHours: 8, midpointMinute: 300),
            makeSession(onset: "2026-04-27T00:30:00Z", durationHours: 7, midpointMinute: 240),
            makeSession(onset: "2026-04-28T00:30:00Z", durationHours: 7, midpointMinute: 240),
            makeSession(onset: "2026-04-29T00:30:00Z", durationHours: 7, midpointMinute: 240),
            makeSession(onset: "2026-04-30T00:30:00Z", durationHours: 7, midpointMinute: 240)
        ]
    }

    var highConfidenceSessions: [SleepSession] {
        (0..<56).compactMap { index in
            guard let onsetDate = Self.calendar.date(byAdding: .day, value: -index - 1, to: date("2026-05-01T00:30:00Z")) else {
                return nil
            }
            let onset = ISO8601DateFormatter().string(from: onsetDate)
            return makeSession(onset: onset, durationHours: 7.5, midpointMinute: midpointMinute(onset: onsetDate, durationHours: 7.5))
        }
    }

    func makeSession(
        sleepDateKey: String? = nil,
        onset: String,
        durationHours: Double,
        midpointMinute: Int,
        quality: SleepDataQuality = .detailedStages,
        sources: [SleepSource] = [SleepSource(name: "Apple Watch", bundleIdentifier: "com.apple.watch", productType: "Watch7,1")]
    ) -> SleepSession {
        let onsetDate = date(onset)
        let duration = durationHours * 3_600
        let startDate = onsetDate.addingTimeInterval(-20 * 60)
        let endDate = onsetDate.addingTimeInterval(duration + 20 * 60)
        let stageEnd = onsetDate.addingTimeInterval(duration)
        XCTAssertEqual(midpointMinute, self.midpointMinute(onset: onsetDate, durationHours: durationHours))

        return SleepSession(
            sleepDateKey: sleepDateKey ?? SleepDateKey.sleepDateKey(forSessionStart: startDate, calendar: Self.calendar),
            startDate: startDate,
            endDate: endDate,
            stages: [
                SleepStage(type: .inBed, startDate: startDate, endDate: onsetDate, source: sources.first),
                SleepStage(type: .core, startDate: onsetDate, endDate: stageEnd, source: sources.first)
            ],
            sources: sources,
            dataQuality: quality,
            totalInBedTime: duration + 40 * 60,
            totalSleepTime: duration,
            awakeDuration: 40 * 60,
            coreDuration: duration,
            efficiency: duration / (duration + 40 * 60)
        )
    }

    func date(_ string: String) -> Date {
        ISO8601DateFormatter().date(from: string)!
    }

    func midpointMinute(onset: Date, durationHours: Double) -> Int {
        let midpoint = onset.addingTimeInterval(durationHours * 1_800)
        let components = Self.calendar.dateComponents([.hour, .minute], from: midpoint)
        return ((components.hour ?? 0) * 60) + (components.minute ?? 0)
    }
}
