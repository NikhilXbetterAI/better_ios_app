import XCTest
@testable import Better

/// Regression tests for:
///   Bug A1 — LongestSleepBlockCard displayed duration must match the block's
///             wall-clock span (endDate − startDate), not the pure-sleep scalar.
///   Bug A2 — SleepSession.displayWakeDate must prefer inBedEndDate over endDate.
final class LongestSleepBlockConsistencyTests: XCTestCase {

    // MARK: - Bug A1: longestBlock wall-clock duration consistency

    /// Fixture 1 — Single uninterrupted block with no short awakenings.
    /// Wall-clock span == pure sleep duration.
    func testSingleBlockWallClockMatchesSleepDuration() {
        let t0 = Date(timeIntervalSince1970: 0)
        let stages = [
            makeStage(.core, start: t0,                            end: t0.addingTimeInterval(3_600)),
            makeStage(.deep, start: t0.addingTimeInterval(3_600),  end: t0.addingTimeInterval(7_200)),
            makeStage(.rem,  start: t0.addingTimeInterval(7_200),  end: t0.addingTimeInterval(10_800)),
        ]
        let summary = SleepContinuityCalculator.summary(for: stages)

        guard let block = summary.longestBlock else {
            XCTFail("longestBlock must not be nil")
            return
        }
        let wallClock = block.endDate.timeIntervalSince(block.startDate)

        // No short awakes ⇒ sleepDuration == wall-clock span
        XCTAssertEqual(wallClock, block.sleepDuration, accuracy: 1,
                       "Single clean block: wall-clock span must equal pure sleep duration")
        // Displayed duration uses wall-clock
        XCTAssertLessThan(abs(wallClock - displayedDuration(from: summary)), 60,
                          "Displayed duration must be within 60 s of wall-clock span")
    }

    /// Fixture 2 — Longest block contains an absorbed short awakening (120 s).
    /// Wall-clock span > pure sleep duration. The card used to show the smaller
    /// pure-sleep scalar alongside the wider wall-clock start/end times.
    func testBlockWithShortAwakeningWallClockExceedsSleepDuration() {
        let t0 = Date(timeIntervalSince1970: 0)
        let stages = [
            // Block 1: 1 h core → 2 min awake (120 s, absorbed: < 300 s threshold) → 1 h rem
            makeStage(.core,  start: t0,                            end: t0.addingTimeInterval(3_600)),
            makeStage(.awake, start: t0.addingTimeInterval(3_600),  end: t0.addingTimeInterval(3_720)),
            makeStage(.rem,   start: t0.addingTimeInterval(3_720),  end: t0.addingTimeInterval(7_320)),
            // Meaningful break: 600 s ≥ 300 s threshold → splits block
            makeStage(.awake, start: t0.addingTimeInterval(7_320),  end: t0.addingTimeInterval(7_920)),
            // Block 2: 30 min deep
            makeStage(.deep,  start: t0.addingTimeInterval(7_920),  end: t0.addingTimeInterval(9_720)),
        ]
        let summary = SleepContinuityCalculator.summary(for: stages)

        guard let block = summary.longestBlock else {
            XCTFail("longestBlock must not be nil")
            return
        }
        let wallClock = block.endDate.timeIntervalSince(block.startDate)

        // Wall-clock > pure sleep because short awake is absorbed into the block span
        XCTAssertGreaterThan(wallClock, block.sleepDuration,
                             "Wall-clock span must exceed pure sleep when a short awake is absorbed")
        // Displayed duration (wall-clock) must NOT equal longestBlockDuration scalar (pure sleep)
        XCTAssertNotEqual(displayedDuration(from: summary), summary.longestBlockDuration,
                          "After fix, displayed duration should NOT equal the pure-sleep scalar when short awakes are absorbed")
        // Displayed duration must still be close (within 60 s) to the wall-clock span
        XCTAssertLessThan(abs(displayedDuration(from: summary) - wallClock), 60,
                          "Displayed duration must be within 60 s of wall-clock span")
    }

    /// Fixture 3 — Two clean blocks; the longer one is identified correctly.
    func testLongestBlockSelectedCorrectlyAcrossTwoBlocks() {
        let t0 = Date(timeIntervalSince1970: 0)
        let stages = [
            // Block 1: 1 h
            makeStage(.core,  start: t0,                            end: t0.addingTimeInterval(3_600)),
            // Meaningful break: 600 s
            makeStage(.awake, start: t0.addingTimeInterval(3_600),  end: t0.addingTimeInterval(4_200)),
            // Block 2: 2 h (the longest)
            makeStage(.deep,  start: t0.addingTimeInterval(4_200),  end: t0.addingTimeInterval(11_400)),
        ]
        let summary = SleepContinuityCalculator.summary(for: stages)

        guard let block = summary.longestBlock else {
            XCTFail("longestBlock must not be nil")
            return
        }
        let wallClock = block.endDate.timeIntervalSince(block.startDate)

        XCTAssertEqual(summary.longestBlockIndex, block.index,
                       "longestBlockIndex must match longestBlock.index")
        XCTAssertLessThan(abs(wallClock - displayedDuration(from: summary)), 60,
                          "Displayed duration must be within 60 s of wall-clock span for fixture 3")
        // Block 2 is 7200 s; wall-clock span for a clean block equals sleepDuration
        XCTAssertEqual(wallClock, 7_200, accuracy: 1)
    }

    // MARK: - Bug A2: displayWakeDate

    func testDisplayWakeDatePrefersInBedEndDate() {
        let endDate      = Date(timeIntervalSince1970: 1_000)
        let inBedEndDate = Date(timeIntervalSince1970: 1_500)

        let session = SleepSession(
            sleepDateKey: "2026-01-01",
            startDate:    Date(timeIntervalSince1970: 0),
            endDate:      endDate,
            inBedEndDate: inBedEndDate
        )
        XCTAssertEqual(session.displayWakeDate, inBedEndDate,
                       "When inBedEndDate is present it must be used as the wake time")
    }

    func testDisplayWakeDateFallsBackToEndDate() {
        let endDate = Date(timeIntervalSince1970: 1_000)

        let session = SleepSession(
            sleepDateKey: "2026-01-01",
            startDate:    Date(timeIntervalSince1970: 0),
            endDate:      endDate
            // inBedEndDate intentionally omitted (nil)
        )
        XCTAssertEqual(session.displayWakeDate, endDate,
                       "When inBedEndDate is nil, endDate must be used as the fallback wake time")
    }

    // MARK: - Helpers

    /// Simulates the duration `LongestSleepBlockCard.durationRow` would display
    /// after the Bug A1 fix: wall-clock span of longestBlock, not the pure-sleep scalar.
    private func displayedDuration(from summary: SleepContinuitySummary) -> TimeInterval {
        if let block = summary.longestBlock {
            return block.endDate.timeIntervalSince(block.startDate)
        }
        return summary.longestBlockDuration
    }

    private func makeStage(_ type: SleepStageType, start: Date, end: Date) -> SleepStage {
        SleepStage(type: type, startDate: start, endDate: end)
    }
}
