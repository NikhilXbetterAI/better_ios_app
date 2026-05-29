import Foundation
import SwiftUI
import Combine
import OSLog

/// UserDefaults keys for the Home "Last night | Tonight" segmented switch and the
/// one-time evening-window hint. Lived alongside the (now-deleted) feature flag.
nonisolated enum ProtocolFormulaHomeSegmentStorage {
    static let key = "better.protocol.formulaHome.segment"
    static let firstSwitchHintShownKey = "better.protocol.formulaHome.firstSwitchHintShown"
}

@MainActor
@Observable
final class ProtocolFormulaHomeViewModel {
    var isLoading: Bool = false
    var versions: [ProtocolFormulaVersion] = []
    /// Pre-built lookup so SwiftUI `body` and computed deriveds can resolve a
    /// version by ID in O(1) instead of scanning `versions` linearly per call.
    var versionsByID: [UUID: ProtocolFormulaVersion] = [:]
    var activeVersion: ProtocolFormulaVersion?
    var selectedTonightVersionID: UUID?
    var tonightAddins: [ProtocolFormulaComponent] = []
    var draftAddinText: String = ""
    var lastNightSession: SleepSession?
    var lastNightLog: ProtocolNightLog?
    var lastNightVersion: ProtocolFormulaVersion?
    var lastNightSnapshot: ProtocolNightMetricSnapshot?
    var impact: ProtocolImpactSummary? {
        didSet { recomputeImpactPairs() }
    }
    /// Cached per-metric (you, baseline, delta, unit) tuples so the impact grid
    /// doesn't re-run a 9-case switch per card per SwiftUI body re-evaluation.
    var impactPairs: [ProtocolFormulaMetric: ImpactPair] = [:]
    struct ImpactPair: Equatable {
        var you: Double?
        var baseline: Double?
        var delta: Double?
        var unit: String
    }
    var baseline: ProtocolBaselineSnapshot?
    var baselineReadiness: ProtocolBaselineReadiness?
    var bestVersion: ProtocolFormulaBestVersion?
    var showQuickLogSheet: Bool = false
    var recentSnapshots: [ProtocolNightMetricSnapshot] = []
    var ribbonSegments: [PvPhaseRibbon.Segment] = []
    var errorMessage: String?

    // MARK: - Tonight save-state feedback

    enum TonightLogSaveState: Equatable {
        case idle
        case saving(status: ProtocolFormulaNightStatus)
        case saved(status: ProtocolFormulaNightStatus)
        case error(retryStatus: ProtocolFormulaNightStatus)
    }
    var tonightLogSaveState: TonightLogSaveState = .idle

    private let localRepository: LocalDataRepositoryProtocol
    private let analysisService: ProtocolFormulaAnalysisService
    private let catalogService: ProtocolFormulaCatalogService
    private let baselineService: ProtocolBaselineService
    private let userDefaults: UserDefaults
    private let calendar: Calendar
    private let nowProvider: () -> Date
    private static let logger = Logger(subsystem: "Better", category: "ProtocolFormula")

    /// Minimum taken nights of the active version before the impact summary is
    /// treated as "ready". Mirrors `ProtocolImpactSummary.isLowData`.
    static let lowDataThreshold: Int = 3

    /// Why the impact card isn't fully populated yet. Drives the Home status
    /// strip so users see something more useful than a generic spinner string.
    enum BaselineStatus: Hashable {
        case ready
        case needsMoreNights(remaining: Int)
        case baselineBuilding(valid: Int, required: Int)
        case baselineMissingMetricData(missing: [String])
        case baselineMissing
        case noFormula
    }

    var baselineStatus: BaselineStatus {
        guard activeVersion != nil else { return .noFormula }
        guard let baseline else {
            if let baselineReadiness {
                return .baselineBuilding(
                    valid: baselineReadiness.validNightCount,
                    required: baselineReadiness.requiredNightCount
                )
            }
            return .baselineMissing
        }
        if baseline.isInsufficient {
            return .baselineBuilding(
                valid: baselineReadiness?.validNightCount ?? baseline.validNightCount,
                required: baselineReadiness?.requiredNightCount ?? ProtocolBaselineService.minimumPersistedNightCount
            )
        }
        if !baseline.hasExtendedMetrics {
            return .baselineMissingMetricData(missing: baseline.missingExtendedMetricLabels)
        }
        let nights = impact?.nightCount ?? 0
        if nights >= Self.lowDataThreshold { return .ready }
        return .needsMoreNights(remaining: Self.lowDataThreshold - nights)
    }

