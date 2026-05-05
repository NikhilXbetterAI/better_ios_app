import Foundation
@preconcurrency import HealthKit

nonisolated struct SleepDataProcessor: Sendable {
    static let minimumSleepDuration: TimeInterval = 300
    static let sessionGapThreshold: TimeInterval = 1_800

    private let calendar: Calendar
    private let sleepGoalHours: Double

    init(
        calendar: Calendar = .current,
        sleepGoalHours: Double = 8
    ) {
        self.calendar = calendar
        self.sleepGoalHours = sleepGoalHours
    }

    func process(samples: [HKCategorySample]) -> [SleepSession] {
        let rawIntervals = samples
            .compactMap(Self.rawInterval(from:))
            .filter { $0.duration > 0 }

        return process(rawIntervals: rawIntervals)
    }

    func computeBaseline(
        from sessions: [SleepSession],
        windowDays: Int,
        generatedAt: Date = Date()
    ) -> SleepBaseline {
        let validSessions = sessions
            .filter { $0.totalSleepTime >= Self.minimumSleepDuration }
            .filter { $0.dataQuality != .inBedOnly && $0.dataQuality != .noData }

        let detailedSessions = validSessions.filter { $0.dataQuality != .unspecifiedSleepOnly }

        return SleepBaseline(
            windowDays: windowDays,
            generatedAt: generatedAt,
            validNights: validSessions.count,
            totalSleepAverage: Self.average(validSessions.map(\.totalSleepTime)),
            totalSleepStandardDeviation: Self.standardDeviation(validSessions.map(\.totalSleepTime)),
            remAverage: Self.average(detailedSessions.map(\.remDuration)),
            remStandardDeviation: Self.standardDeviation(detailedSessions.map(\.remDuration)),
            deepAverage: Self.average(detailedSessions.map(\.deepDuration)),
            deepStandardDeviation: Self.standardDeviation(detailedSessions.map(\.deepDuration)),
            efficiencyAverage: Self.average(validSessions.map(\.efficiency)),
            efficiencyStandardDeviation: Self.standardDeviation(validSessions.map(\.efficiency)),
            wasoAverage: Self.average(validSessions.map(\.waso)),
            wasoStandardDeviation: Self.standardDeviation(validSessions.map(\.waso)),
            latencyAverage: Self.average(validSessions.map(\.sleepLatency)),
            latencyStandardDeviation: Self.standardDeviation(validSessions.map(\.sleepLatency)),
            hrvAverage: Self.average(validSessions.compactMap(\.biometrics?.hrvAverage)),
            hrvStandardDeviation: Self.standardDeviation(validSessions.compactMap(\.biometrics?.hrvAverage)),
            respiratoryRateAverage: Self.average(validSessions.compactMap(\.biometrics?.respiratoryRateAverage)),
            respiratoryRateStandardDeviation: Self.standardDeviation(validSessions.compactMap(\.biometrics?.respiratoryRateAverage)),
            oxygenSaturationAverage: Self.average(validSessions.compactMap(\.biometrics?.oxygenSaturationAverage)),
            oxygenSaturationStandardDeviation: Self.standardDeviation(validSessions.compactMap(\.biometrics?.oxygenSaturationAverage)),
            bedtimeMinuteAverage: Self.circularMeanMinute(validSessions.map { minuteOfDay(for: $0.inBedStartDate ?? $0.startDate) }),
            bedtimeMinuteStandardDeviation: Self.circularStandardDeviationMinute(validSessions.map { minuteOfDay(for: $0.inBedStartDate ?? $0.startDate) }),
            wakeMinuteAverage: Self.circularMeanMinute(validSessions.map { minuteOfDay(for: $0.inBedEndDate ?? $0.endDate) }),
            wakeMinuteStandardDeviation: Self.circularStandardDeviationMinute(validSessions.map { minuteOfDay(for: $0.inBedEndDate ?? $0.endDate) })
        )
    }

    func summarizeBiometrics(
        _ samples: [BiometricSample],
        sessionID: UUID,
        sleepDateKey: String
    ) -> NightlyBiometricSummary {
        let heartRates = samples.values(for: .heartRate)
        let hrv = samples.values(for: .heartRateVariabilitySDNN)
        let oxygen = samples.values(for: .oxygenSaturation)
        let respiratory = samples.values(for: .respiratoryRate)

        return NightlyBiometricSummary(
            sleepSessionID: sessionID,
            sleepDateKey: sleepDateKey,
            samples: samples,
            heartRateAverage: Self.averageOrNil(heartRates),
            heartRateMinimum: heartRates.min(),
            heartRateMaximum: heartRates.max(),
            hrvAverage: Self.averageOrNil(hrv),
            hrvMedian: Self.median(hrv),
            oxygenSaturationAverage: Self.averageOrNil(oxygen),
            oxygenSaturationMinimum: oxygen.min(),
            respiratoryRateAverage: Self.averageOrNil(respiratory)
        )
    }
}

