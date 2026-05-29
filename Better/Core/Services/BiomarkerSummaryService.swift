import Foundation

nonisolated struct BiomarkerDiagnosticService: Sendable {
    private let localRepository: LocalDataRepositoryProtocol
    private let healthRepository: HealthKitRepositoryProtocol
    private let calendar: Calendar

    init(
        localRepository: LocalDataRepositoryProtocol,
        healthRepository: HealthKitRepositoryProtocol,
        calendar: Calendar = .current
    ) {
        self.localRepository = localRepository
        self.healthRepository = healthRepository
        self.calendar = calendar
    }

    func latestNightReport(now: Date = Date()) async throws -> BiomarkerDiagnosticReport {
        guard let session = try await localRepository.fetchLatestSession() else {
            throw BiomarkerDiagnosticError.noCachedSleepSession
        }

        return try await report(for: session, generatedAt: now)
    }

    func report(for session: SleepSession, generatedAt: Date = Date()) async throws -> BiomarkerDiagnosticReport {
        // Biomarker samples do not always land inside the exact sleep interval.
        // We inspect a wider window so support can tell "no sample written" apart from "sample written outside sleep."
        let expandedStart = calendar.date(byAdding: .hour, value: -6, to: session.startDate)
            ?? session.startDate.addingTimeInterval(-6 * 3_600)
        let expandedEnd = calendar.date(byAdding: .hour, value: 12, to: session.endDate)
            ?? session.endDate.addingTimeInterval(12 * 3_600)

        let metricReports = try await withThrowingTaskGroup(of: BiomarkerDiagnosticMetricReport.self) { group in
            for type in BiometricType.diagnosticTypes {
                group.addTask {
                    let sleepWindowSamples = try await healthRepository.fetchBiometrics(
                        for: type,
                        from: session.startDate,
                        to: session.endDate
                    )
                    let expandedWindowSamples = try await healthRepository.fetchBiometrics(
                        for: type,
                        from: expandedStart,
                        to: expandedEnd
                    )
                    let outsideSleepSamples = expandedWindowSamples.filter {
                        !($0.endDate > session.startDate && $0.startDate < session.endDate)
                    }

                    return BiomarkerDiagnosticMetricReport(
                        type: type,
                        sleepWindow: BiomarkerDiagnosticSampleStats(samples: sleepWindowSamples),
                        expandedWindow: BiomarkerDiagnosticSampleStats(samples: expandedWindowSamples),
                        outsideSleepWindowCount: outsideSleepSamples.count
                    )
                }
            }

            var reports: [BiomarkerDiagnosticMetricReport] = []
            for try await report in group {
                reports.append(report)
            }
            return reports.sorted { $0.type.diagnosticSortOrder < $1.type.diagnosticSortOrder }
        }

        return BiomarkerDiagnosticReport(
            generatedAt: generatedAt,
            sleepDateKey: session.sleepDateKey,
            sessionStartDate: session.startDate,
            sessionEndDate: session.endDate,
            expandedStartDate: expandedStart,
            expandedEndDate: expandedEnd,
            sleepSources: session.sources,
            cachedBiometrics: session.biometrics,
            metricReports: metricReports
        )
    }
}

nonisolated enum BiomarkerDiagnosticError: LocalizedError {
    case noCachedSleepSession

    var errorDescription: String? {
        switch self {
        case .noCachedSleepSession:
            "No cached sleep session is available to diagnose. Sync Apple Health first."
        }
    }
}

