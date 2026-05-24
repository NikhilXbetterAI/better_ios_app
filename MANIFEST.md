# BetterSchemaV3 Implementation Manifest

Goal: introduce `BetterSchemaV3` adding (A) `StoredInterventionWindow` model and (B) `versionID: UUID` field on `ProtocolBaselineSnapshot`. Read-only audit; nothing in this manifest has been edited.

Absolute paths are rooted at `/private/tmp/better-schemav3/`.

---

## 1. Schema files

All versioned schema declarations + the migration plan + container factory live in **one** file:

- `/private/tmp/better-schemav3/Better/Core/Persistence/PersistenceModels.swift`
  - `BetterSchemaV1: VersionedSchema` — declared at **L14–L34** (14 V1 models).
  - `BetterSchemaV2: VersionedSchema` — declared at **L36–L46** (V1 models + 4 Protocol Formula `@Model`s).
  - `BetterMigrationPlan: SchemaMigrationPlan` — declared at **L48–L55**. Currently a single `.lightweight` stage from V1 → V2 (L52–L54).
  - `BetterPersistenceContainerFactory` — **L57–L110**.
    - `currentSchema` at L58 (must be flipped to `BetterSchemaV3`).
    - `makeLiveContainer()` at L67 (uses `BetterMigrationPlan` — no change to wiring needed; just append a stage).
    - `makePreviewContainer()` at L78.
  - `PersistenceJSON.encode/decode` — L112–L136 (encrypted-JSON helper used by every blob field).

No other file declares `VersionedSchema`, `SchemaMigrationPlan`, or registers models in a `ModelContainer` (verified via grep). All `@Model` types listed in `BetterSchemaV2.models` (L39–L44) are defined further down in this same file.

---

## 2. ProtocolFormulaVersion

### Domain type
- `/private/tmp/better-schemav3/Better/Core/Models/ProtocolFormulaModels.swift` — `struct ProtocolFormulaVersion` declared **L25–L84**.
  - Fields (L26–L41): `id: UUID`, `displayLabel: String`, `ordinalLabel: String` (computed at fetch time), `formulaText: String`, `components: [ProtocolFormulaComponent]`, `shippedOn: Date`, `colorHex: String`, `isActive: Bool`, `isImportedPlaceholder: Bool`, `archivedAt: Date?`, `createdAt: Date`, `updatedAt: Date`.
  - `defaultPaletteHexes` palette at L78–L83.

### Persisted row
- `/private/tmp/better-schemav3/Better/Core/Persistence/PersistenceModels.swift` — `@Model StoredProtocolFormulaVersion` **L798–L880**.
  - Stored cols (L800–L813): `id` (unique), `displayLabel`, `ordinalIndex`, `shippedOn`, `colorHex`, `isActive`, `isImportedPlaceholder`, `archivedAt`, `bodyData` (encrypted JSON of `ProtocolFormulaVersionBody { formulaText, components }` — L884–L888), `createdAt`, `updatedAt`.
  - `convenience init(domain:ordinalIndex:)` L841–L861, `toDomain(ordinalLabel:)` L863–L879.

### `shippedOn` write sites (where it gets set)
- `/private/tmp/better-schemav3/Better/Core/Models/ProtocolFormulaModels.swift:62` — initializer assigns `shippedOn`.
- `/private/tmp/better-schemav3/Better/Core/Services/ProtocolAdherenceMigrationService.swift:76` — placeholder migration uses derived legacy start date.
- `/private/tmp/better-schemav3/Better/Core/Services/ProtocolFormulaCatalogService.swift:225` — `upsertVersion(for:shippedOn:)` user-driven seed.
- `/private/tmp/better-schemav3/Better/Core/Services/ProtocolFormulaCatalogService.swift:241–L244` — `seedHistory` uses earliest painted date key.
- `/private/tmp/better-schemav3/Better/Features/ProtocolFormula/Onboarding/ProtocolOnboardingViewModel.swift:45` — `shippedOn: Date()` (note: comment at L37 says fabrication has been removed — but this fallback still exists).
- `/private/tmp/better-schemav3/Better/Features/ProtocolFormula/FormulaSetup/ProtocolFormulaSetupViewModel.swift:52, :65` — setup flow assigns `Date()`.
- `/private/tmp/better-schemav3/Better/Core/Persistence/PersistenceModels.swift:831` (init) and L852 (convenience), L871 (toDomain).