nonisolated private extension SleepDataProcessor {
    func process(rawIntervals: [RawSleepInterval]) -> [SleepSession] {
        let cleanedIntervals = Self.cleanedIntervals(from: rawIntervals)
        let groupedIntervals = Self.groupSessions(from: cleanedIntervals)

        return groupedIntervals.compactMap { group in
            makeSession(from: group, rawIntervals: rawIntervals)
        }
    }

    func makeSession(
        from intervals: [CleanedSleepInterval],
        rawIntervals: [RawSleepInterval]
    ) -> SleepSession? {
        guard
            let startDate = intervals.map(\.startDate).min(),
            let endDate = intervals.map(\.endDate).max()
        else {
            return nil
        }

        let totalSleepTime = intervals
            .filter { $0.stage.isSleep }
            .reduce(0) { $0 + $1.duration }

        guard totalSleepTime >= Self.minimumSleepDuration else {
            return nil
        }

        let inBedRawIntervals = rawIntervals
            .filter { $0.stage == .inBed }
            .compactMap { $0.clipped(toStart: startDate, end: endDate) }
        let inBedRange = Self.unionRange(for: inBedRawIntervals)
        let totalInBedTime = inBedRawIntervals.isEmpty
            ? endDate.timeIntervalSince(startDate)
            : Self.unionDuration(of: inBedRawIntervals)

        let firstAsleepStart = intervals
            .filter { $0.stage.isSleep }
            .map(\.startDate)
            .min()
        let finalSleepEnd = intervals
            .filter { $0.stage.isSleep }
            .map(\.endDate)
            .max()

        let sleepLatency: TimeInterval
        if let inBedStart = inBedRange?.startDate, let firstAsleepStart {
            sleepLatency = max(0, firstAsleepStart.timeIntervalSince(inBedStart))
        } else {
            sleepLatency = 0
        }

        let waso = intervals.reduce(0) { partial, interval in
            guard
                interval.stage == .awake,
                let firstAsleepStart,
                let finalSleepEnd,
                interval.startDate >= firstAsleepStart,
                interval.endDate <= finalSleepEnd
            else {
                return partial
            }

            return partial + interval.duration
        }

        let sources = Self.uniqueSources(from: intervals.map(\.source))
        let dataQuality = Self.dataQuality(for: intervals)
        let stages = intervals.map {
            SleepStage(
                type: $0.stage,
                startDate: $0.startDate,
                endDate: $0.endDate,
                source: $0.source
            )
        }
        let coreDuration = intervals.duration(for: .core)
        let deepDuration = intervals.duration(for: .deep)
        let remDuration = intervals.duration(for: .rem)
        let unspecifiedDuration = intervals.duration(for: .unspecified)
        let awakeDuration = intervals.duration(for: .awake)
        let efficiency = totalInBedTime > 0 ? min(1, totalSleepTime / totalInBedTime) : 0

        return SleepSession(
            sleepDateKey: sleepDateKey(for: startDate),
            startDate: startDate,
            endDate: endDate,
            inBedStartDate: inBedRange?.startDate,
            inBedEndDate: inBedRange?.endDate,
            stages: stages,
            sources: sources,
            dataQuality: dataQuality,
            totalInBedTime: totalInBedTime,
            totalSleepTime: totalSleepTime,
            awakeDuration: awakeDuration,
            coreDuration: coreDuration,
            deepDuration: deepDuration,
            remDuration: remDuration,
            unspecifiedSleepDuration: unspecifiedDuration,
            sleepLatency: sleepLatency,
            waso: waso,
            efficiency: efficiency,
            qualityScore: qualityScore(
                totalSleepTime: totalSleepTime,
                efficiency: efficiency,
                remDuration: remDuration,
                deepDuration: deepDuration,
                dataQuality: dataQuality
            )
        )
    }

    func qualityScore(
        totalSleepTime: TimeInterval,
        efficiency: Double,
        remDuration: TimeInterval,
        deepDuration: TimeInterval,
        dataQuality: SleepDataQuality
    ) -> SleepQualityScore {
        let goalSeconds = sleepGoalHours * 3_600
        let durationScore = Self.clampedScore(totalSleepTime / goalSeconds * 100)
        let efficiencyScore = Self.clampedScore(efficiency / 0.92 * 100)

        guard dataQuality != .unspecifiedSleepOnly else {
            let overall = durationScore * 0.60 + efficiencyScore * 0.40
            return SleepQualityScore(
                overall: Self.clampedScore(overall),
                durationScore: durationScore,
                efficiencyScore: efficiencyScore,
                remScore: 0,
                deepScore: 0,
                isPartial: true
            )
        }

        let remRatio = totalSleepTime > 0 ? remDuration / totalSleepTime : 0
        let deepRatio = totalSleepTime > 0 ? deepDuration / totalSleepTime : 0
        let remScore = Self.rangedScore(ratio: remRatio, targetLow: 0.20, targetHigh: 0.25)
        let deepScore = Self.rangedScore(ratio: deepRatio, targetLow: 0.13, targetHigh: 0.23)
        let overall = durationScore * 0.30
            + efficiencyScore * 0.20
            + remScore * 0.25
            + deepScore * 0.25

        return SleepQualityScore(
            overall: Self.clampedScore(overall),
            durationScore: durationScore,
            efficiencyScore: efficiencyScore,
            remScore: remScore,
            deepScore: deepScore,
            isPartial: false
        )
    }

    func sleepDateKey(for startDate: Date) -> String {
        SleepDateKey.sleepDateKey(forSessionStart: startDate, calendar: calendar)
    }

    func minuteOfDay(for date: Date) -> Double {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return Double((components.hour ?? 0) * 60 + (components.minute ?? 0))
    }
}

