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
        guard !isLoading else { return }
        let hasData = metrics.contains { $0.value != nil }
        guard !hasData else { return }
        await load(now: now)
    }

    func load(now: Date = Date()) async {
        isLoading = true
        errorMessage = nil

        let start = calendar.date(byAdding: .day, value: -30, to: now) ?? now.addingTimeInterval(-30 * 86_400)

        // Fetch manual entries unconditionally — they must survive HealthKit failures.
        let manualEntries = (try? await localRepository.fetchManualBiologyEntries()) ?? []

        do {
            async let vo2 = samples(for: .vo2Max, from: start, to: now)
            async let weight = samples(for: .bodyMass, from: start, to: now)
            async let leanMass = samples(for: .leanBodyMass, from: start, to: now)
            async let bodyFat = samples(for: .bodyFatPercentage, from: start, to: now)
            async let bodyTemp = samples(for: .bodyTemperature, from: start, to: now)
            async let rhr = samples(for: .restingHeartRate, from: start, to: now)
            let sessions = try await localRepository.fetchCachedSessions(from: start, to: now)
            let latestSession = try await localRepository.fetchLatestSession()
            let profile = try await localRepository.fetchProfile()
            let baseline = try await localRepository.fetchLatestBaseline(windowDays: profile.baselineWindowDays)

            var built = try await makeMetrics(
                vo2: vo2,
                weight: weight,
                leanMass: leanMass,
                bodyFat: bodyFat,
                bodyTemp: bodyTemp,
                rhr: rhr,
                sessions: sessions,
                latestSession: latestSession,
                baseline: baseline
            )
            metrics = mergeManualEntries(manualEntries, into: built)
        } catch {
            errorMessage = error.localizedDescription
            // Still apply any saved manual entries so user-entered values remain visible.
            metrics = mergeManualEntries(manualEntries, into: Self.placeholderMetrics)
        }

        isLoading = false
    }

    /// Saves a user-provided value for a metric kind and refreshes the metrics list.
    func saveManualEntry(kind: BiologyMetricKind, value: Double) async {
        let entry = ManualBiologyEntry(kind: kind, value: value)
        try? await localRepository.saveManualBiologyEntry(entry)
        await load()
    }

    /// Deletes the stored manual entry for a metric kind and refreshes.
    func deleteManualEntry(kind: BiologyMetricKind) async {
        if let entry = try? await localRepository.fetchManualBiologyEntries().first(where: { $0.kind == kind }) {
            try? await localRepository.deleteManualBiologyEntry(id: entry.id)
        }
        await load()
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
        rhr: [BiometricSample],
        sessions: [SleepSession],
        latestSession: SleepSession?,
        baseline: SleepBaseline?
    ) -> [BiologyMetric] {
        let biometrics = latestSession?.biometrics
        let sortedSessions = sessions.sorted { $0.startDate < $1.startDate }
        let hrvHistory  = Array(sortedSessions.suffix(12).compactMap { $0.biometrics?.hrvAverage })
        let o2History   = Array(sortedSessions.suffix(12).compactMap { $0.biometrics?.oxygenSaturationAverage }.map(percentValue))
        let respHistory = Array(sortedSessions.suffix(12).compactMap { $0.biometrics?.respiratoryRateAverage })

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
                trend: trendFromValues(hrvHistory),
                history: hrvHistory
            ),
            BiologyMetric(
                kind: .restingHeartRateBaseline,
                title: "RHR Baselines",
                value: latestValue(rhr),
                unit: "bpm",
                rating: rhrRating(latestValue(rhr)),
                trend: trend(for: rhr),
                history: history(rhr)
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
                trend: trendFromValues(o2History),
                history: o2History
            ),
            BiologyMetric(
                kind: .respiratoryRate,
                title: "Resp Rate",
                value: biometrics?.respiratoryRateAverage ?? baseline?.respiratoryRateAverage,
                unit: "br/min",
                rating: "Normal",
                trend: trendFromValues(respHistory),
                history: respHistory
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

    /// For every metric whose value is nil, substitute the most-recent manual entry (if one exists).
    /// HealthKit values always take precedence — manual entries only fill gaps.
    func mergeManualEntries(_ entries: [ManualBiologyEntry], into metrics: [BiologyMetric]) -> [BiologyMetric] {
        let byKind = Dictionary(entries.map { ($0.kind, $0) }, uniquingKeysWith: { first, _ in first })
        return metrics.map { metric in
            guard metric.value == nil, let manual = byKind[metric.kind] else { return metric }
            return BiologyMetric(
                kind: metric.kind,
                title: metric.title,
                value: manual.value,
                unit: metric.unit,
                rating: metric.rating,
                trend: "Manual",
                history: metric.history,
                isManualEntry: true
            )
        }
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

    func trendFromValues(_ values: [Double]) -> String {
        guard let first = values.first, let last = values.last, values.count > 1 else { return "No trend" }
        if last > first * 1.02 { return "Increasing" }
        if last < first * 0.98 { return "Decreasing" }
        return "Stable"
    }

    func trend(for samples: [BiometricSample]) -> String {
        let values = history(samples)
        guard let first = values.first, let last = values.last, values.count > 1 else { return "No trend" }
        if last > first * 1.02 { return "Increasing" }
        if last < first * 0.98 { return "Decreasing" }
        return "Stable"
    }

    func vo2Rating(_ value: Double?) -> String {
        guard let value else { return "No data" }
        switch value {
        case ..<35: return "Low"
        case ..<45: return "Fair"
        case ..<55: return "Good"
        default: return "Excellent"
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
