import Foundation

nonisolated struct BiomarkerSummaryService: Sendable {
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

    func summaries(now: Date = Date()) async throws -> [BiomarkerKind: [BiomarkerTimeline: BiomarkerSummary]] {
        let longest = BiomarkerTimeline.sixtyDays
        let endDate = calendar.startOfDay(for: now)
        let startDate = startDate(for: longest, endingAt: endDate)
        let paddedStart = calendar.date(byAdding: .day, value: -2, to: startDate) ?? startDate
        let paddedEnd = calendar.date(byAdding: .day, value: 1, to: endDate) ?? now

        async let sessions = localRepository.fetchCachedSessions(from: paddedStart, to: paddedEnd)
        async let rhrSamples = healthRepository.fetchBiometrics(for: .restingHeartRate, from: startDate, to: paddedEnd)

        let fetchedSessions = try await sessions
        let validSessions = fetchedSessions
            .filter { BaselineEngine.isValidNight($0, calendar: calendar) }
            .sorted { $0.sleepDateKey < $1.sleepDateKey }
        let rhr = try await rhrSamples

        var result: [BiomarkerKind: [BiomarkerTimeline: BiomarkerSummary]] = [:]
        for kind in BiomarkerKind.allCases {
            var byTimeline: [BiomarkerTimeline: BiomarkerSummary] = [:]
            for timeline in BiomarkerTimeline.allCases {
                byTimeline[timeline] = summary(
                    kind: kind,
                    timeline: timeline,
                    sessions: validSessions,
                    restingHeartRateSamples: rhr,
                    endingAt: endDate
                )
            }
            result[kind] = byTimeline
        }
        return result
    }
}

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
        lines.append("Overnight low HR used by Sleep tab RHR: \(Self.format(cachedBiometrics?.heartRateMinimum, unit: "bpm"))")
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
        // Sleep-tab RHR is intentionally based on the overnight minimum heart rate, not HealthKit restingHeartRate.
        lines.append("The Sleep tab RHR value currently comes from overnight heart-rate minimum, not HealthKit restingHeartRate.")
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

private extension BiomarkerSummaryService {
    nonisolated func summary(
        kind: BiomarkerKind,
        timeline: BiomarkerTimeline,
        sessions: [SleepSession],
        restingHeartRateSamples: [BiometricSample],
        endingAt endDate: Date
    ) -> BiomarkerSummary {
        let startDate = startDate(for: timeline, endingAt: endDate)
        let points = points(
            kind: kind,
            timeline: timeline,
            startDate: startDate,
            endDate: endDate,
            sessions: sessions,
            restingHeartRateSamples: restingHeartRateSamples
        )
        let values = points.map(\.value)

        return BiomarkerSummary(
            kind: kind,
            timeline: timeline,
            currentValue: points.last?.value,
            average: average(values),
            bestValue: bestValue(for: kind, values: values),
            minValue: values.min(),
            maxValue: values.max(),
            validSampleCount: values.count,
            expectedDayCount: timeline.rawValue,
            points: points,
            education: education(for: kind),
            calculationNote: calculationNote(for: kind, timeline: timeline)
        )
    }

    nonisolated func points(
        kind: BiomarkerKind,
        timeline: BiomarkerTimeline,
        startDate: Date,
        endDate: Date,
        sessions: [SleepSession],
        restingHeartRateSamples: [BiometricSample]
    ) -> [BiomarkerDailyPoint] {
        switch kind {
        case .restingHeartRate:
            return restingHeartRatePoints(
                samples: restingHeartRateSamples,
                startDate: startDate,
                endDate: endDate,
                timeline: timeline
            )
        case .hrv, .spo2, .respiratoryRate:
            return sessionPoints(
                kind: kind,
                sessions: sessions,
                startDate: startDate,
                endDate: endDate
            )
        }
    }

    nonisolated func sessionPoints(
        kind: BiomarkerKind,
        sessions: [SleepSession],
        startDate: Date,
        endDate: Date
    ) -> [BiomarkerDailyPoint] {
        sessions.compactMap { session in
            guard let date = SleepDateKey.date(from: session.sleepDateKey, calendar: calendar) else { return nil }
            guard date >= startDate && date <= endDate else { return nil }
            guard let value = value(for: kind, from: session) else { return nil }
            return BiomarkerDailyPoint(
                kind: kind,
                dateKey: session.sleepDateKey,
                date: date,
                value: value,
                unit: kind.unit,
                status: status(for: kind, value: value),
                source: "Sleep biometrics",
                isSelectedEligible: true
            )
        }
        .sorted { $0.date < $1.date }
    }

