import Foundation

nonisolated struct ProtocolFormulaCatalogSpec: Hashable, Sendable, Identifiable {
    var id: UUID
    var label: String
    var order: Int
    var formulaText: String
    var colorHex: String
}

nonisolated enum ProtocolFormulaHistoryOnboardingStorage {
    static let completedKey = "better.protocol.formula.historyOnboardingCompleted"
}

nonisolated enum ProtocolFormulaCatalog {
    // Crashing at launch on a typo is worse than the (impossible-in-practice)
    // alternative of a malformed literal escaping review. Centralized helper
    // gives one well-labelled crash site instead of six anonymous force-unwraps.
    private static func staticUUID(_ s: String, file: StaticString = #fileID, line: UInt = #line) -> UUID {
        guard let u = UUID(uuidString: s) else {
            preconditionFailure("Invalid static UUID \(s)", file: file, line: line)
        }
        return u
    }

    static let specs: [ProtocolFormulaCatalogSpec] = [
        ProtocolFormulaCatalogSpec(
            id: staticUUID("BEEF0001-0000-4000-8000-000000000001"),
            label: "V1",
            order: 0,
            formulaText: "Magnesium glycinate 400mg · L-theanine 200mg",
            colorHex: "#34D399"
        ),
        ProtocolFormulaCatalogSpec(
            id: staticUUID("BEEF0015-0000-4000-8000-000000000015"),
            label: "V1.5",
            order: 1,
            formulaText: "Formula details coming soon.",
            colorHex: "#2DD4BF"
        ),
        ProtocolFormulaCatalogSpec(
            id: staticUUID("BEEF0002-0000-4000-8000-000000000002"),
            label: "V2",
            order: 2,
            formulaText: "V1 + Glycine 3g",
            colorHex: "#60A5FA"
        ),
        ProtocolFormulaCatalogSpec(
            id: staticUUID("BEEF0003-0000-4000-8000-000000000003"),
            label: "V3",
            order: 3,
            formulaText: "V2 + Apigenin 50mg",
            colorHex: "#C084FC"
        ),
        ProtocolFormulaCatalogSpec(
            id: staticUUID("BEEF0004-0000-4000-8000-000000000004"),
            label: "V4",
            order: 4,
            formulaText: "V3 - L-theanine + Lemon balm 600mg",
            colorHex: "#67E8F9"
        ),
        ProtocolFormulaCatalogSpec(
            id: staticUUID("BEEF0005-0000-4000-8000-000000000005"),
            label: "V5",
            order: 5,
            formulaText: "Formula details coming soon.",
            colorHex: "#A3E635"
        )
    ]

    // Bumped from 3 → 5 so "best version" requires meaningful sample size before
    // we surface a rank to the user.
    static let minimumRankedNights = 5

    static func spec(for label: String) -> ProtocolFormulaCatalogSpec? {
        specs.first { $0.label.caseInsensitiveCompare(label) == .orderedSame }
    }

    static func spec(for id: UUID) -> ProtocolFormulaCatalogSpec? {
        specs.first { $0.id == id }
    }

    static func order(for version: ProtocolFormulaVersion) -> Int {
        spec(for: version.resolvedLabel)?.order ?? Int.max
    }

    static func sorted(_ versions: [ProtocolFormulaVersion]) -> [ProtocolFormulaVersion] {
        versions.sorted {
            let lhsOrder = order(for: $0)
            let rhsOrder = order(for: $1)
            if lhsOrder != rhsOrder { return lhsOrder < rhsOrder }
            return $0.shippedOn < $1.shippedOn
        }
    }

    static func version(matching spec: ProtocolFormulaCatalogSpec,
                        existing: [ProtocolFormulaVersion]) -> ProtocolFormulaVersion? {
        existing.first { $0.id == spec.id }
            ?? existing.first { $0.resolvedLabel.caseInsensitiveCompare(spec.label) == .orderedSame }
    }
}

nonisolated struct ProtocolFormulaHistorySeed: Sendable, Hashable {
    var dateKeysByVersionID: [UUID: Set<String>]
    var currentVersionID: UUID?

    init(dateKeysByVersionID: [UUID: Set<String>], currentVersionID: UUID?) {
        self.dateKeysByVersionID = dateKeysByVersionID
        self.currentVersionID = currentVersionID
    }
}

nonisolated struct ProtocolFormulaBestVersion: Sendable, Hashable {
    var version: ProtocolFormulaVersion
    var rollup: ProtocolVersionRollup
    var restorativePctDelta: Double?
    var deepDelta: Double?
    var remDelta: Double?
    var awakeDelta: Double?
    var latencyDelta: Double?
}

