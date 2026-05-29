# Security & Vulnerability Analysis — Better iOS App

> Audit date: 2026-05-06  
> Scope: full static analysis of source, entitlements, Info.plist, and test targets  
> Methodology: manual code review of all Swift files, plist inspection, architecture cross-reference

---

## Quick Summary

| Severity | Count | Biggest risk |
|----------|-------|-------------|
| **App Store Blocker** | 3 | Encryption export declaration, HealthKit write description, missing background mode |
| **High** | 3 | Silent encryption fallback, background task race, HealthKit observer error swallowing |
| **Medium** | 3 | HealthKit permission breadth mismatch, migration silent failure, observer query leak |
| **Low** | 2 | Notification permission timing, Keychain error detail |

---

## Part 1 — App Store Blockers

These will get the app rejected or flagged during review.

---

### BLOCKER-1 · `ITSAppUsesNonExemptEncryption` is set to `false` — but you do use it

**File:** `Better/Info.plist:29`

```xml
<key>ITSAppUsesNonExemptEncryption</key>
<false/>
```

**What it means:** Setting this to `false` is a declaration to Apple that your app does not use non-exempt encryption. The app uses **AES-256-GCM implemented via CryptoKit** (`EncryptionService.swift`) to encrypt all health data written to SwiftData. That is non-exempt encryption by definition — you wrote the algorithm calls yourself, regardless of the underlying framework.

**Why it will block you:** Apple's App Store Connect submission process cross-checks this flag. If it's `false` and the app clearly uses AES, the binary analysis during review will catch it. Submitting a false declaration also carries export compliance liability under US EAR regulations.

**Fix:** Set `ITSAppUsesNonExemptEncryption` to `true`. This triggers the encryption documentation questions in App Store Connect. Answer them as follows:
- Does the app use encryption? **Yes**
- Is the encryption solely for data protection at rest? **Yes**
- Do you use only standard encryption algorithms (AES, RSA, etc.)? **Yes**
- Does the app transmit encrypted data outside the device? **No**

This path typically qualifies for self-classification under EAR, requires no ERN, and does not delay review.

---

### RESOLVED · Health update purpose string must stay present while authorization remains read-only

**File:** `Better/Info.plist`

```xml
<key>NSHealthUpdateUsageDescription</key>
<string>Better does not save data to Apple Health. Health write access is not requested by this version of the app; all sleep and biomarker insights are stored locally on your device.</string>
```

**File:** `Better/Core/Repositories/HealthKitRepository.swift`

```swift
healthStore.requestAuthorization(toShare: [], read: readTypes)
```

The app remains read-only at runtime, but App Store validation requires `NSHealthUpdateUsageDescription` when the HealthKit capability is present. Keep the string explicit that Better does not save data to Apple Health unless write support is intentionally implemented later.

**Guardrail:** `BetterTests/AppleHealthReviewComplianceTests.swift` asserts the purpose string exists and HealthKit authorization still uses `toShare: []`.

---

### RESOLVED · Do not add `healthkit` to `UIBackgroundModes`

**File:** `Better/Info.plist`

```xml
<key>UIBackgroundModes</key>
<array>
    <string>fetch</string>
</array>
```

**File:** `Better/Core/Repositories/HealthKitRepository.swift`

```swift
healthStore.enableBackgroundDelivery(for: sleepType, frequency: .immediate) { _, _ in }
```

`healthkit` is not a valid iOS `UIBackgroundModes` value and causes App Store validation to fail. Keep `fetch` for `BGAppRefreshTask`. HealthKit observer delivery is controlled by the `com.apple.developer.healthkit.background-delivery` entitlement in `Better.entitlements`.

**Guardrail:** `BetterTests/AppleHealthReviewComplianceTests.swift` asserts `fetch` is present and `healthkit` is absent from `UIBackgroundModes`.

---

## Part 2 — High Severity

These don't block submission but represent meaningful security risks or instability.

---

## 2026-05-28 Addendum — HealthKit Large-Data Performance Audit

Scope: static audit of HealthKit fetching, sync, SwiftData storage, baseline/dashboard caching, chart inputs, SwiftUI rendering, and privacy-minimal local storage. Source docs reviewed: `BASELINE_AND_HISTORY_IMPLEMENTATION.md`, `sleep_insights_diagnostic.md`, `docs/SLEEP_DASHBOARD.html`, and `CHRONOTYPE_RESEARCH_AND_ARCHITECTURE.html`.

Important constraint: this pass is documentation only. No app code was changed.

### Executive Summary

The app is already pointed in the right direction: HealthKit is read-only, sleep changes use `HKObserverQuery` plus `HKAnchoredObjectQuery`, the dashboard reads from SwiftData, biomarker baselines have a 7-day cache, and many earlier render hot spots have already been reduced.

The remaining lag risk is still high for users with large Apple Health histories because sync work is orchestrated by a `@MainActor` coordinator, incremental sync can fall back to 90-day reprocessing, every changed sleep session fans out into multiple separate HealthKit biometric queries, dashboard baselines are recomputed from sessions on date load instead of persisted as date-keyed snapshots, and SwiftData fetches often decrypt full session blobs when only summaries are needed.

### File-By-File Findings

#### `Better/Core/Services/SyncCoordinator.swift`

Severity: **High**

Issue: `SyncCoordinator` is `@MainActor`, and the central sync path performs HealthKit fetch orchestration, sleep processing, per-session biometric hydration, SwiftData replacement, baseline computation, alert generation, and biomarker-baseline recomputation from the main actor (`performSyncHealthRange`, lines 231-335).

Why it causes lag: Even when HealthKit callbacks are asynchronous, the coordinator serializes major orchestration and state mutation through the main actor. Large result sets or many sessions can keep the UI actor busy scheduling tasks, awaiting actor hops, updating phase state, and collecting results.

Recommended fix / code changes: Split sync into a non-main `HealthSyncEngine` actor that owns HealthKit processing, changed-range expansion, biometric hydration, baseline recomputation, and cache writes. Keep only UI-facing `phase`, `lastSyncedAt`, and `authorizationState` mutations on `@MainActor`. Return a small `SyncResult` to the main actor after persistence completes.

Tests needed: A concurrency test proving `performIncrementalRefresh` does not require `MainActor` for processing; a regression test using 90 days of synthetic samples with UI state updated only after completion; an Instruments trace comparing main-thread time before/after.

Risky assumption: SwiftData `@ModelActor` can remain the persistence boundary while a new sync actor performs CPU work off-main.

Severity: **High**

Issue: Incremental sync uses anchors, but deletion handling or anchor loss falls back to a full 90-day reprocess (`performIncrementalRefresh`, lines 158-165).

Why it causes lag: A single deleted sleep sample can force a 90-day HealthKit sleep query, all-session processing, and biometric rehydration. Users with years of Health data or dense wearable data will feel this during app wake or background refresh.

