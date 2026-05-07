import XCTest
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
}

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
