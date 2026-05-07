import Foundation
@preconcurrency import HealthKit

#if DEBUG
// Null HealthKit repository used only for previews and UI testing.
// Returns empty data so the sync layer doesn't overwrite MockLocalDataRepository state.
nonisolated struct PreviewHealthKitRepository: HealthKitRepositoryProtocol {
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

    func fetchBiometrics(for type: BiometricType, from: Date, to: Date) async throws -> [BiometricSample] {
        let now = Date()
        let values: [Double]
        switch type {
        case .vo2Max:
            values = [44.2, 45.0, 45.8, 46.2, 46.5, 46.8, 47.0]
        case .bodyMass:
            values = [75.1, 75.4, 75.6, 75.8, 76.0, 76.2, 76.3]
        case .leanBodyMass:
            values = [61.8, 61.9, 62.0, 62.1, 62.2, 62.2, 62.3]
        case .bodyFatPercentage:
            values = [0.192, 0.190, 0.189, 0.188, 0.187, 0.186, 0.185]
        case .bodyTemperature:
            values = [36.4, 36.5, 36.5, 36.6, 36.6, 36.7, 36.6]
        case .restingHeartRate:
            values = [58.0, 57.5, 57.0, 56.5, 57.0, 56.0, 55.5]
        case .stepCount:
            values = [8_420]
        case .activeEnergyBurned:
            values = [487]
        case .appleExerciseTime:
            values = [34]
        case .appleStandTime:
            values = [540]
        case .flightsClimbed:
            values = [6]
        case .distanceWalkingRunning:
            values = [5_800]
        default:
            return []
        }

        return values.enumerated().map { index, value in
            let start = Calendar.current.date(byAdding: .day, value: index - values.count + 1, to: now) ?? now
            return BiometricSample(
                type: type,
                value: value,
                unit: type.unitSymbol,
                startDate: start,
                endDate: start.addingTimeInterval(60),
                source: SleepSource(name: "Apple Watch", bundleIdentifier: "com.apple.health", productType: "Watch6,2")
            )
        }
        .filter { $0.endDate >= from && $0.startDate <= to }
    }

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
#endif
