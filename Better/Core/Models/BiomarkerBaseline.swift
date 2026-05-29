import Foundation

/// Identifies the four biomarkers surfaced on the Sleep dashboard.
nonisolated enum BiomarkerKey: String, Codable, Hashable, Sendable, CaseIterable {
    case rhr
    case hrv
    case spo2
    case breath
}

nonisolated enum BiomarkerBaselineReadiness: Codable, Hashable, Sendable {
    case ready(sampleCount: Int, minimumCount: Int)
    case building(sampleCount: Int, minimumCount: Int)
    case unavailable(minimumCount: Int)

    var isReady: Bool {
        if case .ready = self { return true }
        return false
    }

    var sampleCount: Int {
        switch self {
        case .ready(let sampleCount, _), .building(let sampleCount, _):
            return sampleCount
        case .unavailable:
            return 0
        }
    }

    var shortLabel: String {
        switch self {
        case .ready(let sampleCount, _):
            return "\(sampleCount)d"
        case .building(let sampleCount, let minimumCount):
            return "\(sampleCount)/\(minimumCount)"
        case .unavailable(let minimumCount):
            return "0/\(minimumCount)"
        }
    }

    var neutralCopy: String {
        switch self {
        case .ready:
            return "Personal comparison ready."
        case .building(let sampleCount, let minimumCount):
            let needed = max(0, minimumCount - sampleCount)
            return "Needs \(needed) more night\(needed == 1 ? "" : "s") for a personal comparison."
        case .unavailable(let minimumCount):
            return "Needs \(minimumCount) nights with this reading for a personal comparison."
        }
    }
}

nonisolated enum BiomarkerProvenanceConfidence: String, Codable, Hashable, Sendable {
    case high
    case mixed
    case low
    case missing
}

nonisolated struct BiomarkerProvenance: Codable, Hashable, Sendable {
    var key: BiomarkerKey
    var sourceNames: [String]
    var sampleCount: Int
    var containsManualEntry: Bool
    var confidence: BiomarkerProvenanceConfidence

    var compactSourceLabel: String {
        guard !sourceNames.isEmpty else { return "No source captured" }
        if sourceNames.count == 1 {
            return sourceNames[0]
        }
        return "\(sourceNames[0]) +\(sourceNames.count - 1)"
    }

    var neutralTrustCopy: String {
        switch confidence {
        case .high:
            return "Auto-captured overnight"
        case .mixed:
            return "Multiple sources"
        case .low:
            return "Manual or limited source"
        case .missing:
            return "No reading captured"
        }
    }

    static func make(
        key: BiomarkerKey,
        samples: [BiometricSample],
        fallbackSources: [SleepSource],
        hasValue: Bool
    ) -> BiomarkerProvenance {
        let matchingSamples = samples.filter { key.matches(sampleType: $0.type) }
        let sampleSources = matchingSamples.compactMap(\.source)
        let usableSources = sampleSources.isEmpty && hasValue ? fallbackSources : sampleSources
        let sourceNames = Array(
            Set(usableSources.map(\.name).filter { !$0.isEmpty })
        ).sorted()
        let containsManualEntry = usableSources.contains { $0.isManualEntry }
        let confidence: BiomarkerProvenanceConfidence

        if !hasValue {
            confidence = .missing
        } else if containsManualEntry {
            confidence = .low
        } else if sourceNames.count > 1 {
            confidence = .mixed
        } else if !sourceNames.isEmpty && !matchingSamples.isEmpty {
            confidence = .high
        } else {
            confidence = .low
        }

        return BiomarkerProvenance(
            key: key,
            sourceNames: sourceNames,
            sampleCount: matchingSamples.count,
            containsManualEntry: containsManualEntry,
            confidence: confidence
        )
    }
}

