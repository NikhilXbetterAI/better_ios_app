import SwiftData
import SwiftUI

@MainActor
final class AppEnvironment {
    let modelContainer: ModelContainer
    let syncCoordinator: SyncCoordinator
    let backgroundTaskService: BackgroundTaskService
    let localRepository: LocalDataRepositoryProtocol
    let healthRepository: HealthKitRepositoryProtocol

    init(
        modelContainer: ModelContainer,
        syncCoordinator: SyncCoordinator,
        backgroundTaskService: BackgroundTaskService,
        localRepository: LocalDataRepositoryProtocol,
        healthRepository: HealthKitRepositoryProtocol
    ) {
        self.modelContainer = modelContainer
        self.syncCoordinator = syncCoordinator
        self.backgroundTaskService = backgroundTaskService
        self.localRepository = localRepository
        self.healthRepository = healthRepository
    }

    static func live() throws -> AppEnvironment {
        let container = try BetterPersistenceContainerFactory.makeLiveContainer()
        let localRepo = LocalDataRepository(modelContainer: container)
        let healthRepo = HealthKitRepository()
        let coordinator = SyncCoordinator(healthRepository: healthRepo, localRepository: localRepo)
        let backgroundTaskService = BackgroundTaskService(syncCoordinator: coordinator)
        return AppEnvironment(
            modelContainer: container,
            syncCoordinator: coordinator,
            backgroundTaskService: backgroundTaskService,
            localRepository: localRepo,
            healthRepository: healthRepo
        )
    }

    static func preview() -> AppEnvironment {
        sharedPreview
    }

    static func uiTesting() -> AppEnvironment { preview() }
}

private extension AppEnvironment {
    static let sharedPreview: AppEnvironment = makePreview()

    static func makePreview() -> AppEnvironment {
        guard let container = try? BetterPersistenceContainerFactory.makePreviewContainer() else {
            fatalError("Unable to create the preview SwiftData container for Better.")
        }
        let localRepo = PreviewSleepData.makeMockRepository()
        let healthRepo = PreviewHealthKitRepository()
        let coordinator = SyncCoordinator(healthRepository: healthRepo, localRepository: localRepo)
        let backgroundTaskService = BackgroundTaskService(syncCoordinator: coordinator, isEnabled: false)
        return AppEnvironment(
            modelContainer: container,
            syncCoordinator: coordinator,
            backgroundTaskService: backgroundTaskService,
            localRepository: localRepo,
            healthRepository: healthRepo
        )
    }
}