nonisolated private extension SleepDataProcessor {
    static func rawInterval(from sample: HKCategorySample) -> RawSleepInterval? {
        guard let stage = SleepStageType(healthKitRawValue: sample.value) else {
            return nil
        }

        return RawSleepInterval(
            stage: stage,
            startDate: sample.startDate,
            endDate: sample.endDate,
            source: sleepSource(from: sample),
            sourceQuality: sourceQuality(for: sample, stage: stage)
        )
    }

    static func cleanedIntervals(from rawIntervals: [RawSleepInterval]) -> [CleanedSleepInterval] {
        let boundaries = Array(Set(rawIntervals.flatMap { [$0.startDate, $0.endDate] })).sorted()
        guard boundaries.count > 1 else { return [] }

        var cleaned: [CleanedSleepInterval] = []

        for index in boundaries.indices.dropLast() {
            let start = boundaries[index]
            let end = boundaries[index + 1]
            guard end > start else { continue }

            let overlapping = rawIntervals.filter { $0.startDate < end && $0.endDate > start }
            guard let selected = overlapping.max(by: { $0.resolutionPriority < $1.resolutionPriority }) else {
                continue
            }

            let segment = CleanedSleepInterval(
                stage: selected.stage,
                startDate: start,
                endDate: end,
                source: selected.source
            )

            if let previous = cleaned.last,
               previous.stage == segment.stage,
               previous.source == segment.source,
               previous.endDate == segment.startDate {
                cleaned[cleaned.count - 1] = CleanedSleepInterval(
                    stage: previous.stage,
                    startDate: previous.startDate,
                    endDate: segment.endDate,
                    source: previous.source
                )
            } else {
                cleaned.append(segment)
            }
        }

        return cleaned
    }

    static func groupSessions(from intervals: [CleanedSleepInterval]) -> [[CleanedSleepInterval]] {
        let sortedIntervals = intervals.sorted { $0.startDate < $1.startDate }
        var groups: [[CleanedSleepInterval]] = []

        for interval in sortedIntervals {
            guard var currentGroup = groups.popLast(), let previous = currentGroup.last else {
                groups.append([interval])
                continue
            }

            if interval.startDate.timeIntervalSince(previous.endDate) <= sessionGapThreshold {
                currentGroup.append(interval)
                groups.append(currentGroup)
            } else {
                groups.append(currentGroup)
                groups.append([interval])
            }
        }

        return groups
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

    static func sourceQuality(for sample: HKSample, stage: SleepStageType) -> Int {
        let productType = sample.sourceRevision.productType?.lowercased() ?? ""
        let sourceName = sample.sourceRevision.source.name.lowercased()
        let bundleIdentifier = sample.sourceRevision.source.bundleIdentifier.lowercased()
        let isManual = sample.metadata?[HKMetadataKeyWasUserEntered] as? Bool ?? false
        let isAppleWatch = productType.contains("watch")
            || sourceName.contains("watch")
            || bundleIdentifier.contains("watch")

        if isManual {
            return 0
        }

        if isAppleWatch && stage.isDetailedSleepStage {
            return 4
        }

        if stage.isDetailedSleepStage {
            return 3
        }

        if isAppleWatch && stage == .unspecified {
            return 2
        }

        return 1
    }

    static func dataQuality(for intervals: [CleanedSleepInterval]) -> SleepDataQuality {
        let hasDetailed = intervals.contains { $0.stage.isDetailedSleepStage }
        let hasUnspecified = intervals.contains { $0.stage == .unspecified }
        let hasSleep = intervals.contains { $0.stage.isSleep }
        let sleepSources = uniqueSources(from: intervals.filter { $0.stage.isSleep }.map(\.source))
        let hasMultipleSleepSources = sleepSources.count > 1

        if hasDetailed {
            return .detailedStages
        }

        if hasUnspecified {
            return .unspecifiedSleepOnly
        }

        if hasMultipleSleepSources {
            return .mixedSources
        }

        if !hasSleep {
            return .inBedOnly
        }

        return .noData
    }

    static func uniqueSources(from sources: [SleepSource?]) -> [SleepSource] {
        var result: [SleepSource] = []
        var seenKeys = Set<String>()

        for source in sources.compactMap({ $0 }) {
            let key = source.sourceKey
            guard !seenKeys.contains(key) else { continue }
            seenKeys.insert(key)
            result.append(source)
        }

        return result
    }

    static func unionRange(for intervals: [RawSleepInterval]) -> (startDate: Date, endDate: Date)? {
        guard let start = intervals.map(\.startDate).min(), let end = intervals.map(\.endDate).max() else {
            return nil
        }

        return (start, end)
    }

    static func unionDuration(of intervals: [RawSleepInterval]) -> TimeInterval {
        let sorted = intervals.sorted { $0.startDate < $1.startDate }
        var merged: [(start: Date, end: Date)] = []

        for interval in sorted {
            guard var last = merged.popLast() else {
                merged.append((interval.startDate, interval.endDate))
                continue
            }

            if interval.startDate <= last.end {
                last.end = max(last.end, interval.endDate)
                merged.append(last)
            } else {
                merged.append(last)
                merged.append((interval.startDate, interval.endDate))
            }
        }

        return merged.reduce(0) { $0 + $1.end.timeIntervalSince($1.start) }
    }

    static func average(_ values: [Double]) -> Double {
        averageOrNil(values) ?? 0
    }

    static func averageOrNil(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    static func standardDeviation(_ values: [Double]) -> Double {
        guard values.count > 1 else { return 0 }
        let average = average(values)
        let variance = values.reduce(0) { $0 + pow($1 - average, 2) } / Double(values.count)
        return sqrt(variance)
    }

    static func circularMeanMinute(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }

        let radians = values.map { $0 / 1_440 * 2 * Double.pi }
        let sinAverage = radians.map(sin).reduce(0, +) / Double(radians.count)
        let cosAverage = radians.map(cos).reduce(0, +) / Double(radians.count)
        let angle = atan2(sinAverage, cosAverage)
        let normalizedAngle = angle >= 0 ? angle : angle + 2 * Double.pi
        let minute = normalizedAngle / (2 * Double.pi) * 1_440
        return minute >= 1_439.9 ? 0 : minute
    }

    static func circularStandardDeviationMinute(_ values: [Double]) -> Double {
        guard values.count > 1 else { return 0 }

        let mean = circularMeanMinute(values)
        let deltas = values.map { circularMinuteDistance($0, mean) }
        let variance = deltas.reduce(0) { $0 + pow($1, 2) } / Double(deltas.count)
        return sqrt(variance)
    }

    static func circularMinuteDistance(_ lhs: Double, _ rhs: Double) -> Double {
        let rawDifference = abs(lhs - rhs).truncatingRemainder(dividingBy: 1_440)
        return min(rawDifference, 1_440 - rawDifference)
    }

    static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        } else {
            return sorted[middle]
        }
    }

    static func clampedScore(_ score: Double) -> Double {
        min(100, max(0, score))
    }

    static func rangedScore(ratio: Double, targetLow: Double, targetHigh: Double) -> Double {
        if ratio >= targetLow && ratio <= targetHigh {
            return 100
        }

        if ratio < targetLow {
            return clampedScore(ratio / targetLow * 100)
        }

        let upperTolerance = targetHigh * 1.75
        return clampedScore((1 - ((ratio - targetHigh) / upperTolerance)) * 100)
    }
}

