import SwiftData
import SwiftUI

@MainActor
final class AppEnvironment {
    let modelContainer: ModelContainer
    let syncCoordinator: SyncCoordinator
    let backgroundTaskService: BackgroundTaskService
    let localRepository: LocalDataRepositoryProtocol
    let healthRepository: HealthKitRepositoryProtocol
    let migrationService: DataMigrationService
    let privacyDataService: PrivacyDataService

    init(
        modelContainer: ModelContainer,
        syncCoordinator: SyncCoordinator,
        backgroundTaskService: BackgroundTaskService,
        localRepository: LocalDataRepositoryProtocol,
        healthRepository: HealthKitRepositoryProtocol,
        migrationService: DataMigrationService,
        privacyDataService: PrivacyDataService
    ) {
        self.modelContainer = modelContainer
        self.syncCoordinator = syncCoordinator
        self.backgroundTaskService = backgroundTaskService
        self.localRepository = localRepository
        self.healthRepository = healthRepository
        self.migrationService = migrationService
        self.privacyDataService = privacyDataService
    }

    static func live() throws -> AppEnvironment {
        let container = try BetterPersistenceContainerFactory.makeLiveContainer()
        let localRepo = LocalDataRepository(modelContainer: container)
        let healthRepo = HealthKitRepository()
        let coordinator = SyncCoordinator(healthRepository: healthRepo, localRepository: localRepo)
        let backgroundTaskService = BackgroundTaskService(syncCoordinator: coordinator)
        let migrationService = DataMigrationService(repository: localRepo)
        let privacyService = PrivacyDataService(localRepository: localRepo, syncCoordinator: coordinator)
        return AppEnvironment(
            modelContainer: container,
            syncCoordinator: coordinator,
            backgroundTaskService: backgroundTaskService,
            localRepository: localRepo,
            healthRepository: healthRepo,
            migrationService: migrationService,
            privacyDataService: privacyService
        )
    }

    #if DEBUG
    static func preview() -> AppEnvironment {
        sharedPreview
    }

    static func uiTesting() -> AppEnvironment {
        if ProcessInfo.processInfo.arguments.contains("--uitesting-onboarding") {
            return makePreview(hasCompletedOnboarding: false)
        }
        return preview()
    }
    #endif
}

#if DEBUG
private extension AppEnvironment {
    static let sharedPreview: AppEnvironment = makePreview()

    static func makePreview(hasCompletedOnboarding: Bool = true) -> AppEnvironment {
        guard let container = try? BetterPersistenceContainerFactory.makePreviewContainer() else {
            fatalError("Unable to create the preview SwiftData container for Better.")
        }
        let localRepo = PreviewSleepData.makeMockRepository(hasCompletedOnboarding: hasCompletedOnboarding)
        let healthRepo = PreviewHealthKitRepository()
        let coordinator = SyncCoordinator(healthRepository: healthRepo, localRepository: localRepo)
        let backgroundTaskService = BackgroundTaskService(syncCoordinator: coordinator, isEnabled: false)
        let migrationService = DataMigrationService(repository: localRepo)
        let privacyService = PrivacyDataService(localRepository: localRepo, syncCoordinator: coordinator)
        return AppEnvironment(
            modelContainer: container,
            syncCoordinator: coordinator,
            backgroundTaskService: backgroundTaskService,
            localRepository: localRepo,
            healthRepository: healthRepo,
            migrationService: migrationService,
            privacyDataService: privacyService
        )
    }
}
#endif