### `shippedOn` read / ordering sites (every site)
- `/private/tmp/better-schemav3/Better/Core/Repositories/LocalDataRepository.swift:539` — `SortDescriptor(\.shippedOn)` when computing `ordinalIndex` on save.
- `/private/tmp/better-schemav3/Better/Core/Repositories/LocalDataRepository.swift:542` — filter `$0.shippedOn <= version.shippedOn`.
- `/private/tmp/better-schemav3/Better/Core/Repositories/LocalDataRepository.swift:591` — primary sort for `fetchAllFormulaVersions`.
- `/private/tmp/better-schemav3/Better/Core/Services/ProtocolFormulaCatalogService.swift:92` — sort `< shippedOn`.
- `/private/tmp/better-schemav3/Better/Core/Services/ProtocolFormulaCatalogService.swift:303` — best-version tiebreak compares `shippedOn`.
- `/private/tmp/better-schemav3/Better/Features/ProtocolFormula/Home/ProtocolFormulaHomeViewModel.swift:175` — derives baseline cutoff: `versions.compactMap({ Self.sleepDateKey(for: $0.shippedOn) }).min()`.
- `/private/tmp/better-schemav3/Better/Features/ProtocolFormula/Home/ProtocolFormulaHomeViewModel.swift:362` — comment: helper that converts `shippedOn` → date key.

---

## 3. ProtocolBaselineSnapshot

### Domain type
- `/private/tmp/better-schemav3/Better/Core/Models/ProtocolFormulaModels.swift` — `struct ProtocolBaselineSnapshot` **L181–L286**.
  - Fields (L182–L210): `id, frozenAt, windowStart, windowEnd, validNightCount`, restorative-sleep means/stds, `continuityCategoryDistribution`, `isInsufficient`, P0-4 extended means/stds (`meanDeepMin … stdSleepScore`).
  - **No** `versionID` field today. (B) adds it here.

### Persisted row
- `/private/tmp/better-schemav3/Better/Core/Persistence/PersistenceModels.swift` — `@Model StoredProtocolBaselineSnapshot` **L1000–L1092**.
  - Stored cols (L1002–L1009): `id` (unique), `frozenAt`, `windowStart`, `windowEnd`, `validNightCount`, `isInsufficient`, `bodyData` (encrypted JSON `ProtocolBaselineSnapshotBody`, L1094–L1114).
  - `init(domain:)` L1029, `toDomain()` L1062.

### Construction sites (`ProtocolBaselineSnapshot(...)` calls)
- `/private/tmp/better-schemav3/Better/Core/Services/ProtocolBaselineService.swift:59–L84` — `freezeBaseline` builds the snapshot (the only production constructor).
- `/private/tmp/better-schemav3/Better/Core/Services/ProtocolBaselineService.swift:111+` — `augmentBaselineWithExtendedMetricsIfNeeded` *mutates* an existing snapshot via `var augmented = existing` (L111) and re-saves.
- Tests:
  - `/private/tmp/better-schemav3/BetterTests/LocalDataRepositoryTests.swift:820–L848` — `static func protocolBaselineSnapshot()` factory.
  - `/private/tmp/better-schemav3/BetterTests/ProtocolFormulaTrackingTests.swift:236–L237` (`makeBaseline()` helper).
  - `/private/tmp/better-schemav3/BetterTests/ProtocolFormulaTrackingTests.swift:540–L554` — explicit construction in augmentation test.
  - `/private/tmp/better-schemav3/BetterTests/ProtocolFormulaCatalogServiceTests.swift:30` — best-version test fixture.