nonisolated struct BiomarkerDiagnosticReport: Identifiable, Sendable, Hashable {
    var id = UUID()
    var generatedAt: Date
    var sleepDateKey: String
    var sessionStartDate: Date
    var sessionEndDate: Date
    var expandedStartDate: Date
    var expandedEndDate: Date
    var sleepSources: [SleepSource]
    var cachedBiometrics: NightlyBiometricSummary?
    var metricReports: [BiomarkerDiagnosticMetricReport]

    var plainText: String {
        var lines: [String] = []
        lines.append("Better Biomarker Diagnostic")
        lines.append("Generated: \(Self.formatDateTime(generatedAt))")
        lines.append("Sleep date: \(sleepDateKey)")
        lines.append("Sleep window: \(Self.formatDateTime(sessionStartDate)) -> \(Self.formatDateTime(sessionEndDate))")
        lines.append("Expanded window: \(Self.formatDateTime(expandedStartDate)) -> \(Self.formatDateTime(expandedEndDate))")
        lines.append("Sleep sources: \(sourceList(sleepSources))")
        lines.append("")
        lines.append("Cached session biometrics")
        lines.append("Resting heart rate used by Sleep tab RHR: \(Self.format(cachedBiometrics?.heartRateMinimum, unit: "bpm"))")
        lines.append("HRV average: \(Self.format(cachedBiometrics?.hrvAverage, unit: "ms"))")
        lines.append("SpO2 average: \(Self.format(cachedBiometrics?.oxygenSaturationAverage.map { $0 * 100 }, unit: "%"))")
        lines.append("Respiratory average: \(Self.format(cachedBiometrics?.respiratoryRateAverage, unit: "br/min"))")
        lines.append("")
        lines.append("HealthKit sample availability")
        for report in metricReports {
            lines.append("- \(report.type.displayName)")
            lines.append("  Sleep window: \(report.sleepWindow.summaryLine(unit: report.type.displayUnitSymbol))")
            lines.append("  Expanded window: \(report.expandedWindow.summaryLine(unit: report.type.displayUnitSymbol))")
            lines.append("  Outside sleep window in expanded range: \(report.outsideSleepWindowCount)")
            lines.append("  Sources: \(sourceList(report.expandedWindow.sources))")
        }
        lines.append("")
        lines.append("Notes")
        lines.append("Apple Health does not expose per-type read authorization status to apps. Empty counts can mean the source did not write that type, the user denied Better read access, or samples arrived outside the sleep window.")
        lines.append("RHR and HRV are fetched over an extended post-session window (up to 6h past wakeup) to capture device-computed daily values written after sleep ends.")
        return lines.joined(separator: "\n")
    }

    private static func formatDateTime(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }

    private static func format(_ value: Double?, unit: String) -> String {
        guard let value else { return "missing" }
        if unit == "%" || unit == "br/min" {
            return "\(String(format: "%.1f", value)) \(unit)"
        }
        return "\(String(format: "%.0f", value)) \(unit)"
    }

    private func sourceList(_ sources: [SleepSource]) -> String {
        guard !sources.isEmpty else { return "none" }
        return sources
            .map { source in
                let identifier = source.bundleIdentifier ?? source.productType ?? "unknown id"
                return "\(source.name) (\(identifier))"
            }
            .joined(separator: ", ")
    }
}

nonisolated struct BiomarkerDiagnosticMetricReport: Sendable, Hashable {
    var type: BiometricType
    var sleepWindow: BiomarkerDiagnosticSampleStats
    var expandedWindow: BiomarkerDiagnosticSampleStats
    var outsideSleepWindowCount: Int
}

nonisolated struct BiomarkerDiagnosticSampleStats: Sendable, Hashable {
    var count: Int
    var firstSampleStart: Date?
    var lastSampleEnd: Date?
    var minimum: Double?
    var average: Double?
    var maximum: Double?
    var sources: [SleepSource]

    init(samples: [BiometricSample]) {
        let values = samples.map(\.value)
        self.count = samples.count
        self.firstSampleStart = samples.map(\.startDate).min()
        self.lastSampleEnd = samples.map(\.endDate).max()
        self.minimum = values.min()
        self.average = values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
        self.maximum = values.max()
        self.sources = Self.uniqueSources(from: samples.compactMap(\.source))
    }

    func summaryLine(unit: String) -> String {
        guard count > 0 else { return "0 samples" }
        let range = "\(Self.format(minimum, unit: unit)) avg \(Self.format(average, unit: unit)) max \(Self.format(maximum, unit: unit))"
        let dates = [
            firstSampleStart.map(Self.formatDateTime),
            lastSampleEnd.map(Self.formatDateTime)
        ].compactMap { $0 }.joined(separator: " -> ")
        return "\(count) samples, \(range), \(dates)"
    }

    private static func formatDateTime(_ date: Date) -> String {
        date.formatted(date: .numeric, time: .shortened)
    }

    private static func format(_ value: Double?, unit: String) -> String {
        guard let value else { return "missing \(unit)" }
        if unit == "%" {
            let percent = value <= 1 ? value * 100 : value
            return "\(String(format: "%.1f", percent))\(unit)"
        }
        if unit == "br/min" {
            return "\(String(format: "%.1f", value)) \(unit)"
        }
        return "\(String(format: "%.0f", value)) \(unit)"
    }

    private static func uniqueSources(from sources: [SleepSource]) -> [SleepSource] {
        var seen = Set<String>()
        var unique: [SleepSource] = []
        for source in sources {
            let key = [
                source.name,
                source.bundleIdentifier ?? "",
                source.productType ?? "",
                source.isManualEntry ? "manual" : "automatic"
            ].joined(separator: "|")
            guard seen.insert(key).inserted else { continue }
            unique.append(source)
        }
        return unique.sorted { $0.name < $1.name }
    }
}

nonisolated private extension BiometricType {
    static let diagnosticTypes: [BiometricType] = [
        .heartRate,
        .heartRateVariabilitySDNN,
        .oxygenSaturation,
        .respiratoryRate,
        .restingHeartRate
    ]

    var diagnosticSortOrder: Int {
        Self.diagnosticTypes.firstIndex(of: self) ?? Int.max
    }

    var displayUnitSymbol: String {
        switch self {
        case .heartRate, .restingHeartRate:
            "bpm"
        case .respiratoryRate:
            "br/min"
        case .heartRateVariabilitySDNN:
            "ms"
        case .oxygenSaturation:
            "%"
        default:
            unitSymbol
        }
    }
}
