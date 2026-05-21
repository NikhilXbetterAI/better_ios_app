import Foundation
import OSLog

/// Freezes a `ProtocolBaselineSnapshot` for Protocol Formula Tracking V1.
///
/// The snapshot is the **frozen** mean/std of restorative-sleep metrics computed across
/// up to 30 of the most recent qualifying nights from the 90-day window before
/// `cutoff` (typically the first formula version's `shippedOn` date).
///
/// "Qualifying" = `SleepSession.dataQuality ∈ {.detailedStages, .mixedSources}`.
///
/// Once written, the snapshot is **never** recomputed on HealthKit resync. Callers
/// (e.g. `ProtocolAdherenceMigrationService`, the onboarding flow) call `freezeBaseline`
/// exactly once; subsequent calls return the existing snapshot unless `force == true`.
nonisolated struct ProtocolBaselineService: Sendable {
    private let repository: LocalDataRepositoryProtocol
    private let calendar: Calendar
    private static let logger = Logger(subsystem: "Better", category: "ProtocolFormula")

    nonisolated static let windowDays: Int = 90
    nonisolated static let maxNights: Int = 30
    nonisolated static let sufficiencyThreshold: Int = 7

    init(repository: LocalDataRepositoryProtocol, calendar: Calendar = .current) {
        self.repository = repository
        self.calendar = calendar
    }

    /// Returns the frozen baseline. Creates and persists one if none exists yet.
    /// Returns `nil` only when zero qualifying nights exist in the window — in that
    /// case the UI shows "Baseline not available yet" until enough nights accumulate.
    ///
    /// `beforeSleepDateKey` is the exclusive upper bound — the first protocol night.
    /// Sessions are filtered by `sleepDateKey < beforeSleepDateKey` (string compare on
    /// `YYYY-MM-DD` works correctly), so a session that *started* the prior evening but
    /// whose wake-date key matches the first protocol night is correctly excluded.
    @discardableResult
    func freezeBaseline(beforeSleepDateKey cutoffKey: String, force: Bool = false) async throws -> ProtocolBaselineSnapshot? {
        if !force, let existing = try await repository.fetchBaselineSnapshot() {
            Self.logger.debug("baseline freeze reused validNightCount=\(existing.validNightCount, privacy: .public) insufficient=\(existing.isInsufficient, privacy: .public) missing=\(existing.extendedMetricReadinessSummary, privacy: .public)")
            return existing
        }
        guard let cutoffDate = SleepDateKey.date(from: cutoffKey, calendar: calendar),
              let windowStart = calendar.date(byAdding: .day, value: -Self.windowDays, to: cutoffDate) else {
            return nil
        }
        let sessions = try await repository.fetchCachedSessions(from: windowStart, to: cutoffDate)
        let qualifying = sessions
            .filter { $0.dataQuality == .detailedStages || $0.dataQuality == .mixedSources }
            .filter { $0.sleepDateKey < cutoffKey }
            .sorted { $0.startDate > $1.startDate }
        let nights = Array(qualifying.prefix(Self.maxNights))

        guard !nights.isEmpty else { return nil }

        let metrics = Self.metrics(for: nights)
        let distribution = Self.continuityDistribution(for: nights)

        let snapshot = ProtocolBaselineSnapshot(
            frozenAt: Date(),
            windowStart: windowStart,
            windowEnd: cutoffDate,
            validNightCount: nights.count,
            meanRestorativeMin: Self.mean(metrics.restorativeMins),
            stdRestorativeMin: Self.standardDeviation(metrics.restorativeMins),
            meanRestorativePctOfInBed: Self.mean(metrics.restorativePcts),
            stdRestorativePctOfInBed: Self.standardDeviation(metrics.restorativePcts),
            meanLongestRestorativeBlockMin: Self.mean(metrics.longestBlockMins),
            stdLongestRestorativeBlockMin: Self.standardDeviation(metrics.longestBlockMins),
            continuityCategoryDistribution: distribution,
            isInsufficient: nights.count < Self.sufficiencyThreshold,
            meanDeepMin: Self.mean(metrics.deepMins),
            stdDeepMin: Self.standardDeviation(metrics.deepMins),
            meanRemMin: Self.mean(metrics.remMins),
            stdRemMin: Self.standardDeviation(metrics.remMins),
            meanAwakeMin: Self.mean(metrics.awakeMins),
            stdAwakeMin: Self.standardDeviation(metrics.awakeMins),
            meanTotalSleepMin: Self.mean(metrics.totalSleepMins),
            stdTotalSleepMin: Self.standardDeviation(metrics.totalSleepMins),
            meanLatencyMin: Self.mean(metrics.latencyMins),
            stdLatencyMin: Self.standardDeviation(metrics.latencyMins),
            meanSleepScore: Self.mean(metrics.sleepScores),
            stdSleepScore: Self.standardDeviation(metrics.sleepScores)
        )
        try await repository.saveBaselineSnapshot(snapshot)
        Self.logger.debug("baseline frozen validNightCount=\(snapshot.validNightCount, privacy: .public) insufficient=\(snapshot.isInsufficient, privacy: .public) missing=\(snapshot.extendedMetricReadinessSummary, privacy: .public)")
        return snapshot
    }

    /// One-shot augmentation for pre-existing baselines that were frozen before the
    /// full-stage metric scope landed. Re-fetches sessions for the original window and
    /// fills in any nil extended metric fields without touching the originals.
    /// Invariant #7 (frozen baseline) still holds in spirit: only previously-empty
    /// fields are populated, never overwritten.
    @discardableResult
    func augmentBaselineWithExtendedMetricsIfNeeded() async throws -> Bool {
        guard let existing = try await repository.fetchBaselineSnapshot() else { return false }
        let needsAugment = !existing.hasExtendedMetrics
        guard needsAugment else { return false }

        let sessions = try await repository.fetchCachedSessions(from: existing.windowStart, to: existing.windowEnd)
        let cutoffKey = SleepDateKey.calendarDateKey(for: existing.windowEnd, calendar: calendar)
        let qualifying = sessions
            .filter { $0.dataQuality == .detailedStages || $0.dataQuality == .mixedSources }
            .filter { $0.sleepDateKey < cutoffKey }
            .sorted { $0.startDate > $1.startDate }
        let nights = Array(qualifying.prefix(Self.maxNights))
        guard !nights.isEmpty else { return false }

        let metrics = Self.metrics(for: nights)
        var augmented = existing
        augmented.meanDeepMin = augmented.meanDeepMin ?? Self.mean(metrics.deepMins)
        augmented.stdDeepMin = augmented.stdDeepMin ?? Self.standardDeviation(metrics.deepMins)
        augmented.meanRemMin = augmented.meanRemMin ?? Self.mean(metrics.remMins)
        augmented.stdRemMin = augmented.stdRemMin ?? Self.standardDeviation(metrics.remMins)
        augmented.meanAwakeMin = augmented.meanAwakeMin ?? Self.mean(metrics.awakeMins)
        augmented.stdAwakeMin = augmented.stdAwakeMin ?? Self.standardDeviation(metrics.awakeMins)
        augmented.meanTotalSleepMin = augmented.meanTotalSleepMin ?? Self.mean(metrics.totalSleepMins)
        augmented.stdTotalSleepMin = augmented.stdTotalSleepMin ?? Self.standardDeviation(metrics.totalSleepMins)
        augmented.meanLatencyMin = augmented.meanLatencyMin ?? Self.mean(metrics.latencyMins)
        augmented.stdLatencyMin = augmented.stdLatencyMin ?? Self.standardDeviation(metrics.latencyMins)
        augmented.meanSleepScore = augmented.meanSleepScore ?? Self.mean(metrics.sleepScores)
        augmented.stdSleepScore = augmented.stdSleepScore ?? Self.standardDeviation(metrics.sleepScores)
        try await repository.saveBaselineSnapshot(augmented)
        Self.logger.debug("baseline augmented validNightCount=\(augmented.validNightCount, privacy: .public) missing=\(augmented.extendedMetricReadinessSummary, privacy: .public)")
        return true
    }

    private struct ExtractedMetrics {
        var restorativeMins: [Double]
        var restorativePcts: [Double]
        var longestBlockMins: [Double]
        var deepMins: [Double]
        var remMins: [Double]
        var awakeMins: [Double]
        var totalSleepMins: [Double]
        var latencyMins: [Double]
        var sleepScores: [Double]
    }

    private static func metrics(for nights: [SleepSession]) -> ExtractedMetrics {
        let restorativeMins = nights.map { $0.restorativeSleepDuration / 60.0 }
        let restorativePcts: [Double] = nights.compactMap { session in
            guard session.totalInBedTime > 0 else { return nil }
            return min(session.restorativeSleepDuration / session.totalInBedTime * 100.0, 100.0)
        }
        let longestBlockMins = nights.map { $0.continuitySummary.longestBlockDuration / 60.0 }
        let deepMins = nights.map { $0.deepDuration / 60.0 }
        let remMins = nights.map { $0.remDuration / 60.0 }
        let awakeMins = nights.map { $0.awakeDuration / 60.0 }
        let totalSleepMins = nights.map { $0.totalSleepTime / 60.0 }
        let latencyMins = nights.map { $0.sleepLatency / 60.0 }
        let sleepScores = nights.map { $0.qualityScore.overall }
        return ExtractedMetrics(
            restorativeMins: restorativeMins,
            restorativePcts: restorativePcts,
            longestBlockMins: longestBlockMins,
            deepMins: deepMins,
            remMins: remMins,
            awakeMins: awakeMins,
            totalSleepMins: totalSleepMins,
            latencyMins: latencyMins,
            sleepScores: sleepScores
        )
    }

    // MARK: - Stats helpers

    static func mean(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    /// Sample standard deviation (Bessel's correction). Returns `nil` if `values.count < 2`
    /// — std is undefined for a single observation.
    static func standardDeviation(_ values: [Double]) -> Double? {
        guard values.count >= 2, let m = mean(values) else { return nil }
        let variance = values.reduce(0.0) { acc, v in acc + (v - m) * (v - m) }
            / Double(values.count - 1)
        return variance.squareRoot()
    }

    static func continuityDistribution(for sessions: [SleepSession]) -> [SleepContinuityCategory: Double] {
        guard !sessions.isEmpty else { return [:] }
        var counts: [SleepContinuityCategory: Int] = [:]
        for session in sessions {
            let category = session.continuitySummary.continuityCategory
            counts[category, default: 0] += 1
        }
        let total = Double(sessions.count)
        return counts.mapValues { Double($0) / total }
    }
}
