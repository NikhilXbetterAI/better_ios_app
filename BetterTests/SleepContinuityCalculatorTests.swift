import XCTest
@testable import Better

final class SleepContinuityCalculatorTests: XCTestCase {
    func testProductExampleOneFindsThreeHourFiftyMinuteBlock() {
        let summary = SleepContinuityCalculator.summary(for: [
            stage(.core, "2026-05-03T23:00:00Z", "2026-05-04T02:50:00Z"),
            stage(.awake, "2026-05-04T02:50:00Z", "2026-05-04T02:57:00Z"),
            stage(.rem, "2026-05-04T02:57:00Z", "2026-05-04T04:20:00Z"),
            stage(.awake, "2026-05-04T04:20:00Z", "2026-05-04T04:25:00Z"),
            stage(.deep, "2026-05-04T04:25:00Z", "2026-05-04T06:45:00Z")
        ])

        XCTAssertEqual(summary.blocks.map { Int($0.sleepDuration / 60) }, [230, 83, 140])
        XCTAssertEqual(summary.longestBlockDuration, 230 * 60, accuracy: 0.001)
        XCTAssertEqual(summary.longestBlockIndex, 1)
        XCTAssertEqual(summary.continuityCategory, .good)
    }

    func testProductExampleTwoFindsOneHourFiftyFiveMinuteBlock() {
        let summary = SleepContinuityCalculator.summary(for: [
            stage(.core, "2026-05-04T00:00:00Z", "2026-05-04T01:40:00Z"),
            stage(.awake, "2026-05-04T01:40:00Z", "2026-05-04T01:45:00Z"),
            stage(.rem, "2026-05-04T01:45:00Z", "2026-05-04T03:10:00Z"),
            stage(.awake, "2026-05-04T03:10:00Z", "2026-05-04T03:15:00Z"),
            stage(.deep, "2026-05-04T03:15:00Z", "2026-05-04T05:10:00Z"),
            stage(.awake, "2026-05-04T05:10:00Z", "2026-05-04T05:20:00Z"),
            stage(.core, "2026-05-04T05:20:00Z", "2026-05-04T07:00:00Z")
        ])

        XCTAssertEqual(summary.blocks.map { Int($0.sleepDuration / 60) }, [100, 85, 115, 100])
        XCTAssertEqual(summary.longestBlockDuration, 115 * 60, accuracy: 0.001)
        XCTAssertEqual(summary.longestBlockIndex, 3)
        XCTAssertEqual(summary.continuityCategory, .highlyFragmented)
    }

    func testAwakeUnderThreeMinutesIsIgnored() {
        let summary = SleepContinuityCalculator.summary(for: [
            stage(.deep, "2026-05-04T00:00:00Z", "2026-05-04T01:00:00Z"),
            stage(.awake, "2026-05-04T01:00:00Z", "2026-05-04T01:02:59Z"),
            stage(.rem, "2026-05-04T01:02:59Z", "2026-05-04T02:00:00Z")
        ])

        XCTAssertEqual(summary.blocks.count, 1)
        XCTAssertEqual(summary.blocks[0].shortAwakeningCount, 0)
        XCTAssertEqual(summary.longestBlockDuration, 117 * 60 + 1, accuracy: 0.001)
    }

    func testAwakeBetweenThreeAndFiveMinutesDoesNotSplitButIsTracked() {
        let summary = SleepContinuityCalculator.summary(for: [
            stage(.deep, "2026-05-04T00:00:00Z", "2026-05-04T01:00:00Z"),
            stage(.awake, "2026-05-04T01:00:00Z", "2026-05-04T01:04:59Z"),
            stage(.rem, "2026-05-04T01:04:59Z", "2026-05-04T02:00:00Z")
        ])

        XCTAssertEqual(summary.blocks.count, 1)
        XCTAssertEqual(summary.blocks[0].shortAwakeningCount, 1)
        XCTAssertEqual(summary.blocks[0].includedShortAwakeDuration, 299, accuracy: 0.001)
        XCTAssertEqual(summary.meaningfulAwakeningCount, 0)
    }

    func testAwakeExactlyFiveMinutesSplitsBlock() {
        let summary = SleepContinuityCalculator.summary(for: [
            stage(.deep, "2026-05-04T00:00:00Z", "2026-05-04T01:00:00Z"),
            stage(.awake, "2026-05-04T01:00:00Z", "2026-05-04T01:05:00Z"),
            stage(.rem, "2026-05-04T01:05:00Z", "2026-05-04T02:00:00Z")
        ])

        XCTAssertEqual(summary.blocks.count, 2)
        XCTAssertEqual(summary.meaningfulAwakeningCount, 1)
        XCTAssertEqual(summary.blocks.map { Int($0.sleepDuration / 60) }, [60, 55])
    }