    // MARK: - Last Night vs Baseline single-night deltas

    /// Per-metric delta between last night's actual values and the frozen baseline mean.
    /// Returns nil when the baseline is unavailable/insufficient or no snapshot exists.
    struct LastNightDeltas {
        var deep: Double?
        var rem: Double?
        var awake: Double?
        var totalSleep: Double?
    }

    var lastNightVsBaselineDeltas: LastNightDeltas? {
        guard let snap = lastNightSnapshot,
              let bl = baseline, !bl.isInsufficient else { return nil }

        let deepDelta    = snap.deepMinutes.flatMap  { d in bl.meanDeepMin.map      { d - $0 } }
        let remDelta     = snap.remMinutes.flatMap   { d in bl.meanRemMin.map       { d - $0 } }
        let awakeDelta   = snap.awakeMinutes.flatMap { d in bl.meanAwakeMin.map     { d - $0 } }
        let sleepDelta   = snap.totalSleepMinutes.flatMap { d in bl.meanTotalSleepMin.map { d - $0 } }

        return LastNightDeltas(
            deep: deepDelta,
            rem: remDelta,
            awake: awakeDelta,
            totalSleep: sleepDelta
        )
    }

    /// Visible-to-user formulas (archived ones hidden from the Tonight picker).
    var visibleVersions: [ProtocolFormulaVersion] {
        versions.filter { $0.archivedAt == nil }
    }

    init(
        localRepository: LocalDataRepositoryProtocol,
        analysisService: ProtocolFormulaAnalysisService? = nil,
        userDefaults: UserDefaults = .standard,
        calendar: Calendar = .current,
        nowProvider: @escaping () -> Date = Date.init,
        historicalRefresh: (() async -> Void)? = nil
    ) {
        self.localRepository = localRepository
        self.analysisService = analysisService ?? ProtocolFormulaAnalysisService(repository: localRepository)
        self.catalogService = ProtocolFormulaCatalogService(repository: localRepository, calendar: calendar)
        self.baselineService = ProtocolBaselineService(repository: localRepository, calendar: calendar)
        self.userDefaults = userDefaults
        self.calendar = calendar
        self.nowProvider = nowProvider
        self.historicalRefresh = historicalRefresh
    }

    private let historicalRefresh: (() async -> Void)?

    /// Cooldown gate for `historicalRefresh`. The closure performs a 90-day
    /// HealthKit pull; without a gate, every Home refresh on a device whose
    /// baseline never freezes would re-pull the full window and contribute to
    /// peak-memory jetsam crashes. In-memory only — resets on cold launch is
    /// fine because the first launch needs the historical pull anyway.
    private var lastHistoricalRefreshAt: Date?
    private static let historicalRefreshCooldown: TimeInterval = 60 * 60 * 24

    private func runHistoricalRefreshIfStale() async {
        let now = nowProvider()
        if let last = lastHistoricalRefreshAt,
           now.timeIntervalSince(last) < Self.historicalRefreshCooldown {
            return
        }
        lastHistoricalRefreshAt = now
        await historicalRefresh?()
    }

    func onAppear() async {
        await refresh()
    }

