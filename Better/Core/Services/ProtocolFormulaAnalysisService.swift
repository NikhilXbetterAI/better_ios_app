import Foundation
import OSLog

/// Composes per-night `ProtocolNightMetricSnapshot`s and version-level rollups for
/// Protocol Formula Tracking V1.
///
/// **Reuse contract:** this service does NOT recompute restorative-sleep math. It
/// reads `SleepSession.restorativeSleepDuration` and `SleepSession.continuitySummary`
/// directly. The only derivation here is `restorativePctOfInBed = restorative / inBed`.
nonisolated struct ProtocolFormulaAnalysisService: Sendable {
    private let repository: LocalDataRepositoryProtocol
    private static let logger = Logger(subsystem: "Better", category: "ProtocolFormula")

    init(repository: LocalDataRepositoryProtocol) {
        self.repository = repository
    }

    /// Pure function — no I/O. Reads `session` fields and combines with the optional log.
    /// Stage-derived metrics (restorative, longest block, deep, REM) require
    /// `dataQuality ∈ {.detailedStages, .mixedSources}`. Total sleep, latency, and
    /// score are available whenever `dataQuality != .noData`. Awake is computed from
    /// stage data so it tracks the detailed gate.
    static func snapshot(for session: SleepSession, log: ProtocolNightLog?) -> ProtocolNightMetricSnapshot {
        let hasDetailed = session.dataQuality == .detailedStages || session.dataQuality == .mixedSources
        let hasAnySleepData = session.dataQuality != .noData
        let restMin = hasDetailed ? session.restorativeSleepDuration / 60.0 : nil
        let restPctOfInBed: Double? = (hasDetailed && session.totalInBedTime > 0)
            ? min(session.restorativeSleepDuration / session.totalInBedTime * 100.0, 100.0)
            : nil
        let longest = hasDetailed ? session.continuitySummary.longestBlockDuration / 60.0 : nil
        let category = hasDetailed ? session.continuitySummary.continuityCategory : nil
        let deep = hasDetailed ? session.deepDuration / 60.0 : nil
        let rem = hasDetailed ? session.remDuration / 60.0 : nil
        let awake = hasDetailed ? session.awakeDuration / 60.0 : nil
        let totalSleep = hasAnySleepData ? session.totalSleepTime / 60.0 : nil
        let latency = hasAnySleepData ? session.sleepLatency / 60.0 : nil
        let score: Double? = hasAnySleepData ? session.qualityScore.overall : nil
        return ProtocolNightMetricSnapshot(
            sleepDateKey: session.sleepDateKey,
            versionID: log?.versionID,
            restorativeSleepMinutes: restMin,
            restorativePctOfInBed: restPctOfInBed,
            longestRestorativeBlockMinutes: longest,
            continuityCategory: category,
            dataQuality: session.dataQuality,
            deepMinutes: deep,
            remMinutes: rem,
            awakeMinutes: awake,
            totalSleepMinutes: totalSleep,
            latencyMinutes: latency,
            sleepScore: score
        )
    }

    /// Per-version aggregate across the date range. Only nights with `status == .taken`
    /// contribute to the rollup — `.skipped` and `.unknown` (no row) are excluded so the
    /// impact math reflects what the formula actually did on nights the user took it.
    /// For taken-vs-skipped adherence stats, see `adherenceRollups(in:)`.
    func rollups(in dateRange: ClosedRange<Date>) async throws -> [ProtocolVersionRollup] {
        let startKey = Self.dateKey(for: dateRange.lowerBound)
        let endKey = Self.dateKey(for: dateRange.upperBound)
        let sessions = try await repository.fetchCachedSessions(
            from: dateRange.lowerBound,
            to: dateRange.upperBound
        )
        let logs = try await repository.fetchNightLogs(from: startKey, to: endKey)
        let logsByDate = Dictionary(uniqueKeysWithValues: logs.map { ($0.sleepDateKey, $0) })

        var snapshotsByVersion: [UUID: [ProtocolNightMetricSnapshot]] = [:]
        for session in sessions {
            guard let log = logsByDate[session.sleepDateKey], log.status == .taken else { continue }
            let snapshot = Self.snapshot(for: session, log: log)
            snapshotsByVersion[log.versionID, default: []].append(snapshot)
        }

        let rollups = snapshotsByVersion.map { versionID, snapshots in
            let rest = snapshots.compactMap { $0.restorativeSleepMinutes }
            let pct = snapshots.compactMap { $0.restorativePctOfInBed }
            let longest = snapshots.compactMap { $0.longestRestorativeBlockMinutes }
            let deep = snapshots.compactMap { $0.deepMinutes }
            let rem = snapshots.compactMap { $0.remMinutes }
            let awake = snapshots.compactMap { $0.awakeMinutes }
            let total = snapshots.compactMap { $0.totalSleepMinutes }
            let latency = snapshots.compactMap { $0.latencyMinutes }
            let score = snapshots.compactMap { $0.sleepScore }
            var distribution: [SleepContinuityCategory: Double] = [:]
            let categories = snapshots.compactMap { $0.continuityCategory }
            if !categories.isEmpty {
                var counts: [SleepContinuityCategory: Int] = [:]
                for c in categories { counts[c, default: 0] += 1 }
                let categoryTotal = Double(categories.count)
                distribution = counts.mapValues { Double($0) / categoryTotal }
            }
            return ProtocolVersionRollup(
                versionID: versionID,
                nightCount: snapshots.count,
                meanRestorativeMin: ProtocolBaselineService.mean(rest),
                stdRestorativeMin: ProtocolBaselineService.standardDeviation(rest),
                meanRestorativePctOfInBed: ProtocolBaselineService.mean(pct),
                stdRestorativePctOfInBed: ProtocolBaselineService.standardDeviation(pct),
                meanLongestRestorativeBlockMin: ProtocolBaselineService.mean(longest),
                stdLongestRestorativeBlockMin: ProtocolBaselineService.standardDeviation(longest),
                continuityDistribution: distribution,
                meanDeepMin: ProtocolBaselineService.mean(deep),
                stdDeepMin: ProtocolBaselineService.standardDeviation(deep),
                meanRemMin: ProtocolBaselineService.mean(rem),
                stdRemMin: ProtocolBaselineService.standardDeviation(rem),
                meanAwakeMin: ProtocolBaselineService.mean(awake),
                stdAwakeMin: ProtocolBaselineService.standardDeviation(awake),
                meanTotalSleepMin: ProtocolBaselineService.mean(total),
                stdTotalSleepMin: ProtocolBaselineService.standardDeviation(total),
                meanLatencyMin: ProtocolBaselineService.mean(latency),
                stdLatencyMin: ProtocolBaselineService.standardDeviation(latency),
                meanSleepScore: ProtocolBaselineService.mean(score),
                stdSleepScore: ProtocolBaselineService.standardDeviation(score)
            )
        }
        Self.logger.debug("protocol rollups range=\(startKey, privacy: .public)..\(endKey, privacy: .public) sessions=\(sessions.count, privacy: .public) logs=\(logs.count, privacy: .public) versions=\(rollups.count, privacy: .public)")
        return rollups
    }

    /// Single per-version delta vs. the frozen baseline. Sets `isLowData` if < 3 nights.
    /// Caller renders `ProtocolImpactSummary.causalityCaveat` next to every delta.
    func impactSummary(versionID: UUID, in dateRange: ClosedRange<Date>) async throws -> ProtocolImpactSummary {
        let baseline = try await repository.fetchBaselineSnapshot()
        let rollups = try await rollups(in: dateRange)
        let rollup = rollups.first(where: { $0.versionID == versionID })
        let nightCount = rollup?.nightCount ?? 0

        func delta(_ version: Double?, _ baselineValue: Double?) -> Double? {
            guard let version, let baselineValue else { return nil }
            return version - baselineValue
        }

        let summary = ProtocolImpactSummary(
            versionID: versionID,
            nightCount: nightCount,
            isLowData: nightCount < 3,
            deltaRestorativeMin: delta(rollup?.meanRestorativeMin, baseline?.meanRestorativeMin),
            deltaRestorativePctOfInBed: delta(rollup?.meanRestorativePctOfInBed, baseline?.meanRestorativePctOfInBed),
            deltaLongestRestorativeBlockMin: delta(rollup?.meanLongestRestorativeBlockMin, baseline?.meanLongestRestorativeBlockMin),
            versionMeanRestorativeMin: rollup?.meanRestorativeMin,
            versionMeanRestorativePctOfInBed: rollup?.meanRestorativePctOfInBed,
            versionMeanLongestRestorativeBlockMin: rollup?.meanLongestRestorativeBlockMin,
            baselineMeanRestorativeMin: baseline?.meanRestorativeMin,
            baselineMeanRestorativePctOfInBed: baseline?.meanRestorativePctOfInBed,
            baselineMeanLongestRestorativeBlockMin: baseline?.meanLongestRestorativeBlockMin,
            deltaDeepMin: delta(rollup?.meanDeepMin, baseline?.meanDeepMin),
            deltaRemMin: delta(rollup?.meanRemMin, baseline?.meanRemMin),
            deltaAwakeMin: delta(rollup?.meanAwakeMin, baseline?.meanAwakeMin),
            deltaTotalSleepMin: delta(rollup?.meanTotalSleepMin, baseline?.meanTotalSleepMin),
            deltaLatencyMin: delta(rollup?.meanLatencyMin, baseline?.meanLatencyMin),
            deltaSleepScore: delta(rollup?.meanSleepScore, baseline?.meanSleepScore),
            versionMeanDeepMin: rollup?.meanDeepMin,
            versionMeanRemMin: rollup?.meanRemMin,
            versionMeanAwakeMin: rollup?.meanAwakeMin,
            versionMeanTotalSleepMin: rollup?.meanTotalSleepMin,
            versionMeanLatencyMin: rollup?.meanLatencyMin,
            versionMeanSleepScore: rollup?.meanSleepScore,
            baselineMeanDeepMin: baseline?.meanDeepMin,
            baselineMeanRemMin: baseline?.meanRemMin,
            baselineMeanAwakeMin: baseline?.meanAwakeMin,
            baselineMeanTotalSleepMin: baseline?.meanTotalSleepMin,
            baselineMeanLatencyMin: baseline?.meanLatencyMin,
            baselineMeanSleepScore: baseline?.meanSleepScore
        )
        Self.logger.debug("protocol impact version=\(versionID.uuidString, privacy: .public) nights=\(nightCount, privacy: .public) baseline=\(baseline != nil, privacy: .public) missing=\(baseline?.extendedMetricReadinessSummary ?? "none", privacy: .public)")
        return summary
    }

    /// Returns individual per-night snapshots sorted by date (oldest first) for charting.
    /// Includes only nights with `status == .taken` — `.skipped` and `.unknown` are excluded
    /// so charts plot the formula's measured impact, not protocol drop-outs.
    func nightlySnapshots(in dateRange: ClosedRange<Date>) async throws -> [ProtocolNightMetricSnapshot] {
        let startKey = Self.dateKey(for: dateRange.lowerBound)
        let endKey = Self.dateKey(for: dateRange.upperBound)
        let sessions = try await repository.fetchCachedSessions(
            from: dateRange.lowerBound, to: dateRange.upperBound)
        let logs = try await repository.fetchNightLogs(from: startKey, to: endKey)
        let takenLogsByDate = Dictionary(
            uniqueKeysWithValues: logs.filter { $0.status == .taken }.map { ($0.sleepDateKey, $0) }
        )
        let snapshots = sessions
            .filter { takenLogsByDate[$0.sleepDateKey] != nil }
            .sorted { $0.startDate < $1.startDate }
            .map { Self.snapshot(for: $0, log: takenLogsByDate[$0.sleepDateKey]) }
        Self.logger.debug("protocol nightly snapshots range=\(startKey, privacy: .public)..\(endKey, privacy: .public) sessions=\(sessions.count, privacy: .public) takenLogs=\(takenLogsByDate.count, privacy: .public) snapshots=\(snapshots.count, privacy: .public)")
        return snapshots
    }

    /// Per-version adherence counts across the date range — independent of impact math.
    /// Returned counts: `taken` (nights logged as taken), `skipped` (logged as skipped),
    /// `total` (taken + skipped). `.unknown` (no row) is excluded, matching invariant #2.
    struct AdherenceRollup: Hashable, Sendable {
        var versionID: UUID
        var taken: Int
        var skipped: Int
        var total: Int { taken + skipped }
    }

    func adherenceRollups(in dateRange: ClosedRange<Date>) async throws -> [AdherenceRollup] {
        let startKey = Self.dateKey(for: dateRange.lowerBound)
        let endKey = Self.dateKey(for: dateRange.upperBound)
        let logs = try await repository.fetchNightLogs(from: startKey, to: endKey)
        var bucket: [UUID: (taken: Int, skipped: Int)] = [:]
        for log in logs {
            switch log.status {
            case .taken: bucket[log.versionID, default: (0, 0)].taken += 1
            case .skipped: bucket[log.versionID, default: (0, 0)].skipped += 1
            case .unknown: continue
            }
        }
        return bucket.map { AdherenceRollup(versionID: $0.key, taken: $0.value.taken, skipped: $0.value.skipped) }
    }

    /// All rollups across all logged time. Convenience for Timeline / AllMetrics.
    func allRollups() async throws -> [ProtocolVersionRollup] {
        let distant = Date.distantPast...Date()
        return try await rollups(in: distant)
    }

    private static func dateKey(for date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d",
                      components.year ?? 0,
                      components.month ?? 0,
                      components.day ?? 0)
    }
}
