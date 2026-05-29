import XCTest
@preconcurrency import HealthKit
import BackgroundTasks
@testable import Better

/// Verifies that `handleSleepRefresh` calls `setTaskCompleted` exactly once,
/// whether the expiry handler fires first or normal completion fires first.
@MainActor
final class BackgroundTaskServiceTests: XCTestCase {

    // MARK: - Happy path: normal completion before expiry

    func testSetTaskCompletedCalledOnceOnNormalCompletion() async throws {
        let mockTask = MockAppRefreshTask()
        let service = makeService()

        await service.handleSleepRefresh(task: mockTask)

        XCTAssertEqual(
            mockTask.setTaskCompletedCallCount, 1,
            "setTaskCompleted must be called exactly once on normal completion"
        )
    }

    // MARK: - Expiry fires before work finishes

    func testSetTaskCompletedCalledOnceWhenExpiryFiresFirst() async throws {
        let mockTask = MockAppRefreshTask()
        let (blockerStream, blockerContinuation) = AsyncStream<Void>.makeStream()
        let service = makeService(blockerStream: blockerStream)

        // Start the refresh task but don't await it yet.
        let refreshDriveTask = Task { @MainActor in
            await service.handleSleepRefresh(task: mockTask)
        }

        // Yield so handleSleepRefresh can set the expirationHandler.
        await Task.yield()

        // Fire expiry — simulates iOS killing the time slot.
        mockTask.expirationHandler?()

        // Unblock the sync work so the Task can observe cancellation and exit.
        blockerContinuation.finish()

        await refreshDriveTask.value

        XCTAssertEqual(
            mockTask.setTaskCompletedCallCount, 1,
            "setTaskCompleted must be called exactly once when expiry fires first"
        )
    }

    // MARK: - Both paths race

    func testSetTaskCompletedCalledOnceWhenBothPathsRaceSimultaneously() async throws {
        for _ in 0..<20 {
            let mockTask = MockAppRefreshTask()
            let service = makeService()

            await withTaskGroup(of: Void.self) { group in
                group.addTask { @MainActor in
                    await service.handleSleepRefresh(task: mockTask)
                }
                group.addTask { @MainActor in
                    mockTask.expirationHandler?()
                }
            }

            XCTAssertEqual(
                mockTask.setTaskCompletedCallCount, 1,
                "setTaskCompleted must be called exactly once (race iteration)"
            )
        }
    }
}

// MARK: - Helpers

@MainActor
private extension BackgroundTaskServiceTests {
    /// Build a `BackgroundTaskService` backed by a fake sync coordinator so no real HK
    /// work happens. The optional `blockerStream` is consumed by the fake coordinator to
    /// let tests control when the incremental refresh "finishes".
    func makeService(blockerStream: AsyncStream<Void>? = nil) -> BackgroundTaskService {
        let mockScheduler = MockBackgroundTaskScheduler()
        let fakeSyncCoordinator = makeCoordinator(blockerStream: blockerStream)
        return BackgroundTaskService(
            syncCoordinator: fakeSyncCoordinator,
            scheduler: mockScheduler,
            isEnabled: true
        )
    }

    func makeCoordinator(blockerStream: AsyncStream<Void>?) -> SyncCoordinator {
        let hkRepo = SpinningFakeHealthKitRepository(blocker: blockerStream)
        let container = try! BetterPersistenceContainerFactory.makePreviewContainer()
        let localRepo = LocalDataRepository(modelContainer: container)
        return SyncCoordinator(healthRepository: hkRepo, localRepository: localRepo)
    }
}

// MARK: - Mock BGTask

/// Thread-safe mock that counts how many times `setTaskCompleted` is called.
@MainActor
final class MockAppRefreshTask: AppRefreshTaskProtocol {
    var expirationHandler: (() -> Void)?
    private(set) var setTaskCompletedCallCount = 0
    private(set) var lastSuccessValue: Bool?

    func setTaskCompleted(success: Bool) {
        setTaskCompletedCallCount += 1
        lastSuccessValue = success
    }
}

// MARK: - Mock scheduler (no-op, prevents BGTaskScheduler.shared calls in tests)

@MainActor
final class MockBackgroundTaskScheduler: BackgroundTaskSchedulerProtocol {
    func registerSleepRefresh(
        identifier: String,
        launchHandler: @escaping @MainActor (BGAppRefreshTask) async -> Void
    ) -> Bool {
        true
    }

    func submit(_ request: BGAppRefreshTaskRequest) throws {
        // no-op in tests
    }
}

// MARK: - HealthKit fake that can block to simulate slow work

final class SpinningFakeHealthKitRepository: HealthKitRepositoryProtocol, @unchecked Sendable {
    private let blocker: AsyncStream<Void>?

    init(blocker: AsyncStream<Void>?) {
        self.blocker = blocker
    }

    func isHealthDataAvailable() -> Bool { true }

    func requestAuthorization() async throws -> HealthAuthorizationResult {
        HealthAuthorizationResult(requestCompleted: true, healthDataAvailable: true, canQuerySleep: true)
    }

    func fetchSleepSamples(from: Date, to: Date) async throws -> [HKCategorySample] { [] }

    func fetchSleepSessions(from: Date, to: Date) async throws -> [SleepSession] { [] }

    func fetchBiometrics(for type: BiometricType, from: Date, to: Date) async throws -> [BiometricSample] {
        // Consume the blocker stream to let the test control when this returns.
        if let blocker {
            for await _ in blocker { break }
        }
        return []
    }

    func fetchSourceSummaries(from: Date, to: Date) async throws -> [SleepSource] { [] }

    func startObservingSleepChanges() async throws -> AsyncStream<HealthKitChangeEvent> {
        AsyncStream { $0.finish() }
    }

    func fetchIncrementalSleepChanges(anchor: Data?) async throws -> HealthKitAnchoredResult {
        HealthKitAnchoredResult(samples: [], deletedObjects: [], newAnchor: nil)
    }
}