### Read sites
- `/private/tmp/better-schemav3/Better/Core/Repositories/LocalDataRepository.swift:697` — `fetchBaselineSnapshot()` (latest by `frozenAt` desc, `fetchLimit = 1`).
- `/private/tmp/better-schemav3/Better/Core/Services/ProtocolBaselineService.swift:39, :97` — internal reads in freeze + augment.
- `/private/tmp/better-schemav3/Better/Core/Services/ProtocolFormulaAnalysisService.swift:125` — used inside `impactSummary`.
- `/private/tmp/better-schemav3/Better/Core/Services/ProtocolFormulaInsightsService.swift:15` — used inside `insights(for:)`.
- `/private/tmp/better-schemav3/Better/Features/ProtocolFormula/Home/ProtocolFormulaHomeViewModel.swift:168, :177` — Home refresh.
- `/private/tmp/better-schemav3/Better/Features/ProtocolFormula/AllMetrics/ProtocolAllMetricsViewModel.swift:39` — All Metrics reload.
- `/private/tmp/better-schemav3/Better/Features/ProtocolFormula/VersionDive/ProtocolVersionDiveViewModel.swift:36` — Version Dive reload.
- `/private/tmp/better-schemav3/Better/Features/ProtocolFormula/Timeline/ProtocolTimelineViewModel.swift:58` — Timeline reload.

### Singleton / cardinality
- **YES, currently a singleton** (one row).
  - `LocalDataRepository.saveBaselineSnapshot` (`/private/tmp/better-schemav3/Better/Core/Repositories/LocalDataRepository.swift:685–L695`) explicitly deletes every existing row before inserting. Inline comment at L689: *"Only one baseline row is ever persisted — replace any existing."*
  - `fetchBaselineSnapshot` (L697–L703) sorts by `frozenAt` desc and applies `fetchLimit = 1`.
  - Repository protocol method is parameterless: `func fetchBaselineSnapshot() async throws -> ProtocolBaselineSnapshot?` (`RepositoryProtocols.swift:95`).

---

## 4. Persistence

### Models registered in `ModelContainer`
- `/private/tmp/better-schemav3/Better/Core/Persistence/PersistenceModels.swift:38–L45` — `BetterSchemaV2.models` is the registered schema list.
  - V1 (14 models) + `StoredProtocolFormulaVersion`, `StoredProtocolNightLog`, `StoredProtocolLogEdit`, `StoredProtocolBaselineSnapshot`.
  - For V3 the new `StoredInterventionWindow` must be appended.

### `LocalDataRepository` — Protocol Formula touch points
File: `/private/tmp/better-schemav3/Better/Core/Repositories/LocalDataRepository.swift`

ProtocolFormulaVersion:
- `saveFormulaVersion` — **L525–L587** (ordinal compute, immutability rule, active-singleton enforcement, upsert).
- `fetchAllFormulaVersions` — **L589–L597**.
- `fetchActiveFormulaVersion` — **L599–L604**.
- `fetchFormulaVersion(id:)` — **L606–L609**.
- `archiveFormulaVersion(id:)` — **L611–L621**.
- `deleteFormulaVersion(id:)` — **L623–~L630**.
- `pruneDataOlderThan` does **not** delete versions (only night logs at L732, log edits at L735).
- `deleteAllHealthData` deletes versions at **L761** and snapshots at **L764**.
- `migrateToEncryptedStorage` re-encodes versions at **L824–L827** and snapshots at **L835–L837**.
- `fetchDataInventory` counts versions/snapshots at **L877, L880**.

ProtocolBaselineSnapshot:
- `saveBaselineSnapshot` — **L685–L695** (asserts `validNightCount > 0`; deletes any existing row).
- `fetchBaselineSnapshot` — **L697–L703**.

Repository protocol: `/private/tmp/better-schemav3/Better/Core/Repositories/RepositoryProtocols.swift:79–L95` (real methods) and L216–L229 (default no-op extensions for mocks).

