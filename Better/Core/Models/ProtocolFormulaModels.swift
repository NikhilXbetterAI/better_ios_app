import Foundation
import CryptoKit

// MARK: - Formula version

nonisolated struct ProtocolFormulaComponent: Codable, Hashable, Sendable, Identifiable {
    enum Role: String, Codable, Hashable, Sendable {
        case base
        case addin
    }

    var id: UUID
    var name: String
    var dose: String
    var role: Role

    init(id: UUID = UUID(), name: String, dose: String = "", role: Role = .base) {
        self.id = id
        self.name = name
        self.dose = dose
        self.role = role
    }
}

nonisolated struct ProtocolFormulaVersion: Codable, Hashable, Sendable, Identifiable {
    var id: UUID
    /// User-editable label. Empty string means "fall back to the derived ordinal label".
    var displayLabel: String
    /// Derived presentation fallback ("V1", "V2", …) computed at fetch time from
    /// `shippedOn` ordering. Stored here only so equality checks stay total — the
    /// authoritative ordinal value is set by the repository on read.
    var ordinalLabel: String
    var formulaText: String
    var components: [ProtocolFormulaComponent]
    var shippedOn: Date
    var colorHex: String
    var isActive: Bool
    var isImportedPlaceholder: Bool
    var archivedAt: Date?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        displayLabel: String = "",
        ordinalLabel: String = "",
        formulaText: String = "",
        components: [ProtocolFormulaComponent] = [],
        shippedOn: Date = Date(),
        colorHex: String = ProtocolFormulaVersion.defaultPaletteHexes[0],
        isActive: Bool = true,
        isImportedPlaceholder: Bool = false,
        archivedAt: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.displayLabel = displayLabel
        self.ordinalLabel = ordinalLabel
        self.formulaText = formulaText
        self.components = components
        self.shippedOn = shippedOn
        self.colorHex = colorHex
        self.isActive = isActive
        self.isImportedPlaceholder = isImportedPlaceholder
        self.archivedAt = archivedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// What the UI should render: `displayLabel` if non-empty, otherwise the ordinal fallback.
    var resolvedLabel: String {
        let trimmed = displayLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? ordinalLabel : trimmed
    }

    /// Default version palette (matches the JSX `VERSIONS` map: emerald → blue → violet → cyan).
    static let defaultPaletteHexes: [String] = [
        "#34D399",
        "#60A5FA",
        "#C084FC",
        "#67E8F9"
    ]
}

// MARK: - Intervention window (V3)

/// Bounded period during which a `ProtocolFormulaVersion` was the active intervention.
/// One window per version. Closed when the next version ships (`endedAt = next.shippedOn`)
/// or when the version is archived (`endedAt = archivedAt`). Active version's window has
/// `endedAt = nil`. Used for sleep-data attribution and effect-size analysis.
nonisolated struct InterventionWindow: Codable, Hashable, Sendable, Identifiable {
    enum Phase: String, Codable, Hashable, Sendable, CaseIterable {
        /// Version is currently active (`endedAt == nil`).
        case active
        /// Closed because a newer version shipped.
        case superseded
        /// Closed because the version was archived without a successor.
        case archived
    }

    var id: UUID
    var versionID: UUID
    var startedAt: Date
    var endedAt: Date?
    var phase: Phase
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        versionID: UUID,
        startedAt: Date,
        endedAt: Date? = nil,
        phase: Phase = .active,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.versionID = versionID
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.phase = phase
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// Inclusive-start, exclusive-end check against a sleep date.
    func contains(_ date: Date) -> Bool {
        guard date >= startedAt else { return false }
        if let endedAt { return date < endedAt }
        return true
    }
}

// MARK: - Night log

nonisolated enum ProtocolFormulaNightStatus: String, Codable, Hashable, Sendable, CaseIterable {
    case taken
    case skipped
    case unknown

    /// User-facing label. `.skipped` displays as "Didn't take" per the locked design decisions.
    var displayLabel: String {
        switch self {
        case .taken: "Taken"
        case .skipped: "Didn't take"
        case .unknown: "Unknown"
        }
    }
}