/// Per-user rolling baseline for the dashboard biomarkers. Persisted as a single
/// encrypted blob via the existing `StoredSyncAnchor` channel and recomputed on
/// a 7-day TTL (or whenever a new sync lands new sessions).
///
/// `windowDays` follows the same dashboard convention as
/// `BaselineEngine.selectDashboardBaseline(...)` — 30-day primary, 60-day
/// fallback when there are too few nights to anchor 30 (invariant #3, dashboard
/// scope only).
nonisolated struct BiomarkerBaseline: Codable, Hashable, Sendable {
    var computedAt: Date
    var windowDays: Int
    var sampleCounts: [BiomarkerKey: Int]
    var means: [BiomarkerKey: Double]
    var stdDevs: [BiomarkerKey: Double]

    init(
        computedAt: Date,
        windowDays: Int,
        sampleCounts: [BiomarkerKey: Int],
        means: [BiomarkerKey: Double],
        stdDevs: [BiomarkerKey: Double]
    ) {
        self.computedAt = computedAt
        self.windowDays = windowDays
        self.sampleCounts = sampleCounts
        self.means = means
        self.stdDevs = stdDevs
    }

    func isStale(now: Date = Date(), ttlDays: Int = 7) -> Bool {
        let ttl = TimeInterval(ttlDays) * 86_400
        return now.timeIntervalSince(computedAt) > ttl
    }

    func readiness(for key: BiomarkerKey, minimumSamples: Int = 5) -> BiomarkerBaselineReadiness {
        let count = sampleCounts[key] ?? 0
        guard count > 0 else {
            return .unavailable(minimumCount: minimumSamples)
        }
        if count >= minimumSamples, means[key] != nil {
            return .ready(sampleCount: count, minimumCount: minimumSamples)
        }
        return .building(sampleCount: count, minimumCount: minimumSamples)
    }
}

/// Direction of tonight's value relative to the user's usual range. "Improved"
/// is biomarker-specific (lower RHR is good, higher HRV is good, higher SpO₂ is
/// good, breath closest to 14–16 is good).
nonisolated enum BiomarkerReactionDirection: String, Codable, Hashable, Sendable {
    case improved
    case worse
    case neutral
}

/// Tonight's reading compared to the cached baseline. `nil` when either the
/// biomarker is missing tonight or the baseline has too few samples for a
/// meaningful comparison.
nonisolated struct SleepBiomarkerReaction: Hashable, Sendable {
    var key: BiomarkerKey
    var tonightValue: Double
    var baselineMean: Double
    var baselineStdDev: Double
    var delta: Double
    var zScore: Double
    var direction: BiomarkerReactionDirection

    /// Returns nil when the comparison is not informative.
    static func make(
        key: BiomarkerKey,
        tonight: Double?,
        baseline: BiomarkerBaseline?,
        meaningfulZ: Double = 0.75,
        minSamples: Int = 5
    ) -> SleepBiomarkerReaction? {
        guard
            let tonight,
            let baseline,
            (baseline.sampleCounts[key] ?? 0) >= minSamples,
            let mean = baseline.means[key]
        else { return nil }

        let stdDev = baseline.stdDevs[key] ?? 0
        let delta = tonight - mean
        let z = stdDev > 0 ? delta / stdDev : 0
        let direction = Self.direction(for: key, delta: delta, zScore: z, threshold: meaningfulZ)

        return SleepBiomarkerReaction(
            key: key,
            tonightValue: tonight,
            baselineMean: mean,
            baselineStdDev: stdDev,
            delta: delta,
            zScore: z,
            direction: direction
        )
    }

    private static func direction(
        for key: BiomarkerKey,
        delta: Double,
        zScore: Double,
        threshold: Double
    ) -> BiomarkerReactionDirection {
        guard abs(zScore) >= threshold else { return .neutral }
        switch key {
        case .rhr:
            return delta < 0 ? .improved : .worse
        case .hrv, .spo2:
            return delta > 0 ? .improved : .worse
        case .breath:
            // Optimal breath rate sits around 14–16 br/min — drift in either
            // direction is "worse"; convergence is "improved". The mean is the
            // user's own usual, so we treat absolute distance from the mean as
            // worse when |z| crosses the threshold AND the absolute change is
            // at least 1 br/min (sub-1 br/min drifts are measurement noise).
            guard abs(delta) >= 1.0 else { return .neutral }
            return .worse
        }
    }
}

