# Better — Crash & Performance Analysis

**Date:** 2026-05-24
**Branch:** `main` (36 uncommitted files + recent commit `3f1d8ea Add Protocol Formula Tracking and Red Light Filter features`)
**Symptom:** App crashes on a real iPhone. Suspected memory pressure, especially around the new **Protocol Formula** tab.

---

## TL;DR — Most Likely Crash Causes (Ranked)

| # | Cause | File | Severity |
|---|---|---|---|
| 1 | 90-day HealthKit refetch fired from Protocol tab on every baseline-freeze attempt | `RootTabView.swift:110` + `ProtocolFormulaHomeViewModel.swift:184` | **Critical** |
| 2 | Three concurrent 90-day SwiftData fetches in `SleepDashboardViewModel.loadBodyClockResult()` running in parallel with #1 | `SleepDashboardViewModel.swift:261-283` | **High** |
| 3 | `allRollups()` / `nightlySnapshots(in: distantPast...now)` load *all history* into memory, then discard 14 items | `ProtocolFormulaAnalysisService.swift:216`, `ProtocolFormulaHomeViewModel.swift:229` | **High** |
| 4 | SwiftData V1→V2 migration: `fatalError` on container init failure (no recovery UI) | `BetterApp.swift:14-18` | **High** |
| 5 | O(n·m) version/rollup lookups inside SwiftUI `body` re-runs | `ProtocolFormulaHomeView.swift:668-677`, `…HomeViewModel.swift:237-247` | Medium |

The pattern is: **memory ballooning during initial Protocol-tab appear**, while another tab is already doing heavy work, on a device with years of HealthKit history. The simulator has ~2× the RAM headroom of a real iPhone, which is why it hides in development.

---

## 1. Recent Changes That Likely Introduced the Regression

### Commit `3f1d8ea` (Protocol Formula + Red Light Filter)
- Bumped `maximumBaselineWindowDays` and `dataRetentionDays` **60 → 90**, increasing every full-window scan by 50% in memory.
- Added 4 new SwiftData models for Protocol Formula (`ProtocolFormulaVersion`, `ProtocolNightLog`, `ProtocolBaselineSnapshot`, `ProtocolVersionRollup`) plus a V1→V2 lightweight migration.
- Added `ChronotypeCalculationService` (~200 lines of nightly stats over the 90-day window).
- Container init switched from "silently wipe on failure" to "throw" — correct in spirit, but `BetterApp.swift` still calls `fatalError(...)` on the throw, so a migration failure now hard-crashes at launch instead of recovering.

### Uncommitted (36 files)
- `RootTabView.swift` now passes `historicalRefresh:` into `ProtocolFormulaTabView`, wired to `SyncCoordinator.performInitialSync()` (a 90-day HealthKit pull).
- `ProtocolFormulaHomeViewModel.swift` calls `historicalRefresh?()` on appear/refresh (line ~184) **before** baseline freeze — every Protocol tab open re-pulls 90 days.
- `SleepDashboardViewModel.swift` added `loadBodyClockResult()` that fires three parallel 90-day fetches (`fetchCachedSessions`, `fetchContextEntries`, `fetchActivityStatusLogs`) followed by `ChronotypeCalculationService.estimate()` over all of them.
- New computed/`@State` for `bodyClockResult`, `selectedSleepBodyClockAlignment`, caveats — held for the lifetime of the dashboard and never evicted.

---

## 2. Why the App Crashes on Device

iOS will jetsam-kill an app at ~1.0–1.4 GB of resident memory on most iPhones. Two simultaneous 90-day pulls + Chronotype/Protocol post-processing routinely allocate hundreds of MB of transient `SleepSession` / `SleepContextEntry` arrays, plus encrypted-field decoding (each row goes through `PersistenceJSON.decode()`).

**Pinch points:**

1. **`SyncCoordinator.performInitialSync()`** is invoked from `historicalRefresh` inside `ProtocolFormulaHomeViewModel` *unconditionally* on every refresh — not gated by "first launch" or "stale baseline".
2. **`nightlySnapshots(in: Date.distantPast...Date())`** at `ProtocolFormulaHomeViewModel.swift:229-230` fetches the *entire* protocol history just to keep the last 14 (`Array(allRecent.suffix(14))`).
3. **`allRollups()`** at `ProtocolFormulaAnalysisService.swift:216-219` does the same — `distantPast...Date()` window, no limit, called from Home, AllMetrics, Timeline, and VersionDive *independently*.
4. **`SleepDashboardViewModel.loadBodyClockResult()`** runs the same shape (90 days × three tables) in parallel.

When the user lands on Sleep then taps Protocol, both pipelines run at once — peak memory dominates everything else.

---

## 3. Repeated / Suboptimal Calculations on the Protocol Screen

### A. Repeated full-history scans (the biggest waste)
- **`allRollups()` called per-screen.** Each of `ProtocolFormulaHomeViewModel`, `ProtocolAllMetricsViewModel`, `ProtocolTimelineViewModel`, `ProtocolVersionDiveViewModel` calls it independently. A tab switch inside the Protocol stack triggers a fresh full scan.
- **Fix:** hoist a single `@State var rollupCache: [ProtocolVersionRollup]` (or an actor-backed cache) at `ProtocolFormulaTabView` and inject into child viewmodels. Invalidate only on log/version change.

