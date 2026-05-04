import Foundation
@preconcurrency import HealthKit

// Null HealthKit repository used only for previews and UI testing.
// Returns empty data so the sync layer doesn't overwrite MockLocalDataRepository state.
struct PreviewHealthKitRepository: HealthKitRepositoryProtocol {
    func isHealthDataAvailable() -> Bool { true }

    func requestAuthorization() async throws -> HealthAuthorizationResult {
        HealthAuthorizationResult(
            requestCompleted: true,
            healthDataAvailable: true,
            canQuerySleep: true,
            lastQueryReturnedSamples: true
        )
    }

    func fetchSleepSamples(from: Date, to: Date) async throws -> [HKCategorySample] { [] }

    func fetchSleepSessions(from: Date, to: Date) async throws -> [SleepSession] { [] }

    func fetchBiometrics(for type: BiometricType, from: Date, to: Date) async throws -> [BiometricSample] { [] }

    func fetchSourceSummaries(from: Date, to: Date) async throws -> [SleepSource] {
        [
            SleepSource(name: "Apple Watch", bundleIdentifier: "com.apple.health", productType: "Watch6,2"),
            SleepSource(name: "Apple Health", bundleIdentifier: "com.apple.Health")
        ]
    }

    func startObservingSleepChanges() async throws -> AsyncStream<HealthKitChangeEvent> {
        AsyncStream { _ in }
    }

    func fetchIncrementalSleepChanges(anchor: Data?) async throws -> HealthKitAnchoredResult {
        HealthKitAnchoredResult(samples: [], deletedObjects: [], newAnchor: nil)
    }
}
