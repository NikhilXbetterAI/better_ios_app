import Foundation
import Observation

@MainActor
@Observable
final class BiologyViewModel {
    private let localRepository: LocalDataRepositoryProtocol
    private let healthRepository: HealthKitRepositoryProtocol
    private let calendar: Calendar

    var metrics: [BiologyMetric] = []
    var isLoading = false
    var errorMessage: String?

    init(
        localRepository: LocalDataRepositoryProtocol,
        healthRepository: HealthKitRepositoryProtocol,
        calendar: Calendar = .current
    ) {
        self.localRepository = localRepository
        self.healthRepository = healthRepository
        self.calendar = calendar
    }

    func onAppear(now: Date = Date()) async {
        guard metrics.isEmpty else { return }
        await load(now: now)
    }

    func load(now: Date = Date()) async {
        isLoading = true
        errorMessage = nil

        let start = calendar.date(byAdding: .day, value: -30, to: now) ?? now.addingTimeInterval(-30 * 86_400)
        do {
            async let vo2 = samples(for: .vo2Max, from: start, to: now)
            async let weight = samples(for: .bodyMass, from: start, to: now)
            async let leanMass = samples(for: .leanBodyMass, from: start, to: now)
            async let bodyFat = samples(for: .bodyFatPercentage, from: start, to: now)
            async let bodyTemp = samples(for: .bodyTemperature, from: start, to: now)
            let latestSession = try await localRepository.fetchLatestSession()
            let profile = try await localRepository.fetchProfile()
            let baseline = try await localRepository.fetchLatestBaseline(windowDays: profile.baselineWindowDays)

            metrics = try await makeMetrics(
                vo2: vo2,
                weight: weight,
                leanMass: leanMass,
                bodyFat: bodyFat,
                bodyTemp: bodyTemp,
                latestSession: latestSession,
                baseline: baseline
            )
        } catch {
            errorMessage = error.localizedDescription
            metrics = Self.placeholderMetrics
        }

        isLoading = false
    }
}

private extension BiologyViewModel {
    func samples(for type: BiometricType, from start: Date, to end: Date) async throws -> [BiometricSample] {
        try await healthRepository.fetchBiometrics(for: type, from: start, to: end)
    }

    func makeMetrics(
        vo2: [BiometricSample],
        weight: [BiometricSample],
        leanMass: [BiometricSample],
        bodyFat: [BiometricSample],
        bodyTemp: [BiometricSample],
        latestSession: SleepSession?,
        baseline: SleepBaseline?
    ) -> [BiologyMetric] {
        let biometrics = latestSession?.biometrics
        return [
            BiologyMetric(
                kind: .vo2Max,
                title: "VO2 Max",
                value: latestValue(vo2),
                unit: BiometricType.vo2Max.unitSymbol,
                rating: vo2Rating(latestValue(vo2)),
                trend: trend(for: vo2),
                history: history(vo2)
            ),
            BiologyMetric(
                kind: .hrvBaseline,
                title: "HRV Baselines",
                value: biometrics?.hrvAverage ?? baseline?.hrvAverage,
                unit: "ms",
                rating: hrvRating(biometrics?.hrvAverage ?? baseline?.hrvAverage),
                trend: "Stabilizing",
                history: syntheticHistory(around: biometrics?.hrvAverage ?? baseline?.hrvAverage)
            ),
            BiologyMetric(
                kind: .restingHeartRateBaseline,
                title: "RHR Baselines",
                value: restingHeartRateFallback(latestSession: latestSession),
                unit: "bpm",
                rating: rhrRating(restingHeartRateFallback(latestSession: latestSession)),
                trend: "Stable",
                history: syntheticHistory(around: restingHeartRateFallback(latestSession: latestSession))
            ),
            BiologyMetric(
                kind: .weight,
                title: "Weight",
                value: latestValue(weight),
                unit: "kg",
                rating: "Tracking",
                trend: trend(for: weight),
                history: history(weight)
            ),
            BiologyMetric(
                kind: .leanBodyMass,
                title: "Lean Body Mass",
                value: latestValue(leanMass),
                unit: "kg",
                rating: "No trend",
                trend: trend(for: leanMass),
                history: history(leanMass)
            ),
            BiologyMetric(
                kind: .bodyFatPercentage,
                title: "Body Fat",
                value: percentValue(latestValue(bodyFat)),
                unit: "%",
                rating: "Acceptable",
                trend: trend(for: bodyFat),
                history: history(bodyFat).map(percentValue)
            ),
            BiologyMetric(
                kind: .bloodOxygen,
                title: "Blood O2",
                value: percentValue(biometrics?.oxygenSaturationAverage ?? baseline?.oxygenSaturationAverage),
                unit: "%",
                rating: oxygenRating(percentValue(biometrics?.oxygenSaturationAverage ?? baseline?.oxygenSaturationAverage)),
                trend: "Normal",
                history: syntheticHistory(around: percentValue(biometrics?.oxygenSaturationAverage ?? baseline?.oxygenSaturationAverage))
            ),
            BiologyMetric(
                kind: .respiratoryRate,
                title: "Resp Rate",
                value: biometrics?.respiratoryRateAverage ?? baseline?.respiratoryRateAverage,
                unit: "br/min",
                rating: "Normal",
                trend: "Stable",
                history: syntheticHistory(around: biometrics?.respiratoryRateAverage ?? baseline?.respiratoryRateAverage)
            ),
            BiologyMetric(
                kind: .bodyTemperature,
                title: "Temp",
                value: latestValue(bodyTemp),
                unit: "C",
                rating: latestValue(bodyTemp) == nil ? "Not available" : "Normal",
                trend: trend(for: bodyTemp),
                history: history(bodyTemp)
            )
        ]
    }