---

## 5. Services that consume baselines/versions

### `ProtocolBaselineService`
File: `/private/tmp/better-schemav3/Better/Core/Services/ProtocolBaselineService.swift`
- L20–L22 — constants `windowDays = 90`, `maxNights = 30`, `sufficiencyThreshold = 7`.
- L38 `freezeBaseline(beforeSleepDateKey:force:)` — Returns existing snapshot (L39) unless `force`. Builds a single snapshot from sessions ≤ cutoff and saves it at L85.
- L96 `augmentBaselineWithExtendedMetricsIfNeeded()` — Re-fetches sessions in original window, fills nil extended-metric fields without overwriting existing values, saves at L124.
- L141 `metrics(for:)` — pure stage extraction.
- L169/L176 `mean` / `standardDeviation` (also called from `ProtocolFormulaAnalysisService`).
- L183 `continuityDistribution(for:)`.

### `ProtocolFormulaAnalysisService.rollups`
File: `/private/tmp/better-schemav3/Better/Core/Services/ProtocolFormulaAnalysisService.swift`
- L23 `static snapshot(for:log:)` — pure per-night composition (uses `log?.versionID` at L40).
- L59 `rollups(in:)` — fetches sessions + logs in range, **groups by `log.versionID`** (L73). Result is per-version. Already version-aware.
- L124 `impactSummary(versionID:in:)` — fetches global singleton baseline (L125) and selects matching rollup (L127). **This is the call site that will need to load the per-version baseline once (B) lands.**
- L195 `AdherenceRollup` and `adherenceRollups(in:)` (L204) — also keyed by `log.versionID`.
- L218 `allRollups()` — convenience wrapper for `Date.distantPast...distantFuture`.

### Other services reading the singleton baseline
- `/private/tmp/better-schemav3/Better/Core/Services/ProtocolFormulaInsightsService.swift:15` — fetches the single baseline; compares each version's rollup against it (L45+, L61+).
- `/private/tmp/better-schemav3/Better/Core/Services/ProtocolFormulaCatalogService.swift:270–L303` — `bestVersion(versions:rollups:baseline:)` accepts the singleton baseline as parameter; consumers above pass the singleton.
- `/private/tmp/better-schemav3/Better/Core/Services/ResearchAnalysisService.swift:47` — only reads `fetchAllFormulaVersions` (does **not** touch baseline snapshots).

---

## 6. UI consumers

### `ProtocolFormulaHomeViewModel`
File: `/private/tmp/better-schemav3/Better/Features/ProtocolFormula/Home/ProtocolFormulaHomeViewModel.swift`
- L161 — `versions = try await catalogService.ensureCatalogVersions()`.
- L162 — selects active version.
- L168 — `baseline = try await localRepository.fetchBaselineSnapshot()`.
- L175–L177 — lazy-freeze fallback using `versions.compactMap({ Self.sleepDateKey(for: $0.shippedOn) }).min()` → calls `baselineService.freezeBaseline` then re-fetches.
- L200 — `analysisService.impactSummary(versionID: active.id, in: Date.distantPast...now)`.
- L207 — `analysisService.allRollups()`.
- L208–L212 — `bestVersion(versions:rollups:baseline:)`.

### `ProtocolVersionDiveViewModel`
File: `/private/tmp/better-schemav3/Better/Features/ProtocolFormula/VersionDive/ProtocolVersionDiveViewModel.swift`
- L31 — versions via `catalogService.ensureCatalogVersions()`.
- L36 — `baseline = try await repository.fetchBaselineSnapshot()`.
- L37 — `rollups = try await analysisService.allRollups()`.
- L48 — `selectedRollup = rollups.first { $0.versionID == selectedVersionID }`.
- L58–L75 — `restorativeComparison`/`comparison(for:)` use the singleton `baseline`.

