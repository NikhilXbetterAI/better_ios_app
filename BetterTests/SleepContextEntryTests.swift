import XCTest
@testable import Better

final class SleepContextEntryTests: XCTestCase {

    // MARK: - Tristate semantics

    func testUnknownIsNotFalse() {
        let entry = SleepContextEntry(sleepDateKey: "2026-06-01")
        XCTAssertNil(entry.caffeineLate, "Unknown must be nil, not false")
        XCTAssertNil(entry.alcohol)
        XCTAssertNil(entry.workout)
    }

    func testExplicitFalseIsDistinctFromNil() {
        let entry = SleepContextEntry(sleepDateKey: "2026-06-01", caffeineLate: false)
        XCTAssertEqual(entry.caffeineLate, false)
        XCTAssertNil(entry.alcohol, "Unset field must remain nil")
    }

    func testExplicitTrueIsDistinctFromNilAndFalse() {
        let entry = SleepContextEntry(sleepDateKey: "2026-06-01", caffeineLate: true)
        XCTAssertEqual(entry.caffeineLate, true)
        XCTAssertNotEqual(entry.caffeineLate, false)
    }

    // MARK: - Completion status

    func testCompletionStatusNotFilledWhenAllNil() {
        let entry = SleepContextEntry(sleepDateKey: "2026-06-01")
        XCTAssertEqual(entry.completionStatus, .notFilled)
    }

    func testCompletionStatusPartialWhenSomeAnswered() {
        let entry = SleepContextEntry(sleepDateKey: "2026-06-01", caffeineLate: true, alcohol: false)
        XCTAssertEqual(entry.completionStatus, .partial)
    }

    func testCompletionStatusCompleteWhenAllEightAnswered() {
        let entry = SleepContextEntry(
            sleepDateKey: "2026-06-01",
            caffeineLate: true,
            alcohol: false,
            workout: true,
            lateMeal: false,
            highStress: nil,      // explicitly nil → partial not complete
            screenTimeLate: true,
            nap: false,
            travel: true
        )
        // highStress is nil → not all eight answered
        XCTAssertEqual(entry.completionStatus, .partial)
    }

    func testCompletionStatusCompleteWhenAllEightHaveExplicitAnswer() {
        let entry = SleepContextEntry(
            sleepDateKey: "2026-06-01",
            caffeineLate: true,
            alcohol: false,
            workout: true,
            lateMeal: false,
            highStress: false,
            screenTimeLate: true,
            nap: false,
            travel: true
        )
        XCTAssertEqual(entry.completionStatus, .complete)
    }

    func testHasNotesReturnsFalseForNilNotes() {
        let entry = SleepContextEntry(sleepDateKey: "2026-06-01")
        XCTAssertFalse(entry.hasNotes)
    }

    func testHasNotesReturnsTrueForNonEmptyNotes() {
        let entry = SleepContextEntry(sleepDateKey: "2026-06-01", notes: "Stressful day")
        XCTAssertTrue(entry.hasNotes)
    }

    func testHasNotesReturnsFalseForEmptyString() {
        let entry = SleepContextEntry(sleepDateKey: "2026-06-01", notes: "")
        XCTAssertFalse(entry.hasNotes)
    }

    // MARK: - Codable round-trip (encryption compatibility)

    func testCodableRoundTrip() throws {
        let original = SleepContextEntry(
            sleepDateKey: "2026-06-01",
            caffeineLate: true,
            alcohol: nil,
            workout: false,
            perceivedSleepQuality: .good,
            morningEnergy: .high,
            notes: "Testing"
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SleepContextEntry.self, from: data)
        XCTAssertEqual(decoded.caffeineLate, true)
        XCTAssertNil(decoded.alcohol)
        XCTAssertEqual(decoded.workout, false)
        XCTAssertEqual(decoded.perceivedSleepQuality, .good)
        XCTAssertEqual(decoded.morningEnergy, .high)
        XCTAssertEqual(decoded.notes, "Testing")
        XCTAssertEqual(decoded.sleepDateKey, "2026-06-01")
    }
}
