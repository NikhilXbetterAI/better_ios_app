import Foundation
@preconcurrency import HealthKit
import OSLog

/// Sendable result returned from `HealthSyncEngine.perform(...)`.
nonisolated struct SyncEngineResult: Sendable {
    let syncedAt: Date
    let errorMessage: String?
}

/// Performs the CPU-intensive portion of a health sync entirely off the
/// main actor.  `SyncCoordinator` calls this and updates its published state
/// only on the returned result.
///
/// All parameters are `Sendable`.  `BiomarkerBaselineService` is `@MainActor`
/// so the recompute call hops back to main inside `perform(...)` — that one
/// call is intentional and documented.
nonisolated enum HealthSyncEngine {

    private static let logger = Logger(subsystem: "Better", category: "HealthSyncEngine")

    // MARK: - Metadata key constants (mirrors SyncCoordinator)
    static let lastDailyProcessingMetadataKey = "better.metadata.lastDailyProcessing"
    static let windowMetadataKey = "better.metadata.window"

    // MARK: - Entry point

    /// Runs HK fetch → process → biometric hydration → persist → baseline
    /// selection → alert generation, entirely off the main actor.
    ///
    /// - Parameters:
    ///   - startDate: Lower bound of the HK fetch window.
    ///   - endDate: Upper bound of the HK fetch window.
    ///   - forceDailyProcessing: When `true` always runs daily maintenance
    ///     regardless of the last-processed timestamp.
    ///   - dataRetentionDays: Sessions older than this are pruned.
    ///   - baselineWindowDaysMin: Minimum clamp for the user's baseline window.
    ///   - baselineWindowDaysMax: Maximum clamp for the user's baseline window.
    ///   - healthRepository: Read-only HK repository (invariant #1).
    ///   - localRepository: Persistence layer (`@ModelActor`, already off main).
    ///   - processor: `SleepDataProcessor` — `nonisolated struct Sendable`.
    ///   - alertService: `actor AlertGenerationService`.
    ///   - notificationPreferencesStore: `nonisolated protocol Sendable`.
    ///   - calendar: `Calendar` (value type, `Sendable`).
    ///   - biomarkerBaselineService: Optional `@MainActor` service — recompute
    ///     hops to main exactly once at the end of daily processing.
    static func perform(
        startDate: Date,
        endDate: Date,
        forceDailyProcessing: Bool,
        dataRetentionDays: Int,
        baselineWindowDaysMin: Int,
        baselineWindowDaysMax: Int,
        healthRepository: HealthKitRepositoryProtocol,
        localRepository: LocalDataRepositoryProtocol,
        processor: SleepDataProcessor,
        alertService: AlertGenerationService,
        notificationPreferencesStore: AlertNotificationPreferencesStoring,
        calendar: Calendar,
        biomarkerBaselineService: BiomarkerBaselineService?
    ) async throws -> SyncEngineResult {
        // 1. Fetch HK samples (network/HK I/O — already off main).
        let samples = try await healthRepository.fetchSleepSamples(from: startDate, to: endDate)

        // 2. CPU: process raw samples into SleepSessions (nonisolated struct).
        let sessions = processor.process(samples: samples)

        // 3. Biometric hydration — concurrent HK fetches per session.
        let hydratedSessions = try await withThrowingTaskGroup(of: SleepSession.self) { group in
            for session in sessions {
                group.addTask {
                    try await attachBiometrics(
                        to: session,
                        healthRepository: healthRepository,
                        localRepository: localRepository,
                        processor: processor
                    )
                }
            }
            var results: [SleepSession] = []
            for try await session in group {
                results.append(session)
            }
            return results.sorted { $0.startDate < $1.startDate }
        }

        // 4. Persist hydrated sessions for this window.
        try await localRepository.replaceSessions(hydratedSessions, from: startDate, to: endDate)

        // 5. Daily maintenance gate.
        guard try await shouldRunDailyProcessing(
            at: endDate,
            force: forceDailyProcessing,
            localRepository: localRepository,
            calendar: calendar
        ) else {
            return SyncEngineResult(syncedAt: endDate, errorMessage: nil)
        }

        // 6. Prune old data (invariant #8 — retention unchanged).
        try await localRepository.pruneDataOlderThan(days: dataRetentionDays)

        // 7. Per-window baseline computation (invariant #3 — windows: 7/15/30).
        let windowDays = [7, 15, 30]
        var latestSelection: BaselineSelection?

        for days in windowDays {
            let shouldRun = try await shouldRunWindowedBaseline(
                windowDays: days,
                at: endDate,
                force: forceDailyProcessing,
                localRepository: localRepository,
                calendar: calendar
            )
            guard shouldRun else { continue }

            let windowStart = calendar.date(byAdding: .day, value: -days, to: endDate)!
            let windowSessions = try await localRepository.fetchCachedSessions(from: windowStart, to: endDate)

            // CPU: BaselineEngine is nonisolated struct Sendable — safe off main.
            let selection = BaselineEngine(processor: processor, calendar: calendar)
                .selectBaseline(from: windowSessions, generatedAt: endDate)

            if let baseline = selection.allBaselines.first(where: { $0.windowDays <= days }) {
                try await localRepository.saveBaseline(baseline)
            }

            try await saveMetadataDate(endDate, for: "\(windowMetadataKey).\(days)", localRepository: localRepository)
            latestSelection = selection
        }

        // 8. Resolve active baseline for alert generation.
        let profile = try await localRepository.fetchProfile()
        let clampedWindow = min(
            max(profile.baselineWindowDays, baselineWindowDaysMin),
            baselineWindowDaysMax
        )

        let activeBaseline: SleepBaseline?
        if let selection = latestSelection {
            activeBaseline = selection.activeBaseline
        } else {
            activeBaseline = try await localRepository.fetchLatestBaseline(windowDays: clampedWindow)
        }

        // 9. Alert generation.
        let baselineStart = calendar.date(byAdding: .day, value: -clampedWindow, to: endDate)
            ?? endDate.addingTimeInterval(Double(-clampedWindow) * 86_400)
        let cachedSessions = try await localRepository.fetchCachedSessions(from: baselineStart, to: endDate)
        let appStartKey = SleepDateKey.calendarDateKey(for: profile.createdAt, calendar: calendar)
        let alertEligibleSessions = hydratedSessions.filter { $0.sleepDateKey >= appStartKey }

        if let activeBaseline {
            let alertSettings = notificationPreferencesStore.load().alertGenerationSettings
            let previousAlerts = try await localRepository.fetchAlerts(
                unreadOnly: false,
                fromSleepDateKey: appStartKey,
                limit: nil
            )
            let alerts = try await alertService.generateAlerts(
                sessions: alertEligibleSessions,
                recentSessions: cachedSessions,
                baseline: activeBaseline,
                profile: profile,
                settings: alertSettings,
                previousAlerts: previousAlerts,
                createdAt: endDate
            )
            try await localRepository.saveAlerts(alerts)
        }

        try await saveMetadataDate(endDate, for: lastDailyProcessingMetadataKey, localRepository: localRepository)

        // 10. Precompute dashboard baseline snapshots for today + yesterday so
        //     the next date-swipe reads from cache instead of recomputing.
        //     Invalidates any existing snapshots whose window overlaps the synced range first.
        await precomputeDashboardBaselineSnapshots(
            endDate: endDate,
            localRepository: localRepository,
            processor: processor,
            calendar: calendar
        )

        // 10b. Invalidate the chronotype snapshot for today's window so the next
        //      load recomputes with the freshly-synced sessions. Sessions for earlier
        //      dates do not change during a sync so their snapshots remain valid.
        await invalidateChronotypeSnapshot(endDate: endDate, localRepository: localRepository, calendar: calendar)

        // 11. Invalidate biomarker baseline cache.
        // `BiomarkerBaselineService` is `@MainActor`; this is the one deliberate
        // hop back to main after all CPU/IO work is done.
        if let biomarkerBaselineService {
            await biomarkerBaselineService.recompute(now: endDate)
        }

        return SyncEngineResult(syncedAt: endDate, errorMessage: nil)
    }

    // MARK: - Biometric hydration

    private static func attachBiometrics(
        to session: SleepSession,
        healthRepository: HealthKitRepositoryProtocol,
        localRepository: LocalDataRepositoryProtocol,
        processor: SleepDataProcessor
    ) async throws -> SleepSession {
        // Zepp, Oura, and similar devices write their computed daily RHR and HRV to
        // HealthKit after wakeup, not during the sleep window itself. Extend the fetch
        // window by 6 hours past session end for both types so those writes are captured.
        let extendedFetchEnd = min(session.endDate.addingTimeInterval(6 * 3_600), Date())

        let sampleGroups = await withTaskGroup(of: [BiometricSample].self) { group in
            for type in HealthSyncEngine.dashboardBiometricTypes {
                group.addTask {
                    (try? await healthRepository.fetchBiometrics(
                        for: type,
                        from: session.startDate,
                        to: session.endDate
                    )) ?? []
                }
            }
            // Fetch RHR and HRV over the extended post-session window — device daily
            // summaries for these types are written after wakeup, not during sleep.
            for type in [BiometricType.restingHeartRate, .heartRateVariabilitySDNN] {
                group.addTask {
                    (try? await healthRepository.fetchBiometrics(
                        for: type,
                        from: session.startDate,
                        to: extendedFetchEnd
                    )) ?? []
                }
            }
            var all: [[BiometricSample]] = []
            for await samples in group {
                all.append(samples)
            }
            return all
        }
        let samples = sampleGroups.flatMap { $0 }
        guard !samples.isEmpty else { return session }

        let summary = processor.summarizeBiometrics(
            samples,
            sessionID: session.id,
            sleepDateKey: session.sleepDateKey,
            sleepEndDate: session.endDate
        )
        try await localRepository.saveBiometricSummary(summary)

        var updatedSession = session
        updatedSession.biometrics = summary
        return updatedSession
    }

    // MARK: - Metadata helpers

    static func shouldRunDailyProcessing(
        at date: Date,
        force: Bool,
        localRepository: LocalDataRepositoryProtocol,
        calendar: Calendar
    ) async throws -> Bool {
        if force { return true }
        guard let lastProcessing = try await fetchMetadataDate(
            for: lastDailyProcessingMetadataKey,
            localRepository: localRepository
        ) else {
            return true
        }
        return !calendar.isDate(lastProcessing, inSameDayAs: date)
    }

    static func shouldRunWindowedBaseline(
        windowDays: Int,
        at date: Date,
        force: Bool,
        localRepository: LocalDataRepositoryProtocol,
        calendar: Calendar
    ) async throws -> Bool {
        if force { return true }
        let key = "\(windowMetadataKey).\(windowDays)"
        guard let lastRun = try await fetchMetadataDate(for: key, localRepository: localRepository) else {
            return true
        }
        let elapsedSeconds = date.timeIntervalSince(lastRun)
        let windowSeconds = Double(windowDays) * 86_400
        return elapsedSeconds >= windowSeconds
    }

    static func saveMetadataDate(
        _ date: Date,
        for key: String,
        localRepository: LocalDataRepositoryProtocol
    ) async throws {
        let data = try PersistenceJSON.encode(date)
        try await localRepository.saveSyncAnchor(data, for: key)
    }

    static func fetchMetadataDate(
        for key: String,
        localRepository: LocalDataRepositoryProtocol
    ) async throws -> Date? {
        guard let data = try await localRepository.fetchSyncAnchor(for: key) else { return nil }
        return try? PersistenceJSON.decode(Date.self, from: data)
    }

    // MARK: - Dashboard baseline snapshot precomputation

    /// Precomputes and persists dashboard baseline snapshots for today and
    /// yesterday so the next dashboard open / date-swipe hits the cache.
    ///
    /// Also invalidates any snapshot whose source window contains a session key
    /// that was replaced during this sync (conservative — one invalidation per
    /// affected key; Phase 5 refines to window-aware invalidation).
    // MARK: - Chronotype snapshot invalidation (Phase 4)

    /// Deletes the `StoredChronotypeSnapshot` for today's `windowEndSleepDateKey` so
    /// the chronotype is recomputed fresh after any sync. Silently ignores errors —
    /// invalidation is best-effort; a stale snapshot will simply expire via TTL.
    static func invalidateChronotypeSnapshot(
        endDate: Date,
        localRepository: LocalDataRepositoryProtocol,
        calendar: Calendar
    ) async {
        // The window end key used by all three consumers is the calendar day *after*
        // the selected sleep date (i.e. today's date key for a "today" load).
        let todayKey = SleepDateKey.calendarDateKey(for: endDate, calendar: calendar)
        // Overwrite with a placeholder that has no estimateData — this ensures the
        // next `cachedEstimate` call returns nil (generatedAt is epoch → TTL exceeded
        // immediately) rather than finding the stale snapshot.
        let staleMarker = ChronotypeSnapshotRecord(
            windowEndSleepDateKey: todayKey,
            generatedAt: Date(timeIntervalSince1970: 0),
            estimateData: nil,
            coverageNightCount: 0,
            windowDays: 90
        )
        try? await localRepository.saveChronotypeSnapshot(staleMarker)
    }

    static func precomputeDashboardBaselineSnapshots(
        endDate: Date,
        localRepository: LocalDataRepositoryProtocol,
        processor: SleepDataProcessor,
        calendar: Calendar
    ) async {
        let engine = BaselineEngine(processor: processor, calendar: calendar)
        let fetchWindow = BaselineEngine.dashboardFallbackWindow

        // Compute for today and yesterday (the two keys most likely to be viewed next).
        for dayOffset in 0 ... 1 {
            guard let targetDate = calendar.date(byAdding: .day, value: -dayOffset, to: endDate) else { continue }
            let sleepDateKey = SleepDateKey.calendarDateKey(for: targetDate, calendar: calendar)

            // Invalidate stale snapshots before writing fresh ones.
            try? await localRepository.deleteBaselineSnapshots(containingSleepDateKey: sleepDateKey)

            let windowStart = calendar.date(byAdding: .day, value: -fetchWindow, to: targetDate)
                ?? targetDate.addingTimeInterval(Double(-fetchWindow) * 86_400)

            guard let sessions = try? await localRepository.fetchCachedSessions(
                from: windowStart,
                to: targetDate
            ) else { continue }

            let selection = engine.selectDashboardBaseline(
                from: sessions.filter { $0.sleepDateKey < sleepDateKey },
                generatedAt: targetDate
            )
            guard let baseline = selection.activeBaseline else { continue }

            let windowKind = (baseline.windowDays == BaselineEngine.dashboardFallbackWindow)
                ? "dashboard60" : "dashboard30"
            let duration = baseline.totalSleepAverage
            let snapshot = DashboardBaselineSnapshotRecord(
                asOfSleepDateKey: sleepDateKey,
                windowKind: windowKind,
                generatedAt: targetDate,
                validNightCount: baseline.validNights,
                sourceWindowStart: windowStart,
                sourceWindowEnd: targetDate,
                durationMean: duration,
                durationStdDev: baseline.totalSleepStandardDeviation,
                bedtimeMeanHour: baseline.bedtimeMinuteAverage / 60.0,
                bedtimeStdDev: baseline.bedtimeMinuteStandardDeviation / 60.0,
                remRatioMean: duration > 0 ? baseline.remAverage / duration : 0,
                deepRatioMean: duration > 0 ? baseline.deepAverage / duration : 0,
                baselineData: try? PersistenceJSON.encode(baseline)
            )
            try? await localRepository.saveBaselineSnapshot(snapshot)
        }
    }
}

private extension HealthSyncEngine {
    /// Biometric types fetched and summarised for every synced session.
    /// Computed var (not `static let`) so Swift cannot infer @MainActor isolation
    /// on the stored constant — `nonisolated` static stored properties are
    /// unsupported before Swift 6; a computed property is the correct alternative.
    nonisolated static var dashboardBiometricTypes: [BiometricType] {
        // .heartRateVariabilitySDNN is fetched via the extended post-session window
        // alongside .restingHeartRate — devices write daily HRV summaries after wakeup.
        [.heartRate, .oxygenSaturation, .respiratoryRate]
    }
}