Recommended fix / code changes: Persist per-type sync metadata: last successful anchor, last affected sleep date keys, and last full backfill completion. For deletes, use the deleted object UUID if it maps to a stored raw sample index; otherwise reprocess only a conservative window around the last known affected sleep date, e.g. `changedStart - 36h ... changedEnd + 36h`. If the app cannot map a deletion, fall back to 14 days first, then schedule a background full reconciliation.

Tests needed: Anchor tests for added-only, deleted-known, deleted-unknown, nil-anchor first run, corrupted-anchor recovery, and ensuring full 90-day fallback is not used for ordinary deletion updates.

Risky assumption: The current app does not persist raw HealthKit sample UUIDs, so precise delete invalidation needs a small local raw-sample index or a changed-date index.

Severity: **High**

Issue: Biometric hydration is per session times per metric (`attachBiometrics`, lines 338-360). For each session, it starts one query for each dashboard biometric type.

Why it causes lag: A 90-day backfill with 90 sessions and 4 dashboard biomarker types can issue roughly 360 separate `HKSampleQuery` calls. That creates query overhead, HealthKit database pressure, and many actor hops. It also duplicates queries for overlapping sleep windows.

Recommended fix / code changes: Batch-fetch biometrics by type for the whole changed sync range once, then bucket samples into sleep sessions in memory. Store nightly summaries by sleep date/session. Keep per-session HealthKit queries only for diagnostics/manual support actions.

Tests needed: A fake HealthKit repository call-count test proving one query per type per sync range; biomarker bucketing tests for overlapping session windows and boundary samples; performance test for 90 nights.

Risky assumption: Dashboard biomarker summaries do not need raw sample provenance beyond the per-night summary and minimal source metadata.

Severity: **Medium**

Issue: Baselines are recomputed in several windows every daily/forced processing run (`performSyncHealthRange`, lines 266-290), but only "latest" window baselines are stored. There is no date-keyed dashboard baseline cache.

Why it causes lag: Historical dashboard browsing recomputes as-of baselines from up to 60 cached sessions per selected date, and repeated daily processing refetches and recomputes overlapping windows.

Recommended fix / code changes: Add `StoredDashboardBaselineSnapshot` keyed by `(asOfSleepDateKey, windowKind)` with generatedAt, source session range, validNightCount, and metric averages. During sync, identify affected sleepDateKeys and precompute snapshots for those dates plus dependent following dates. Expire snapshots weekly and invalidate early when HealthKit changes touch any source sleep date.

Tests needed: Snapshot hit/miss tests, weekly TTL expiration tests, early invalidation tests when a source session changes, and historical date selection tests that do not call `BaselineEngine` when a fresh snapshot exists.

Risky assumption: A baseline snapshot is health-derived data and must be deleted by `deleteAllHealthData`.

#### `Better/Core/Repositories/HealthKitRepository.swift`

Severity: **High**

Issue: Sleep and biometric queries use `HKObjectQueryNoLimit` (`fetchSleepSamples`, lines 71-91; `fetchBiometrics`, lines 114-140).

Why it causes lag: For wide date ranges, HealthKit may return very large arrays at once. The app then processes the full array in memory and cannot stream partial results or apply backpressure.

Recommended fix / code changes: Use anchored queries for sleep as the primary path after first backfill. For quantity biometrics, prefer `HKStatisticsCollectionQuery` or bounded `HKSampleQuery` pages where only aggregate nightly values are needed. Keep raw sample queries only for diagnostics.

Tests needed: Repository tests that enforce query limits or statistics use through fakes; integration performance tests against large synthetic biometric arrays.

Risky assumption: Some biomarker calculations need min/avg/median, but not every raw point. HRV median may still require samples unless approximated or computed from a batched sample set.

Severity: **Medium**

Issue: `requestAuthorization()` treats `success` as `canQuerySleep` (lines 35-57). Apple Health authorization can complete even when individual types are denied.

Why it causes lag: The app may continue to run refresh paths that query denied types and produce empty data repeatedly, increasing useless work and confusing cache state.

Recommended fix / code changes: After authorization, run a cheap bounded sleep probe and set `lastQueryReturnedSamples`/presentation state based on actual query behavior. Track empty biometric type counts separately so denied/missing types can be skipped for a cooldown period.

Tests needed: Fake authorization success with denied/empty sleep query; type-level biometric cooldown tests.

Risky assumption: HealthKit does not expose per-type read authorization reliably, so empty results must be treated as ambiguous.

#### `Better/Core/Repositories/LocalDataRepository.swift`

Severity: **High**

Issue: `fetchAvailableSleepDates` fetches `StoredSleepSession` rows then calls `stored.toDomain().qualityScore.overall` (lines 70-86), which decrypts/decodes full JSON blobs just to display calendar dots.

Why it causes lag: Opening the month calendar can decrypt and decode `stagesData`, `sourcesData`, `qualityScoreData`, and optional biometrics for every day in the month even though the UI needs only score, duration, quality, and presence.

Recommended fix / code changes: Store `qualityScoreOverall` as a scalar column on `StoredSleepSession`, or add a separate `StoredSleepDaySummary` table keyed by `sleepDateKey`. Return summaries without `toDomain()`.

Tests needed: Calendar summary fetch test that does not decode encrypted blobs; migration test backfilling scalar score/summary from existing sessions.

Risky assumption: `qualityScore.overall` is non-sensitive enough to be a scalar column. It is still health-derived, so it remains protected by the encrypted/file-protected store and delete flow.

Severity: **Medium**

Issue: `fetchCachedSessions` and `fetchSessions(beforeSleepDateKey:)` always decode full `SleepSession` models (lines 33-67), including stage/source/biometric blobs.

Why it causes lag: Trends, chronotype, baseline, and dashboard cards often need only scalar columns and a few metrics. Full decode turns every chart load into unnecessary encrypted blob work.

Recommended fix / code changes: Add lightweight projections: `SleepSessionSummary`, `SleepBaselineInput`, `TrendPointInput`, and `ChronotypeInput`. Fetch only full `SleepSession` for selected-night detail and hypnogram/stage UI.

Tests needed: Projection correctness tests comparing full-session and projection-derived results; performance tests for 90-day trend load.

Risky assumption: SwiftData projection support may be limited; if so, use separate summary models.

Severity: **Medium**

Issue: `replaceSessions` deletes every stored session overlapping the sync range, then inserts processed sessions (lines 15-30).

Why it causes lag: Large overlapping refreshes churn SwiftData rows, encrypted blobs, and unique indexes even when most sessions did not change.

Recommended fix / code changes: Upsert by `sleepDateKey` and skip writes when a stable content hash is unchanged. Delete only affected keys that are no longer present after reprocessing.

Tests needed: Idempotent sync test proving repeated refresh writes zero unchanged rows; deletion test proving stale affected sessions are removed.

Risky assumption: A stable hash should exclude generated IDs and include stage intervals, source identifiers, scalar metrics, and biometric summary values.

Severity: **Low**

