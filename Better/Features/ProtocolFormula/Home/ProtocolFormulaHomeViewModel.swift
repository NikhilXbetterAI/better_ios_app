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
    enum Segment: String, Hashable {
        case lastNight
        case tonight
    }

    var segment: Segment {
        didSet { userDefaults.set(segment.rawValue, forKey: ProtocolFormulaHomeSegmentStorage.key) }
    }

    var isLoading: Bool = false
    var versions: [ProtocolFormulaVersion] = []
    var activeVersion: ProtocolFormulaVersion?
    var selectedTonightVersionID: UUID?
    var tonightAddins: [ProtocolFormulaComponent] = []
    var draftAddinText: String = ""
    var lastNightSession: SleepSession?
    var lastNightLog: ProtocolNightLog?
    var lastNightVersion: ProtocolFormulaVersion?
    var lastNightSnapshot: ProtocolNightMetricSnapshot?
    var impact: ProtocolImpactSummary?
    var baseline: ProtocolBaselineSnapshot?
    var bestVersion: ProtocolFormulaBestVersion?
    var showFirstSwitchHint: Bool = false
    var recentSnapshots: [ProtocolNightMetricSnapshot] = []
    var ribbonSegments: [PvPhaseRibbon.Segment] = []

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
        case baselineInsufficient
        case baselineMissingMetricData(missing: [String])
        case baselineMissing
        case noFormula
    }

    var baselineStatus: BaselineStatus {
        guard activeVersion != nil else { return .noFormula }
        guard let baseline else { return .baselineMissing }
        if baseline.isInsufficient { return .baselineInsufficient }
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
        var deepPctVsBaseline: Double?   // fractional improvement: (delta / baseline) * 100
        var remPctVsBaseline: Double?
        var awakePctVsBaseline: Double?
        var totalSleepPctVsBaseline: Double?
    }

    var lastNightVsBaselineDeltas: LastNightDeltas? {
        guard let snap = lastNightSnapshot,
              let bl = baseline, !bl.isInsufficient else { return nil }

        func pct(_ delta: Double?, baseline: Double?) -> Double? {
            guard let d = delta, let b = baseline, b != 0 else { return nil }
            return (d / b) * 100
        }

        let deepDelta    = snap.deepMinutes.flatMap  { d in bl.meanDeepMin.map      { d - $0 } }
        let remDelta     = snap.remMinutes.flatMap   { d in bl.meanRemMin.map       { d - $0 } }
        let awakeDelta   = snap.awakeMinutes.flatMap { d in bl.meanAwakeMin.map     { d - $0 } }
        let sleepDelta   = snap.totalSleepMinutes.flatMap { d in bl.meanTotalSleepMin.map { d - $0 } }

        return LastNightDeltas(
            deep: deepDelta,
            rem: remDelta,
            awake: awakeDelta,
            totalSleep: sleepDelta,
            deepPctVsBaseline:      pct(deepDelta,  baseline: bl.meanDeepMin),
            remPctVsBaseline:       pct(remDelta,   baseline: bl.meanRemMin),
            awakePctVsBaseline:     pct(awakeDelta, baseline: bl.meanAwakeMin),
            totalSleepPctVsBaseline: pct(sleepDelta, baseline: bl.meanTotalSleepMin)
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
        nowProvider: @escaping () -> Date = Date.init
    ) {
        self.localRepository = localRepository
        self.analysisService = analysisService ?? ProtocolFormulaAnalysisService(repository: localRepository)
        self.catalogService = ProtocolFormulaCatalogService(repository: localRepository, calendar: calendar)
        self.baselineService = ProtocolBaselineService(repository: localRepository, calendar: calendar)
        self.userDefaults = userDefaults
        self.calendar = calendar
        self.nowProvider = nowProvider
        let raw = userDefaults.string(forKey: ProtocolFormulaHomeSegmentStorage.key) ?? Segment.lastNight.rawValue
        self.segment = Segment(rawValue: raw) ?? .lastNight
    }

    func onAppear() async {
        await refresh()
        applyFirstSwitchHintIfNeeded()
    }

    func refresh() async {
        isLoading = true
        defer { isLoading = false }
        do {
            versions = try await catalogService.ensureCatalogVersions()
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
            if baseline == nil, let earliestKey = versions.compactMap({ Self.sleepDateKey(for: $0.shippedOn) }).min() {
                _ = try? await baselineService.freezeBaseline(beforeSleepDateKey: earliestKey)
                baseline = try await localRepository.fetchBaselineSnapshot()
                let refetchedExists = baseline != nil
                let refetchedMissing = baseline?.extendedMetricReadinessSummary ?? "none"
                Self.logger.debug("home refresh baseline refetched exists=\(refetchedExists, privacy: .public) missing=\(refetchedMissing, privacy: .public)")
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
            let rollups = try await analysisService.allRollups()
            bestVersion = ProtocolFormulaCatalogService.bestVersion(
                versions: versions,
                rollups: rollups,
                baseline: baseline
            )
            
            // Fetch 14-night trend snapshots
            let allRecent = try await analysisService.nightlySnapshots(in: Date.distantPast...now)
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
            Self.logger.error("home refresh failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Tonight CTA actions

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

    // MARK: - Helpers

    /// First entry into 19:00–04:00 with no tonight log → one-time preselect Tonight + hint.
    private func applyFirstSwitchHintIfNeeded() {
        let alreadyShown = userDefaults.bool(forKey: ProtocolFormulaHomeSegmentStorage.firstSwitchHintShownKey)
        guard !alreadyShown else { return }
        let hour = calendar.component(.hour, from: nowProvider())
        let inEveningWindow = hour >= 19 || hour < 4
        guard inEveningWindow else { return }
        let key = Self.tonightSleepDateKey(calendar: calendar, now: nowProvider())
        let hasLog = lastNightLog?.sleepDateKey == key
        guard !hasLog else { return }
        segment = .tonight
        showFirstSwitchHint = true
        userDefaults.set(true, forKey: ProtocolFormulaHomeSegmentStorage.firstSwitchHintShownKey)
    }

    func dismissHint() { showFirstSwitchHint = false }

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
}
