# Protocol Formula Tracking v3 — Implementation Document

End-to-end log of what shipped across Phases 0–5, where each piece lives, and how each part hangs together. Use this when picking up the feature later — it maps every requirement from the original plan to the file (and line, where useful) that fulfills it.

Companion docs:
- [Plan](/Users/nikhilkhatale/.claude/plans/you-are-working-in-delightful-adleman.md) — original Protocol Formula v3 plan (V1 scope + Phase deferrals)
- [APP_ARCHITECTURE.md](APP_ARCHITECTURE.md) §7b — high-level Protocol Formula Tracking architecture
- [CLAUDE.md](CLAUDE.md) — invariant #11 (Protocol Formula rules)
- JSX UI spec: `Sleep Dashbooard (4)/protocol-v3-core.jsx`, `protocol-v3-home.jsx`, `protocol-v3-screens.jsx`

---

## Phase 0 — Docs sync

Updated existing docs to capture the locked invariants. No code changes.

| What | Where |
|------|-------|
| Protocol Formula Tracking architecture section | [APP_ARCHITECTURE.md](APP_ARCHITECTURE.md) §7b |
| Invariant #11 (reuse restorative APIs, formulaText immutability, frozen baseline, no silent wipe, restorative % null without stage detail) | [CLAUDE.md](CLAUDE.md) |

---

## Phase 1 — Data layer & safer migration

### Domain models — [`Better/Core/Models/ProtocolFormulaModels.swift`](Better/Core/Models/ProtocolFormulaModels.swift)

All value types are `nonisolated`, `Codable`, `Sendable`.

| Type | Purpose |
|------|---------|
| `ProtocolFormulaComponent` | A base or add-in ingredient (`name`, `dose`, `role`). |
| `ProtocolFormulaVersion` | A named formula (V1, V2…). `displayLabel` + derived `ordinalLabel`, `formulaText`, `components`, `shippedOn`, `colorHex`, `isActive`, `isImportedPlaceholder`, `archivedAt`. |
| `ProtocolFormulaNightStatus` | `.taken` / `.skipped` (displays as "Didn't take") / `.unknown` (no row). |
| `ProtocolNightLog` | One row per `sleepDateKey`. Carries `versionID` (non-nil for taken/skipped), `status`, `addins`, `takenAt`, `note`, `formulaSnapshotHash`. Sentinel `importedPlaceholderHash`. |
| `ProtocolLogEdit` | Append-only audit row (`beforeData`, `afterData` JSON blobs, `editedAt`). |
| `ProtocolBaselineSnapshot` | Frozen baseline: window range, valid night count, mean/std for restorative min/pct/longest block, continuity distribution, `isInsufficient`. |
| `ProtocolNightMetricSnapshot` | In-memory per-night metric composition (no DB row). |
| `ProtocolVersionRollup` | In-memory per-version aggregate (mean/std, distribution). |
| `ProtocolImpactSummary` | Version-vs-baseline deltas + `static causalityCaveat`. |
| `ProtocolFormulaInsight` / `Kind` | Phase 4 — narrative insight cards. |
| `ProtocolFormulaHashing` | SHA-256 of normalized formula text + sorted components for drift detection. |

### Persistence (SwiftData) — [`Better/Core/Persistence/PersistenceModels.swift`](Better/Core/Persistence/PersistenceModels.swift)

- `BetterSchemaV1: VersionedSchema` — the original 14 `@Model` classes
- `BetterSchemaV2: VersionedSchema` — V1 + 4 new tables
- `BetterMigrationPlan: SchemaMigrationPlan` with one `.lightweight` stage
- **No silent wipe**: `makeLiveContainer` no longer catches and deletes store files. Migration failures now propagate — recovery is manual via Settings.
- New `@Model` classes (encrypted blob bodies via `PersistenceJSON`):
  - `StoredProtocolFormulaVersion`
  - `StoredProtocolNightLog` (query keys: `sleepDateKey`, `versionIDString`)
  - `StoredProtocolLogEdit`
  - `StoredProtocolBaselineSnapshot` (singleton via `@Attribute(.unique) id`)

### Repository surface