nonisolated struct ProtocolNightLog: Codable, Hashable, Sendable, Identifiable {
    var id: UUID
    /// `"YYYY-MM-DD"` — one log per sleep date.
    var sleepDateKey: String
    /// Non-nil for `.taken` and `.skipped`. Only `.unknown` (no stored row) lacks a version.
    var versionID: UUID
    var status: ProtocolFormulaNightStatus
    /// Free-form add-in components recorded against this night (e.g. one-off supplement).
    var addins: [ProtocolFormulaComponent]
    var takenAt: Date?
    var note: String?
    /// SHA-256 hash of normalized formula text + sorted component list captured at log time.
    /// Sentinel `"imported-placeholder"` for legacy migrations until backfilled.
    var formulaSnapshotHash: String
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        sleepDateKey: String,
        versionID: UUID,
        status: ProtocolFormulaNightStatus,
        addins: [ProtocolFormulaComponent] = [],
        takenAt: Date? = nil,
        note: String? = nil,
        formulaSnapshotHash: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.sleepDateKey = sleepDateKey
        self.versionID = versionID
        self.status = status
        self.addins = addins
        self.takenAt = takenAt
        self.note = note
        self.formulaSnapshotHash = formulaSnapshotHash
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    static let importedPlaceholderHash = "imported-placeholder"
}

// MARK: - Edit history

nonisolated struct ProtocolLogEdit: Codable, Hashable, Sendable, Identifiable {
    var id: UUID
    var nightLogID: UUID
    var sleepDateKey: String
    /// JSON-encoded ProtocolNightLog before the edit (nil if the log didn't exist yet).
    var beforeData: Data?
    /// JSON-encoded ProtocolNightLog after the edit.
    var afterData: Data
    var editedAt: Date
    var reason: String?

    init(
        id: UUID = UUID(),
        nightLogID: UUID,
        sleepDateKey: String,
        beforeData: Data?,
        afterData: Data,
        editedAt: Date = Date(),
        reason: String? = nil
    ) {
        self.id = id
        self.nightLogID = nightLogID
        self.sleepDateKey = sleepDateKey
        self.beforeData = beforeData
        self.afterData = afterData
        self.editedAt = editedAt
        self.reason = reason
    }
}

// MARK: - Frozen baseline