Issue: `pruneDataOlderThan` deletes baselines by `generatedAt` (lines 823-826), not by the source/as-of date.

Why it causes lag: Old generated baseline rows can linger if generated recently from old source data, while useful as-of baseline cache rows would be hard to manage later.

Recommended fix / code changes: Once baseline snapshots are added, expire by `asOfSleepDateKey` and `sourceEndSleepDateKey`, not only generation time.

Tests needed: Retention tests for generated-at vs as-of boundaries.

Risky assumption: Current baseline count is small, so this is a future cache-correctness issue more than a current hot spot.

#### `Better/Core/Persistence/PersistenceModels.swift`

Severity: **Medium**

Issue: `StoredSleepSession` stores many useful dashboard/chart values as scalar columns, but score is only inside encrypted `qualityScoreData` and biomarker raw samples are stored inside `StoredNightlyBiometricSummary.samplesData` (lines 180-202 and 360-382).

Why it causes lag: UI lists and charts must decrypt/decode when they need score; diagnostics and biomarker views can load large raw sample arrays when summary fields would be enough.

Recommended fix / code changes: Add scalar `qualityScoreOverall`, score component columns if needed, and a minimal biomarker-summary projection. Consider not storing raw biometric samples by default; store only aggregate value, unit, count, time range, and source summary unless a user explicitly generates a diagnostic report.

Tests needed: Migration tests, privacy delete tests, and summary rendering tests without raw samples.

Risky assumption: Removing raw biomarker sample persistence should not change user-facing behavior; diagnostic copy may need to say raw availability is queried live.

Severity: **Low**

Issue: The comment above `PersistenceJSON.encode` still says encryption fallback returns plain JSON (lines 155-158), but the code now throws on encryption failure (line 163).

Why it causes lag/security confusion: This does not cause lag, but it can mislead future performance work into adding fallback writes.

Recommended fix / code changes: Update the comment to match current fail-closed behavior.

Tests needed: Existing encryption tests should assert no plaintext fallback on encryption failure.

Risky assumption: None.

#### `Better/Features/Sleep/SleepDashboardViewModel.swift`

Severity: **High**

Issue: `loadSelectedDate` fetches session, profile, computes baseline, loads recent sessions, context, builds insights, computes chronotype over 90 days, refreshes biomarker baseline, and loads month summaries for every selected date (lines 149-220).

Why it causes lag: Swiping dates or opening the Sleep tab can trigger multiple storage reads, decrypt 60-90 days of sessions, run baseline computation, run chronotype estimation, and then mutate many `@Observable` properties. That creates both CPU work and SwiftUI invalidation fan-out.

Recommended fix / code changes: Load selected-night dashboard values from a `DashboardSnapshot` table: selected summary, cached score, cached baseline, cached insights, cached body-clock alignment, and biomarker reaction map. Move chronotype and biomarker refresh into background recompute jobs keyed by affected sleep dates. Batch assign one state struct instead of many observable properties.

Tests needed: Date-selection test proving no HealthKit query and no baseline recompute when snapshot exists; observable invalidation tests are hard, but unit tests can assert a single state replacement path.

Risky assumption: Cached insight text must stay identical to current logic; snapshot invalidation must include profile sleep goal, context travel flag, and baseline changes.

Severity: **High**

Issue: `baseline(asOfSleepDateKey:)` computes dashboard baseline on demand from cached sessions every time (lines 239-258).

Why it causes lag: This repeats the same 60-day fetch/filter/sort/average work for today and for each historical date.

Recommended fix / code changes: Persist `DashboardBaselineSnapshot` by `asOfSleepDateKey`. Use weekly TTL and early invalidation on changed HealthKit samples, changed context that affects scoring, or profile baseline settings. Precompute today and recent dates after sync.

Tests needed: Snapshot cache tests, as-of exclusion tests ensuring selected/current session is not included, and invalidation tests when any source session in the rolling window changes.

Risky assumption: Weekly TTL is acceptable for historical dates unless source data changes.

Severity: **Medium**

Issue: `sortedRecentSessions` is documented as "computed once" but is a computed property that sorts on every access (lines 37-41).

Why it causes lag: The sleep view passes this into multiple cards. With 60 sessions, this is modest, but it is still avoidable render work.

Recommended fix / code changes: Store `sortedRecentSessions` as a real property updated when `recentSessions` changes, or make `recentSessions` already sorted and do not expose a sorting computed property.

Tests needed: View model test that loaded recent sessions remain sorted.

Risky assumption: Current data size is capped at 60 for this property, so severity is medium/low unless combined with frequent re-renders.

#### `Better/Features/Sleep/SleepTabView.swift`

Severity: **Medium**

Issue: The score is still computed in view code in `GeometryReader` and again in `sessionContent` (`body`, lines 23-33; `sessionContent`, line 130; helper lines 897-903).

Why it causes lag: It is reduced from earlier repeated score computation, but view recomputation still runs score estimation during layout/body evaluation. Score depends on session, baseline, goal, and context and belongs in the dashboard snapshot/view model.

Recommended fix / code changes: Add `selectedScoreEstimate` to `SleepDashboardViewModel`/`DashboardSnapshot` and pass it into the view. Keep `HealthSleepScoreEstimator` out of `body`.

Tests needed: Score parity test comparing cached/view-model score with existing estimator.

Risky assumption: Score should update immediately when context entry or sleep goal changes; these must invalidate the snapshot.

Severity: **Medium**

Issue: The hero ring still uses blur and continuous pulse animation (lines 345-349, 393-400, 416-437).

Why it causes lag: GPU work can remain active even after data loading is optimized, masking sync improvements as animation jank on older devices.

Recommended fix / code changes: Disable pulse after first appearance or behind Low Power Mode/reduce motion, replace blurred glow with static shadow/drawing group, and verify with SwiftUI/Instruments.

Tests needed: Manual Instruments render-server/frame-time comparison; screenshot tests cannot detect GPU cost.

Risky assumption: Visual behavior should remain close enough not to count as user-facing behavior change.

#### `Better/Core/Processors/SleepDataProcessor.swift`

Severity: **High**

Issue: `cleanedIntervals` builds all unique boundaries and then filters all raw intervals for every segment (lines 273-285).

Why it causes lag: This is O(boundaries * samples). Dense HealthKit sleep data with many overlapping in-bed/stage samples can make the initial backfill and fallback reprocess expensive.

Recommended fix / code changes: Replace with a sweep-line interval resolver: create start/end events, maintain active intervals ordered by resolution priority, and emit cleaned segments in O(n log n). Keep behavior identical for overlapping source priority.

Tests needed: Existing sleep processor tests plus new overlap stress tests comparing old and new outputs on generated sample sets.

Risky assumption: The current source-priority resolution rules are correct and must be preserved exactly.

Severity: **Medium**

Issue: `computeBaseline` repeatedly maps valid sessions for every metric (lines 32-63).

Why it causes lag: For 30-90 sessions this is not huge, but repeated on-demand baseline computation magnifies it.

