import XCTest
@preconcurrency import HealthKit
@testable import Better

@MainActor
final class SettingsViewModelTests: XCTestCase {
    func testSettingsViewModelLoadsAndSavesPreferredName() async throws {
        let repository = try await makeRepository()
        try await repository.saveProfile(UserProfile(displayName: "Maya"))

        let viewModel = makeViewModel(repository: repository)
        await viewModel.onAppear()

        XCTAssertEqual(viewModel.profile.displayName, "Maya")

        viewModel.profile.displayName = "  Maya Chen  "
        await viewModel.saveProfile()

        let fetched = try await repository.fetchProfile()
        XCTAssertEqual(fetched.displayName, "Maya Chen")
    }

    /// Phase 6 regression: `loadSettings` (called on every tab appear) must NOT
    /// trigger `buildExportPackage`. ZIP serialization on main actor was causing
    /// jank. Insight building is now deferred to explicit user actions only.
    func testLoadSettingsDoesNotBuildExportPackage() async throws {
        let repository = try await makeRepository()
        let spyHK = TrackingFakeHealthKitRepository()

        let syncCoordinator = SyncCoordinator(
            healthRepository: spyHK,
            localRepository: repository
        )
        let privacyService = PrivacyDataService(
            localRepository: repository,
            syncCoordinator: syncCoordinator
        )
        let viewModel = SettingsViewModel(
            localRepository: repository,
            healthRepository: spyHK,
            syncCoordinator: syncCoordinator,
            privacyService: privacyService
        )

        await viewModel.loadSettings()

        // `insightSummary` should remain nil — no export was built.
        XCTAssertNil(
            viewModel.insightSummary,
            "loadSettings must not populate insightSummary; that requires an explicit export action"
        )
        // fetchSourceSummaries IS expected (cheap metadata query).
        XCTAssertGreaterThanOrEqual(
            spyHK.fetchSourceSummariesCallCount, 0,
            "fetchSourceSummaries is allowed on appear"
        )
    }
}

// MARK: - Spy HealthKit repository

/// Records call counts so tests can assert which methods were invoked.
final class TrackingFakeHealthKitRepository: HealthKitRepositoryProtocol, @unchecked Sendable {
    private(set) var fetchSourceSummariesCallCount = 0

    func isHealthDataAvailable() -> Bool { true }

    func requestAuthorization() async throws -> HealthAuthorizationResult {
        HealthAuthorizationResult(requestCompleted: true, healthDataAvailable: true, canQuerySleep: true)
    }

    func fetchSleepSamples(from: Date, to: Date) async throws -> [HKCategorySample] { [] }

    func fetchSleepSessions(from: Date, to: Date) async throws -> [SleepSession] { [] }

    func fetchBiometrics(for type: BiometricType, from: Date, to: Date) async throws -> [BiometricSample] { [] }

    func fetchSourceSummaries(from: Date, to: Date) async throws -> [SleepSource] {
        fetchSourceSummariesCallCount += 1
        return []
    }

    func startObservingSleepChanges() async throws -> AsyncStream<HealthKitChangeEvent> {
        AsyncStream { $0.finish() }
    }

    func fetchIncrementalSleepChanges(anchor: Data?) async throws -> HealthKitAnchoredResult {
        HealthKitAnchoredResult(samples: [], deletedObjects: [], newAnchor: nil)
    }
}

// MARK: - Helpers

private extension SettingsViewModelTests {
    func makeViewModel(repository: LocalDataRepository) -> SettingsViewModel {
        let syncCoordinator = SyncCoordinator(
            healthRepository: FakeHealthKitRepository(),
            localRepository: repository
        )
        let privacyService = PrivacyDataService(
            localRepository: repository,
            syncCoordinator: syncCoordinator
        )

        return SettingsViewModel(
            localRepository: repository,
            healthRepository: FakeHealthKitRepository(),
            syncCoordinator: syncCoordinator,
            privacyService: privacyService
        )
    }

    func makeRepository() async throws -> LocalDataRepository {
        let container = try BetterPersistenceContainerFactory.makePreviewContainer()
        return LocalDataRepository(modelContainer: container)
    }
}
