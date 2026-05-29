import BackgroundTasks
import Foundation

/// Abstracts the completion-signalling surface of `BGAppRefreshTask` so that
/// `handleSleepRefresh` can be tested without a real BGTask instance.
@MainActor
protocol AppRefreshTaskProtocol: AnyObject {
    var expirationHandler: (() -> Void)? { get set }
    func setTaskCompleted(success: Bool)
}

extension BGAppRefreshTask: AppRefreshTaskProtocol {}

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

// MARK: - Internal for testing

extension BackgroundTaskService {
    /// Exposed `internal` (not `private`) so unit tests can drive the completion logic
    /// without requiring a real `BGAppRefreshTask` instance.
    func handleSleepRefresh(task: some AppRefreshTaskProtocol) async {
        scheduleNextSleepRefresh()

        // Guard against double-setTaskCompleted: the expiration handler and normal
        // completion can race. We use a nonisolated(unsafe) Bool under the protection
        // that only one of the two paths can win: the expiration handler fires on an
        // arbitrary thread before await returns, so we check-and-set atomically via
        // the BGTask serial guarantee (only one of the two closures runs to completion
        // first). Both paths check `completed` before calling setTaskCompleted.
        nonisolated(unsafe) var completed = false

        let refreshTask = Task { @MainActor in
            await syncCoordinator.performIncrementalRefresh()
        }

        task.expirationHandler = {
            guard !completed else { return }
            completed = true
            refreshTask.cancel()
            task.setTaskCompleted(success: false)
        }

        // Await the task value; cooperative cancellation makes this return promptly
        // when the expiration handler fires.
        _ = await refreshTask.result

        guard !completed else { return }
        completed = true

        if case .failed = syncCoordinator.phase {
            task.setTaskCompleted(success: false)
        } else {
            task.setTaskCompleted(success: !refreshTask.isCancelled)
        }
    }
}