- Protocol: [`Better/Core/Repositories/RepositoryProtocols.swift`](Better/Core/Repositories/RepositoryProtocols.swift)
  - New formula/log/edit/baseline CRUD methods on `LocalDataRepositoryProtocol`
  - `LocalDataInventory` extended with 4 new counts
  - `ProtocolFormulaRepositoryError` enum (`.formulaTextLocked`, `.baselineSnapshotEmpty`)
  - Default no-op extensions so `MockLocalDataRepository` compiles unchanged

- Implementation: [`Better/Core/Repositories/LocalDataRepository.swift`](Better/Core/Repositories/LocalDataRepository.swift)
  - `saveFormulaVersion` enforces: active-singleton, immutability (compares decoded body), placeholder backfill exception
  - `pruneDataOlderThan` covers `ProtocolNightLog` / `ProtocolLogEdit` by `sleepDateKey`
  - `deleteAllHealthData` deletes the 4 new model types
  - `fetchDataInventory` populates the 4 new counts
  - `migrateToEncryptedStorage` re-encodes the 3 blob types

### Services

| Service | File | Responsibility |
|---------|------|----------------|
| `ProtocolBaselineService` | [`Better/Core/Services/ProtocolBaselineService.swift`](Better/Core/Services/ProtocolBaselineService.swift) | Freezes baseline once: window = 90 days before cutoff, max 30 nights, filters to `.detailedStages`/`.mixedSources`. `isInsufficient` when <7 nights. Returns `nil` (no row) at 0 nights. |
| `ProtocolAdherenceMigrationService` | [`Better/Core/Services/ProtocolAdherenceMigrationService.swift`](Better/Core/Services/ProtocolAdherenceMigrationService.swift) | One-shot legacy → formula tracking migration. Idempotency key `better.protocol.formulaTracking.migrationCompleted`. Creates placeholder V1, collapses `(protocolID, dateKey)` → one log per `dateKey` (any-taken → `.taken`, else `.skipped`), then freezes baseline. |

### App wiring

- [`Better/App/AppEnvironment.swift`](Better/App/AppEnvironment.swift) — `runProtocolFormulaMigrationIfNeeded()` constructs the migration service and ignores errors (idempotent)
- [`Better/App/RootTabView.swift`](Better/App/RootTabView.swift) — `.task { await environment.runProtocolFormulaMigrationIfNeeded() }` on startup; Protocol tab gated by `ProtocolFormulaFlag.isEnabled()` (default off)

---

## Phase 2 — Analysis service

- [`Better/Core/Services/ProtocolFormulaAnalysisService.swift`](Better/Core/Services/ProtocolFormulaAnalysisService.swift)

| Method | Behavior |
|--------|----------|
| `static snapshot(for:log:)` | Pure function. Reads `session.restorativeSleepDuration / 60` (min), `restorativeSleepDuration / totalInBedTime * 100` (%), `continuitySummary.longestBlockDuration / 60` (min), and `continuitySummary.continuityCategory`. All **nil** unless `dataQuality ∈ {.detailedStages, .mixedSources}`. **No new math** beyond the percent ratio. |
| `rollups(in:)` | Groups snapshots by `versionID`. Mean/std for each non-nil field. Continuity distribution as fractions. Excludes nights with no log. |
| `impactSummary(versionID:in:)` | Deltas vs frozen baseline. `isLowData = nightCount < 3`. Caller renders `ProtocolImpactSummary.causalityCaveat`. |
| `nightlySnapshots(in:)` *(Phase 4)* | Per-night sorted list for charting. |
| `allRollups()` *(Phase 4)* | All-time rollups convenience. |

---

## Phase 3 — V1 UI behind feature flag

**Feature flag:** `better.protocol.useFormulaTrackingUI` (`UserDefaults`, default `false`).

