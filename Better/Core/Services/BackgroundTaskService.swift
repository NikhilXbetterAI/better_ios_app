import BackgroundTasks
import Foundation

@MainActor
protocol BackgroundTaskSchedulerProtocol: AnyObject {
    func registerSleepRefresh(
        identifier: String,
        launchHandler: @escaping @MainActor (BGAppRefreshTask) async -> Void
    ) -> Bool
    func submit(_ request: BGAppRefreshTaskRequest) throws
}

@MainActor
final class SystemBackgroundTaskScheduler: BackgroundTaskSchedulerProtocol {
    func registerSleepRefresh(
        identifier: String,
        launchHandler: @escaping @MainActor (BGAppRefreshTask) async -> Void
    ) -> Bool {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }

            Task { @MainActor in
                await launchHandler(refreshTask)
            }
        }
    }

    func submit(_ request: BGAppRefreshTaskRequest) throws {
        try BGTaskScheduler.shared.submit(request)
    }
}

@MainActor
@Observable
final class BackgroundTaskService {
    static let sleepRefreshTaskIdentifier = "ai.better-health.Better.sleep-sync"

    private let syncCoordinator: SyncCoordinator
    private let scheduler: BackgroundTaskSchedulerProtocol
    private let isEnabled: Bool
    private var hasRegisteredLaunchHandler = false

    private(set) var lastScheduleErrorMessage: String?

    init(
        syncCoordinator: SyncCoordinator,
        scheduler: BackgroundTaskSchedulerProtocol? = nil,
        isEnabled: Bool = true
    ) {
        self.syncCoordinator = syncCoordinator
        self.scheduler = scheduler ?? SystemBackgroundTaskScheduler()
        self.isEnabled = isEnabled
    }

    func registerLaunchHandlers() {
        guard isEnabled, !hasRegisteredLaunchHandler else { return }

        hasRegisteredLaunchHandler = scheduler.registerSleepRefresh(
            identifier: Self.sleepRefreshTaskIdentifier
        ) { [weak self] task in
            await self?.handleSleepRefresh(task: task)
        }

        if hasRegisteredLaunchHandler {
            scheduleNextSleepRefresh()
        }
    }

    func startHealthKitObservers() async {
        guard isEnabled else { return }
        await syncCoordinator.startObservingHealthChanges()
    }

    static let backgroundRefreshInterval: TimeInterval = 6 * 60 * 60

    @discardableResult
    func scheduleNextSleepRefresh(
        earliestBeginDate: Date = Date(timeIntervalSinceNow: 6 * 60 * 60)
    ) -> Bool {
        guard isEnabled else { return false }

        let request = BGAppRefreshTaskRequest(identifier: Self.sleepRefreshTaskIdentifier)
        request.earliestBeginDate = earliestBeginDate

        do {
            try scheduler.submit(request)
            lastScheduleErrorMessage = nil
            return true
        } catch {
            lastScheduleErrorMessage = error.localizedDescription
            return false
        }
    }
}

private extension BackgroundTaskService {
    func handleSleepRefresh(task: BGAppRefreshTask) async {
        scheduleNextSleepRefresh()

        let refreshTask = Task { @MainActor in
            await syncCoordinator.performIncrementalRefresh()
        }
        task.expirationHandler = { refreshTask.cancel() }
        await refreshTask.value
        if case .failed = syncCoordinator.phase {
            task.setTaskCompleted(success: false)
        } else {
            task.setTaskCompleted(success: !refreshTask.isCancelled)
        }
    }
}