nonisolated struct ProtocolBaselineSnapshot: Codable, Hashable, Sendable {
    var id: UUID
    /// V3+: per-version frozen baseline. `nil` means legacy singleton snapshot
    /// pre-V3 backfill — treated as belonging to the active version at read time.
    var versionID: UUID?
    var frozenAt: Date
    var windowStart: Date
    var windowEnd: Date
    var validNightCount: Int
    var meanRestorativeMin: Double?
    var stdRestorativeMin: Double?
    var meanRestorativePctOfInBed: Double?
    var stdRestorativePctOfInBed: Double?
    var meanLongestRestorativeBlockMin: Double?
    var stdLongestRestorativeBlockMin: Double?
    /// Fraction (0…1) of valid nights in each continuity bucket.
    var continuityCategoryDistribution: [SleepContinuityCategory: Double]
    var isInsufficient: Bool
    // P0-4: extended baseline metrics. Optional so previously-frozen snapshots decode
    // cleanly via `PersistenceJSON` — populated lazily by the one-shot baseline
    // augmentation in `AppEnvironment.runProtocolFormulaMigrationIfNeeded`.
    var meanDeepMin: Double?
    var stdDeepMin: Double?
    var meanRemMin: Double?
    var stdRemMin: Double?
    var meanAwakeMin: Double?
    var stdAwakeMin: Double?
    var meanTotalSleepMin: Double?
    var stdTotalSleepMin: Double?
    var meanLatencyMin: Double?
    var stdLatencyMin: Double?
    var meanSleepScore: Double?
    var stdSleepScore: Double?

    init(
        id: UUID = UUID(),
        versionID: UUID? = nil,
        frozenAt: Date,
        windowStart: Date,
        windowEnd: Date,
        validNightCount: Int,
        meanRestorativeMin: Double?,
        stdRestorativeMin: Double?,
        meanRestorativePctOfInBed: Double?,
        stdRestorativePctOfInBed: Double?,
        meanLongestRestorativeBlockMin: Double?,
        stdLongestRestorativeBlockMin: Double?,
        continuityCategoryDistribution: [SleepContinuityCategory: Double],
        isInsufficient: Bool,
        meanDeepMin: Double? = nil,
        stdDeepMin: Double? = nil,
        meanRemMin: Double? = nil,
        stdRemMin: Double? = nil,
        meanAwakeMin: Double? = nil,
        stdAwakeMin: Double? = nil,
        meanTotalSleepMin: Double? = nil,
        stdTotalSleepMin: Double? = nil,
        meanLatencyMin: Double? = nil,
        stdLatencyMin: Double? = nil,
        meanSleepScore: Double? = nil,
        stdSleepScore: Double? = nil
    ) {
        self.id = id
        self.versionID = versionID
        self.frozenAt = frozenAt
        self.windowStart = windowStart
        self.windowEnd = windowEnd
        self.validNightCount = validNightCount
        self.meanRestorativeMin = meanRestorativeMin
        self.stdRestorativeMin = stdRestorativeMin
        self.meanRestorativePctOfInBed = meanRestorativePctOfInBed
        self.stdRestorativePctOfInBed = stdRestorativePctOfInBed
        self.meanLongestRestorativeBlockMin = meanLongestRestorativeBlockMin
        self.stdLongestRestorativeBlockMin = stdLongestRestorativeBlockMin
        self.continuityCategoryDistribution = continuityCategoryDistribution
        self.isInsufficient = isInsufficient
        self.meanDeepMin = meanDeepMin
        self.stdDeepMin = stdDeepMin
        self.meanRemMin = meanRemMin
        self.stdRemMin = stdRemMin
        self.meanAwakeMin = meanAwakeMin
        self.stdAwakeMin = stdAwakeMin
        self.meanTotalSleepMin = meanTotalSleepMin
        self.stdTotalSleepMin = stdTotalSleepMin
        self.meanLatencyMin = meanLatencyMin
        self.stdLatencyMin = stdLatencyMin
        self.meanSleepScore = meanSleepScore
        self.stdSleepScore = stdSleepScore
    }

    var missingExtendedMetricLabels: [String] {
        var missing: [String] = []
        if meanDeepMin == nil { missing.append("Deep") }
        if meanRemMin == nil { missing.append("REM") }
        if meanAwakeMin == nil { missing.append("Awake") }
        if meanTotalSleepMin == nil { missing.append("Sleep duration") }
        if meanLatencyMin == nil { missing.append("Latency") }
        if meanSleepScore == nil { missing.append("Score") }
        return missing
    }

    var hasExtendedMetrics: Bool {
        missingExtendedMetricLabels.isEmpty
    }

    var extendedMetricReadinessSummary: String {
        let missing = missingExtendedMetricLabels
        guard !missing.isEmpty else { return "complete" }
        return missing.joined(separator: ", ")
    }
}

// MARK: - Analysis snapshots (in-memory only)

nonisolated struct ProtocolNightMetricSnapshot: Hashable, Sendable {
    var sleepDateKey: String
    var versionID: UUID?
    var restorativeSleepMinutes: Double?
    var restorativePctOfInBed: Double?
    var longestRestorativeBlockMinutes: Double?
    var continuityCategory: SleepContinuityCategory?
    var dataQuality: SleepDataQuality
    // Full sleep-stage metrics (P0-4). Stage-derived fields require
    // `dataQuality ∈ {.detailedStages, .mixedSources}`; the trio at the bottom
    // is available for any `dataQuality != .noData`.
    var deepMinutes: Double?
    var remMinutes: Double?
    var awakeMinutes: Double?
    var totalSleepMinutes: Double?
    var latencyMinutes: Double?
    var sleepScore: Double?
}

