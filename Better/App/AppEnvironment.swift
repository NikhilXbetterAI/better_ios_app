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
    let sleepModeNotificationService: SleepModeNotificationService
    let sleepModeScheduleService: SleepModeScheduleService
    let sleepModeCoordinator: SleepModeCoordinator
    let redLightFilterService: RedLightFilterService
    let biomarkerBaselineService: BiomarkerBaselineService

    init(
        modelContainer: ModelContainer,
        syncCoordinator: SyncCoordinator,
        backgroundTaskService: BackgroundTaskService,
        localRepository: LocalDataRepositoryProtocol,
        healthRepository: HealthKitRepositoryProtocol,
        migrationService: DataMigrationService,
        privacyDataService: PrivacyDataService,
        sleepModeNotificationService: SleepModeNotificationService,
        sleepModeScheduleService: SleepModeScheduleService,
        sleepModeCoordinator: SleepModeCoordinator,
        redLightFilterService: RedLightFilterService,
        biomarkerBaselineService: BiomarkerBaselineService
    ) {
        self.modelContainer = modelContainer
        self.syncCoordinator = syncCoordinator
        self.backgroundTaskService = backgroundTaskService
        self.localRepository = localRepository
        self.healthRepository = healthRepository
        self.migrationService = migrationService
        self.privacyDataService = privacyDataService
        self.sleepModeNotificationService = sleepModeNotificationService
        self.sleepModeScheduleService = sleepModeScheduleService
        self.sleepModeCoordinator = sleepModeCoordinator
        self.redLightFilterService = redLightFilterService
        self.biomarkerBaselineService = biomarkerBaselineService
    }

    /// Runs the one-shot legacy ProtocolAdherence → Protocol Formula migration if needed.
    /// Idempotency lives in `ProtocolAdherenceMigrationService` via UserDefaults.
    /// Safe to call on every launch.
    func runProtocolFormulaMigrationIfNeeded() async {
        let service = ProtocolAdherenceMigrationService(repository: localRepository)
        _ = try? await service.runIfNeeded()
        // Catalog rows are now created lazily — only when onboarding's seedHistory
        // (or another explicit user action) actually paints a version. Eager
        // creation at launch was fabricating fake shippedOn dates for every user.
        await augmentProtocolBaselineExtendedMetricsIfNeeded()
        await BackfillCoordinator.runV3Backfill(repository: localRepository)
    }

    /// Pass to fill in the full-sleep-stage baseline metrics (deep / REM / awake /
    /// total sleep / latency / score) on baselines frozen before the P0-4 scope
    /// expansion. The service is idempotent and only fills missing fields.
    private func augmentProtocolBaselineExtendedMetricsIfNeeded() async {
        let baselineService = ProtocolBaselineService(repository: localRepository)
        guard (try? await baselineService.augmentBaselineWithExtendedMetricsIfNeeded()) == true else {
            return
        }
    }

    static func live() throws -> AppEnvironment {
        let container = try BetterPersistenceContainerFactory.makeLiveContainer()
        let localRepo = LocalDataRepository(modelContainer: container)
        let healthRepo = HealthKitRepository()
        let coordinator = SyncCoordinator(healthRepository: healthRepo, localRepository: localRepo)
        let backgroundTaskService = BackgroundTaskService(syncCoordinator: coordinator)
        let migrationService = DataMigrationService(repository: localRepo)
        let privacyService = PrivacyDataService(localRepository: localRepo, syncCoordinator: coordinator)
        let sleepModeNotificationService = SleepModeNotificationService()
        let sleepModeScheduleService = SleepModeScheduleService(
            repository: localRepo,
            notificationService: sleepModeNotificationService
        )
        let sleepModeCoordinator = SleepModeCoordinator()
        sleepModeScheduleService.onForegroundActivation = { [sleepModeCoordinator] presentation in
            sleepModeCoordinator.activePresentation = presentation
        }
        let biomarkerBaselineService = BiomarkerBaselineService(repository: localRepo)
        coordinator.setBiomarkerBaselineService(biomarkerBaselineService)
        return AppEnvironment(
            modelContainer: container,
            syncCoordinator: coordinator,
            backgroundTaskService: backgroundTaskService,
            localRepository: localRepo,
            healthRepository: healthRepo,
            migrationService: migrationService,
            privacyDataService: privacyService,
            sleepModeNotificationService: sleepModeNotificationService,
            sleepModeScheduleService: sleepModeScheduleService,
            sleepModeCoordinator: sleepModeCoordinator,
            redLightFilterService: RedLightFilterService(),
            biomarkerBaselineService: biomarkerBaselineService
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
        let sleepModeNotificationService = SleepModeNotificationService()
        let sleepModeScheduleService = SleepModeScheduleService(
            repository: localRepo,
            notificationService: sleepModeNotificationService
        )
        let sleepModeCoordinator = SleepModeCoordinator()
        sleepModeScheduleService.onForegroundActivation = { [sleepModeCoordinator] presentation in
            sleepModeCoordinator.activePresentation = presentation
        }
        let biomarkerBaselineService = BiomarkerBaselineService(repository: localRepo)
        coordinator.setBiomarkerBaselineService(biomarkerBaselineService)
        return AppEnvironment(
            modelContainer: container,
            syncCoordinator: coordinator,
            backgroundTaskService: backgroundTaskService,
            localRepository: localRepo,
            healthRepository: healthRepo,
            migrationService: migrationService,
            privacyDataService: privacyService,
            sleepModeNotificationService: sleepModeNotificationService,
            sleepModeScheduleService: sleepModeScheduleService,
            sleepModeCoordinator: sleepModeCoordinator,
            redLightFilterService: RedLightFilterService(),
            biomarkerBaselineService: biomarkerBaselineService
        )
    }
}
#endif