Recommended fix / code changes: Once baseline snapshots exist, this becomes less important. If kept, collect metric arrays in one pass.

Tests needed: Baseline parity tests.

Risky assumption: Floating-point results may differ slightly if computation order changes.

#### `Better/Core/Services/BiomarkerBaselineService.swift`

Severity: **Medium**

Issue: The service has weekly TTL and cache persistence, but `SyncCoordinator` calls `recompute` after any daily processing (lines 49-80 in service, lines 333-335 in coordinator).

Why it causes lag: The TTL is bypassed on sync, so frequent HealthKit observer events can recompute baseline even when changed data is unrelated or outside the biomarker baseline window.

Recommended fix / code changes: Add affected-date input to `recomputeIfAffected(changedSleepDateKeys:)`. Recompute only if a changed session is inside the primary/fallback biomarker window or the cached value is stale.

Tests needed: TTL-respected sync test; early invalidation test for an in-window biomarker change; no-op test for out-of-window changes.

Risky assumption: HealthKit sleep changes are the only relevant trigger; biometric-only HealthKit changes are not currently observed.

#### `Better/Core/Services/BiomarkerSummaryService.swift`

Severity: **Medium**

Issue: Biology summary still performs a live HealthKit resting-heart-rate query over the 60-day window (`summaries`, lines 18-32).

Why it causes lag: If this surface is reintroduced or called from settings/diagnostics, it bypasses local summaries and queries HealthKit directly.

Recommended fix / code changes: Incrementally sync daily biometric summaries into SwiftData and make this service read local summaries by default. Keep live HealthKit query behind a manual "refresh" or diagnostic path.

Tests needed: Service tests using local daily summaries only; HealthKit fake call-count test.

Risky assumption: File comment says Biology tab is retired, so this may be dead code. If truly dead, delete it instead of optimizing it.

Severity: **Low**

Issue: Diagnostic report intentionally runs two HealthKit queries per diagnostic type (lines 75-96).

Why it causes lag: This is expensive but user-initiated/support-only. It should not run on dashboard appear.

Recommended fix / code changes: Leave as manual diagnostic only; add guardrails so no dashboard or tab load path calls it.

Tests needed: Dependency/call-path test or simple code ownership convention.

Risky assumption: Diagnostics are not invoked automatically anywhere else.

#### `Better/Features/Trends/TrendsViewModel.swift`

Severity: **Medium**

Issue: `loadData` fetches up to 91+ days of full sessions, context, activity, baseline, adherence, and then computes chart points, comparisons, latest insights, derived metrics, and chronotype (lines 286-324).

Why it causes lag: Trends is mostly aggregate/chart UI and does not need full stage/source/biometric raw blobs for every path. The work is mostly local, but it can still stall tab switching with large cached history.

Recommended fix / code changes: Read from local daily/weekly/monthly summary tables for chart points and period averages. Compute chronotype from a dedicated projection or cached chronotype snapshot. Replace `TrendChartPoint.id = UUID()` with stable `dateKey + metric` identity to reduce chart churn.

Tests needed: Trend summary parity tests, stable identity tests, and chart update tests when metric changes.

Risky assumption: User-visible trend values must match current full-session calculations exactly.

Severity: **Medium**

Issue: Metric caching is in-memory and cleared on every `loadData` (lines 286-287), while period averages, chart points, and comparison summaries repeatedly filter/compactMap the same session arrays (lines 470-540).

Why it causes lag: Repeated metric changes are okay, but every tab reload rebuilds all derived data.

Recommended fix / code changes: Persist daily metric summaries and precomputed week/month aggregates. Keep view-model cache only for transient UI metric switches.

Tests needed: Aggregate invalidation tests when a sleep session changes.

Risky assumption: Summary storage does not need raw HealthKit samples to explain values.

#### `Better/Features/Cronotype/CronotypeViewModel.swift` and `Better/Core/Services/ChronotypeCalculationService.swift`

Severity: **Medium**

Issue: Chronotype loads 91 days of sessions/context/activity and computes estimates on appear (view model lines 35-72). The service sorts/filters and computes medians from full sessions.

Why it causes lag: The Sleep dashboard also computes chronotype alignment for selected dates, so the same 90-day calculation can be repeated across Sleep, Trends, and Chronotype.

Recommended fix / code changes: Add `ChronotypeSnapshot` cache keyed by `windowEndSleepDateKey` and invalidated by changed sessions/context/activity logs. Sleep dashboard should read only the latest applicable snapshot and compute one-night alignment cheaply.

Tests needed: Snapshot invalidation tests for changed sleep, travel context, and activity status; parity test against live `estimate`.

Risky assumption: Body-clock estimate can be cached weekly or until source data changes without surprising users.

#### `Better/Core/Services/ProtocolFormulaAnalysisService.swift`

Severity: **Medium**

Issue: Protocol rollups and nightly snapshots fetch full sessions/logs and recompute rollups for requested ranges (lines 59-94 and 174-187).

Why it causes lag: Protocol screens and exports can repeatedly recompute the same per-version aggregates from full sessions.

Recommended fix / code changes: Persist `ProtocolDailyMetricSnapshot` and `ProtocolVersionRollupCache` keyed by version/date range granularity. Invalidate when sleep session for a date or protocol log for that date changes.

Tests needed: Rollup cache parity tests; invalidation tests for changed log status and changed sleep session.

Risky assumption: Protocol formula "frozen baseline" behavior must remain unchanged; cache only derived rollups, not baseline semantics.

#### `Better/Core/Services/ResearchAnalysisService.swift`

Severity: **Low**

Issue: Export caps sleep sessions to 60 days but can still query HealthKit biometrics/activity while building package (`buildExportPackage`, lines 26-35; `sum`, lines 409-412).

Why it causes lag: Export is user-initiated, so lag is less harmful, but it should not block UI.

Recommended fix / code changes: Run export work in a background task with progress and use local daily activity/biometric summaries where possible.

Tests needed: Export call-count tests and cancellation/progress tests.

Risky assumption: Export freshness requirements may justify live HealthKit reads.

#### `Better/App/RootTabView.swift`

Severity: **Medium**

Issue: Protocol tab passes `historicalRefresh: { await environment.syncCoordinator.performInitialSync() }` (lines 125-128).

Why it causes lag: Any Protocol surface invoking that closure triggers a full 90-day HealthKit sync, not an incremental or missing-range refresh.

Recommended fix / code changes: Replace with a missing-range backfill API that checks cached coverage and uses anchored/incremental sync first. Full initial sync should be first-install/reset only.

Tests needed: Protocol historical refresh test proving it does not call full initial sync when 90-day cache already exists.

Risky assumption: The Protocol UI uses this closure sparingly; if it is visible CTA-driven, severity drops.

### Missing Architecture Pieces To Implement

