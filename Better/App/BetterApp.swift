import SwiftData
import SwiftUI

@main
struct BetterApp: App {
    @Environment(\.scenePhase) private var scenePhase

    private let environment: AppEnvironment

    init() {
        if ProcessInfo.processInfo.arguments.contains("--uitesting") {
            environment = .uiTesting()
        } else {
            do {
                environment = try .live()
            } catch {
                fatalError("Unable to create Better app environment: \(error)")
            }
        }

        environment.backgroundTaskService.registerLaunchHandlers()
    }

    var body: some Scene {
        WindowGroup {
            RootTabView(environment: environment)
                .modelContainer(environment.modelContainer)
                .task {
                    await environment.backgroundTaskService.startHealthKitObservers()
                }
                .onChange(of: scenePhase) { _, newPhase in
                    guard newPhase == .active else { return }
                    Task { @MainActor in
                        await environment.backgroundTaskService.startHealthKitObservers()
                        environment.backgroundTaskService.scheduleNextSleepRefresh()
                    }
                }
        }
    }
}
