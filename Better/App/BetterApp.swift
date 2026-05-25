import OSLog
import SwiftData
import SwiftUI

@main
struct BetterApp: App {
    @Environment(\.scenePhase) private var scenePhase

    @State private var bootState: BootState

    private static let logger = Logger(subsystem: "Better", category: "Boot")

    /// App-launch state. Migration failures used to call `fatalError`, which
    /// jetsam-killed the app on every launch when the SwiftData store was
    /// corrupted. We now surface a non-destructive recovery screen so users
    /// can opt into wiping the local store rather than losing the install.
    enum BootState {
        case ready(AppEnvironment)
        case failed(Error)
    }

    init() {
        let initial: BootState
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--uitesting") {
            initial = .ready(.uiTesting())
        } else {
            initial = Self.makeInitialBootState()
        }
        #else
        initial = Self.makeInitialBootState()
        #endif

        if case .ready(let environment) = initial {
            Self.bootEnvironment(environment)
        }
        _bootState = State(initialValue: initial)
    }

    private static func makeInitialBootState() -> BootState {
        do {
            return .ready(try .live())
        } catch {
            logger.error("AppEnvironment.live failed: \(error.localizedDescription, privacy: .public)")
            return .failed(error)
        }
    }

    private static func bootEnvironment(_ environment: AppEnvironment) {
        environment.backgroundTaskService.registerLaunchHandlers()
        let sleepModeNotificationService = environment.sleepModeNotificationService
        Task {
            await sleepModeNotificationService.registerCategories()
        }
    }

    var body: some Scene {
        WindowGroup {
            switch bootState {
            case .ready(let environment):
                RootTabView(environment: environment)
                    .modelContainer(environment.modelContainer)
                    .task {
                        // Run storage migration before starting observers so that
                        // all write paths use the new encrypted format from the start.
                        await environment.migrationService.migrateIfNeeded()
                        await environment.sleepModeScheduleService.loadSchedule()
                        await environment.sleepModeScheduleService.rescheduleRemindersIfNeeded()
                        await environment.backgroundTaskService.startHealthKitObservers()
                        environment.sleepModeScheduleService.evaluateForegroundActivation()
                    }
                    .onChange(of: scenePhase) { _, newPhase in
                        guard newPhase == .active else { return }
                        Task { @MainActor in
                            await environment.backgroundTaskService.startHealthKitObservers()
                            environment.backgroundTaskService.scheduleNextSleepRefresh()
                            await environment.sleepModeScheduleService.loadSchedule()
                            environment.sleepModeScheduleService.evaluateForegroundActivation()
                        }
                    }
            case .failed(let error):
                BootRecoveryView(error: error) {
                    BetterPersistenceContainerFactory.wipeStoreFiles()
                    let next = Self.makeInitialBootState()
                    if case .ready(let environment) = next {
                        Self.bootEnvironment(environment)
                    }
                    bootState = next
                }
            }
        }
    }
}
