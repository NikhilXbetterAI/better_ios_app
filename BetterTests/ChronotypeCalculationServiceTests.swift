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

    func testReturnsInsufficientDataBelowSevenValidNights() {
        let result = service.estimate(
            sessions: Array(fillerSessions.prefix(6)),
            contextEntries: [],
            activityLogs: [],
            endingAt: date("2026-05-01T00:00:00Z"),
            calendar: Self.calendar
        )

        XCTAssertEqual(result.status, .insufficientData)
        XCTAssertTrue(result.missingRequirements.contains(.totalNights))
    }

    func testSevenToThirteenNightsReturnsEarlyEstimate() {
        let result = service.estimate(
            sessions: Array(fillerSessions.prefix(7)),
            contextEntries: [],
            activityLogs: [],
            endingAt: date("2026-05-01T00:00:00Z"),
            calendar: Self.calendar
        )

        XCTAssertEqual(result.status, .estimated)
        XCTAssertEqual(result.estimate?.bodyClockReadiness, .preview)
    }

    func testReturnsEstimateWhenFreeDayNightsAreMissing() {
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

        XCTAssertEqual(result.status, .estimated)
        XCTAssertTrue(result.missingRequirements.isEmpty)
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

    func testBodyClockReadinessUsesStableNightCount() {
        let preview = service.estimate(
            sessions: fillerSessions,
            contextEntries: [],
            activityLogs: [],
            endingAt: date("2026-05-01T00:00:00Z"),
            calendar: Self.calendar
        )
        let stable = service.estimate(
            sessions: stableSessions,
            contextEntries: [],
            activityLogs: [],
            endingAt: date("2026-05-01T00:00:00Z"),
            calendar: Self.calendar
        )
        let high = service.estimate(
            sessions: highConfidenceSessions,
            contextEntries: [],
            activityLogs: [],
            endingAt: date("2026-05-01T00:00:00Z"),
            calendar: Self.calendar
        )

        XCTAssertEqual(preview.estimate?.bodyClockReadiness, .goodEstimate)
        XCTAssertEqual(stable.estimate?.bodyClockReadiness, .stable)
        XCTAssertEqual(high.estimate?.bodyClockReadiness, .highConfidence)
    }

    func testBodyClockCaveatsReportWeakInputs() {
        let travel = makeSession(sleepDateKey: "2026-04-05", onset: "2026-04-05T23:00:00Z", durationHours: 8, midpointMinute: 180)
        let result = service.estimate(
            sessions: fillerSessions + [travel],
            contextEntries: [SleepContextEntry(sleepDateKey: "2026-04-05", travel: true)],
            activityLogs: [],
            endingAt: date("2026-05-01T00:00:00Z"),
            calendar: Self.calendar
        )

        XCTAssertTrue(result.estimate?.bodyClockCaveats.contains(.previewOnly) == true)
        XCTAssertTrue(result.estimate?.bodyClockCaveats.contains(.fewFreeDays) == true)
        XCTAssertTrue(result.estimate?.bodyClockCaveats.contains(.travelRecentlyExcluded) == true)
    }

    func testBodyClockAlignmentThresholds() {
        let estimate = makeEstimate(targetMidpointMinute: 240)

        XCTAssertEqual(alignment(onset: "2026-04-05T00:00:00Z", durationHours: 8, estimate: estimate)?.category, .aligned)
        XCTAssertEqual(alignment(onset: "2026-04-05T00:30:00Z", durationHours: 8, estimate: estimate)?.category, .aligned)
        XCTAssertEqual(alignment(onset: "2026-04-04T23:29:00Z", durationHours: 8, estimate: estimate)?.category, .slightlyEarly)
        XCTAssertEqual(alignment(onset: "2026-04-05T01:15:00Z", durationHours: 8, estimate: estimate)?.category, .slightlyLate)
        XCTAssertEqual(alignment(onset: "2026-04-05T01:16:00Z", durationHours: 8, estimate: estimate)?.category, .late)
    }

    func testSocialJetlagMinutesNilWhenInsufficientData() {
        let onlyWorkdaySessions = fillerSessions.filter { session in
            Self.calendar.component(.weekday, from: session.startDate) <= 5
        }

        let result = service.estimate(
            sessions: Array(onlyWorkdaySessions.prefix(7)),
            contextEntries: [],
            activityLogs: [],
            endingAt: date("2026-05-01T00:00:00Z"),
            calendar: Self.calendar
        )

        XCTAssertNil(result.estimate?.socialJetlagMinutes)
    }

    func testSocialJetlagMinutesCircularDelta() {
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
            makeSession(onset: "2026-04-10T01:30:00Z", durationHours: 8, midpointMinute: 330),
            makeSession(onset: "2026-04-11T01:30:00Z", durationHours: 8, midpointMinute: 330),
            makeSession(onset: "2026-04-17T01:30:00Z", durationHours: 8, midpointMinute: 330),
            makeSession(onset: "2026-04-18T01:30:00Z", durationHours: 8, midpointMinute: 330)
        ]

        let result = service.estimate(
            sessions: sessions,
            contextEntries: [],
            activityLogs: [],
            endingAt: date("2026-05-01T00:00:00Z"),
            calendar: Self.calendar
        )

        XCTAssertNotNil(result.estimate?.socialJetlagMinutes)
        XCTAssertEqual(result.estimate?.socialJetlagMinutes ?? 0, 90, accuracy: 5)
    }

    func testNightsUntilNextTierPreview() {
        let result = service.estimate(
            sessions: Array(fillerSessions.prefix(7)),
            contextEntries: [],
            activityLogs: [],
            endingAt: date("2026-05-01T00:00:00Z"),
            calendar: Self.calendar
        )

        XCTAssertEqual(result.estimate?.bodyClockReadiness, .preview)
        XCTAssertEqual(result.estimate?.nightsUntilNextTier, 7)
        XCTAssertEqual(result.estimate?.nextTierName, "Good Estimate")
    }

    func testNightsUntilNextTierNilAtHighConfidence() {
        let result = service.estimate(
            sessions: highConfidenceSessions,
            contextEntries: [],
            activityLogs: [],
            endingAt: date("2026-05-01T00:00:00Z"),
            calendar: Self.calendar
        )

        XCTAssertEqual(result.estimate?.bodyClockReadiness, .highConfidence)
        XCTAssertNil(result.estimate?.nightsUntilNextTier)
        XCTAssertNil(result.estimate?.nextTierName)
    }

    func testSocialJetlagCategoryBands() {
        func makeEstimateWithJetlag(_ minutes: Int?) -> ChronotypeEstimate {
            var est = makeEstimate(targetMidpointMinute: 240)
            est.socialJetlagMinutes = minutes
            return est
        }

        XCTAssertEqual(makeEstimateWithJetlag(15).socialJetlagCategory, .low)
        XCTAssertEqual(makeEstimateWithJetlag(30).socialJetlagCategory, .moderate)
        XCTAssertEqual(makeEstimateWithJetlag(60).socialJetlagCategory, .high)
        XCTAssertEqual(makeEstimateWithJetlag(91).socialJetlagCategory, .severe)
        XCTAssertNil(makeEstimateWithJetlag(nil).socialJetlagCategory)
    }

    func testBodyClockAlignmentHandlesMidnightWraparound() {
        let estimate = makeEstimate(targetMidpointMinute: 23 * 60 + 50)
        let alignment = alignment(onset: "2026-04-04T20:20:00Z", durationHours: 8, estimate: estimate)

        XCTAssertEqual(alignment?.actualMidpointMinute, 20)
        XCTAssertEqual(alignment?.signedDeltaMinutes, 30)
        XCTAssertEqual(alignment?.category, .aligned)
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

    var stableSessions: [SleepSession] {
        (0..<32).compactMap { index in
            guard let onsetDate = Self.calendar.date(byAdding: .day, value: -index - 1, to: date("2026-05-01T00:30:00Z")) else {
                return nil
            }
            let onset = ISO8601DateFormatter().string(from: onsetDate)
            return makeSession(onset: onset, durationHours: 7.5, midpointMinute: midpointMinute(onset: onsetDate, durationHours: 7.5))
        }
    }

    func alignment(
        onset: String,
        durationHours: Double,
        estimate: ChronotypeEstimate
    ) -> BodyClockSleepAlignment? {
        let session = makeSession(
            onset: onset,
            durationHours: durationHours,
            midpointMinute: midpointMinute(onset: date(onset), durationHours: durationHours)
        )
        return service.alignment(for: session, estimate: estimate, calendar: Self.calendar)
    }

    func makeEstimate(targetMidpointMinute: Int) -> ChronotypeEstimate {
        ChronotypeEstimate(
            bucket: .intermediate,
            correctedMidpointMinute: targetMidpointMinute,
            workdayMidpointMinute: targetMidpointMinute,
            freeDayMidpointMinute: targetMidpointMinute,
            workdayMedianDuration: 8 * 3_600,
            freeDayMedianDuration: 8 * 3_600,
            weeklyAverageDuration: 8 * 3_600,
            validNightCount: 30,
            workdayNightCount: 20,
            freeDayNightCount: 10,
            excludedNightCount: 0,
            excludedCountsByReason: [:],
            confidence: .medium,
            bodyClockReadiness: .stable,
            optimalSleepWindow: SleepWindowRecommendation(startMinute: targetMidpointMinute - 240, endMinute: targetMidpointMinute + 240, duration: 8 * 3_600)
        )
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
