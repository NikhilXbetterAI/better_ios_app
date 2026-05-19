import SwiftData
import SwiftUI

@main
struct BetterApp: App {
    @Environment(\.scenePhase) private var scenePhase

    private let environment: AppEnvironment

    init() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--uitesting") {
            environment = .uiTesting()
        } else {
            do {
                environment = try .live()
            } catch {
                fatalError("Unable to create Better app environment: \(error)")
            }
        }
        #else
        do {
            environment = try .live()
        } catch {
            fatalError("Unable to create Better app environment: \(error)")
        }
        #endif

        environment.backgroundTaskService.registerLaunchHandlers()
        let sleepModeNotificationService = environment.sleepModeNotificationService
        Task {
            await sleepModeNotificationService.registerCategories()
        }
    }

    var body: some Scene {
        WindowGroup {
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
        }
    }
}
