import Foundation

/// One-shot migration from legacy `ProtocolAdherence` rows to the new
/// `ProtocolFormulaVersion` + `ProtocolNightLog` model.
///
/// Trigger criteria (all must hold) — checked by `runIfNeeded`:
///   1. Schema V2 is online (always true once this build ships).
///   2. No `ProtocolFormulaVersion` rows exist.
///   3. At least one `ProtocolAdherence` row exists.
///   4. The `UserDefaults` idempotency flag is unset.
///
/// What it does:
///   - Derives a start date (UserDefaults override → earliest `taken == true` row →
///     `nil`, in which case onboarding will be responsible for asking the user).
///   - Creates exactly one V1 `ProtocolFormulaVersion` with `isImportedPlaceholder = true`
///     and empty `formulaText` so the user can backfill once (see immutability exception
///     in `LocalDataRepository.saveFormulaVersion`).
///   - Collapses legacy `(protocolID, dateKey)` pairs to one `ProtocolNightLog` per
///     `sleepDateKey`. Rule: any `taken == true` for that dateKey → `.taken`; else any
///     `taken == false` → `.skipped`; absent → no row (= `.unknown`).
///   - Stamps every emitted log with `formulaSnapshotHash = "imported-placeholder"`.
///   - Attempts to freeze the baseline via `ProtocolBaselineService`.
///   - Sets the idempotency flag so it never runs again.
@MainActor
final class ProtocolAdherenceMigrationService {
    static let idempotencyKey = "better.protocol.formulaTracking.migrationCompleted"
    static let legacyStartDateKey = "better.protocol.startDate"

    private let repository: LocalDataRepositoryProtocol
    private let baselineService: ProtocolBaselineService
    private let userDefaults: UserDefaults

    init(
        repository: LocalDataRepositoryProtocol,
        baselineService: ProtocolBaselineService? = nil,
        userDefaults: UserDefaults = .standard
    ) {
        self.repository = repository
        self.baselineService = baselineService ?? ProtocolBaselineService(repository: repository)
        self.userDefaults = userDefaults
    }

    /// Returns `true` if the migration ran on this call, `false` if it was skipped.
    @discardableResult
    func runIfNeeded(referenceDate: Date = Date()) async throws -> Bool {
        guard !userDefaults.bool(forKey: Self.idempotencyKey) else { return false }

        if !(try await repository.fetchAllFormulaVersions()).isEmpty {
            // V1 has already been created (e.g. via onboarding) — no migration needed.
            userDefaults.set(true, forKey: Self.idempotencyKey)
            return false
        }

        let legacyRange = DateInterval(
            start: Date(timeIntervalSince1970: 0),
            end: referenceDate.addingTimeInterval(86_400)
        )
        let legacy = try await repository.fetchAdherence(from: legacyRange.start, to: legacyRange.end)
        guard !legacy.isEmpty else {
            // No legacy data → nothing to migrate. Flag so we don't re-check every launch.
            userDefaults.set(true, forKey: Self.idempotencyKey)
            return false
        }

        let derivedStart = deriveStartDate(legacy: legacy)
        guard let startDate = derivedStart else {
            // Can't determine a start date without user input — let onboarding handle this.
            return false
        }

        let placeholderVersion = ProtocolFormulaVersion(
            displayLabel: "",
            ordinalLabel: "V1",
            formulaText: "",
            components: [],
            shippedOn: startDate,
            colorHex: ProtocolFormulaVersion.defaultPaletteHexes[0],
            isActive: true,
            isImportedPlaceholder: true
        )
        try await repository.saveFormulaVersion(placeholderVersion)

        // Group legacy rows by dateKey → emit one ProtocolNightLog per date.
        let grouped = Dictionary(grouping: legacy, by: { $0.dateKey })
        for (dateKey, rows) in grouped {
            let status: ProtocolFormulaNightStatus
            let takenAt: Date?
            let firstTaken = rows.first(where: { $0.taken })
            if let firstTaken {
                status = .taken
                takenAt = firstTaken.takenAt
            } else if rows.contains(where: { !$0.taken }) {
                status = .skipped
                takenAt = nil
            } else {
                continue
            }
            let log = ProtocolNightLog(
                sleepDateKey: dateKey,
                versionID: placeholderVersion.id,
                status: status,
                addins: [],
                takenAt: takenAt,
                note: nil,
                formulaSnapshotHash: ProtocolNightLog.importedPlaceholderHash
            )
            try await repository.saveNightLog(log)
        }

        // Earliest taken dateKey in legacy data is the exclusive upper bound — any
        // session whose sleepDateKey is < this key predates the protocol and contributes
        // to baseline. The legacy `dateKey` is already a `YYYY-MM-DD` sleep key.
        let cutoffKey: String
        if let firstTakenKey = legacy.filter({ $0.taken }).map(\.dateKey).min() {
            cutoffKey = firstTakenKey
        } else {
            cutoffKey = SleepDateKey.calendarDateKey(for: startDate)
        }
        _ = try await baselineService.freezeBaseline(beforeSleepDateKey: cutoffKey)
        userDefaults.set(true, forKey: Self.idempotencyKey)
        return true
    }

    private func deriveStartDate(legacy: [ProtocolAdherence]) -> Date? {
        if let stored = userDefaults.object(forKey: Self.legacyStartDateKey) as? Date {
            return stored
        }
        let takenRows = legacy.filter { $0.taken }.sorted(by: { $0.dateKey < $1.dateKey })
        if let earliest = takenRows.first {
            return Self.date(forDateKey: earliest.dateKey)
        }
        return nil
    }

    private static func date(forDateKey key: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: key)
    }
}