nonisolated struct ProtocolVersionRollup: Hashable, Sendable {
    var versionID: UUID
    var nightCount: Int
    var meanRestorativeMin: Double?
    var stdRestorativeMin: Double?
    var meanRestorativePctOfInBed: Double?
    var stdRestorativePctOfInBed: Double?
    var meanLongestRestorativeBlockMin: Double?
    var stdLongestRestorativeBlockMin: Double?
    var continuityDistribution: [SleepContinuityCategory: Double]
    // P0-4 extended metric aggregates.
    var meanDeepMin: Double?
    var stdDeepMin: Double?
    var meanRemMin: Double?
    var stdRemMin: Double?
    var meanAwakeMin: Double?
    var stdAwakeMin: Double?
    var meanTotalSleepMin: Double?
    var stdTotalSleepMin: Double?
    var meanLatencyMin: Double?
    var stdLatencyMin: Double?
    var meanSleepScore: Double?
    var stdSleepScore: Double?
}

nonisolated struct ProtocolImpactSummary: Hashable, Sendable {
    var versionID: UUID
    var nightCount: Int
    var isLowData: Bool
    var deltaRestorativeMin: Double?
    var deltaRestorativePctOfInBed: Double?
    var deltaLongestRestorativeBlockMin: Double?
    var versionMeanRestorativeMin: Double?
    var versionMeanRestorativePctOfInBed: Double?
    var versionMeanLongestRestorativeBlockMin: Double?
    var baselineMeanRestorativeMin: Double?
    var baselineMeanRestorativePctOfInBed: Double?
    var baselineMeanLongestRestorativeBlockMin: Double?
    // P0-4 extended deltas + means.
    var deltaDeepMin: Double?
    var deltaRemMin: Double?
    var deltaAwakeMin: Double?
    var deltaTotalSleepMin: Double?
    var deltaLatencyMin: Double?
    var deltaSleepScore: Double?
    var versionMeanDeepMin: Double?
    var versionMeanRemMin: Double?
    var versionMeanAwakeMin: Double?
    var versionMeanTotalSleepMin: Double?
    var versionMeanLatencyMin: Double?
    var versionMeanSleepScore: Double?
    var baselineMeanDeepMin: Double?
    var baselineMeanRemMin: Double?
    var baselineMeanAwakeMin: Double?
    var baselineMeanTotalSleepMin: Double?
    var baselineMeanLatencyMin: Double?
    var baselineMeanSleepScore: Double?
    /// Always shown next to every delta — the locked "observed, not causal" caveat string.
    static let causalityCaveat = "Observed, not causal — your baseline isn't a control group."
}