### B. O(n²) ribbon and trend lookups inside `body`
- `ProtocolFormulaHomeViewModel.swift:237-247` — `for v in versions { rollups.first(where: { $0.versionID == v.id }) … }`.
- `ProtocolFormulaHomeView.swift:668-677` — for each of 14 snapshots, `viewModel.versions.first(where:)` is called inline in `body`.
- **Fix:** build `let versionsByID = Dictionary(uniqueKeysWithValues: versions.map { ($0.id, $0) })` once; use `versionsByID[id]`.

### C. Computed properties that re-run on every render
- `ProtocolAllMetricsViewModel.swift:60-69` — `chartPoints` is a computed `var` that filters all snapshots and looks up versions every body re-evaluation.
- `ProtocolFormulaHomeView.swift:375-406` — `impactPair(for: metric)` runs a 9-case switch per card per render.
- **Fix:** cache derived state in `@State` / stored properties on the `@Observable` model; recompute via `onChange(of: snapshots)` / `onChange(of: impact)`.

### D. Redundant baseline work
- `ProtocolFormulaHomeViewModel.swift:187-195` — calls `freezeBaseline()` then `readiness()` back-to-back; both walk the same 90-day window.
- **Fix:** have `freezeBaseline` return the readiness it already computed (tuple).

### E. Sleep dashboard
- `SleepDashboardViewModel.swift:261-283` — three parallel 90-day fetches plus a chronotype recomputation, no debouncing, no cache. Re-runs whenever the Sleep tab reappears.
- **Fix:** memoize keyed by the latest sleep-session date; only recompute when newer data arrives.

---

## 4. SwiftUI Hotspots

- **`ProtocolFormulaHomeView` body is ~1,000+ lines** with a dozen private sub-`var` sections. Every state change diffs the whole tree.
  - **Fix:** extract `HeroSection`, `RibbonSection`, `TrendSection`, `MetricGrid` into separate `View` structs so SwiftUI can skip unchanged subtrees.
- **`ForEach(viewModel.versions)`** in `ProtocolAllMetricsView.swift:226` lacks an explicit `id:`; struct-identity diffing is slower and prone to spurious re-renders.
- **Sheet creation** of `ImpactMetricDetailSheet` re-instantiates the full view per tap; not a crash, but adds churn.

---

## 5. Migration / Startup Risk (`fatalError` path)

`BetterApp.swift:14-18` (commit `3f1d8ea`):
```swift
fatalError("Unable to create Better app environment: \(error)")
```
The new V1→V2 migration removed the silent wipe — good — but the throw now travels straight into a fatal error. On a device with a partly-corrupted store (e.g. user updated mid-sync) this is an instant crash on launch.

**Fix:** wrap `AppEnvironment.live()` in a recovery flow that surfaces a "Reset local data" UI, similar to how the Privacy screen wipes the store. Log the underlying error to `os_log` for triage.

---

## 6. Concrete Action List (in order)

1. **Stop the bleeding (1-line changes):**
   - `ProtocolFormulaHomeViewModel.swift:184` — guard `historicalRefresh` so it only runs when baseline is missing or older than 24 h. Don't re-pull 90 days on every Home refresh.
   - `ProtocolFormulaHomeViewModel.swift:229` — replace `Date.distantPast...now` with `(now - 30 days)...now`.
   - `ProtocolFormulaAnalysisService.swift:216` — same: bound to the active analysis window (default 30–60 days), expose a separate `allRollupsUnbounded()` only for export paths.

2. **Cache rollups at the tab level.** One fetch per Protocol-tab session, shared with all child screens.

3. **Build `versionsByID` lookup once per refresh.** Replace every inline `versions.first(where:)`.

4. **Promote `chartPoints` and `impactPair` results to stored state** updated via `onChange`.

5. **Decouple Sleep dashboard chronotype work** from view appear; debounce on session changes only.

6. **Wrap `AppEnvironment.live()` in a recovery state** instead of `fatalError` — show a "Restore" screen if migration fails.

7. **Memory instrumentation:** add `os_signpost` around `performInitialSync`, `allRollups`, `loadBodyClockResult`, and run an Instruments Allocations trace on device to confirm peaks drop.

---

## 7. Why I did *not* push the current branch

- 36 files are dirty including `Better.xcodeproj/project.pbxproj`, schema-adjacent models, and core services. Several of these likely contain debug/WIP edits.
- The crash is on `main`. Pushing now ships the regression to anyone else on the branch and makes bisection harder.
- Recommend: stage **only** the small fixes from §6.1 first, validate on device, commit, then push. The rest of the dirty tree should be reviewed file-by-file.

---

## Appendix — Files Most Implicated

```
Better/App/RootTabView.swift                                           (historicalRefresh wiring)
Better/Features/ProtocolFormula/Home/ProtocolFormulaHomeViewModel.swift (refresh path, full-history fetches)
Better/Features/ProtocolFormula/Home/ProtocolFormulaHomeView.swift      (1000-line body, O(n²) lookups)
Better/Features/ProtocolFormula/AllMetrics/ProtocolAllMetricsViewModel.swift (computed chartPoints)
Better/Core/Services/ProtocolFormulaAnalysisService.swift               (allRollups distantPast)
Better/Core/Services/ProtocolBaselineService.swift                      (readiness re-walk)
Better/Core/Services/ChronotypeCalculationService.swift                 (90-day per-tab compute)
Better/Features/Sleep/SleepDashboardViewModel.swift                     (parallel 90-day fetches)
Better/App/BetterApp.swift                                              (fatalError on env init)
```