    func refresh() async {
        isLoading = true
        defer { isLoading = false }
        do {
            errorMessage = nil
            versions = try await catalogService.ensureCatalogVersions()
            versionsByID = Dictionary(uniqueKeysWithValues: versions.map { ($0.id, $0) })
            let active = versions.first(where: { $0.isActive })
            activeVersion = active
            if selectedTonightVersionID == nil || versions.contains(where: { $0.id == selectedTonightVersionID }) == false {
                selectedTonightVersionID = active?.id
            }
            try await refreshTonightLogState()
            baseline = try await localRepository.fetchBaselineSnapshot()
            let baselineExists = baseline != nil
            let baselineMissing = baseline?.extendedMetricReadinessSummary ?? "none"
            Self.logger.debug("home refresh baseline exists=\(baselineExists, privacy: .public) missing=\(baselineMissing, privacy: .public)")
            // Lazy-freeze: onboarding/migration may have run before any qualifying
            // nights existed in HealthKit. Retry on Home appear so users don't get
            // stuck on "Comparing vs baseline..." indefinitely.
            if (baseline == nil || baseline?.isInsufficient == true),
               let earliestKey = versions.compactMap({ Self.sleepDateKey(for: $0.shippedOn) }).min() {
                await runHistoricalRefreshIfStale()
                _ = try? await baselineService.freezeBaseline(beforeSleepDateKey: earliestKey)
                baseline = try await localRepository.fetchBaselineSnapshot()
                baselineReadiness = try? await baselineService.readiness(beforeSleepDateKey: earliestKey)
                let refetchedExists = baseline != nil
                let refetchedMissing = baseline?.extendedMetricReadinessSummary ?? "none"
                Self.logger.debug("home refresh baseline refetched exists=\(refetchedExists, privacy: .public) missing=\(refetchedMissing, privacy: .public)")
            } else if let earliestKey = versions.compactMap({ Self.sleepDateKey(for: $0.shippedOn) }).min() {
                baselineReadiness = try? await baselineService.readiness(beforeSleepDateKey: earliestKey)
            } else {
                baselineReadiness = nil
            }
            let now = Date()
            let weekAgo = calendar.date(byAdding: .day, value: -7, to: now) ?? now
            let recent = try await localRepository.fetchCachedSessions(from: weekAgo, to: now)
            let session = recent.sorted(by: { $0.startDate > $1.startDate }).first
            lastNightSession = session
            if let session {
                lastNightLog = try await localRepository.fetchNightLog(forSleepDateKey: session.sleepDateKey)
                lastNightVersion = lastNightLog.flatMap { log in versions.first { $0.id == log.versionID } }
                lastNightSnapshot = ProtocolFormulaAnalysisService.snapshot(for: session, log: lastNightLog)
            } else {
                lastNightLog = nil
                lastNightVersion = nil
                lastNightSnapshot = nil
            }
            if let active {
                // Use all-time so older taken nights still contribute. The 30-day
                // window dropped them, leaving the impact card stuck on "low data"
                // even after users had >3 historical nights logged.
                impact = try await analysisService.impactSummary(versionID: active.id, in: Date.distantPast...now)
                let impactNights = impact?.nightCount ?? 0
                let isLowData = impact?.isLowData ?? true
                Self.logger.debug("home impact nightCount=\(impactNights, privacy: .public) lowData=\(isLowData, privacy: .public)")
            } else {
                impact = nil
            }
            let rollups = try await analysisService.recentRollups(now: now)
            bestVersion = ProtocolFormulaCatalogService.bestVersion(
                versions: versions,
                rollups: rollups,
                baseline: baseline
            )
            
            // Fetch 14-night trend snapshots. Bound to 30 days — the UI only
            // shows the last 14, and `Date.distantPast` materializes years of
            // sessions/logs, blowing up peak memory on real devices.
            let trendWindowStart = calendar.date(byAdding: .day, value: -30, to: now) ?? now
            let allRecent = try await analysisService.nightlySnapshots(in: trendWindowStart...now)
            recentSnapshots = Array(allRecent.suffix(14))
            let recentSnapshotCount = recentSnapshots.count
            let ribbonCount = ribbonSegments.count
            Self.logger.debug("home recentSnapshots=\(recentSnapshotCount, privacy: .public) ribbonSegments=\(ribbonCount, privacy: .public)")
            
            // Build ribbon segments
            var segments: [PvPhaseRibbon.Segment] = []
            for v in versions {
                if let rollup = rollups.first(where: { $0.versionID == v.id }), rollup.nightCount > 0 {
                    segments.append(PvPhaseRibbon.Segment(
                        id: v.id,
                        label: v.resolvedLabel,
                        colorHex: v.colorHex,
                        nights: rollup.nightCount
                    ))
                }
            }
            ribbonSegments = segments
        } catch {
            // Errors during background refresh are non-fatal; the UI shows empty states.
            errorMessage = error.localizedDescription
            Self.logger.error("home refresh failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Tonight CTA actions

    /// Sets `version` as the active formula. The repository singleton rule
    /// auto-clears `isActive` on every other row, so a single save is enough.
    func setActive(_ version: ProtocolFormulaVersion) async {
        var updated = version
        updated.isActive = true
        do {
            try await localRepository.saveFormulaVersion(updated)
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func markTonightTaken() async {
        await writeTonightLog(status: .taken)
    }

    func markTonightSkipped() async {
        await writeTonightLog(status: .skipped)
    }

    func retryTonightLogSave() async {
        guard case .error(let retryStatus) = tonightLogSaveState else { return }
        await writeTonightLog(status: retryStatus)
    }

    func resetTonightLog() async {
        let key = Self.tonightSleepDateKey(calendar: calendar, now: nowProvider())
        do {
            try await localRepository.deleteNightLog(forSleepDateKey: key)
            tonightLogSaveState = .idle
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func selectTonightVersion(_ version: ProtocolFormulaVersion) {
        selectedTonightVersionID = version.id
    }

    func addTonightAddin() {
        let parts = draftAddinText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        for part in parts where tonightAddins.contains(where: { $0.name.caseInsensitiveCompare(part) == .orderedSame }) == false {
            tonightAddins.append(ProtocolFormulaComponent(name: part, role: .addin))
        }
        draftAddinText = ""
    }

    func removeTonightAddin(_ addin: ProtocolFormulaComponent) {
        tonightAddins.removeAll { $0.id == addin.id }
    }

    private func writeTonightLog(status: ProtocolFormulaNightStatus) async {
        guard let versionID = selectedTonightVersionID,
              let version = versions.first(where: { $0.id == versionID }) else { return }

        // Show saving state immediately
        tonightLogSaveState = .saving(status: status)

        let now = nowProvider()
        let key = Self.tonightSleepDateKey(calendar: calendar, now: now)
        let log = ProtocolNightLog(
            sleepDateKey: key,
            versionID: version.id,
            status: status,
            addins: status == .taken ? tonightAddins : [],
            takenAt: status == .taken ? now : nil,
            formulaSnapshotHash: ProtocolFormulaHashing.snapshotHash(for: version)
        )
        do {
            try await localRepository.saveNightLog(log)
            selectedTonightVersionID = version.id
            tonightAddins = []
            draftAddinText = ""
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                tonightLogSaveState = .saved(status: status)
            }
            await refresh()
        } catch {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                tonightLogSaveState = .error(retryStatus: status)
            }
        }
    }

    private func refreshTonightLogState() async throws {
        let key = Self.tonightSleepDateKey(calendar: calendar, now: nowProvider())
        if let tonightLog = try await localRepository.fetchNightLog(forSleepDateKey: key) {
            selectedTonightVersionID = tonightLog.versionID
            tonightLogSaveState = .saved(status: tonightLog.status)
        } else if case .saving = tonightLogSaveState {
            return
        } else if case .error = tonightLogSaveState {
            return
        } else {
            tonightLogSaveState = .idle
        }
    }

    // MARK: - Quick Log for Last Night

    func markLastNightTaken() async {
        guard let session = lastNightSession, let active = activeVersion else { return }
        let log = ProtocolNightLog(
            sleepDateKey: session.sleepDateKey,
            versionID: active.id,
            status: .taken,
            addins: [],
            takenAt: nowProvider(),
            formulaSnapshotHash: ProtocolFormulaHashing.snapshotHash(for: active)
        )
        do {
            try await localRepository.saveNightLog(log)
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func markLastNightSkipped() async {
        guard let session = lastNightSession, let active = activeVersion else { return }
        let log = ProtocolNightLog(
            sleepDateKey: session.sleepDateKey,
            versionID: active.id,
            status: .skipped,
            addins: [],
            takenAt: nil,
            formulaSnapshotHash: ProtocolFormulaHashing.snapshotHash(for: active)
        )
        do {
            try await localRepository.saveNightLog(log)
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Rebuilds `impactPairs` from the latest `impact`. Triggered automatically
    /// by `impact`'s didSet — view code reads `viewModel.impactPairs[metric]`
    /// instead of calling a per-render switch helper.
    private func recomputeImpactPairs() {
        guard let impact else {
            impactPairs = [:]
            return
        }
        impactPairs = [
            .restorativePct: ImpactPair(
                you: impact.versionMeanRestorativePctOfInBed,
                baseline: impact.baselineMeanRestorativePctOfInBed,
                delta: impact.deltaRestorativePctOfInBed,
                unit: "%"
            ),
            .deep: ImpactPair(
                you: impact.versionMeanDeepMin,
                baseline: impact.baselineMeanDeepMin,
                delta: impact.deltaDeepMin,
                unit: "m"
            ),
            .rem: ImpactPair(
                you: impact.versionMeanRemMin,
                baseline: impact.baselineMeanRemMin,
                delta: impact.deltaRemMin,
                unit: "m"
            ),
            .duration: ImpactPair(
                you: impact.versionMeanTotalSleepMin,
                baseline: impact.baselineMeanTotalSleepMin,
                delta: impact.deltaTotalSleepMin,
                unit: "m"
            ),
            .longestBlock: ImpactPair(
                you: impact.versionMeanLongestRestorativeBlockMin,
                baseline: impact.baselineMeanLongestRestorativeBlockMin,
                delta: impact.deltaLongestRestorativeBlockMin,
                unit: "m"
            ),
            .restorativeMin: ImpactPair(
                you: impact.versionMeanRestorativeMin,
                baseline: impact.baselineMeanRestorativeMin,
                delta: impact.deltaRestorativeMin,
                unit: "m"
            ),
            .awake: ImpactPair(
                you: impact.versionMeanAwakeMin,
                baseline: impact.baselineMeanAwakeMin,
                delta: impact.deltaAwakeMin,
                unit: "m"
            ),
            .latency: ImpactPair(
                you: impact.versionMeanLatencyMin,
                baseline: impact.baselineMeanLatencyMin,
                delta: impact.deltaLatencyMin,
                unit: "m"
            ),
            .score: ImpactPair(
                you: impact.versionMeanSleepScore,
                baseline: impact.baselineMeanSleepScore,
                delta: impact.deltaSleepScore,
                unit: "pts"
            )
        ]
    }

    /// Resolves "tonight" to the upcoming-night's wake-date sleep key.
    ///
    /// Rules (local time):
    ///   - `hour < 4`: late-night logging for the night-in-progress; wake date = today.
    ///   - `4 <= hour < 12`: morning/midday; "Tonight" means the upcoming night → tomorrow.
    ///     Without this rule, tapping "Mark Tonight Taken" at 9 AM would overwrite last night's log.
    ///   - `hour >= 12`: afternoon/evening; `forSessionStart` already advances to tomorrow's key.
    ///
    /// `now` is injectable so tests can pin the clock.
    static func tonightSleepDateKey(calendar: Calendar = .current, now: Date = Date()) -> String {
        let hour = calendar.component(.hour, from: now)
        if hour < 4 {
            return SleepDateKey.calendarDateKey(for: now, calendar: calendar)
        }
        if hour < 12 {
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) ?? now
            return SleepDateKey.calendarDateKey(for: tomorrow, calendar: calendar)
        }
        return SleepDateKey.sleepDateKey(forSessionStart: now, calendar: calendar)
    }

    /// `YYYY-MM-DD` key for the calendar date of `date`. Used to derive the
    /// baseline-cutoff key from a version's `shippedOn`.
    static func sleepDateKey(for date: Date, calendar: Calendar = .current) -> String {
        SleepDateKey.calendarDateKey(for: date, calendar: calendar)
    }

    /// Index offset from the latest night (0 = most recent)
    var nightOffset: Int = 0

    var isShowingLatestNight: Bool { nightOffset == 0 }

    func goToPreviousNight() async {
        nightOffset += 1
        await refreshForOffset()
    }

    func goToNextNight() async {
        guard nightOffset > 0 else { return }
        nightOffset -= 1
        if nightOffset == 0 {
            await refresh()
        } else {
            await refreshForOffset()
        }
    }

    private func refreshForOffset() async {
        let now = nowProvider()
        let windowStart = calendar.date(byAdding: .day, value: -(nightOffset + 14), to: now) ?? now
        let sessions = try? await localRepository.fetchCachedSessions(from: windowStart, to: now)
        let sorted = (sessions ?? []).sorted { $0.startDate > $1.startDate }
        guard nightOffset < sorted.count else { return }
        let session = sorted[nightOffset]
        lastNightSession = session
        lastNightLog = try? await localRepository.fetchNightLog(forSleepDateKey: session.sleepDateKey)
        lastNightVersion = lastNightLog.flatMap { log in versions.first { $0.id == log.versionID } }
        lastNightSnapshot = ProtocolFormulaAnalysisService.snapshot(for: session, log: lastNightLog)
    }
}