### `ProtocolAllMetricsViewModel`
File: `/private/tmp/better-schemav3/Better/Features/ProtocolFormula/AllMetrics/ProtocolAllMetricsViewModel.swift`
- L38 — versions.
- L39 — `baseline = try await repository.fetchBaselineSnapshot()`.
- L42 — rollups.
- L43 — nightly snapshots.
- L70 — `baselineValue` returns `activeMetric.baselineValue(from:)` keyed off the singleton baseline.

(Also for completeness: `ProtocolTimelineViewModel.swift:58` reads the baseline; `ProtocolFormulaSetupViewModel.swift:75` writes a version; `ProtocolOnboardingViewModel.swift:146` calls `freezeBaseline`.)

---

## 7. Tests

Mock used: `MockLocalDataRepository` lives at `/private/tmp/better-schemav3/Better/Core/Repositories/MockLocalDataRepository.swift` (under `Better/`, not under `BetterTests/`). It does **not** implement Protocol Formula methods; it relies on the protocol-extension no-op defaults at `RepositoryProtocols.swift:216–L229`. Only Sleep / activity / sleep-mode / context-entry methods are exercised.

Tests dedicated to Protocol Formula use a private actor `ProtocolFormulaMemoryRepo` defined inline at `/private/tmp/better-schemav3/BetterTests/ProtocolFormulaTrackingTests.swift:17–L213`. This actor has real Protocol Formula state and full ordering semantics. The new V3 fields will need to be added here (see (8)).

### Existing tests — methods that touch versions or baseline snapshots

`/private/tmp/better-schemav3/BetterTests/ProtocolFormulaTrackingTests.swift`:
- `formulaVersions` store at L26, `baseline` at L29.
- Mock methods saving/fetching: L65 `saveFormulaVersion`, L73 `fetchAllFormulaVersions`, L76 `fetchActiveFormulaVersion`, L79 `fetchFormulaVersion`, L80 `archiveFormulaVersion`, L84 `deleteFormulaVersion`, L108 `saveBaselineSnapshot`, L112 `fetchBaselineSnapshot`.
- `makeVersion` at L216, `makeBaseline` at L236.
- Tests that exercise versions/baselines: L371, L394, L425, L455, L468, L480, L492, L502, L518 (`testAugmentBaselineWithExtendedMetrics_preservesExistingBaselineFields`), L574 (`testFreezeBaseline_force_recomputesSnapshot`), L596, L645, L670, L697, L727, L751, L773, L796, L801, L831, L869, L881 (`testRunIfNeeded_idempotencyFlag_preventsSecondRun`), L892, L909 (`testInsights_noBaseline_returnsBaselineUnavailable`), L919, L933, L952, L979, L992.

`/private/tmp/better-schemav3/BetterTests/LocalDataRepositoryTests.swift`:
- L158 `testLocalRepositoryPersistsProtocolBaselineSnapshotExtendedMetrics`.
- L183 `testLocalRepositoryDecodesLegacyProtocolBaselineSnapshotBody` — directly inserts a `StoredProtocolBaselineSnapshot` with a legacy body shape (L195).
- L820 helper `protocolBaselineSnapshot()`.
- L891 `LegacyProtocolBaselineSnapshotBody` — the legacy decode-fallback fixture (will need to verify after V3 change.)

`/private/tmp/better-schemav3/BetterTests/ProtocolFormulaCatalogServiceTests.swift`:
- L30 builds a `ProtocolBaselineSnapshot` for `bestVersion` tests.
- L65 `version(label:shippedOn:)` factory.

`/private/tmp/better-schemav3/BetterTests/ResearchAnalysisServiceTests.swift` — uses `MockLocalDataRepository` only; does not hit baselines/versions directly (verified — no `fetchBaselineSnapshot` or `formulaVersions` references).

---

## 8. Migration plan sketch (BetterSchemaV3)

Update `/private/tmp/better-schemav3/Better/Core/Persistence/PersistenceModels.swift`:

