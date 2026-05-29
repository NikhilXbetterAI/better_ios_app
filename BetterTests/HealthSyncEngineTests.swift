import Foundation
import Testing
@testable import Better

/// Verifies that HealthSyncEngine.perform runs off the main actor and returns
/// a valid SyncEngineResult with no errors when given an empty HK repository.
struct HealthSyncEngineTests {

    private let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    // MARK: - Off-main execution

    @Test
    func perform_completesOffMainActor_withEmptyRepository() async throws {
        // Arrange
        let now = date("2026-05-25T00:00:00Z")
        let startDate = calendar.date(byAdding: .day, value: -7, to: now)!
        let healthRepo = PreviewHealthKitRepository()
        let localRepo = MockLocalDataRepository(
            profile: .init(
                id: UUID(),
                baselineWindowDays: 14,
                createdAt: calendar.date(byAdding: .day, value: -30, to: now)!
            )
        )
        let processor = SleepDataProcessor(calendar: calendar)
        let alertService = AlertGenerationService()
        let notifPrefs = UserDefaultsAlertNotificationPreferencesStore()

        // Act — call from a non-main context to confirm it doesn't require main
        let result = try await Task.detached(priority: .background) {
            try await HealthSyncEngine.perform(
                startDate: startDate,
                endDate: now,
                forceDailyProcessing: true,
                dataRetentionDays: 90,
                baselineWindowDaysMin: 15,
                baselineWindowDaysMax: 90,
                healthRepository: healthRepo,
                localRepository: localRepo,
                processor: processor,
                alertService: alertService,
                notificationPreferencesStore: notifPrefs,
                calendar: Calendar.current,
                biomarkerBaselineService: nil
            )
        }.value

        // Assert
        #expect(result.errorMessage == nil)
        #expect(result.syncedAt == now)
    }

    // MARK: - Metadata helpers

    @Test
    func fetchMetadataDate_returnsNil_whenNoAnchorStored() async throws {
        let repo = MockLocalDataRepository()
        let fetched = try await HealthSyncEngine.fetchMetadataDate(
            for: "test.key.missing",
            localRepository: repo
        )
        #expect(fetched == nil)
    }

    @Test
    func saveAndFetchMetadataDate_roundTrips() async throws {
        let repo = MockLocalDataRepository()
        let now = date("2026-05-25T12:00:00Z")
        try await HealthSyncEngine.saveMetadataDate(now, for: "test.key", localRepository: repo)
        let fetched = try await HealthSyncEngine.fetchMetadataDate(for: "test.key", localRepository: repo)
        // Allow 1-second tolerance for PersistenceJSON encode/decode rounding.
        let diff = abs(fetched!.timeIntervalSince(now))
        #expect(diff < 1.0)
    }

    // MARK: - shouldRunDailyProcessing

    @Test
    func shouldRunDailyProcessing_trueWhenForced() async throws {
        let repo = MockLocalDataRepository()
        let result = try await HealthSyncEngine.shouldRunDailyProcessing(
            at: Date(),
            force: true,
            localRepository: repo,
            calendar: calendar
        )
        #expect(result == true)
    }

    @Test
    func shouldRunDailyProcessing_falseOnSameDay() async throws {
        let repo = MockLocalDataRepository()
        let now = date("2026-05-25T10:00:00Z")
        // Save "ran today" timestamp.
        try await HealthSyncEngine.saveMetadataDate(
            now,
            for: HealthSyncEngine.lastDailyProcessingMetadataKey,
            localRepository: repo
        )
        let result = try await HealthSyncEngine.shouldRunDailyProcessing(
            at: date("2026-05-25T23:59:00Z"),
            force: false,
            localRepository: repo,
            calendar: calendar
        )
        #expect(result == false)
    }

    @Test
    func shouldRunDailyProcessing_trueOnNextDay() async throws {
        let repo = MockLocalDataRepository()
        let yesterday = date("2026-05-24T10:00:00Z")
        try await HealthSyncEngine.saveMetadataDate(
            yesterday,
            for: HealthSyncEngine.lastDailyProcessingMetadataKey,
            localRepository: repo
        )
        let result = try await HealthSyncEngine.shouldRunDailyProcessing(
            at: date("2026-05-25T08:00:00Z"),
            force: false,
            localRepository: repo,
            calendar: calendar
        )
        #expect(result == true)
    }

    // MARK: - shouldRunWindowedBaseline

    @Test
    func shouldRunWindowedBaseline_trueWhenElapsedExceedsWindow() async throws {
        let repo = MockLocalDataRepository()
        let windowDays = 7
        let lastRun = date("2026-05-18T00:00:00Z")   // 7 days ago exactly
        try await HealthSyncEngine.saveMetadataDate(
            lastRun,
            for: "\(HealthSyncEngine.windowMetadataKey).\(windowDays)",
            localRepository: repo
        )
        let result = try await HealthSyncEngine.shouldRunWindowedBaseline(
            windowDays: windowDays,
            at: date("2026-05-25T01:00:00Z"),   // just over 7 days later
            force: false,
            localRepository: repo,
            calendar: calendar
        )
        #expect(result == true)
    }

    @Test
    func shouldRunWindowedBaseline_falseWhenWindowNotYetElapsed() async throws {
        let repo = MockLocalDataRepository()
        let windowDays = 7
        let lastRun = date("2026-05-24T12:00:00Z")   // less than 7 days ago
        try await HealthSyncEngine.saveMetadataDate(
            lastRun,
            for: "\(HealthSyncEngine.windowMetadataKey).\(windowDays)",
            localRepository: repo
        )
        let result = try await HealthSyncEngine.shouldRunWindowedBaseline(
            windowDays: windowDays,
            at: date("2026-05-25T00:00:00Z"),
            force: false,
            localRepository: repo,
            calendar: calendar
        )
        #expect(result == false)
    }

    // MARK: - Helpers

    private func date(_ iso: String) -> Date {
        let f = ISO8601DateFormatter()
        return f.date(from: iso)!
    }
}