// MARK: - First-screen body signal presentation

nonisolated enum BiomarkerBodySignal: String, Codable, Hashable, Sendable {
    case harder
    case recovered
    case steady
    case building
    case missing
}

nonisolated enum BiomarkerBodySignalMagnitude: String, Codable, Hashable, Sendable {
    case same
    case slight
    case meaningful
    case large

    static func make(percentDelta: Double) -> BiomarkerBodySignalMagnitude {
        let absolute = abs(percentDelta)
        switch absolute {
        case 0...5:
            return .same
        case 5...12:
            return .slight
        case 12...20:
            return .meaningful
        default:
            return .large
        }
    }
}

nonisolated struct BiomarkerBodySignalPresentation: Hashable, Sendable {
    var key: BiomarkerKey
    var value: Double?
    var baselineMean: Double?
    var percentDelta: Double?
    var percentText: String
    var comparisonText: String
    var statusText: String
    var meaningText: String
    var signal: BiomarkerBodySignal
    var magnitude: BiomarkerBodySignalMagnitude

    static func make(
        key: BiomarkerKey,
        tonight: Double?,
        baseline: BiomarkerBaseline?,
        reaction: SleepBiomarkerReaction?,
        readiness: BiomarkerBaselineReadiness,
        provenance: BiomarkerProvenance?
    ) -> BiomarkerBodySignalPresentation {
        guard let tonight else {
            return BiomarkerBodySignalPresentation(
                key: key,
                value: nil,
                baselineMean: nil,
                percentDelta: nil,
                percentText: "--",
                comparisonText: provenance?.neutralTrustCopy ?? "No reading captured tonight",
                statusText: "No reading",
                meaningText: "No reading captured tonight.",
                signal: .missing,
                magnitude: .same
            )
        }

        guard readiness.isReady, let mean = baseline?.means[key], mean != 0 else {
            return BiomarkerBodySignalPresentation(
                key: key,
                value: tonight,
                baselineMean: nil,
                percentDelta: nil,
                percentText: "--",
                comparisonText: readiness.neutralCopy,
                statusText: "Baseline building",
                meaningText: "Need more nights for your baseline comparison.",
                signal: .building,
                magnitude: .same
            )
        }

        let percentDelta = ((tonight - mean) / mean) * 100
        let magnitude = Self.magnitude(for: key, percentDelta: percentDelta)
        let signal = Self.signal(for: key, reaction: reaction, percentDelta: percentDelta, magnitude: magnitude)

        return BiomarkerBodySignalPresentation(
            key: key,
            value: tonight,
            baselineMean: mean,
            percentDelta: percentDelta,
            percentText: Self.percentText(for: percentDelta, magnitude: magnitude),
            comparisonText: Self.comparisonText(for: percentDelta, magnitude: magnitude),
            statusText: Self.statusText(for: key, signal: signal, magnitude: magnitude, percentDelta: percentDelta),
            meaningText: Self.meaningText(for: key, signal: signal),
            signal: signal,
            magnitude: magnitude
        )
    }

    static func comparisonText(for percentDelta: Double, magnitude: BiomarkerBodySignalMagnitude? = nil) -> String {
        let magnitude = magnitude ?? Self.magnitude(for: .rhr, percentDelta: percentDelta)
        let rounded = Int(abs(percentDelta).rounded())
        guard magnitude != .same, rounded >= 1 else { return "same as baseline" }
        return "\(rounded)% \(percentDelta > 0 ? "higher" : "lower") than baseline"
    }

    static func percentText(for percentDelta: Double, magnitude: BiomarkerBodySignalMagnitude? = nil) -> String {
        let magnitude = magnitude ?? Self.magnitude(for: .rhr, percentDelta: percentDelta)
        guard magnitude != .same else {
            return "\(Int(percentDelta.rounded()))%"
        }
        return "\(percentDelta > 0 ? "+" : "-")\(Int(abs(percentDelta).rounded()))%"
    }

    private static func magnitude(
        for key: BiomarkerKey,
        percentDelta: Double
    ) -> BiomarkerBodySignalMagnitude {
        // Pulse-ox changes below 2% are usually device noise; breath needs a
        // larger shift before it should affect the first-screen story.
        switch key {
        case .spo2:
            if percentDelta <= -2 {
                return abs(percentDelta) >= 5 ? .large : .meaningful
            }
            return .same
        case .breath where abs(percentDelta) < 8:
            return .same
        default:
            return BiomarkerBodySignalMagnitude.make(percentDelta: percentDelta)
        }
    }

    private static func signal(
        for key: BiomarkerKey,
        reaction: SleepBiomarkerReaction?,
        percentDelta: Double,
        magnitude: BiomarkerBodySignalMagnitude
    ) -> BiomarkerBodySignal {
        if magnitude == .same {
            return .steady
        }

        if let reaction {
            switch reaction.direction {
            case .worse:
                return .harder
            case .improved:
                return .recovered
            case .neutral:
                return .steady
            }
        }

        switch key {
        case .rhr:
            return percentDelta > 0 ? .harder : .recovered
        case .hrv, .spo2:
            return percentDelta > 0 ? .recovered : .harder
        case .breath:
            return .steady
        }
    }

    private static func statusText(
        for key: BiomarkerKey,
        signal: BiomarkerBodySignal,
        magnitude: BiomarkerBodySignalMagnitude,
        percentDelta: Double
    ) -> String {
        guard signal != .steady else { return "Normal" }

        let degree: String
        switch magnitude {
        case .large:
            degree = "Much "
        case .meaningful:
            degree = ""
        case .slight:
            degree = "Slightly "
        case .same:
            degree = ""
        }

        switch (key, signal, percentDelta > 0) {
        case (.rhr, .harder, true):
            return "\(degree)above baseline"
        case (.rhr, .recovered, false):
            return "\(degree)calmer"
        case (.hrv, .recovered, true):
            return "\(degree)better than baseline"
        case (.hrv, .harder, false):
            return "\(degree)below baseline"
        case (.spo2, .harder, false):
            return "\(degree)below baseline"
        case (.spo2, .recovered, true):
            return "\(degree)strong"
        case (.breath, .harder, _):
            return "\(degree)off rhythm"
        default:
            return "Normal"
        }
    }

    private static func meaningText(for key: BiomarkerKey, signal: BiomarkerBodySignal) -> String {
        switch (key, signal) {
        case (.rhr, .harder):
            return "Higher heart rate can mean more strain."
        case (.rhr, .recovered):
            return "Lower heart rate can mean a calmer night."
        case (.hrv, .recovered):
            return "Higher HRV typically means better recovery."
        case (.hrv, .harder):
            return "Lower HRV can mean lighter recovery."
        case (.spo2, .harder):
            return "Oxygen dipped more than your baseline."
        case (.spo2, .recovered):
            return "Oxygen stayed strong overnight."
        case (.breath, .harder):
            return "Breathing moved away from your baseline rhythm."
        case (.breath, .recovered):
            return "Breathing stayed close to your best rhythm."
        case (.spo2, _):
            return "Oxygen stayed steady overnight."
        case (.breath, _):
            return "Breathing stayed close to your baseline rhythm."
        case (_, .building):
            return "Need more nights for your baseline comparison."
        case (_, .missing):
            return "No reading captured tonight."
        case (_, .steady):
            return "This stayed close to your baseline."
        }
    }
}

