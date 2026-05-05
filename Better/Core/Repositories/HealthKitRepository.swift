import Foundation
@preconcurrency import HealthKit

nonisolated enum HealthKitRepositoryError: Error {
    case healthDataUnavailable
    case unsupportedBiometricType(BiometricType)
    case invalidAnchorData
    case unexpectedSampleType
}

nonisolated final class HealthKitRepository: HealthKitRepositoryProtocol, @unchecked Sendable {
    private let healthStore: HKHealthStore
    private let sleepProcessor: SleepDataProcessor
    private let observerLock = NSLock()
    private var observerQueries: [HKObserverQuery] = []

    init(
        healthStore: HKHealthStore = HKHealthStore(),
        sleepProcessor: SleepDataProcessor = SleepDataProcessor()
    ) {
        self.healthStore = healthStore
        self.sleepProcessor = sleepProcessor
    }

    func isHealthDataAvailable() -> Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    func requestAuthorization() async throws -> HealthAuthorizationResult {
        guard isHealthDataAvailable() else {
            return HealthAuthorizationResult(
                requestCompleted: false,
                healthDataAvailable: false,
                canQuerySleep: false
            )
        }

        let readTypes = Set(HealthKitRepository.readObjectTypes)

        let completed = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Bool, Error>) in
            healthStore.requestAuthorization(toShare: [], read: readTypes) { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: success)
                }
            }
        }

        return HealthAuthorizationResult(
            requestCompleted: completed,
            healthDataAvailable: true,
            canQuerySleep: completed,
            lastQueryReturnedSamples: nil
        )
    }

    func fetchSleepSamples(from: Date, to: Date) async throws -> [HKCategorySample] {
        let sleepType = Self.sleepType
        let predicate = HKQuery.predicateForSamples(
            withStart: from,
            end: to,
            options: [.strictEndDate]
        )
        let sortDescriptors = [
            NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        ]

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: sleepType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: sortDescriptors
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let sleepSamples = samples as? [HKCategorySample] else {
                    continuation.resume(throwing: HealthKitRepositoryError.unexpectedSampleType)
                    return
                }

                continuation.resume(returning: sleepSamples)
            }

            healthStore.execute(query)
        }
    }

    func fetchSleepSessions(from: Date, to: Date) async throws -> [SleepSession] {
        let samples = try await fetchSleepSamples(from: from, to: to)
        return sleepProcessor.process(samples: samples)
    }

    func fetchBiometrics(for type: BiometricType, from: Date, to: Date) async throws -> [BiometricSample] {
        guard let quantityType = Self.quantityType(for: type) else {
            throw HealthKitRepositoryError.unsupportedBiometricType(type)
        }

        let predicate = HKQuery.predicateForSamples(
            withStart: from,
            end: to,
            options: [.strictEndDate]
        )
        let sortDescriptors = [
            NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        ]

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: quantityType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: sortDescriptors
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                let quantitySamples = samples as? [HKQuantitySample] ?? []
                let biometrics = quantitySamples.map { sample in
                    BiometricSample(
                        type: type,
                        value: sample.quantity.doubleValue(for: Self.unit(for: type)),
                        unit: type.unitSymbol,
                        startDate: sample.startDate,
                        endDate: sample.endDate,
                        source: Self.sleepSource(from: sample)
                    )
                }
                continuation.resume(returning: biometrics)
            }

            healthStore.execute(query)
        }
    }

    func fetchSourceSummaries(from: Date, to: Date) async throws -> [SleepSource] {
        let samples = try await fetchSleepSamples(from: from, to: to)
        var sourcesByKey: [String: SleepSource] = [:]

        for sample in samples {
            let source = Self.sleepSource(from: sample)
            sourcesByKey[source.sourceKey] = source
        }

        return sourcesByKey.values.sorted { $0.name < $1.name }
    }

    func startObservingSleepChanges() async throws -> AsyncStream<HealthKitChangeEvent> {
        guard isHealthDataAvailable() else {
            throw HealthKitRepositoryError.healthDataUnavailable
        }

        let sleepType = Self.sleepType

        return AsyncStream { continuation in
            let query = HKObserverQuery(sampleType: sleepType, predicate: nil) { _, completionHandler, error in
                if error != nil {
                    completionHandler()
                    return
                }

                continuation.yield(
                    HealthKitChangeEvent(typeIdentifier: sleepType.identifier) {
                        completionHandler()
                    }
                )
            }

            retainObserverQuery(query)
            healthStore.execute(query)
            healthStore.enableBackgroundDelivery(for: sleepType, frequency: .immediate) { _, _ in }

            continuation.onTermination = { [weak self] _ in
                self?.stopObserverQuery(query)
            }
        }
    }

    func fetchIncrementalSleepChanges(anchor: Data?) async throws -> HealthKitAnchoredResult {
        let sleepType = Self.sleepType
        let queryAnchor = try Self.decodeAnchor(from: anchor)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKAnchoredObjectQuery(
                type: sleepType,
                predicate: nil,
                anchor: queryAnchor,
                limit: HKObjectQueryNoLimit
            ) { _, samples, deletedObjects, newAnchor, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let sleepSamples = samples as? [HKCategorySample] else {
                    continuation.resume(throwing: HealthKitRepositoryError.unexpectedSampleType)
                    return
                }

                do {
                    let encodedAnchor = try Self.encodeAnchor(newAnchor)
                    continuation.resume(
                        returning: HealthKitAnchoredResult(
                            samples: sleepSamples,
                            deletedObjects: deletedObjects ?? [],
                            newAnchor: encodedAnchor
                        )
                    )
                } catch {
                    continuation.resume(throwing: error)
                }
            }

            healthStore.execute(query)
        }
    }
}

