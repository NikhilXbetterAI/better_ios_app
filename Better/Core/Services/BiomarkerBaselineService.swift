import Foundation
import OSLog

/// Computes and caches the dashboard biomarker baseline (RHR / HRV / SpO₂ / Breath).
///
/// Cached as a single encrypted blob via `LocalDataRepository.saveSyncAnchor`
/// keyed at `Self.cacheKey`. TTL is 7 days — a forced sync past 7 days, or a
/// new session arriving via `SyncCoordinator`'s post-sync hook, triggers a
/// recompute. Rationale: this is a slow-moving "your usual" baseline; we don't
/// want to recompute on every dashboard render.
///
/// Window selection mirrors `BaselineEngine.selectDashboardBaseline(...)` —
/// 30-day primary with 60-day fallback when fewer than `minimumNights`
/// biometrics are present. Scoped to the Sleep dashboard only (invariant #3).
@MainActor
final class BiomarkerBaselineService {
    static let cacheKey = "better.metadata.biomarkerBaseline.v1"
    static let primaryWindowDays = 30
    static let fallbackWindowDays = 60
    static let minimumNights = 5
    static let ttlDays = 7

    private let repository: LocalDataRepositoryProtocol
    private let calendar: Calendar
    private let logger = Logger(subsystem: "Better", category: "BiomarkerBaseline")

    init(repository: LocalDataRepositoryProtocol, calendar: Calendar = .current) {
        self.repository = repository
        self.calendar = calendar
    }

    /// Returns the cached baseline if fresh, otherwise recomputes and caches it.
    func currentBaseline(now: Date = Date()) async -> BiomarkerBaseline? {
        if let cached = await loadCached(), !cached.isStale(now: now, ttlDays: Self.ttlDays) {
            return cached
        }
        return await recompute(now: now)
    }

    /// Returns the most recent cached value without triggering a recompute.
    /// Use for non-critical reads (e.g. rendering before async work resolves).
    func cachedBaseline() async -> BiomarkerBaseline? {
        await loadCached()
    }

    /// Forces a recompute regardless of TTL. Returns the freshly computed
    /// baseline (or `nil` if there isn't enough data).
    @discardableResult
    func recompute(now: Date = Date()) async -> BiomarkerBaseline? {
        do {
            let endDate = now
            let primaryStart = calendar.date(byAdding: .day, value: -Self.primaryWindowDays, to: endDate) ?? endDate
            let primarySessions = try await repository.fetchCachedSessions(from: primaryStart, to: endDate)
            let primaryNightCount = primarySessions.filter { $0.biometrics != nil }.count

            let chosenSessions: [SleepSession]
            let chosenWindow: Int

            if primaryNightCount >= Self.minimumNights {
                chosenSessions = primarySessions
                chosenWindow = Self.primaryWindowDays
            } else {
                let fallbackStart = calendar.date(byAdding: .day, value: -Self.fallbackWindowDays, to: endDate) ?? endDate
                chosenSessions = try await repository.fetchCachedSessions(from: fallbackStart, to: endDate)
                chosenWindow = Self.fallbackWindowDays
            }

            let baseline = Self.computeBaseline(
                from: chosenSessions,
                windowDays: chosenWindow,
                computedAt: now
            )

            // Don't cache an empty baseline — keep whatever we had so the UI can
            // still render the previous "usual" until enough data lands.
            if baseline.sampleCounts.values.contains(where: { $0 > 0 }) {
                await persist(baseline)
                return baseline
            }
            return await loadCached()
        } catch {
            logger.error("BiomarkerBaseline recompute failed: \(error.localizedDescription)")
            return await loadCached()
        }
    }

    // MARK: - Computation

    static func computeBaseline(
        from sessions: [SleepSession],
        windowDays: Int,
        computedAt: Date
    ) -> BiomarkerBaseline {
        var samples: [BiomarkerKey: [Double]] = [:]
        for key in BiomarkerKey.allCases { samples[key] = [] }

        for session in sessions {
            guard let bio = session.biometrics else { continue }
            if let v = bio.heartRateMinimum { samples[.rhr]?.append(v) }
            if let v = bio.hrvAverage { samples[.hrv]?.append(v) }
            if let v = bio.oxygenSaturationAverage { samples[.spo2]?.append(v * 100) }
            if let v = bio.respiratoryRateAverage { samples[.breath]?.append(v) }
        }

        var counts: [BiomarkerKey: Int] = [:]
        var means: [BiomarkerKey: Double] = [:]
        var stdDevs: [BiomarkerKey: Double] = [:]

        for (key, values) in samples {
            counts[key] = values.count
            guard !values.isEmpty else { continue }
            let mean = values.reduce(0, +) / Double(values.count)
            means[key] = mean
            stdDevs[key] = standardDeviation(values, mean: mean)
        }

        return BiomarkerBaseline(
            computedAt: computedAt,
            windowDays: windowDays,
            sampleCounts: counts,
            means: means,
            stdDevs: stdDevs
        )
    }

    private static func standardDeviation(_ values: [Double], mean: Double) -> Double {
        guard values.count > 1 else { return 0 }
        let sumSquares = values.reduce(0.0) { acc, v in acc + (v - mean) * (v - mean) }
        // Sample standard deviation (n-1) — we're estimating the population
        // standard deviation from a small window of nights.
        return (sumSquares / Double(values.count - 1)).squareRoot()
    }

    // MARK: - Persistence

    private func loadCached() async -> BiomarkerBaseline? {
        do {
            guard let data = try await repository.fetchSyncAnchor(for: Self.cacheKey) else {
                return nil
            }
            return try PersistenceJSON.decode(BiomarkerBaseline.self, from: data)
        } catch {
            logger.error("BiomarkerBaseline load failed: \(error.localizedDescription)")
            return nil
        }
    }

    private func persist(_ baseline: BiomarkerBaseline) async {
        do {
            let data = try PersistenceJSON.encode(baseline)
            try await repository.saveSyncAnchor(data, for: Self.cacheKey)
        } catch {
            logger.error("BiomarkerBaseline persist failed: \(error.localizedDescription)")
        }
    }
}