- **Incremental HealthKit sync:** keep anchored sleep sync, but add raw sample/date index, bounded delete invalidation, anchor corruption recovery, and one-query-per-type biomarker batching.
- **Local summaries by day/week/month:** add day summary rows for sleep score/stages/biomarkers/activity, then aggregate week/month rows for Trends and dashboard comparison.
- **Cached dashboard values:** add `DashboardSnapshot` keyed by `sleepDateKey` containing score estimate, baseline id/snapshot, selected summary, insight inputs/output, biomarker reactions, and body-clock alignment.
- **Precomputed baseline cache:** add date-keyed dashboard baseline snapshots with 30-day primary and 60-day fallback.
- **Weekly cache expiration:** store `computedAt` and TTL policy per cache type; expire dashboard/baseline/chronotype snapshots weekly unless source data changes first.
- **Early invalidation:** HealthKit observer/anchored changes should compute affected sleep date keys and invalidate dependent dashboard snapshots, trend aggregates, biomarker baseline, chronotype snapshots, and protocol rollups.
- **Background recomputation:** perform recompute in a non-main actor from BG refresh/observer paths, then publish small UI state updates.
- **Main-thread-safe UI updates:** replace broad mutable `@Observable` property fan-out with state structs per screen and single assignment after async loading.
- **Secure/minimal storage:** keep raw HealthKit samples out of persistence unless required for a user-triggered diagnostic. Store aggregates, source summaries, counts, and date ranges; ensure all new tables are included in `deleteAllHealthData`.

### Priority Implementation Plan

1. Move sync processing off `@MainActor` and batch biometric hydration by type/range.
2. Add day summary and dashboard snapshot models; make Sleep dashboard load snapshots first.
3. Add date-keyed baseline snapshots with weekly TTL and source-date invalidation.
4. Replace 90-day deletion fallback with affected-date invalidation plus scheduled reconciliation.
5. Add trend/week/month aggregate tables and stable chart identities.
6. Add chronotype snapshot caching shared by Sleep, Trends, and Chronotype.
7. Trim persisted raw biomarker samples to minimal summaries unless diagnostics are explicitly requested.

### Global Test Matrix Needed

- Large synthetic HealthKit backfill: 90 days, dense overlapping stages, multiple sources.
- Incremental add/delete/update: anchor advances, affected date keys are correct, and only bounded ranges reprocess.
- Main actor budget: dashboard tab open and date swipe do not perform HealthKit queries or baseline recomputation when caches are fresh.
- Cache TTL: weekly expiration and early invalidation both work.
- Privacy delete: all new summaries, snapshots, anchors, and rollups are removed by `deleteAllHealthData`.
- Value parity: cached dashboard/trends/protocol/chronotype values match current calculations within floating-point tolerance.
- Performance regression: query count, SwiftData write count, and wall-clock time for initial sync and one-night incremental sync.

### Risky Assumptions

- User-facing values must remain identical, so cache invalidation must include profile sleep goal, travel context, protocol logs, activity status, and HealthKit sleep changes.
- HealthKit biometric-only changes are not currently observed; if biomarker freshness matters, add observers/anchors for relevant quantity types or accept TTL-based freshness.
- SwiftData projections may not be ergonomic enough for all summary reads; separate summary tables are safer.
- Removing raw biometric sample persistence improves privacy and performance, but diagnostic workflows may need live HealthKit queries.

---

### HIGH-1 · Encryption silently falls back to plain JSON on failure

**File:** `Better/Core/Persistence/PersistenceModels.swift:59–63`

```swift
nonisolated static func encode<T: Encodable>(_ value: T) throws -> Data {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let jsonData = try encoder.encode(value)
    return (try? EncryptionService.shared.encrypt(jsonData)) ?? jsonData  // ← plain-text written if encryption fails
}
```

The comment says "the store's own file protection still applies." That is true but incomplete. File protection (`FileProtectionType.complete`) only blocks access while the device is **locked**. An attacker with a jailbroken device or physical access immediately after unlock can read the SQLite file. The app promises users AES-256 encryption of health data in both its UI and its `PrivacyControlsView`. If the Keychain is momentarily unavailable (low-battery auto-lock race, Keychain reset), this promise breaks silently — no error, no log, the user never knows their data went in as plain text.

**Scenarios where this triggers:**
1. First launch on a new device where Keychain hasn't been set up yet and an iOS upgrade is in progress
2. `resetKey()` is called (e.g. in tests or a future privacy "delete all" flow) and a write happens before the new key is generated
3. MDM profile revokes Keychain access while the app is backgrounded

**Fix:** Throw instead of falling back. Let callers handle the error with a UI prompt:

```swift
nonisolated static func encode<T: Encodable>(_ value: T) throws -> Data {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let jsonData = try encoder.encode(value)
    return try EncryptionService.shared.encrypt(jsonData)  // let it throw
}
```

If you want write resilience during migration, handle the fallback explicitly in `DataMigrationService` with a logged warning, not in the generic encode path.

---

### HIGH-2 · Background task double-completion race condition

**File:** `Better/Core/Services/BackgroundTaskService.swift:101–124`

```swift
var didCompleteTask = false
let refreshTask = Task { @MainActor in
    await syncCoordinator.performIncrementalRefresh()
}

task.expirationHandler = {
    refreshTask.cancel()
    Task { @MainActor in
        guard !didCompleteTask else { return }
        didCompleteTask = true
        task.setTaskCompleted(success: false)  // path A
    }
}

await refreshTask.value

guard !didCompleteTask else { return }
didCompleteTask = true

// path B
task.setTaskCompleted(success: !refreshTask.isCancelled)
```

`didCompleteTask` is a local `var` accessed from two concurrent `Task { @MainActor in }` closures. Both path A and path B can proceed to call `setTaskCompleted()` if the expiration fires at the exact moment `await refreshTask.value` returns. `BGTask.setTaskCompleted()` called twice is documented as undefined behaviour and has crashed apps in production.

**Fix:** Use `Task.isCancelled` and a single completion point:

```swift
func handleSleepRefresh(task: BGAppRefreshTask) async {
    scheduleNextSleepRefresh()
    let refreshTask = Task { @MainActor in
        await syncCoordinator.performIncrementalRefresh()
    }
    task.expirationHandler = { refreshTask.cancel() }
    await refreshTask.value
    task.setTaskCompleted(success: !refreshTask.isCancelled)
}
```

---

### HIGH-3 · HealthKit observer errors silently swallowed — permission revocation goes undetected

**File:** `Better/Core/Repositories/HealthKitRepository.swift:162–166`

```swift
let query = HKObserverQuery(sampleType: sleepType, predicate: nil) { _, completionHandler, error in
    if error != nil {
        completionHandler()
        return
    }
    // …
}
```

**File:** `Better/Core/Repositories/HealthKitRepository.swift:177`

```swift
healthStore.enableBackgroundDelivery(for: sleepType, frequency: .immediate) { _, _ in }
```

When the user revokes HealthKit permission in Settings, the next observer callback fires with an error. The current code acknowledges the callback and silently continues. The app will keep running in a state where it thinks it has HealthKit access but doesn't, until the next foreground refresh (which will fail and set the fallback state). Background delivery errors are completely discarded.