// MARK: - Plain-English education + sleep impact

extension BiomarkerKey {
    nonisolated func matches(sampleType: BiometricType) -> Bool {
        switch self {
        case .rhr:
            return sampleType == .heartRate
        case .hrv:
            return sampleType == .heartRateVariabilitySDNN
        case .spo2:
            return sampleType == .oxygenSaturation
        case .breath:
            return sampleType == .respiratoryRate
        }
    }

    /// One short, kid-friendly sentence explaining what this biomarker measures.
    nonisolated var simpleExplanation: String {
        switch self {
        case .rhr:
            return "Your lowest heart rate while asleep. Lower typically means your body is calm and recovering."
        case .hrv:
            return "How well your heart adapts between beats. Higher numbers typically mean your body is well-rested."
        case .spo2:
            return "How much oxygen your blood carries overnight. Steady, high values mean your breathing was easy."
        case .breath:
            return "How many breaths you take each minute while asleep. Calm, steady breathing means your body is at ease."
        }
    }

    /// One short sentence describing why this number matters for sleep.
    nonisolated var sleepImpactExplanation: String {
        switch self {
        case .rhr:
            return "A calm heart helps your body drop into deeper, more restorative sleep."
        case .hrv:
            return "Higher HRV at night is a strong sign your body recovered well during sleep."
        case .spo2:
            return "Stable oxygen levels keep your sleep uninterrupted and your brain well-fed."
        case .breath:
            return "Steady breathing helps you stay in deeper sleep stages without small wake-ups."
        }
    }
}

