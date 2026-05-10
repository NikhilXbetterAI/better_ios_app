import XCTest
@testable import Better

@MainActor
final class OnboardingViewModelTests: XCTestCase {
    func testHealthOnboardingStepUsesAppReviewCompliantControls() {
        XCTAssertFalse(OnboardingStep.health.canSkip)
        XCTAssertEqual(OnboardingStep.health.primaryTitle, "Continue")
        XCTAssertTrue(OnboardingStep.assessmentIntro.canSkip)
        XCTAssertEqual(OnboardingStep.assessmentIntro.primaryTitle, "Continue")
        XCTAssertTrue(OnboardingStep.notifications.canSkip)
    }

    func testConnectHealthRequestsAuthorizationOnFirstAction() async throws {
        let repository = try await makeRepository()
        let healthRepository = FakeHealthKitRepository()
        let viewModel = makeViewModel(repository: repository, healthRepository: healthRepository)

        await viewModel.connectHealth()

        XCTAssertEqual(healthRepository.requestAuthorizationCallCount, 1)
    }

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
    func makeViewModel(
        repository: LocalDataRepository,
        healthRepository: FakeHealthKitRepository = FakeHealthKitRepository()
    ) -> OnboardingViewModel {
        OnboardingViewModel(
            localRepository: repository,
            syncCoordinator: SyncCoordinator(
                healthRepository: healthRepository,
                localRepository: repository
            )
        )
    }

    func makeRepository() async throws -> LocalDataRepository {
        let container = try BetterPersistenceContainerFactory.makePreviewContainer()
        return LocalDataRepository(modelContainer: container)
    }
}