**Fix:** On observer error, log it and push an event upstream so `SyncCoordinator` can update `authorizationState`:

```swift
if let error {
    logger.error("HealthKit observer error: \(error.localizedDescription, privacy: .public)")
    completionHandler()
    return
}
```

For background delivery:

```swift
healthStore.enableBackgroundDelivery(for: sleepType, frequency: .immediate) { success, error in
    if let error {
        logger.error("Background delivery failed: \(error.localizedDescription, privacy: .public)")
    }
}
```

---

## Part 3 — Medium Severity

Real issues that degrade security guarantees or user experience, but don't cause immediate data loss.

---

### MEDIUM-1 · HealthKit permission description doesn't cover all requested types

**File:** `Better/Info.plist:31–32`

```xml
<key>NSHealthShareUsageDescription</key>
<string>Better reads your sleep, heart, HRV, oxygen saturation, and respiratory data from Apple Health to show sleep trends and protocol insights.</string>
```

**File:** `Better/Core/Repositories/HealthKitRepository.swift:230–249`

The app requests **17 distinct HealthKit types**, including:
- `bodyMass`, `leanBodyMass`, `bodyFatPercentage`, `bodyTemperature` (body composition)
- `vo2Max` (fitness)
- `stepCount`, `activeEnergyBurned`, `appleExerciseTime`, `appleStandTime`, `flightsClimbed`, `distanceWalkingRunning` (activity)

None of these are mentioned in the usage description. Apple's review guideline 5.1.1 requires that the description "clearly and completely describes your app's use of the data." Requesting undisclosed types is flagged during review.

**Fix:** Update `NSHealthShareUsageDescription` to list all categories:

```
Better reads sleep, heart rate, HRV, blood oxygen, respiratory rate, body composition (weight, body fat, temperature), fitness (VO2 Max), and daily activity (steps, calories, exercise, stand hours) from Apple Health to power sleep insights and research tracking.
```

---

### MEDIUM-2 · Data migration silently leaves records unencrypted on error

**File:** `Better/Core/Repositories/LocalDataRepository.swift` (migration methods)

```swift
session.qualityScoreData = (try? PersistenceJSON.encode(domain.qualityScore)) ?? session.qualityScoreData
```

The `try?` pattern means if `PersistenceJSON.encode` throws (e.g., Keychain unavailable during migration), the original unencrypted data is kept in place without any log entry, warning, or retry. After migration completes, `UserDefaults` records migration as done. On the next launch, migration is skipped. The record stays unencrypted forever.

**Fix:** Either propagate the error out of the migration function so it retries on next launch, or log a specific warning that a record remained unencrypted.

---

### MEDIUM-3 · Observer query array is append-only — potential memory leak on repeated observation starts

**File:** `Better/Core/Repositories/HealthKitRepository.swift:343–347`

```swift
func retainObserverQuery(_ query: HKObserverQuery) {
    observerLock.lock()
    observerQueries.append(query)
    observerLock.unlock()
}
```

`stopObserverQuery` does remove entries, but if `startObservingSleepChanges()` is called more than once without a corresponding stop (e.g., due to a reconnect loop or a bug in the caller), queries accumulate indefinitely. Each retained query holds a reference to the `HKHealthStore`.

**Fix:** Add a guard at the start of `startObservingSleepChanges()` that stops and removes all existing observer queries before registering a new one.

---

## Part 4 — Low Severity

Minor issues worth addressing before launch.

---

### LOW-1 · Notification permission requested at app launch, before the user enables notifications

**File:** `Better/Core/Services/AlertGenerationService.swift:19–41`

`localNotificationsEnabled` defaults to `false`. However, depending on how `AlertGenerationService` is wired in `AppEnvironment`, authorization may be requested during onboarding regardless of whether the user will ever enable notifications. iOS gives each app **one** system permission prompt for notifications. Wasting it before the user has expressed intent is a known conversion killer.

**Fix:** Only call `UNUserNotificationCenter.requestAuthorization()` at the moment the user toggles notifications ON in Settings, not during general onboarding unless there is a dedicated notification onboarding step that explains the value first.

---

### LOW-2 · Keychain error messages don't include human-readable OSStatus descriptions

**File:** `Better/Core/Security/KeychainService.swift:74–80`

```swift
case .storeFailed(let status): "Keychain store failed: \(status)"
```

OSStatus codes like `-25300` (errSecItemNotFound) or `-34018` (errSecMissingEntitlement) are opaque to developers reading crash reports. When these errors surface in production logs or TestFlight feedback, they require a lookup to decode.

**Fix:** Add a helper that maps common OSStatus codes to readable strings, or use `SecCopyErrorMessageString(status, nil)` which returns Apple's own description.

---

## Part 5 — Encryption Architecture Assessment

The overall encryption design is **sound**:

