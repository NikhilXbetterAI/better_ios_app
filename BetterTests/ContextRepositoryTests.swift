import XCTest
@testable import Better

final class ContextRepositoryTests: XCTestCase {
    private var repo: MockLocalDataRepository!

    override func setUp() async throws {
        repo = MockLocalDataRepository()
    }

    // MARK: - Save and fetch

    func testSaveAndFetchContextEntry() async throws {
        let entry = SleepContextEntry(
            sleepDateKey: "2026-06-01",
            caffeineLate: true,
            alcohol: false,
            highStress: nil
        )
        try await repo.saveContextEntry(entry)

        let fetched = try await repo.fetchContextEntry(forSleepDateKey: "2026-06-01")
        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.caffeineLate, true)
        XCTAssertEqual(fetched?.alcohol, false)
        XCTAssertNil(fetched?.highStress, "Unknown must remain nil after round-trip")
    }

    func testFetchReturnsNilForMissingDateKey() async throws {
        let result = try await repo.fetchContextEntry(forSleepDateKey: "2026-06-05")
        XCTAssertNil(result)
    }

    // MARK: - Upsert (one entry per night)

    func testSavingForSameDateKeyReplacesExistingEntry() async throws {
        var entry = SleepContextEntry(sleepDateKey: "2026-06-01", caffeineLate: true)
        try await repo.saveContextEntry(entry)

        entry.caffeineLate = false
        entry.workout = true
        try await repo.saveContextEntry(entry)

        let fetched = try await repo.fetchContextEntry(forSleepDateKey: "2026-06-01")
        XCTAssertEqual(fetched?.caffeineLate, false)
        XCTAssertEqual(fetched?.workout, true)
    }

    // MARK: - Fetch by date range

    func testFetchContextEntriesInRange() async throws {
        let entries = [
            SleepContextEntry(sleepDateKey: "2026-06-01", caffeineLate: true),
            SleepContextEntry(sleepDateKey: "2026-06-03", caffeineLate: false),
            SleepContextEntry(sleepDateKey: "2026-06-05", caffeineLate: true)
        ]
        for e in entries { try await repo.saveContextEntry(e) }

        let inRange = try await repo.fetchContextEntries(from: "2026-06-01", to: "2026-06-03")
        XCTAssertEqual(inRange.count, 2)
        XCTAssertFalse(inRange.contains { $0.sleepDateKey == "2026-06-05" })
    }

    func testFetchContextEntriesReturnsEmptyForNoMatches() async throws {
        let results = try await repo.fetchContextEntries(from: "2026-01-01", to: "2026-01-31")
        XCTAssertTrue(results.isEmpty)
    }

    // MARK: - Delete

    func testDeleteContextEntryById() async throws {
        let entry = SleepContextEntry(sleepDateKey: "2026-06-01")
        try await repo.saveContextEntry(entry)

        try await repo.deleteContextEntry(id: entry.id)

        let fetched = try await repo.fetchContextEntry(forSleepDateKey: "2026-06-01")
        XCTAssertNil(fetched)
    }

    func testDeleteAllContextEntries() async throws {
        for day in 1...5 {
            let entry = SleepContextEntry(
                sleepDateKey: String(format: "2026-06-%02d", day),
                caffeineLate: true
            )
            try await repo.saveContextEntry(entry)
        }
        try await repo.deleteAllContextEntries()

        let results = try await repo.fetchContextEntries(from: "2026-06-01", to: "2026-06-30")
        XCTAssertTrue(results.isEmpty)
    }

    // MARK: - deleteAllHealthData removes context entries

    func testDeleteAllHealthDataRemovesContextEntries() async throws {
        let entry = SleepContextEntry(sleepDateKey: "2026-06-01", caffeineLate: true)
        try await repo.saveContextEntry(entry)

        try await repo.deleteAllHealthData()

        let fetched = try await repo.fetchContextEntry(forSleepDateKey: "2026-06-01")
        XCTAssertNil(fetched, "deleteAllHealthData must remove all context entries")
    }

    // MARK: - Inventory

    func testFetchDataInventoryIncludesContextCount() async throws {
        for day in 1...3 {
            let entry = SleepContextEntry(
                sleepDateKey: String(format: "2026-06-%02d", day)
            )
            try await repo.saveContextEntry(entry)
        }

        let inventory = try await repo.fetchDataInventory()
        XCTAssertEqual(inventory.contextEntryCount, 3)
    }

    func testFetchDataInventoryContextCountZeroAfterDelete() async throws {
        let entry = SleepContextEntry(sleepDateKey: "2026-06-01")
        try await repo.saveContextEntry(entry)
        try await repo.deleteAllContextEntries()

        let inventory = try await repo.fetchDataInventory()
        XCTAssertEqual(inventory.contextEntryCount, 0)
    }
}