| What | Where |
|------|-------|
| Feature-flag storage | [`Better/Features/ProtocolFormula/ProtocolFormulaFlag.swift`](Better/Features/ProtocolFormula/ProtocolFormulaFlag.swift) |
| Settings toggle | [`Better/Features/Settings/ProtocolFormulaFeatureFlagCard.swift`](Better/Features/Settings/ProtocolFormulaFeatureFlagCard.swift), wired into [`SettingsTabView.swift`](Better/Features/Settings/SettingsTabView.swift) |
| Tab gating | [`Better/App/RootTabView.swift`](Better/App/RootTabView.swift) — flag on → `ProtocolFormulaTabView`; flag off → legacy `ProtocolTabView` |
| Shell + navigation | [`Better/Features/ProtocolFormula/ProtocolFormulaTabView.swift`](Better/Features/ProtocolFormula/ProtocolFormulaTabView.swift) — checks for any existing version → shows onboarding if none; ellipsis menu opens Formula setup / Edit log / Timeline / All metrics / Version dive |

### Reusable atoms — [`Better/Features/ProtocolFormula/Components/`](Better/Features/ProtocolFormula/Components/)

| File | What it renders |
|------|-----------------|
| `ProtocolPalette.swift` | `versionColor(hex:)` (delegates to existing `Color(hex:)`), `addinColor`, `goodColor`, `badColor`, `mutedText`, `dimText` |
| `ProtocolFormulaAtoms.swift` | `VersionChip`, `DeltaBadge`, `ObservedNotCausalCaption`, `LowDataBanner`, `ContinuityBadge`, `RestorativeMetricCard`, `LongestRestorativeBlockCard`, `EditAffordance` |

### Screens

| Screen | ViewModel | View |
|--------|-----------|------|
| **Home** — segmented Last night / Tonight, impact summary, tonight CTA, no-formula card | [`Home/ProtocolFormulaHomeViewModel.swift`](Better/Features/ProtocolFormula/Home/ProtocolFormulaHomeViewModel.swift) | [`Home/ProtocolFormulaHomeView.swift`](Better/Features/ProtocolFormula/Home/ProtocolFormulaHomeView.swift) |
| **Formula setup** — list, lock state, "Make a new version" / "Edit", editor sheet | [`FormulaSetup/ProtocolFormulaSetupViewModel.swift`](Better/Features/ProtocolFormula/FormulaSetup/ProtocolFormulaSetupViewModel.swift) | [`FormulaSetup/ProtocolFormulaSetupView.swift`](Better/Features/ProtocolFormula/FormulaSetup/ProtocolFormulaSetupView.swift) |
| **Edit log** — calendar grid, per-day editor, append-only audit | [`EditLog/ProtocolEditLogViewModel.swift`](Better/Features/ProtocolFormula/EditLog/ProtocolEditLogViewModel.swift) | [`EditLog/ProtocolEditLogView.swift`](Better/Features/ProtocolFormula/EditLog/ProtocolEditLogView.swift) |
| **Onboarding** — 3-step intro, seeds first version + freezes baseline | [`Onboarding/ProtocolOnboardingViewModel.swift`](Better/Features/ProtocolFormula/Onboarding/ProtocolOnboardingViewModel.swift) | [`Onboarding/ProtocolOnboardingView.swift`](Better/Features/ProtocolFormula/Onboarding/ProtocolOnboardingView.swift) |

Behaviors implemented:
- Persistent segmented switch (UserDefaults via `ProtocolFormulaHomeSegmentStorage`)
- First-time 19:00–04:00 with no Tonight log → one-time preselect Tonight + hint chip
- "Observed, not causal" caveat shown next to every delta
- Low-data banner (`Need K more nights`) shown when `nightCount < 3`

---

## Phase 4 — Timeline, All Metrics, Version Dive, Insights

### Insights pipeline

- Domain: `ProtocolFormulaInsight` + `ProtocolFormulaInsightKind` in [`ProtocolFormulaModels.swift`](Better/Core/Models/ProtocolFormulaModels.swift)
- Service: [`Better/Core/Services/ProtocolFormulaInsightsService.swift`](Better/Core/Services/ProtocolFormulaInsightsService.swift)
  - Compares each non-archived version's rollup vs the frozen baseline
  - Emits insight cards for:
    - Restorative improvement / regression (≥5 min absolute delta)
    - Longest restorative block improvement (≥10 min delta)
    - Low data (`<3` nights on a version)
    - Baseline not yet available
  - Every body string includes `ProtocolImpactSummary.causalityCaveat`

### Timeline — [`Better/Features/ProtocolFormula/Timeline/`](Better/Features/ProtocolFormula/Timeline/)