| Property | Assessment |
|----------|-----------|
| Algorithm | AES-256-GCM via CryptoKit — correct and modern |
| Key storage | iOS Keychain with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` — correct binding |
| Key scope | Per-install, generated locally, never transmitted — correct |
| File protection | SQLite files set to `.complete` — correct |
| Migration path | `PersistenceJSON.decode` falls back to plain JSON for old records — intentional, acceptable |
| Test isolation | Unique Keychain accounts per test — correct |

The main weakness is the **silent fallback on encode failure** (HIGH-1 above), which is the only path that can undermine the encryption guarantee at runtime.

---

## Part 6 — Data Transmission Assessment

No outbound network calls were found in the codebase. All data stays on device unless the user explicitly exports via the Share Sheet. This is a strong privacy posture and should be highlighted in the App Store privacy nutrition label.

**Recommended App Store privacy label settings:**

| Data type | Collected | Linked to user | Used for tracking |
|-----------|-----------|----------------|-------------------|
| Health & Fitness | Yes — processed locally only | No | No |
| Usage Data | No | — | — |
| Diagnostics | No | — | — |

---

## 2026-05-29 Addendum — Verification Pass + Deep Performance Re-Audit

Scope: re-read the actual source against the 2026-05-28 addendum's claims (line numbers had drifted as the code evolved), then a fresh full-app sweep for HealthKit/large-data lag. Documentation only — no app code changed. Files read in full this pass: `SyncCoordinator.swift`, `HealthKitRepository.swift`, `LocalDataRepository.swift`, `PersistenceModels.swift`, `SleepDashboardViewModel.swift`, plus targeted reads across Trends, Chronotype, Protocol, Research/Export, and the biomarker services.

Tone note: most of the prior findings hold up. The line numbers were stale and a few were partially mitigated (the windowed-baseline TTL gate now exists). But the architecture still has the same shape: **CPU-heavy processing runs on the `@MainActor` sync coordinator, the dashboard recomputes baselines + chronotype on every date load, and the persistence layer decrypts full blobs for views that only need scalars.** None of that is fixed.

### A. Verification of the 2026-05-28 addendum

| Prior finding | Verdict | Current location | Note |
|---|---|---|---|
| `SyncCoordinator` is `@MainActor`, orchestrates everything on main | **Confirmed** | `SyncCoordinator.swift:14` | Worse than described: `processor.process(samples:)` at `:237` and `BaselineEngine.selectBaseline` at `:278` run **synchronously on the main actor** — not just orchestration, actual CPU work. |
| Incremental sync falls back to 90-day reprocess on deletion / anchor loss | **Confirmed** | `SyncCoordinator.swift:158–165` | Unchanged. A single deleted sample → full 90-day sleep query + reprocess. |
| Per-session × per-metric biometric hydration | **Confirmed** | `attachBiometrics` `:338–365`, fan-out `:339–351` | N sessions × 4 dashboard types. 90-night backfill ≈ 360 `HKSampleQuery` calls. |
| Baselines recomputed in several windows, only "latest" stored | **Partially mitigated** | `:267–291`, TTL gate `shouldRunWindowedBaseline` `:416–426` | A per-window TTL now exists. **But** `forceDailyProcessing: true` bypasses it, and both `performIncrementalRefresh` (`:159`, `:164`) and the observer path (`:203–206`) force it. So every HealthKit observer event still recomputes all three `[7,15,30]` baselines **and** the biomarker baseline (`:333–335`). Still no date-keyed snapshot cache. |
| `fetchSleepSamples` / biometrics use `HKObjectQueryNoLimit` | **Confirmed** | `HealthKitRepository.swift:75`, `:119`, anchored `:207` | Unbounded arrays; first-run anchored query (nil anchor) pulls full history. |
| `fetchAvailableSleepDates` decrypts full blobs for calendar dots | **Confirmed** | `LocalDataRepository.swift:78–87` | `stored.toDomain().qualityScore.overall` at `:81` decrypts `stagesData`+`sourcesData`+`qualityScoreData`+`biometricsData` per day. Root cause verified in storage layer (B1). |
| `fetchCachedSessions` always full-decodes sessions | **Confirmed** | `LocalDataRepository.swift:33–43` (`:42`) | Every Trends/baseline/chronotype read decrypts every blob even when only scalars are used. |
| `replaceSessions` deletes overlap then re-inserts | **Confirmed** | `LocalDataRepository.swift:15–31` | No upsert/content-hash skip; churns rows + encrypted blobs + unique index on every refresh. |
| `SleepDashboardViewModel.loadSelectedDate` does too much per date | **Confirmed, severe** | `:159–196` | Per selected date: session fetch + profile + on-demand baseline (60-day fetch + `BaselineEngine`) + 59-session recent fetch + context + insights + **90-day chronotype** (`loadBodyClockResult :324–346`) + biomarker refresh + month summaries. Every date swipe pays all of it. |
| `baseline(asOfSleepDateKey:)` recomputes on demand every call | **Confirmed** | `:234–260` | Fetches 60 days and runs `BaselineEngine` each call; no snapshot cache. |
| `sortedRecentSessions` "computed once" but sorts on every access | **Confirmed, still wrong** | `:44–46` | Comment claims it's memoized; it's a plain computed property that re-sorts on every access. |
| HIGH-1 silent encryption fallback | **Already resolved** | `PersistenceModels.swift` encode now throws | The comment-vs-behavior mismatch noted earlier is the only residue. |

### B. New findings this pass (not in the prior addendum)

**B1 · Severity High — No scalar `qualityScoreOverall` column; score is trapped in the encrypted blob.**
`StoredSleepSession` (`PersistenceModels.swift:181–202`) has scalar columns for every duration, `efficiency`, `waso`, `dataQualityRawValue` — but the **quality score is only inside `qualityScoreData` (`:199`)**. So any surface needing the score (calendar dots, trend points, list rows) must `toDomain()` → decrypt 4 blobs (`:298–311`). This is the literal root cause of the `fetchAvailableSleepDates` lag. Fix: add `qualityScoreOverall: Double` (and the 3–4 score components if Trends needs them) as scalar columns, backfill on migration, and return summaries without `toDomain()`.

**B2 · Severity High — `StoredNightlyBiometricSummary` already has scalar aggregates, yet `toDomain()` still decodes the raw sample blob every fetch.**
The model carries `heartRateAverage/Minimum/Maximum`, `hrvAverage/Median`, `oxygenSaturation…`, `respiratoryRateAverage` as scalars (`:323–330`) **and** a `samplesData` blob (`:322`). `toDomain()` (`:382`) always decodes `samplesData`. The dashboard reaction model only reads the scalar aggregates (`SleepDashboardViewModel.swift:209–216`). Fix: a scalar-only projection read path; stop persisting raw per-sample arrays unless a user-triggered diagnostic needs them (this is also a privacy win — fewer raw health points at rest).

**B3 · Severity High — Chronotype is computed three independent times over ~90 days.**
`SleepDashboardViewModel.loadBodyClockResult` (`:324–346`, `windowDays: 90`), `TrendsViewModel` (~`:307`), and `CronotypeViewModel` (~`:59`) each fetch their own ~91-day session window and run `ChronotypeCalculationService.estimate`. Switching Sleep → Trends → Chronotype runs the full MSFsc calculation three times, each decoding 90 sessions' stage arrays. Worse: `ChronotypeCalculationService` iterates `session.stages` per session (onset/timing extraction) — full stage-blob decode × 90 × 3 surfaces. Fix: one `ChronotypeSnapshot` keyed by `windowEndSleepDateKey`, invalidated by changed sessions/context/activity; all three surfaces read it; the dashboard computes only the cheap one-night alignment.

**B4 · Severity High — `ResearchAnalysisService.buildExportPackage` runs on every Settings tab appear.**
`SettingsViewModel.loadSettings()` → `loadResearchInsight` calls the **full export pipeline** (session fetch + `BaselineEngine.selectBaseline` recompute + protocol comparison + chronotype estimate + activity summaries) just to surface one insight string. The activity step (`loadActivitySummaries`, ~`:363–392`) can fire up to 6 live HealthKit queries **per uncached day** (≈360 queries for a 60-day window). And the ZIP serialization (`ResearchCSVExporter.writeZIP`, CRC32 byte loop) runs synchronously on the `@MainActor` `SettingsViewModel` with no `Task.detached`. Fix: persist an insight cache; move export to a background task; read activity from local daily summaries, keep live HK behind an explicit refresh.

**B5 · Severity Medium — `BiomarkerSummaryService.summaries()` queries HealthKit live every call.**
Resting-heart-rate is fetched directly from HealthKit over 60+ days (`async let rhrSamples … fetchBiometrics(for: .restingHeartRate …)`) with no SwiftData cache — RHR isn't stored in `SleepSession.biometrics`. Any screen calling this bypasses the local cache entirely. The companion `BiomarkerDiagnosticService.report` issues ~10 serial HK queries per run from a `@MainActor` path. Confirm whether `summaries()` is dead (file comment says the Biology tab is retired); if dead, delete it rather than optimize.

**B6 · Severity Medium — `TrendsViewModel` fetch window balloons to ~180 days on the 3-month view, and chart points use `UUID()` identity.**
The single fetch spans `min(comparisonStart, chronotypeStart) … now`; with the 90-day window selected, `comparisonStart` is ~180 days back → up to 180 full-decoded sessions. Separately, `TrendChartPoint` and `StageCompositionPoint` assign `id = UUID()` in `init`, so every array rebuild gives every element a new identity — `Chart`/`ForEach` diffing is defeated and the whole chart re-renders. Fix: bound the fetch to what each comparison needs; use stable `dateKey + metric` identity.

**B7 · Severity Medium — `ProtocolFormulaHomeViewModel.refresh()` double-fetches and recomputes rollups over all-time.**
`refresh()` fetches the baseline, then `impactSummary(...)` fetches the same baseline again, and `impactSummary` internally calls `rollups(in:)` over `Date.distantPast...now` (all stored sessions + logs decoded) while `recentRollups`/`nightlySnapshots` re-fetch overlapping windows — the same sessions decoded 2–3× per Home appear, all on `@MainActor`. `refreshForOffset()` re-fetches a growing `nightOffset+14`-day window on every chevron tap. Fix: one shared fetch per refresh; persist `ProtocolDailyMetricSnapshot`/version rollup cache; bound the all-time fetch.

**B8 · Severity Medium — Quadratic hot loops in stage/continuity processing.**
`SleepDataProcessor.cleanedIntervals` (`:274`, `:284`) is O(boundaries × samples) — full `rawIntervals.filter` per boundary segment. `SleepContinuityCalculator.hasFutureSleepStage` (~`:158–167`) is O(awake × stages) inside the enumerated loop. Single-night cost is fine; the danger is the unbounded `HKObjectQueryNoLimit` feeding months of raw samples into one call (B-cross-ref with HK queries). Fix: sweep-line interval resolver (O(n log n)); precompute a suffix "any sleep after index i" array for continuity.

**B9 · Severity Low — Inconsistent stddev definitions.**
`SleepDataProcessor.standardDeviation` (~`:457–462`) divides by `n` (population), while `BiomarkerBaselineService.standardDeviation` (~`:126–132`) is Bessel-corrected (`n-1`, sample). Not a lag issue, but a silent numeric inconsistency between two baseline systems. Pick one and document why.

**B10 · Severity Low — Observer error/background-delivery handling still swallows.**
`HealthKitRepository.swift:175` logs then continues the stream with no error channel; revoked permission keeps the observer firing useless refreshes. `enableBackgroundDelivery` completion (`:189–193`) is fire-and-forget. `BackgroundTaskService` (`:103–113`) still has the documented double-`setTaskCompleted` window. (These echo HIGH-2/HIGH-3 above — re-confirmed still present.)

### C. Database / storage changes that directly reduce lag

These are the highest-leverage and they don't change any user-facing number.

1. **Add scalar projection columns** to `StoredSleepSession` (`qualityScoreOverall`, optional score components, and the handful of metrics charts actually plot). Backfill on a V4 migration (invariant #7). Add a `fetchSleepDaySummaries` / `fetchTrendPoints` read path that returns structs built from columns only — never `toDomain()`. This kills the calendar-dot and trend-load decryption cost outright.
2. **Stop persisting raw biometric sample arrays by default.** `StoredNightlyBiometricSummary` already has every scalar the dashboard reads (B2). Drop `samplesData` from the default write path (keep a diagnostic-only opt-in). Smaller rows, less decrypt work, better privacy posture.
3. **Date-keyed baseline snapshot table** (`StoredDashboardBaselineSnapshot` keyed by `asOfSleepDateKey` + windowKind), with `generatedAt`, source range, validNightCount. Dashboard `baseline(asOfSleepDateKey:)` reads the snapshot instead of recomputing (`:234–260`). Weekly TTL + early invalidation when a source sleep date changes. Must be deleted by `deleteAllHealthData`.
4. **`ChronotypeSnapshot` + day/week/month summary tables** so Trends/Chronotype/Sleep read precomputed aggregates instead of re-decoding 90–180 sessions.
5. **Upsert by `sleepDateKey` with a content hash** in `replaceSessions` (`:15–31`) — skip writes for unchanged nights instead of delete-all-then-insert.
6. **Index `sleepDateKey`/`startDate`/`endDate`** if SwiftData query plans show scans on the wider windows.

### D. Calculation optimizations (no behavior change)

1. **Move sync CPU off `@MainActor`.** Introduce a non-main `HealthSyncEngine` (or mark `processor.process` / `BaselineEngine.selectBaseline` / biomarker `computeBaseline` `nonisolated` and run in a detached task). Keep only `phase`/`lastSyncedAt`/`authorizationState` on the main actor; assign one result struct after persistence. This is the single biggest perceived-jank fix.
2. **Batch biometric hydration by type over the whole sync range once**, then bucket samples into sessions in memory — collapses N×4 `HKSampleQuery` into 4. Prefer `HKStatisticsCollectionQuery` where only nightly aggregates are needed.
3. **Respect the baseline TTL on the hot path.** Stop passing `forceDailyProcessing: true` from observer-driven `performIncrementalRefresh`; recompute only baselines whose window contains a changed sleep date (`recomputeIfAffected(changedSleepDateKeys:)`).
4. **Compute the three windowed baselines in one pass** — last-7 ⊂ last-14 ⊂ last-30 of the same sorted array (`BaselineEngine.selectBaseline`); single map per metric instead of re-mapping per window (`SleepDataProcessor.computeBaseline`).
5. **Memoize `sortedRecentSessions`** as a stored property updated when `recentSessions` changes (or store `recentSessions` already sorted).
6. **Bound `HKObjectQueryNoLimit`** to anchored/paged queries after first backfill.

### E. Risky assumptions

- Adding a scalar `qualityScoreOverall` exposes a health-derived value as a plain column. It's still under `FileProtectionType.complete` and must be wiped by `deleteAllHealthData`; acceptable, but it is a (small) reduction in at-rest encryption coverage versus the blob.
- Moving processing off `@MainActor` assumes `@ModelActor LocalDataRepository` remains the persistence boundary (it does — `LocalDataRepository.swift:4–5`), so SwiftData writes stay serialized while CPU runs elsewhere.
- Dropping raw biometric samples assumes no live surface reads `biometrics.samples` beyond provenance/diagnostics — `SleepDashboardViewModel.refreshBiomarkerBaseline` uses it only for `BiomarkerProvenance.make` (`:218–223`), which needs source metadata, not the raw values. Verify before removing.
- Cached values must invalidate on: profile sleep goal, travel/context flags, protocol logs, activity status, and HealthKit sleep changes — or user-facing numbers will silently diverge from live calculation.

---

*End of Security Analysis — Better iOS App*