nonisolated struct ProtocolFormulaCatalogService: Sendable {
    private let repository: LocalDataRepositoryProtocol
    private let calendar: Calendar

    init(repository: LocalDataRepositoryProtocol, calendar: Calendar = .current) {
        self.repository = repository
        self.calendar = calendar
    }

    /// Loads catalog versions the user has actually painted/seeded. Reconciles
    /// label/text/color drift against the in-code spec but NEVER creates new
    /// rows — that only happens via `upsertVersion` from explicit user action
    /// (onboarding seed, formula setup picker).
    @discardableResult
    func loadExistingVersions(currentVersionID: UUID? = nil) async throws -> [ProtocolFormulaVersion] {
        let existing = try await repository.fetchAllFormulaVersions()
        for spec in ProtocolFormulaCatalog.specs {
            guard var matched = ProtocolFormulaCatalog.version(matching: spec, existing: existing) else { continue }
            var needsSave = false
            if matched.displayLabel != spec.label {
                matched.displayLabel = spec.label
                needsSave = true
            }
            if matched.formulaText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                matched.formulaText == "Formula details coming soon." {
                matched.formulaText = spec.formulaText
                needsSave = true
            }
            if matched.colorHex != spec.colorHex {
                matched.colorHex = spec.colorHex
                needsSave = true
            }
            if let currentVersionID, currentVersionID == matched.id, !matched.isActive {
                matched.isActive = true
                needsSave = true
            }
            if needsSave {
                do {
                    try await repository.saveFormulaVersion(matched)
                } catch ProtocolFormulaRepositoryError.formulaTextLocked {
                    // Logged formulas are immutable; reconciliation is best-effort.
                }
            }
        }

        var all = try await repository.fetchAllFormulaVersions()
        if let currentVersionID,
           let current = all.first(where: { $0.id == currentVersionID }),
           !current.isActive {
            var active = current
            active.isActive = true
            try? await repository.saveFormulaVersion(active)
            all = try await repository.fetchAllFormulaVersions()
        }
        return ProtocolFormulaCatalog.sorted(all.filter { version in
            ProtocolFormulaCatalog.specs.contains { spec in
                spec.id == version.id || spec.label.caseInsensitiveCompare(version.resolvedLabel) == .orderedSame
            }
        })
    }

    /// Back-compat alias. Semantically equivalent to `loadExistingVersions` —
    /// the previous eager fabrication of V1…V5 with synthesized `shippedOn`
    /// values has been removed. Callers that genuinely need a new row must use
    /// `upsertVersion(for:shippedOn:currentVersionID:)`.
    @discardableResult
    func ensureCatalogVersions(currentVersionID: UUID? = nil) async throws -> [ProtocolFormulaVersion] {
        try await loadExistingVersions(currentVersionID: currentVersionID)
    }

    /// Creates or updates a single catalog version. `shippedOn` MUST originate
    /// from real user input (earliest painted date) — there is no fallback.
    @discardableResult
    func upsertVersion(
        for spec: ProtocolFormulaCatalogSpec,
        shippedOn: Date,
        currentVersionID: UUID?
    ) async throws -> ProtocolFormulaVersion {
        let existing = try await repository.fetchAllFormulaVersions()
        if var matched = ProtocolFormulaCatalog.version(matching: spec, existing: existing) {
            var needsSave = false
            if matched.displayLabel != spec.label { matched.displayLabel = spec.label; needsSave = true }
            if matched.formulaText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                matched.formulaText == "Formula details coming soon." {
                matched.formulaText = spec.formulaText
                needsSave = true
            }
            if matched.colorHex != spec.colorHex { matched.colorHex = spec.colorHex; needsSave = true }
            let shouldBeActive = currentVersionID == matched.id
            if matched.isActive != shouldBeActive { matched.isActive = shouldBeActive; needsSave = true }
            if needsSave {
                do { try await repository.saveFormulaVersion(matched) }
                catch ProtocolFormulaRepositoryError.formulaTextLocked { }
            }
            return matched
        }
        let version = ProtocolFormulaVersion(
            id: spec.id,
            displayLabel: spec.label,
            ordinalLabel: spec.label,
            formulaText: spec.formulaText,
            components: [],
            shippedOn: shippedOn,
            colorHex: spec.colorHex,
            isActive: currentVersionID == spec.id
        )
        try await repository.saveFormulaVersion(version)

        // V3: emit InterventionWindow transitions for the newly-created version.
        // Close any window whose `endedAt == nil` by stamping it with the new
        // version's shippedOn and phase = .superseded. Then open a new active
        // window for the new version. Idempotent for an already-existing window
        // for this versionID (saveInterventionWindow upserts by id).
        let existingWindows = try await repository.fetchInterventionWindows()
        let now = Date()
        for window in existingWindows where window.endedAt == nil && window.versionID != version.id {
            var closed = window
            closed.endedAt = max(window.startedAt, shippedOn)
            closed.phase = .superseded
            closed.updatedAt = now
            try await repository.saveInterventionWindow(closed)
        }
        if !existingWindows.contains(where: { $0.versionID == version.id }) {
            let newWindow = InterventionWindow(
                versionID: version.id,
                startedAt: shippedOn,
                endedAt: nil,
                phase: .active,
                createdAt: now,
                updatedAt: now
            )
            try await repository.saveInterventionWindow(newWindow)
        }
        return version
    }

    /// V3 archive flow: archives the version row and closes its intervention
    /// window with `phase = .archived`. `endedAt` is clamped to be ≥ the
    /// window's `startedAt`.
    func archiveVersion(id versionID: UUID) async throws {
        try await repository.archiveFormulaVersion(id: versionID)
        let archivedAt = Date()
        let windows = try await repository.fetchInterventionWindows()
        guard var window = windows.first(where: { $0.versionID == versionID }) else { return }
        if window.endedAt == nil {
            window.endedAt = max(window.startedAt, archivedAt)
        } else if let existingEnd = window.endedAt {
            window.endedAt = max(window.startedAt, existingEnd)
        }
        window.phase = .archived
        window.updatedAt = archivedAt
        try await repository.saveInterventionWindow(window)
    }

    func seedHistory(_ seed: ProtocolFormulaHistorySeed) async throws {
        let allKeys = seed.dateKeysByVersionID.values.flatMap { $0 }
        guard let startKey = allKeys.min(), let endKey = allKeys.max() else { return }

        var versionsByID: [UUID: ProtocolFormulaVersion] = [:]
        for (versionID, dateKeys) in seed.dateKeysByVersionID {
            guard let spec = ProtocolFormulaCatalog.spec(for: versionID), !dateKeys.isEmpty else { continue }
            let earliestKey = dateKeys.min()
            let shippedOn = earliestKey.flatMap { SleepDateKey.date(from: $0) } ?? Date()
            let version = try await upsertVersion(
                for: spec,
                shippedOn: shippedOn,
                currentVersionID: seed.currentVersionID
            )
            versionsByID[versionID] = version
        }

        let existingLogs = try await repository.fetchNightLogs(from: startKey, to: endKey)
        let existingByKey = ProtocolFormulaDeduping.latestLogsByDate(existingLogs, context: "catalog-seed-history")

        for (versionID, dateKeys) in seed.dateKeysByVersionID {
            guard let version = versionsByID[versionID] else { continue }
            for key in dateKeys.sorted() where existingByKey[key] == nil {
                let log = ProtocolNightLog(
                    sleepDateKey: key,
                    versionID: versionID,
                    status: .taken,
                    takenAt: nil,
                    formulaSnapshotHash: ProtocolFormulaHashing.snapshotHash(for: version)
                )
                try await repository.saveNightLog(log)
            }
        }
    }

    static func bestVersion(
        versions: [ProtocolFormulaVersion],
        rollups: [ProtocolVersionRollup],
        baseline: ProtocolBaselineSnapshot?,
        minimumNights: Int = ProtocolFormulaCatalog.minimumRankedNights
    ) -> ProtocolFormulaBestVersion? {
        // Insufficient baselines cannot ground a delta — surface "—" instead of ranking.
        guard let baseline, baseline.isInsufficient == false else { return nil }
        let versionsByID = ProtocolFormulaDeduping.latestVersionsByID(versions, context: "best-version")
        func delta(_ value: Double?, _ base: Double?) -> Double? {
            guard let value, let base else { return nil }
            return value - base
        }

        let candidates = rollups.compactMap { rollup -> ProtocolFormulaBestVersion? in
            guard rollup.nightCount >= minimumNights,
                  let version = versionsByID[rollup.versionID],
                  let restorativeDelta = delta(rollup.meanRestorativePctOfInBed, baseline.meanRestorativePctOfInBed)
            else { return nil }
            return ProtocolFormulaBestVersion(
                version: version,
                rollup: rollup,
                restorativePctDelta: restorativeDelta,
                deepDelta: delta(rollup.meanDeepMin, baseline.meanDeepMin),
                remDelta: delta(rollup.meanRemMin, baseline.meanRemMin),
                awakeDelta: delta(rollup.meanAwakeMin, baseline.meanAwakeMin),
                latencyDelta: delta(rollup.meanLatencyMin, baseline.meanLatencyMin)
            )
        }

        return candidates.sorted { lhs, rhs in
            let l = lhs.restorativePctDelta ?? -.greatestFiniteMagnitude
            let r = rhs.restorativePctDelta ?? -.greatestFiniteMagnitude
            if l != r { return l > r }
            if lhs.rollup.nightCount != rhs.rollup.nightCount { return lhs.rollup.nightCount > rhs.rollup.nightCount }
            if lhs.version.shippedOn != rhs.version.shippedOn { return lhs.version.shippedOn > rhs.version.shippedOn }
            return ProtocolFormulaCatalog.order(for: lhs.version) < ProtocolFormulaCatalog.order(for: rhs.version)
        }.first
    }
}

// TODO(post-v1): remove formulaSnapshotHash usage; it is stamped on every log
// but never read for drift detection. Keep the field in `ProtocolNightLog` for
// schema stability — drop the hashing call sites in a follow-up.
