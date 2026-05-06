# Suggested Improvements — Bug Fixes & Strengthening What Exists

> Superseded: use `FUTURE_IMPROVEMENT_PLAN.md` for the current improvement roadmap. This file is preserved as a historical audit, but some findings below are stale against the current code.

> Focus: perfect the fundamentals. No new features. Fix what's broken, complete what's half-done, make the existing logic rigorous.

---

## Priority 1 — Bugs That Produce Wrong Data

These are the most urgent. They make the app show incorrect information to users.

---

### BUG 1: Biology Tab Shows Fabricated Trend History

**File:** `Better/Features/Biology/BiologyViewModel.swift`

**What's wrong:**
The `syntheticHistory(around:)` function generates fake sparkline data using a hardcoded noise pattern `[-0.08, -0.04, -0.02, 0.01, -0.01, 0.02, 0.0]`. Every metric — HRV, respiratory rate, blood oxygen — shows this same manufactured trajectory regardless of what the user's actual biometric history looks like.

```swift
// Current (wrong)
func syntheticHistory(around value: Double?) -> [Double] {
    guard let value else { return [] }
    return [-0.08, -0.04, -0.02, 0.01, -0.01, 0.02, 0.0].map { value * (1 + $0) }
}
```

**What to do:**
Pull real biometric history from `LocalDataRepository`. For HRV: aggregate `biometrics?.hrvAverage` across the last N sleep sessions. For O2 and respiratory: same approach using `spo2Average` and `respiratoryRateAverage`.

If a session has no biometric data for a given metric, exclude it from the history rather than filling with synthetic noise. An empty sparkline is more honest than a fabricated one.

---

### BUG 2: All Trend Labels Are Hardcoded Strings

**File:** `Better/Features/Biology/BiologyViewModel.swift` (inside `makeMetrics()`)

**What's wrong:**
The `trend` field on every `BiologyMetric` is hardcoded to a static string. A `trend()` function exists in the same file but is never called.

```swift
// Current (wrong) — same for every metric
BiologyMetric(
    ...
    trend: "Stabilizing",  // ← never changes
    ...
)
```

**What to do:**
Wire `trend()` to the actual computed history. The function takes an array of Doubles and returns a direction. Once Bug 1 is fixed and `history` reflects real values, `trend: trend(history)` becomes trivially correct. The fix is a one-line change per metric once real history data is available.

---

### BUG 3: Resting Heart Rate Uses Sleep HR Instead of Apple's RHR

**File:** `Better/Features/Biology/BiologyViewModel.swift`

**What's wrong:**
The resting heart rate fallback uses `heartRateAverage` from a sleep session. That's the average HR during sleep — a different measurement entirely from resting heart rate, which Apple Watch calculates during quiet waking periods.

```swift
// Current (wrong)
func restingHeartRateFallback(latestSession: SleepSession?) -> Double? {
    latestSession?.biometrics?.heartRateAverage  // sleep HR ≠ resting HR
}
```

**What to do:**
Query `HKQuantityType(.restingHeartRate)` directly from HealthKit, with a date range query for the last available value. Apple Watch computes this natively. The `HealthKitRepository` already has the infrastructure for quantity-type queries — add `restingHeartRate` to the biometric fetch or expose a dedicated query method.

---

### BUG 4: Research Analysis Includes Sick/Injured Nights in "Adjusted" Metrics

**File:** `Better/Core/Services/ResearchAnalysisService.swift` (inside `buildProtocolSummaries()`)

**What's wrong:**
The confounding adjustment step filters out only travel and jet-lag nights. Sick and injured nights are excluded from the `isConfounded` check in the adjusted analysis but should be treated the same way — they're equally likely to distort the relationship between a protocol and sleep quality.

```swift
// Current (wrong)
let adjustedTakenRows = takenRows.filter { !$0.isTravelConfounded }
let adjustedMissedRows = missedRows.filter { !$0.isTravelConfounded }

// Should be
let adjustedTakenRows = takenRows.filter { !$0.isConfounded }
let adjustedMissedRows = missedRows.filter { !$0.isConfounded }
```

**What to do:**
Replace `isTravelConfounded` with `isConfounded` in both filter calls. The `isConfounded` property already correctly covers travel, jet-lag, sick, and injured states. This is a two-character change with meaningful statistical impact — sick nights with disrupted sleep could falsely inflate or suppress protocol effect sizes.

---

## Priority 2 — Logic Inconsistencies That Undermine Trust

These don't crash the app but produce quietly wrong calculations.

---

### ISSUE 5: Health Score Uses 8.8-Hour Target; Baseline Uses 8.0-Hour Goal

**File:** `Better/Core/Models/SleepModels.swift` (inside `HealthSleepScoreEstimator`)  
**Also:** `Better/Core/Processors/SleepDataProcessor.swift`

**What's wrong:**
The `HealthSleepScoreEstimator.durationComponent()` hardcodes a 8.8-hour sleep target for its scoring curve. The `SleepDataProcessor` uses `sleepGoalHours`, which defaults to 8 hours and is conceptually configurable. The same user's performance is evaluated against two different targets depending on which part of the code runs.