`ProtocolTimelineViewModel.swift` + `ProtocolTimelineView.swift`

- Summary header: total tracked nights + best restorative lift (`DeltaBadge`)
- Phase ribbon: proportional version color bar weighted by night count
- Vertical version cards newest-first: version chip, NOW badge for active, formula text, date range from log keys, restorative % headline, delta vs baseline, metric tiles (restorative min + longest block), add-in chips
- Baseline anchor card at the bottom of the timeline

### All Metrics — [`Better/Features/ProtocolFormula/AllMetrics/`](Better/Features/ProtocolFormula/AllMetrics/)

`ProtocolAllMetricsViewModel.swift` + `ProtocolAllMetricsView.swift`

- 3 metric tabs: Restorative (min), Restorative % of in-bed, Longest block (min)
  - We track these 3 since they are what `ProtocolNightMetricSnapshot` actually carries. The JSX additionally references deep / REM / awake / latency — those would require a session-data join and are intentionally NOT built in this phase to keep the analysis service the single source of truth for protocol math.
- Trend chart: per-version phase shading, dashed baseline line, smooth path, end-of-line dot
- Per-version means table with current version highlighted

### Version Dive — [`Better/Features/ProtocolFormula/VersionDive/`](Better/Features/ProtocolFormula/VersionDive/)

`ProtocolVersionDiveViewModel.swift` + `ProtocolVersionDiveView.swift`

- Version selector chip row
- Header card: version label, formula text, night count, low-data banner
- 3 comparison bars (You vs Baseline) for restorative min / restorative % / longest block, each with signed delta
- Nightly dots scatter for restorative % with baseline dashed line
- Footer caption: "Observed, not causal"

Note: **cohort comparison was dropped** per locked plan decisions — every comparison is user vs. own frozen baseline.

### Wiring

[`ProtocolFormulaTabView.swift`](Better/Features/ProtocolFormula/ProtocolFormulaTabView.swift) — added 3 new routes (`.timeline`, `.allMetrics`, `.versionDive`) to the ellipsis menu and `navigationDestination` switch.

---

## Phase 5 — CSV export columns

`ResearchCSVExporter` now emits 4 additional columns at the end of `nightly_research_rows.csv`, **preserving existing column order** per [CLAUDE.md](CLAUDE.md) invariant #9.

| Column | Source |
|--------|--------|
| `formula_version_label` | `ProtocolFormulaVersion.resolvedLabel` of the night's log version |
| `formula_version_id` | `ProtocolFormulaVersion.id.uuidString` |
| `formula_night_status` | `ProtocolFormulaNightStatus.rawValue` (`taken` / `skipped` / `unknown`) |
| `restorative_pct_of_in_bed` | `ProtocolNightMetricSnapshot.restorativePctOfInBed` (nil unless stage detail present) |

Changes:
- [`Better/Core/Models/ResearchAnalysisModels.swift`](Better/Core/Models/ResearchAnalysisModels.swift) — 4 new optional fields appended to `NightlyResearchRow` + init params
- [`Better/Core/Services/ResearchCSVExporter.swift`](Better/Core/Services/ResearchCSVExporter.swift) — 4 columns appended to header and per-row body