    nonisolated func restingHeartRatePoints(
        samples: [BiometricSample],
        startDate: Date,
        endDate: Date,
        timeline: BiomarkerTimeline
    ) -> [BiomarkerDailyPoint] {
        let grouped = Dictionary(grouping: samples) { sample in
            SleepDateKey.calendarDateKey(for: sample.endDate, calendar: calendar)
        }

        return grouped.compactMap { dateKey, daySamples in
            guard let date = SleepDateKey.date(from: dateKey, calendar: calendar) else { return nil }
            guard date >= startDate && date <= endDate else { return nil }
            guard let value = average(daySamples.map(\.value)) else { return nil }
            return BiomarkerDailyPoint(
                kind: .restingHeartRate,
                dateKey: dateKey,
                date: date,
                value: value,
                unit: BiomarkerKind.restingHeartRate.unit,
                status: status(for: .restingHeartRate, value: value),
                source: "Apple Health RHR",
                isSelectedEligible: true
            )
        }
        .sorted { $0.date < $1.date }
    }

    nonisolated func value(for kind: BiomarkerKind, from session: SleepSession) -> Double? {
        switch kind {
        case .hrv:
            session.biometrics?.hrvAverage
        case .spo2:
            session.biometrics?.oxygenSaturationAverage.map(percentValue)
        case .respiratoryRate:
            session.biometrics?.respiratoryRateAverage
        case .restingHeartRate:
            nil
        }
    }

    nonisolated func startDate(for timeline: BiomarkerTimeline, endingAt endDate: Date) -> Date {
        calendar.date(byAdding: .day, value: -(timeline.rawValue - 1), to: endDate) ?? endDate
    }

    nonisolated func average(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    nonisolated func bestValue(for kind: BiomarkerKind, values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        switch kind {
        case .hrv, .spo2:
            return values.max()
        case .restingHeartRate:
            return values.min()
        case .respiratoryRate:
            return values.min { abs($0 - 15) < abs($1 - 15) }
        }
    }

    nonisolated func percentValue(_ value: Double) -> Double {
        value <= 1 ? value * 100 : value
    }

    nonisolated func status(for kind: BiomarkerKind, value: Double) -> String {
        switch kind {
        case .restingHeartRate:
            if value <= 58 { return "Optimal" }
            if value <= 68 { return "Normal" }
            if value <= 80 { return "Fair" }
            return "Needs Attention"
        case .hrv:
            if value >= 60 { return "Optimal" }
            if value >= 40 { return "Normal" }
            if value >= 20 { return "Fair" }
            return "Needs Attention"
        case .spo2:
            if value >= 98 { return "Optimal" }
            if value >= 95 { return "Normal" }
            if value >= 93 { return "Fair" }
            return "Needs Attention"
        case .respiratoryRate:
            if value >= 14 && value <= 16 { return "Optimal" }
            if value >= 12 && value <= 18 { return "Normal" }
            if value >= 10 && value <= 20 { return "Fair" }
            return "Needs Attention"
        }
    }

    nonisolated func education(for kind: BiomarkerKind) -> String {
        switch kind {
        case .hrv:
            return "HRV reflects how well your body adapts and recovers. Higher values often align with stronger recovery readiness and lower strain."
        case .restingHeartRate:
            return "Resting heart rate reflects baseline cardiovascular load. Higher values can show strain, poor recovery, illness, or stress."
        case .spo2:
            return "SpO2 reflects overnight oxygen saturation. Stable oxygen levels support clearer sleep-breathing and recovery interpretation."
        case .respiratoryRate:
            return "Breathing rate reflects overnight respiratory rhythm. Shifts can add context for stress, illness, training load, or recovery."
        }
    }

    nonisolated func calculationNote(for kind: BiomarkerKind, timeline: BiomarkerTimeline) -> String {
        switch kind {
        case .restingHeartRate:
            return "Average, best, and range use Apple Health resting heart rate samples from the last \(timeline.rawValue) days."
        case .hrv:
            return "Average, best, and range use valid sleep nights with overnight HRV values from the last \(timeline.rawValue) days."
        case .spo2:
            return "Average, best, and range use valid sleep nights with overnight SpO2 values from the last \(timeline.rawValue) days."
        case .respiratoryRate:
            return "Average, best, and range use valid sleep nights with breathing-rate values from the last \(timeline.rawValue) days."
        }
    }
}

private extension BiometricType {
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