```swift
// SleepModels.swift — hardcoded
let targetSleepSeconds = 8.8 * 3_600

// SleepDataProcessor — uses the goal
let durationScore = min(totalSleepTime / (sleepGoalHours * 3_600), 1.0) * 100
```

**What to do:**
Unify the target. Either pass `sleepGoalHours` into the health score estimation, or define a single constant that both systems reference. The health score should reflect the same goal the user set (or the same default the processor uses).

---

### ISSUE 6: Protocol Timing Is Computed But Never Analyzed

**File:** `Better/Core/Services/ResearchAnalysisService.swift`

**What's wrong:**
`NightlyResearchRow.minutesFromProtocolToSleep` is calculated and included in the CSV export. It captures how many minutes before sleep each protocol was taken. This data is collected, formatted, and shipped — but it's never used in the effect summary computation.

The protocol effect summary compares "taken vs missed" but treats all "taken" nights identically, whether the supplement was taken 30 minutes or 5 hours before sleep. For many supplements, timing is the variable that matters most.

**What to do:**
In `buildProtocolSummaries()`, add a timing bucket split: group "taken" rows into early (>3h before sleep), optimal (1–3h), and late (<1h). If sample sizes allow (≥5 per bucket), report the delta per bucket. If sample sizes are too small to split, note it as a caveat. This doesn't require new data collection — the data already exists in the rows.

---

### ISSUE 7: Missing Null Safety on Biometric Aggregations

**File:** `Better/Core/Processors/SleepDataProcessor.swift`

**What's wrong:**
When computing biometric summaries (HRV, HR, O2, respiratory) for a session, values are aggregated only if present. But several downstream consumers — notably `ResearchAnalysisService.buildNightlyRows()` — access `biometrics?.hrvAverage` without guarding for the case where an entire night has no biometric data.

If HealthKit doesn't return heart rate data for a session (older device, Watch not worn, HK permissions revoked), the downstream delta calculations produce `nil` deltas. These nil deltas are then written to CSV as empty strings, which silently breaks any external analysis that expects numeric columns to always have values.

**What to do:**
In `buildNightlyRows()`, mark rows with missing biometrics explicitly: either a boolean `hasBiometrics` column in the CSV, or a convention of writing `-1` / `NA` for unavailable values with documentation in `export_metadata.csv`. This makes the data export correctly interpretable rather than having columns that are sometimes numeric, sometimes empty.

---

## Priority 3 — Test Coverage Gaps

The existing tests are high quality. These gaps mean real bugs in these areas could go undetected.

---

### GAP 8: BiologyViewModel Has Zero Tests

The `BiologyViewModel` contains the three bugs above and no test coverage. A test would have caught the hardcoded trend strings immediately.

**What to add:**
- Test that `makeMetrics()` returns a non-empty array when biometric data is available
- Test that `trend` values are derived from `history` values, not static strings
- Test that real HRV history from mock sessions flows into the sparkline data
- Test that resting heart rate uses the correct HealthKit type

---

### GAP 9: ResearchAnalysisService Confounding Filter Is Not Tested

The bug in Priority 1, Issue 4 (sick nights included in adjusted analysis) would have been caught if there was a test for confounded row filtering.

**What to add:**
- Test `buildProtocolSummaries()` with a mix of active, traveling, and sick nights — verify sick nights are excluded from the adjusted mean calculation
- Test that the `confounderFraction` calculation in confidence scoring counts sick/injured nights, not just travel

---

### GAP 10: Circular Statistics Not Tested for Edge Cases Near Midnight

**File:** `BetterTests/SleepDataProcessorTests.swift`

The circular mean tests exist, but there's no test for the circular standard deviation calculation when bedtimes are tightly clustered around midnight (e.g., 11:45pm and 12:15am). A regression here would cause schedule consistency scores to appear artificially high or low.

**What to add:**
- Test circular std-dev with a set of times that straddle midnight
- Test that the schedule consistency display in `ScheduleConsistencyView` correctly reflects the calculated std-dev, not just that the calculation is right

---

## Summary

| # | Area | Severity | Fix Scope |
|---|------|----------|-----------|
| 1 | Synthetic biometric history | High — wrong data shown | Replace with real HealthKit history |
| 2 | Hardcoded trend labels | High — wrong data shown | Wire `trend()` to real history |
| 3 | Sleep HR used as resting HR | High — wrong health metric | Query `HKQuantityType(.restingHeartRate)` |
| 4 | Sick nights in adjusted analysis | Medium — statistical error | Change `isTravelConfounded` → `isConfounded` |
| 5 | Mismatched sleep goal targets | Medium — inconsistent scoring | Unify `targetSleepSeconds` constant |
| 6 | Protocol timing ignored in analysis | Medium — incomplete analysis | Add timing bucket split in summaries |
| 7 | Silent nulls in CSV biometric columns | Low-Medium — bad export data | Explicit null markers in CSV |
| 8 | BiologyViewModel untested | Coverage gap | Add ViewModel unit tests |
| 9 | Confounding filter untested | Coverage gap | Add confounding filter tests |
| 10 | Circular std-dev edge cases | Coverage gap | Add midnight-straddle tests |

The highest leverage fixes are 1–4. They directly affect what numbers the user sees and trusts. Fixing these makes the existing product substantially more reliable without adding a single new feature.
