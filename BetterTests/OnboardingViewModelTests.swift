import XCTest
@testable import Better

@MainActor
final class OnboardingViewModelTests: XCTestCase {
    func testCompleteOnboardingTrimsPreferredNameBeforeSaving() async throws {
        let repository = try await makeRepository()
        let viewModel = makeViewModel(repository: repository)
        viewModel.profile.displayName = "  Ada Lovelace  "

        let completed = await viewModel.completeOnboarding()
        let fetched = try await repository.fetchProfile()

        XCTAssertTrue(completed)
        XCTAssertEqual(fetched.displayName, "Ada Lovelace")
        XCTAssertTrue(fetched.hasCompletedOnboarding)
    }

    func testCompleteOnboardingAllowsBlankPreferredName() async throws {
        let repository = try await makeRepository()
        let viewModel = makeViewModel(repository: repository)
        viewModel.profile.displayName = "   "

        let completed = await viewModel.completeOnboarding()
        let fetched = try await repository.fetchProfile()

        XCTAssertTrue(completed)
        XCTAssertNil(fetched.displayName)
        XCTAssertTrue(fetched.hasCompletedOnboarding)
    }
}

private extension OnboardingViewModelTests {
    func makeViewModel(repository: LocalDataRepository) -> OnboardingViewModel {
        OnboardingViewModel(
            localRepository: repository,
            syncCoordinator: SyncCoordinator(
                healthRepository: FakeHealthKitRepository(),
                localRepository: repository
            )
        )
    }

    func makeRepository() async throws -> LocalDataRepository {
        let container = try BetterPersistenceContainerFactory.makePreviewContainer()
        return LocalDataRepository(modelContainer: container)
    }
}