    func testAdjacentAwakeIntervalsMergeBeforeThresholdCheck() {
        let summary = SleepContinuityCalculator.summary(for: [
            stage(.core, "2026-05-04T00:00:00Z", "2026-05-04T01:00:00Z"),
            stage(.awake, "2026-05-04T01:00:00Z", "2026-05-04T01:02:30Z"),
            stage(.awake, "2026-05-04T01:02:30Z", "2026-05-04T01:05:00Z"),
            stage(.rem, "2026-05-04T01:05:00Z", "2026-05-04T02:00:00Z")
        ])

        XCTAssertEqual(summary.blocks.count, 2)
        XCTAssertEqual(summary.meaningfulAwakeningCount, 1)
    }

    func testAwakeBeforeAndAfterSleepDoesNotCreateExtraBlocks() {
        let summary = SleepContinuityCalculator.summary(for: [
            stage(.awake, "2026-05-04T00:00:00Z", "2026-05-04T00:20:00Z"),
            stage(.core, "2026-05-04T00:20:00Z", "2026-05-04T02:00:00Z"),
            stage(.awake, "2026-05-04T02:00:00Z", "2026-05-04T02:30:00Z")
        ])

        XCTAssertEqual(summary.blocks.count, 1)
        XCTAssertEqual(summary.meaningfulAwakeningCount, 0)
        XCTAssertEqual(summary.blocks[0].sleepDuration, 100 * 60, accuracy: 0.001)
    }

    func testUnspecifiedCountsAsSleepAndInBedDoesNot() {
        let summary = SleepContinuityCalculator.summary(for: [
            stage(.inBed, "2026-05-04T00:00:00Z", "2026-05-04T08:00:00Z"),
            stage(.unspecified, "2026-05-04T00:30:00Z", "2026-05-04T07:30:00Z")
        ])

        XCTAssertEqual(summary.blocks.count, 1)
        XCTAssertEqual(summary.longestBlockDuration, 7 * 3_600, accuracy: 0.001)
        XCTAssertEqual(summary.continuityCategory, .exceptional)
    }

    func testEmptyAndInvalidStagesReturnUnavailable() {
        let summary = SleepContinuityCalculator.summary(for: [
            stage(.inBed, "2026-05-04T00:00:00Z", "2026-05-04T08:00:00Z"),
            stage(.core, "2026-05-04T02:00:00Z", "2026-05-04T02:00:00Z")
        ])

        XCTAssertTrue(summary.blocks.isEmpty)
        XCTAssertEqual(summary.continuityCategory, .unavailable)
    }

    func testUnsortedStagesStillProduceCorrectBlocks() {
        let summary = SleepContinuityCalculator.summary(for: [
            stage(.rem, "2026-05-04T02:10:00Z", "2026-05-04T03:00:00Z"),
            stage(.core, "2026-05-04T00:00:00Z", "2026-05-04T01:00:00Z"),
            stage(.awake, "2026-05-04T01:00:00Z", "2026-05-04T01:10:00Z"),
            stage(.deep, "2026-05-04T01:10:00Z", "2026-05-04T02:10:00Z")
        ])

        XCTAssertEqual(summary.blocks.map { Int($0.sleepDuration / 60) }, [60, 110])
        XCTAssertEqual(summary.longestBlockIndex, 2)
    }

    func testGapOfFiveMinutesWithoutExplicitAwakeSplitsBlock() {
        let summary = SleepContinuityCalculator.summary(for: [
            stage(.core, "2026-05-04T00:00:00Z", "2026-05-04T01:00:00Z"),
            stage(.rem, "2026-05-04T01:05:00Z", "2026-05-04T02:00:00Z")
        ])

        XCTAssertEqual(summary.blocks.count, 2)
        XCTAssertEqual(summary.meaningfulAwakeningCount, 1)
    }

    private func stage(_ type: SleepStageType, _ start: String, _ end: String) -> SleepStage {
        SleepStage(type: type, startDate: date(start), endDate: date(end))
    }

    private func date(_ string: String) -> Date {
        ISO8601DateFormatter().date(from: string)!
    }
}