nonisolated extension HealthKitRepository {
    static var sleepType: HKCategoryType {
        HKCategoryType(.sleepAnalysis)
    }

    static var readObjectTypes: [HKObjectType] {
        [
            sleepType,
            HKQuantityType(.heartRate),
            HKQuantityType(.heartRateVariabilitySDNN),
            HKQuantityType(.oxygenSaturation),
            HKQuantityType(.respiratoryRate),
            HKQuantityType(.restingHeartRate),
            HKQuantityType(.vo2Max),
            HKQuantityType(.bodyMass),
            HKQuantityType(.leanBodyMass),
            HKQuantityType(.bodyFatPercentage),
            HKQuantityType(.bodyTemperature),
            HKQuantityType(.stepCount),
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.appleExerciseTime),
            HKQuantityType(.appleStandTime),
            HKQuantityType(.flightsClimbed),
            HKQuantityType(.distanceWalkingRunning)
        ]
    }

    static func quantityType(for type: BiometricType) -> HKQuantityType? {
        switch type {
        case .heartRate:
            HKQuantityType(.heartRate)
        case .heartRateVariabilitySDNN:
            HKQuantityType(.heartRateVariabilitySDNN)
        case .oxygenSaturation:
            HKQuantityType(.oxygenSaturation)
        case .respiratoryRate:
            HKQuantityType(.respiratoryRate)
        case .restingHeartRate:
            HKQuantityType(.restingHeartRate)
        case .vo2Max:
            HKQuantityType(.vo2Max)
        case .bodyMass:
            HKQuantityType(.bodyMass)
        case .leanBodyMass:
            HKQuantityType(.leanBodyMass)
        case .bodyFatPercentage:
            HKQuantityType(.bodyFatPercentage)
        case .bodyTemperature:
            HKQuantityType(.bodyTemperature)
        case .stepCount:
            HKQuantityType(.stepCount)
        case .activeEnergyBurned:
            HKQuantityType(.activeEnergyBurned)
        case .appleExerciseTime:
            HKQuantityType(.appleExerciseTime)
        case .appleStandTime:
            HKQuantityType(.appleStandTime)
        case .flightsClimbed:
            HKQuantityType(.flightsClimbed)
        case .distanceWalkingRunning:
            HKQuantityType(.distanceWalkingRunning)
        }
    }

    static func unit(for type: BiometricType) -> HKUnit {
        switch type {
        case .heartRate, .respiratoryRate, .restingHeartRate:
            HKUnit.count().unitDivided(by: .minute())
        case .heartRateVariabilitySDNN:
            HKUnit.secondUnit(with: .milli)
        case .oxygenSaturation:
            HKUnit.percent()
        case .vo2Max:
            HKUnit(from: "mL/kg*min")
        case .bodyMass, .leanBodyMass:
            HKUnit.gramUnit(with: .kilo)
        case .bodyFatPercentage:
            HKUnit.percent()
        case .bodyTemperature:
            HKUnit.degreeCelsius()
        case .stepCount, .flightsClimbed:
            HKUnit.count()
        case .activeEnergyBurned:
            HKUnit.kilocalorie()
        case .appleExerciseTime, .appleStandTime:
            HKUnit.minute()
        case .distanceWalkingRunning:
            HKUnit.meter()
        }
    }

    static func sleepSource(from sample: HKSample) -> SleepSource {
        let sourceRevision = sample.sourceRevision
        let version = sourceRevision.operatingSystemVersion
        let operatingSystemVersion = "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"

        return SleepSource(
            name: sourceRevision.source.name,
            bundleIdentifier: sourceRevision.source.bundleIdentifier,
            productType: sourceRevision.productType,
            operatingSystemVersion: operatingSystemVersion,
            isManualEntry: sample.metadata?[HKMetadataKeyWasUserEntered] as? Bool ?? false
        )
    }

    static func encodeAnchor(_ anchor: HKQueryAnchor?) throws -> Data? {
        guard let anchor else { return nil }
        return try NSKeyedArchiver.archivedData(withRootObject: anchor, requiringSecureCoding: true)
    }

    static func decodeAnchor(from data: Data?) throws -> HKQueryAnchor? {
        guard let data else { return nil }
        guard let anchor = try NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: data) else {
            throw HealthKitRepositoryError.invalidAnchorData
        }
        return anchor
    }

    func retainObserverQuery(_ query: HKObserverQuery) {
        observerLock.lock()
        observerQueries.append(query)
        observerLock.unlock()
    }

    func stopObserverQuery(_ query: HKObserverQuery) {
        healthStore.stop(query)
        observerLock.lock()
        observerQueries.removeAll { $0 === query }
        observerLock.unlock()
    }
}

nonisolated private extension SleepSource {
    var sourceKey: String {
        [
            name,
            bundleIdentifier ?? "",
            productType ?? "",
            operatingSystemVersion ?? "",
            isManualEntry ? "manual" : "automatic"
        ].joined(separator: "|")
    }
}