    func latestValue(_ samples: [BiometricSample]) -> Double? {
        samples.max { $0.endDate < $1.endDate }?.value
    }

    func history(_ samples: [BiometricSample]) -> [Double] {
        Array(samples.sorted { $0.endDate < $1.endDate }.suffix(12).map(\.value))
    }

    func percentValue(_ value: Double?) -> Double? {
        guard let value else { return nil }
        return value <= 1 ? value * 100 : value
    }

    func percentValue(_ value: Double) -> Double {
        value <= 1 ? value * 100 : value
    }

    func syntheticHistory(around value: Double?) -> [Double] {
        guard let value else { return [] }
        return [-0.08, -0.04, -0.02, 0.01, -0.01, 0.02, 0.0].map { value * (1 + $0) }
    }

    func trend(for samples: [BiometricSample]) -> String {
        let values = history(samples)
        guard let first = values.first, let last = values.last, values.count > 1 else { return "No trend" }
        if last > first * 1.02 { return "Increasing" }
        if last < first * 0.98 { return "Decreasing" }
        return "Stable"
    }

    func restingHeartRateFallback(latestSession: SleepSession?) -> Double? {
        latestSession?.biometrics?.heartRateAverage
    }

    func vo2Rating(_ value: Double?) -> String {
        guard let value else { return "No data" }
        switch value {
        case ..<35: "Low"
        case ..<45: "Fair"
        case ..<55: "Good"
        default: "Excellent"
        }
    }

    func hrvRating(_ value: Double?) -> String {
        guard let value else { return "No data" }
        return value >= 60 ? "Strong" : value >= 40 ? "Stabilizing" : "Low"
    }

    func rhrRating(_ value: Double?) -> String {
        guard let value else { return "No data" }
        return value <= 58 ? "Good" : value <= 68 ? "Fair" : "Elevated"
    }

    func oxygenRating(_ value: Double?) -> String {
        guard let value else { return "No data" }
        return value >= 95 ? "Good" : "Watch"
    }

    static let placeholderMetrics: [BiologyMetric] = [
        BiologyMetric(kind: .vo2Max, title: "VO2 Max", value: nil, unit: "mL/kg/min", rating: "No data"),
        BiologyMetric(kind: .hrvBaseline, title: "HRV Baselines", value: nil, unit: "ms", rating: "No data"),
        BiologyMetric(kind: .restingHeartRateBaseline, title: "RHR Baselines", value: nil, unit: "bpm", rating: "No data"),
        BiologyMetric(kind: .weight, title: "Weight", value: nil, unit: "kg", rating: "No data"),
        BiologyMetric(kind: .leanBodyMass, title: "Lean Body Mass", value: nil, unit: "kg", rating: "No data"),
        BiologyMetric(kind: .bodyFatPercentage, title: "Body Fat", value: nil, unit: "%", rating: "No data"),
        BiologyMetric(kind: .bloodOxygen, title: "Blood O2", value: nil, unit: "%", rating: "No data"),
        BiologyMetric(kind: .respiratoryRate, title: "Resp Rate", value: nil, unit: "br/min", rating: "No data"),
        BiologyMetric(kind: .bodyTemperature, title: "Temp", value: nil, unit: "C", rating: "Not available")
    ]
}