**Not implemented in Phase 5** (deferred to a follow-up per the plan's "Future" section):
- Alert pipeline rewrite for formula-aware alerts
- Legacy `ProtocolTabView` / `ProtocolViewModel` deletion (still ships behind the flag-off path)
- Behavioral journal UI removal from the Protocol tab

These remain as `!ProtocolFormulaFlag.isEnabled()` legacy code paths in `RootTabView`. The intended cutover is to delete them once V1 is exercised in production and no users remain on the legacy flow.

---

## Critical invariants — preserved

1. **Unknown ≠ not-taken** — missing log = `.unknown`, never coerced
2. **HealthKit read-only** — no writes added
3. **Sensitive data encrypted** — all 3 new blob types go through `PersistenceJSON`
4. **No silent wipe** — `makeLiveContainer` now uses `BetterMigrationPlan` with errors propagated
5. **Restorative math reused, not duplicated** — `restorativeSleepDuration` is referenced exactly once in protocol services (in `ProtocolFormulaAnalysisService.snapshot`)
6. **Formula text immutable after first log** — enforced in `LocalDataRepository.saveFormulaVersion`; one backfill exception for `isImportedPlaceholder`
7. **Baseline frozen** — `ProtocolBaselineService.freezeBaseline` is idempotent (returns existing snapshot unless forced)
8. **CSV column order preserved** — Phase 5 columns appended at the end
9. **Business logic out of view bodies** — all derivations live in `@Observable` view models
10. **No huge files** — one file per screen, separate view models, atoms in `Components/`

---

## File tree summary

```
Better/Core/
  Models/
    ProtocolFormulaModels.swift        # all domain types + Insight + Hashing
    ResearchAnalysisModels.swift       # NightlyResearchRow +4 formula fields (Phase 5)
  Persistence/
    PersistenceModels.swift            # V1/V2 schemas + migration plan + 4 @Model classes
  Repositories/
    RepositoryProtocols.swift          # extended protocol + error enum
    LocalDataRepository.swift          # CRUD + immutability + active-singleton enforcement
  Services/
    ProtocolBaselineService.swift      # freeze baseline (90d window, ≤30 nights)
    ProtocolAdherenceMigrationService.swift  # one-shot legacy migration
    ProtocolFormulaAnalysisService.swift     # snapshot/rollups/impact/nightly/allRollups
    ProtocolFormulaInsightsService.swift     # narrative insight generation (Phase 4)
    ResearchCSVExporter.swift          # +4 columns at end (Phase 5)

Better/Features/ProtocolFormula/
  ProtocolFormulaFlag.swift            # UserDefaults flag
  ProtocolFormulaTabView.swift         # shell + 5 routes
  Components/
    ProtocolPalette.swift              # tokens
    ProtocolFormulaAtoms.swift         # shared atoms (chips, banners, badges)
  Home/                                # last-night-first home
  FormulaSetup/                        # version list + editor sheet
  EditLog/                             # calendar + per-day editor
  Onboarding/                          # 3-step intro
  Timeline/                            # Phase 4 — vertical phase cards
  AllMetrics/                          # Phase 4 — metric tabs + trend chart
  VersionDive/                         # Phase 4 — per-version drill

Better/Features/Settings/
  ProtocolFormulaFeatureFlagCard.swift # toggle for the flag
  SettingsTabView.swift                # card slotted into settings

Better/App/
  AppEnvironment.swift                 # runProtocolFormulaMigrationIfNeeded()
  RootTabView.swift                    # flag-gated routing + migration kick-off
```

---

## Verification

- Build: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -scheme Better -configuration Debug -destination "generic/platform=iOS Simulator" build` → **BUILD SUCCEEDED**
- Manual verification path (recommended next):
  1. Enable the flag in Settings → "Protocol Formula Tracking"
  2. Confirm onboarding → mark tonight → review last-night impact card
  3. Visit Timeline, All Metrics, Version Dive from the Protocol tab ellipsis menu
  4. Edit a past night via Edit log → confirm impact card refreshes
  5. Export research CSV from Settings → confirm 4 new formula columns at the end of `nightly_research_rows.csv`

---

## Deferred / explicitly not built

Per the plan's V1 scope cut and the "Future (NOT in this PR)" section:

- Cohort comparison (dropped permanently)
- Deep / REM / awake / latency tabs in All Metrics (would require session-data join; deferred)
- Alert pipeline rewrite for formula-based alerts
- Legacy Protocol tab UI + `ProtocolViewModel` deletion
- Journal UI removal from the Protocol tab
- Journey-map designer screen (was always non-user-facing)
- Phase 1/2/3/4 test files (`LocalDataRepository+FormulaTests`, `ProtocolBaselineServiceTests`, `ProtocolAdherenceMigrationServiceTests`, `SchemaUpgradeFromPopulatedStoreTests`, `ProtocolFormulaAnalysisServiceTests`, `ProtocolHomeViewModelTests`, `ProtocolEditLogViewModelTests`, `ProtocolFormulaSetupViewModelTests`, `ProtocolOnboardingViewModelTests`)

These are tracked in the original plan and remain available as follow-up work.