nonisolated private struct RawSleepInterval: Sendable, Hashable {
    var stage: SleepStageType
    var startDate: Date
    var endDate: Date
    var source: SleepSource
    var sourceQuality: Int

    var duration: TimeInterval {
        endDate.timeIntervalSince(startDate)
    }

    var resolutionPriority: Int {
        stage.resolutionPriority * 10 + sourceQuality
    }

    func clipped(toStart clipStart: Date, end clipEnd: Date) -> RawSleepInterval? {
        let clippedStart = max(startDate, clipStart)
        let clippedEnd = min(endDate, clipEnd)
        guard clippedEnd > clippedStart else { return nil }

        return RawSleepInterval(
            stage: stage,
            startDate: clippedStart,
            endDate: clippedEnd,
            source: source,
            sourceQuality: sourceQuality
        )
    }
}

nonisolated private struct CleanedSleepInterval: Sendable, Hashable {
    var stage: SleepStageType
    var startDate: Date
    var endDate: Date
    var source: SleepSource?

    var duration: TimeInterval {
        endDate.timeIntervalSince(startDate)
    }
}

nonisolated private extension SleepStageType {
    init?(healthKitRawValue: Int) {
        switch healthKitRawValue {
        case HKCategoryValueSleepAnalysis.inBed.rawValue:
            self = .inBed
        case HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue:
            self = .unspecified
        case HKCategoryValueSleepAnalysis.awake.rawValue:
            self = .awake
        case HKCategoryValueSleepAnalysis.asleepCore.rawValue:
            self = .core
        case HKCategoryValueSleepAnalysis.asleepDeep.rawValue:
            self = .deep
        case HKCategoryValueSleepAnalysis.asleepREM.rawValue:
            self = .rem
        default:
            return nil
        }
    }

    var isDetailedSleepStage: Bool {
        switch self {
        case .core, .deep, .rem:
            true
        case .inBed, .unspecified, .awake:
            false
        }
    }

    var resolutionPriority: Int {
        switch self {
        case .deep, .rem, .core:
            4
        case .awake:
            3
        case .unspecified:
            2
        case .inBed:
            1
        }
    }
}

nonisolated private extension Array where Element == CleanedSleepInterval {
    func duration(for stage: SleepStageType) -> TimeInterval {
        filter { $0.stage == stage }.reduce(0) { $0 + $1.duration }
    }
}

nonisolated private extension Array where Element == BiometricSample {
    func values(for type: BiometricType) -> [Double] {
        filter { $0.type == type }.map(\.value)
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