/// Identifies a single Protocol Formula metric across snapshot, rollup, baseline, and
/// impact-summary structs. `betterIsLower` flips delta-color logic in views (awake +
/// latency are the lower-is-better axes; everything else is higher-is-better).
nonisolated enum ProtocolFormulaMetric: String, CaseIterable, Identifiable, Sendable {
    case restorativeMin
    case restorativePct
    case longestBlock
    case deep
    case rem
    case awake
    case duration
    case latency
    case score

    var id: String { rawValue }

    var betterIsLower: Bool {
        switch self {
        case .awake, .latency: true
        default: false
        }
    }

    var shortLabel: String {
        switch self {
        case .restorativeMin: "Restore"
        case .restorativePct: "Rest %"
        case .longestBlock: "Block"
        case .deep: "Deep"
        case .rem: "REM"
        case .awake: "Awake"
        case .duration: "Sleep"
        case .latency: "Latency"
        case .score: "Score"
        }
    }

    var fullLabel: String {
        switch self {
        case .restorativeMin: "Restorative Sleep"
        case .restorativePct: "Total Restorative Sleep %"
        case .longestBlock: "Longest Restorative Block"
        case .deep: "Deep Sleep"
        case .rem: "REM Sleep"
        case .awake: "Awake Time"
        case .duration: "Total Sleep"
        case .latency: "Sleep Latency"
        case .score: "Sleep Score"
        }
    }

    var unit: String {
        switch self {
        case .restorativePct: "%"
        case .score: "pts"
        default: "min"
        }
    }

    var colorHex: String {
        switch self {
        case .restorativeMin: "#34D399"
        case .restorativePct: "#60A5FA"
        case .longestBlock: "#C084FC"
        case .deep: "#818CF8"
        case .rem: "#F472B6"
        case .awake: "#FBBF24"
        case .duration: "#67E8F9"
        case .latency: "#FB923C"
        case .score: "#A3E635"
        }
    }

    func value(from snapshot: ProtocolNightMetricSnapshot) -> Double? {
        switch self {
        case .restorativeMin: snapshot.restorativeSleepMinutes
        case .restorativePct: snapshot.restorativePctOfInBed
        case .longestBlock: snapshot.longestRestorativeBlockMinutes
        case .deep: snapshot.deepMinutes
        case .rem: snapshot.remMinutes
        case .awake: snapshot.awakeMinutes
        case .duration: snapshot.totalSleepMinutes
        case .latency: snapshot.latencyMinutes
        case .score: snapshot.sleepScore
        }
    }

    func baselineValue(from baseline: ProtocolBaselineSnapshot) -> Double? {
        switch self {
        case .restorativeMin: baseline.meanRestorativeMin
        case .restorativePct: baseline.meanRestorativePctOfInBed
        case .longestBlock: baseline.meanLongestRestorativeBlockMin
        case .deep: baseline.meanDeepMin
        case .rem: baseline.meanRemMin
        case .awake: baseline.meanAwakeMin
        case .duration: baseline.meanTotalSleepMin
        case .latency: baseline.meanLatencyMin
        case .score: baseline.meanSleepScore
        }
    }

    func rollupMean(from rollup: ProtocolVersionRollup) -> Double? {
        switch self {
        case .restorativeMin: rollup.meanRestorativeMin
        case .restorativePct: rollup.meanRestorativePctOfInBed
        case .longestBlock: rollup.meanLongestRestorativeBlockMin
        case .deep: rollup.meanDeepMin
        case .rem: rollup.meanRemMin
        case .awake: rollup.meanAwakeMin
        case .duration: rollup.meanTotalSleepMin
        case .latency: rollup.meanLatencyMin
        case .score: rollup.meanSleepScore
        }
    }
}

// MARK: - Insight

nonisolated enum ProtocolFormulaInsightKind: String, Codable, Sendable {
    case restorativeImprovement
    case restorativeRegression
    case longestBlockImprovement
    case continuityImprovement
    case lowData
    case baselineUnavailable
}

nonisolated struct ProtocolFormulaInsight: Identifiable, Sendable {
    var id: UUID
    var kind: ProtocolFormulaInsightKind
    var versionID: UUID?
    /// Short headline shown in the card.
    var headline: String
    /// Supporting body (always includes the observed-not-causal caveat when applicable).
    var body: String
    var isPositive: Bool

    init(id: UUID = UUID(), kind: ProtocolFormulaInsightKind, versionID: UUID? = nil,
         headline: String, body: String, isPositive: Bool = true) {
        self.id = id; self.kind = kind; self.versionID = versionID
        self.headline = headline; self.body = body; self.isPositive = isPositive
    }
}

// MARK: - Hashing helper

nonisolated enum ProtocolFormulaHashing {
    /// Stable SHA-256 of (normalized formula text + sorted component name|dose|role).
    /// Used by `ProtocolNightLog.formulaSnapshotHash` so logs detect drift against the version.
    static func snapshotHash(for version: ProtocolFormulaVersion) -> String {
        let text = version.formulaText.trimmingCharacters(in: .whitespacesAndNewlines)
        let components = version.components
            .map { "\($0.name)|\($0.dose)|\($0.role.rawValue)" }
            .sorted()
            .joined(separator: ";")
        let combined = "\(text)::\(components)"
        let digest = SHA256.hash(data: Data(combined.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