1. Add new model `StoredInterventionWindow` (mirrors domain `StoredInterventionWindow { id: UUID, versionID: UUID, startedAt: Date, endedAt: Date?, phase: Phase }`). `phase` likely stored as `phaseRawValue: String` for SwiftData compatibility (consistent with the rest of this file's pattern; see e.g. `StoredAlert.kindRawValue` at L550).
2. Add `versionID: UUID` field to `StoredProtocolBaselineSnapshot` (new column — V2's row had no version association). Update `init(domain:)` (L1029) and `toDomain()` (L1062) to round-trip it. Update domain `ProtocolBaselineSnapshot` in `ProtocolFormulaModels.swift:181–L286` accordingly.
3. Append `BetterSchemaV3: VersionedSchema` containing V2 models + the new `StoredInterventionWindow` and the *modified* `StoredProtocolBaselineSnapshot`. The modified snapshot type forces the stage to be **custom**, not `.lightweight`.
4. Append a `MigrationStage.custom(fromVersion: BetterSchemaV2.self, toVersion: BetterSchemaV3.self, willMigrate:didMigrate:)` to `BetterMigrationPlan.stages` (L52).
5. Flip `BetterPersistenceContainerFactory.currentSchema` (L58) to `BetterSchemaV3`.

### `willMigrate` / `didMigrate` operations (plain English)

`willMigrate`:
- *(no-op recommended)*. SwiftData's custom-migration semantics let us do all transformation work in `didMigrate` once both schemas are in scope. We don't need to read pre-migration encrypted blobs because the snapshot's `bodyData` shape is unchanged — only a new top-level column is added.

`didMigrate(context:)`:
1. **(A) Synthesize one `StoredInterventionWindow` per existing version.**
   - Fetch all V2 versions sorted by `(shippedOn ASC, createdAt ASC)` (matches the existing read order in `LocalDataRepository.fetchAllFormulaVersions:591`).
   - For each version `v[i]` with the sorted list `v[0..n)`:
     - Insert `StoredInterventionWindow(id: UUID(), versionID: v[i].id, startedAt: v[i].shippedOn, endedAt: i+1 < n ? v[i+1].shippedOn : nil, phase: .intervention)`.
   - Note: the spec says "one .intervention window per existing ProtocolFormulaVersion" — archived/imported-placeholder versions are still iterated (they have `shippedOn`); confirm with product whether `archivedAt != nil` should be skipped or get a closed window with `endedAt = archivedAt`. Current spec language: every existing version gets one window — implement literally.

2. **(B) Backfill `versionID` on the singleton `StoredProtocolBaselineSnapshot`.**
   - Fetch all baseline snapshot rows (cardinality is ≤ 1 in practice — see §3 singleton invariant — but iterate defensively).
   - Compute oldest version: same sort as above, take `first`.
   - If oldest exists, set `snapshot.versionID = oldest.id` for each existing snapshot row; otherwise the snapshot is orphaned (very rare — possible only if a baseline exists with zero versions, which the freeze flow does not produce). Recommended fallback: leave the row but assign `UUID()` and log; or delete orphans. Choose deletion for simplicity (the freeze flow rebuilds snapshots).
   - `try context.save()`.

### Encrypted-JSON column shape changes

- `StoredProtocolBaselineSnapshot.bodyData` (`PersistenceModels.swift:1009`, body struct `ProtocolBaselineSnapshotBody` L1094–L1114): **no change**. The new `versionID` is added as a SwiftData column, NOT into the JSON body. This avoids touching `PersistenceJSON.encode/decode` paths and preserves the legacy-decode fallback test at `LocalDataRepositoryTests.swift:183`.
- `StoredProtocolFormulaVersion.bodyData` (L811, body struct L884–L888): no change.
- `StoredProtocolNightLog.bodyData` (L901): no change.
- `StoredInterventionWindow`: phase is stored as a raw-valued string column; no JSON blob needed (small fixed schema).

If a future PR moves any of these fields *out of* the JSON blob, that is a separate, additive concern — not required for V3.

### Code surface that must change (besides PersistenceModels.swift)

- `RepositoryProtocols.swift:94–L95` — likely add `fetchBaselineSnapshot(versionID:)` and keep the singleton method as a convenience that returns "current version's snapshot". Update default no-op extension at L228–L229.
- `LocalDataRepository.swift:685–L703` — `saveBaselineSnapshot` must NOT delete all rows (since baselines are now per-version). Replace the "delete all then insert" with upsert keyed by `versionID`. `fetchBaselineSnapshot` needs a version-keyed variant.
- `ProtocolBaselineService.swift:38, :85, :96, :124` — freeze is called per version transition; existing-snapshot reuse check at L39 must compare `versionID` not just existence.
- `ProtocolFormulaAnalysisService.impactSummary` (L125) — load the per-version baseline.
- `ProtocolFormulaInsightsService.swift:15` — same.
- `ProtocolFormulaHomeViewModel:168/L177`, `ProtocolVersionDiveViewModel:36`, `ProtocolAllMetricsViewModel:39`, `ProtocolTimelineViewModel:58` — switch to per-version fetch.
- New service or extension to register a `StoredInterventionWindow` whenever a new `ProtocolFormulaVersion` is saved (write-time), to keep windows in sync after migration.
- `LocalDataRepository.deleteAllHealthData` (L749+) and `migrateToEncryptedStorage` (L820+) and `fetchDataInventory` (L876+) — add the new `StoredInterventionWindow` table.
- Tests in §7 — add `versionID` to `makeBaseline`/`protocolBaselineSnapshot()` factories and `LegacyProtocolBaselineSnapshotBody` decode test (which still must succeed: legacy rows have no `versionID` column post-migration unless migration ran — guarantee via a test that boots a V2 store, runs migration, and asserts `versionID == oldest.id`).

---

## 9. Risk flags

### Code that assumes a singleton baseline (`.first`, `fetchLimit = 1`, count==1)
- `/private/tmp/better-schemav3/Better/Core/Repositories/LocalDataRepository.swift:685–L695` — `saveBaselineSnapshot` deletes every existing row then inserts. **Will silently wipe other versions' baselines after V3 if not changed.** Highest-risk site.
- `/private/tmp/better-schemav3/Better/Core/Repositories/LocalDataRepository.swift:701` — `descriptor.fetchLimit = 1` in `fetchBaselineSnapshot`.
- `/private/tmp/better-schemav3/Better/Core/Repositories/RepositoryProtocols.swift:95` — protocol method has no `versionID` parameter.
- `/private/tmp/better-schemav3/Better/Core/Services/ProtocolBaselineService.swift:39` — `if !force, let existing = …` short-circuits on *any* baseline; will skip per-version freeze on V3.
- `/private/tmp/better-schemav3/Better/Core/Services/ProtocolBaselineService.swift:97` — `augmentBaselineWithExtendedMetricsIfNeeded` mutates the global singleton; needs to iterate per version.
- `/private/tmp/better-schemav3/Better/Core/Services/ProtocolFormulaAnalysisService.swift:125` — `impactSummary` consumes one global baseline.
- `/private/tmp/better-schemav3/Better/Core/Services/ProtocolFormulaInsightsService.swift:15` — single baseline used for *every* version's insight.
- `/private/tmp/better-schemav3/Better/Core/Services/ProtocolFormulaCatalogService.swift:270` — `bestVersion(versions:rollups:baseline:)` takes one baseline; needs a baseline-by-versionID map.
- `/private/tmp/better-schemav3/Better/Features/ProtocolFormula/Home/ProtocolFormulaHomeViewModel.swift:168, :177, :211` — single baseline value passed into `bestVersion`.
- `/private/tmp/better-schemav3/Better/Features/ProtocolFormula/AllMetrics/ProtocolAllMetricsViewModel.swift:39, :47, :70` — single baseline value drives every chart line.
- `/private/tmp/better-schemav3/Better/Features/ProtocolFormula/VersionDive/ProtocolVersionDiveViewModel.swift:36, :59, :63, :73` — single baseline used for comparison bars.
- `/private/tmp/better-schemav3/Better/Features/ProtocolFormula/Timeline/ProtocolTimelineViewModel.swift:58, :92, :112` — single baseline gates "best lift" tile.
- `/private/tmp/better-schemav3/Better/Core/Repositories/RepositoryProtocols.swift:134, :154, :173` — `LocalDataInventory.protocolBaselineSnapshotCount` exposes a count that consumers may have implicitly assumed is 0/1.

### Code that reads `ProtocolFormulaVersion.shippedOn` ordering — could break with windows
- `/private/tmp/better-schemav3/Better/Core/Repositories/LocalDataRepository.swift:539, :542` — ordinal index derives from `shippedOn` ordering; identical `shippedOn` collisions are tolerated only because `<= shippedOn` count is used. With windows, identical timestamps risk overlapping windows.
- `/private/tmp/better-schemav3/Better/Core/Repositories/LocalDataRepository.swift:591` — primary sort uses `shippedOn` then `createdAt`; the migration must use this **same secondary key** when generating `endedAt` so two versions shipped on the same day still produce non-overlapping windows.
- `/private/tmp/better-schemav3/Better/Core/Services/ProtocolFormulaCatalogService.swift:92, :303` — sort/tiebreak on `shippedOn` (must reconcile with window-derived ordering once windows exist).
- `/private/tmp/better-schemav3/Better/Features/ProtocolFormula/Home/ProtocolFormulaHomeViewModel.swift:175` — earliest `shippedOn` is treated as the *protocol-tracking start* for baseline cutoff. With explicit intervention windows, this should derive from the oldest window's `startedAt` instead.
- `/private/tmp/better-schemav3/Better/Core/Services/ProtocolAdherenceMigrationService.swift:76, :110–L118` — legacy migration path also infers a "start date" that, post-V3, should be the placeholder version's *intervention window* start.
- `/private/tmp/better-schemav3/Better/Features/ProtocolFormula/Onboarding/ProtocolOnboardingViewModel.swift:45` — onboarding default `shippedOn: Date()` will create a V3 window with `endedAt = nil` if a previous version exists with a *later* `shippedOn` — the migration logic must handle "incoming new version with `shippedOn < latest`" (closes the previous window retroactively, which `saveFormulaVersion` does not currently do).

### Other notable risks
- The legacy-decode test (`LocalDataRepositoryTests.swift:183`) directly constructs a V2 `StoredProtocolBaselineSnapshot` using its current init signature. After (B), this fixture must include `versionID:` (or the test must use a SQLite store snapshotted at V2 + run migration).
- `ProtocolBaselineSnapshot` is `Codable` (JSON-encoded into `bodyData` after V3 changes too). Adding `versionID` only to the SwiftData column (and not to the body struct) keeps wire compatibility and avoids the `PersistenceJSON.decode` fallback path needing a default. This is the recommended path.
- `ProtocolFormulaCatalogService.upsertVersion` (L196) does not currently emit an intervention window. Post-V3, version save and window creation must be transactional or there will be drift.
- The V2 schema declaration explicitly forbids mutation: header comment at `PersistenceModels.swift:11–L12` — *"Never mutate `BetterSchemaV1` / `BetterSchemaV2` after they ship."* The new column on `StoredProtocolBaselineSnapshot` therefore must live on the V3 copy of the type. This requires SwiftData's ability to reference both versions of the same `@Model` class — which in practice means defining the model once and using migration stages to bridge. Confirm via Apple's `VersionedSchema` docs whether the V2 declaration still type-checks against the *same* class reference; if not, the V3 work needs separate `StoredProtocolBaselineSnapshotV2` / `StoredProtocolBaselineSnapshotV3` shadow types — a meaningful scope expansion.

