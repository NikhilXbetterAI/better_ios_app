import Foundation
import OSLog

/// One-shot V3 backfill — assigns `versionID` to legacy frozen baselines and
/// emits `InterventionWindow` rows for every existing `ProtocolFormulaVersion`.
/// Idempotent and gated on a `UserDefaults` flag so subsequent launches no-op.
///
/// Window derivation:
///   - Sort versions by `(shippedOn ASC, createdAt ASC)`.
///   - For version i:
///       startedAt = version.shippedOn
///       endedAt   = version[i+1].shippedOn (if successor exists)
///                   else version.archivedAt (clamped ≥ shippedOn) if archived
///                   else nil (active window)
///       phase     = .active     if endedAt == nil
///                   .archived   if version.archivedAt != nil and no successor
///                   .superseded otherwise
nonisolated enum BackfillCoordinator {
    static let v3CompletedKey = "better.protocolFormula.v3BackfillCompleted"
    private static let logger = Logger(subsystem: "Better", category: "BackfillCoordinator")

    static func runV3Backfill(
        repository: LocalDataRepositoryProtocol,
        userDefaults: UserDefaults = .standard
    ) async {
        guard !userDefaults.bool(forKey: v3CompletedKey) else { return }
        do {
            try await performBackfill(repository: repository)
            userDefaults.set(true, forKey: v3CompletedKey)
            Self.logger.debug("V3 backfill completed")
        } catch {
            Self.logger.error("V3 backfill failed: \(String(describing: error), privacy: .public)")
        }
    }

    private static func performBackfill(repository: LocalDataRepositoryProtocol) async throws {
        let versions = try await repository.fetchAllFormulaVersions()
            .sorted { lhs, rhs in
                if lhs.shippedOn != rhs.shippedOn { return lhs.shippedOn < rhs.shippedOn }
                return lhs.createdAt < rhs.createdAt
            }

        // 1) Backfill versionID on the (at most one) legacy singleton baseline by
        //    binding it to the currently-active version. Pre-V3 only ever stored
        //    one row, so this resolves the "current" baseline owner uniquely.
        if let legacy = try await repository.fetchBaselineSnapshot(),
           legacy.versionID == nil,
           let active = try await repository.fetchActiveFormulaVersion() {
            // Re-key the legacy singleton row to the active version. Bump
            // `frozenAt` so the migrated row sorts newest in subsequent
            // `fetchBaselineSnapshot()` (no-arg, newest-by-frozenAt) reads.
            // The original frozen window/values are preserved.
            var migrated = legacy
            migrated.versionID = active.id
            migrated.frozenAt = Date()
            try await repository.saveBaselineSnapshot(migrated)
        }

        // 2) Emit InterventionWindow rows for every version, idempotently.
        let existingWindows = try await repository.fetchInterventionWindows()
        var windowsByVersion: [UUID: InterventionWindow] = [:]
        for window in existingWindows { windowsByVersion[window.versionID] = window }

        let now = Date()
        for (i, version) in versions.enumerated() {
            let successor = (i + 1 < versions.count) ? versions[i + 1] : nil
            let startedAt = version.shippedOn
            let endedAt: Date?
            let phase: InterventionWindow.Phase
            if let successor {
                endedAt = max(startedAt, successor.shippedOn)
                phase = (version.archivedAt != nil) ? .archived : .superseded
            } else if let archivedAt = version.archivedAt {
                endedAt = max(startedAt, archivedAt)
                phase = .archived
            } else {
                endedAt = nil
                phase = .active
            }

            if let existing = windowsByVersion[version.id] {
                var updated = existing
                updated.startedAt = startedAt
                updated.endedAt = endedAt
                updated.phase = phase
                updated.updatedAt = now
                try await repository.saveInterventionWindow(updated)
            } else {
                let window = InterventionWindow(
                    versionID: version.id,
                    startedAt: startedAt,
                    endedAt: endedAt,
                    phase: phase,
                    createdAt: now,
                    updatedAt: now
                )
                try await repository.saveInterventionWindow(window)
            }
        }
    }
}