extension SleepBiomarkerReaction {
    /// Plain-English headline describing tonight's value vs the user's usual.
    /// e.g. "11 bpm below your usual — calmer night."
    nonisolated func plainEnglishHeadline() -> String {
        let unit: String
        let delta: String
        switch key {
        case .rhr:    unit = "bpm";    delta = String(format: "%.0f", abs(self.delta))
        case .hrv:    unit = "ms";     delta = String(format: "%.0f", abs(self.delta))
        case .spo2:   unit = "%";      delta = String(format: "%.1f", abs(self.delta))
        case .breath: unit = "br/min"; delta = String(format: "%.1f", abs(self.delta))
        }
        switch (key, direction) {
        case (.rhr, .improved):
            return "\(delta) \(unit) below your baseline — calmer night."
        case (.rhr, .worse):
            return "\(delta) \(unit) above your baseline — body worked harder."
        case (.hrv, .improved):
            return "\(delta) \(unit) above your baseline — strong recovery signal."
        case (.hrv, .worse):
            return "\(delta) \(unit) below your baseline — recovery looked light."
        case (.spo2, .improved):
            return "\(delta) \(unit) above your baseline — breathing felt easy."
        case (.spo2, .worse):
            return "\(delta) \(unit) below your baseline — oxygen dipped more than baseline."
        case (.breath, .worse):
            let direction = self.delta > 0 ? "faster" : "slower"
            return "\(delta) \(unit) \(direction) than your baseline — breathing drifted off."
        case (_, .neutral):
            return "Tonight matched your baseline range."
        case (.breath, .improved):
            return "Right on your baseline breathing rhythm."
        }
    }
}

/// Synthesises a short "Impact on sleep" line tying tonight's reaction to a
/// quality-score outcome heuristic. Returns a neutral default if no quality
/// score is available.
enum BiomarkerInsightSynthesizer {
    static func impactLine(
        reaction: SleepBiomarkerReaction,
        sleepScore: Int?
    ) -> String {
        let strongSleep = (sleepScore ?? 0) >= 75
        let weakSleep = (sleepScore ?? 100) < 55
        switch reaction.direction {
        case .improved where strongSleep:
            return "Your body's calm signal matched a strong sleep score tonight."
        case .improved:
            return "A positive recovery signal, even if other parts of sleep were mixed."
        case .worse where weakSleep:
            return "This drift lines up with a tougher sleep score — worth watching tomorrow."
        case .worse:
            return "Worth a glance over the next few nights to see if it sticks."
        case .neutral:
            return "Tonight tracked close to your typical pattern."
        }
    }
}
