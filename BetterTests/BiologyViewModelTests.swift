import Foundation
import HealthKit
@testable import Better

// Retired BiologyViewModelTests - Biology ViewModel is retired.
// Keep BiologyFakeHealthKitRepository here as it is shared by other test suites.

actor BiologyFakeHealthKitRepository: HealthKitRepositoryProtocol {
    var samples: [BiometricType: [BiometricSample]]
    private(set) var queriedTypes: Set<BiometricType> = []
    private(set) var fetchCallCount = 0

    init(samples: [BiometricType: [BiometricSample]] = [:]) {
        self.samples = samples
    }

    nonisolated func isHealthDataAvailable() -> Bool { true }

    func requestAuthorization() async throws -> HealthAuthorizationResult {
        HealthAuthorizationResult(requestCompleted: true, healthDataAvailable: true, canQuerySleep: true)
    }

    func fetchSleepSamples(from: Date, to: Date) async throws -> [HKCategorySample] { [] }

    func fetchSleepSessions(from: Date, to: Date) async throws -> [SleepSession] { [] }

    func fetchBiometrics(for type: BiometricType, from: Date, to: Date) async throws -> [BiometricSample] {
        queriedTypes.insert(type)
        fetchCallCount += 1
        return samples[type, default: []].filter { $0.endDate > from && $0.startDate < to }
    }

    func fetchSourceSummaries(from: Date, to: Date) async throws -> [SleepSource] { [] }

    func startObservingSleepChanges() async throws -> AsyncStream<HealthKitChangeEvent> {
        AsyncStream { continuation in continuation.finish() }
    }

    func fetchIncrementalSleepChanges(anchor: Data?) async throws -> HealthKitAnchoredResult {
        HealthKitAnchoredResult(samples: [], deletedObjects: [], newAnchor: anchor)
    }
}
