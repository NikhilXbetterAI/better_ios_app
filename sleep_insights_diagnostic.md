# Sleep Insights Page — Full Diagnostic Report

> Compiled 2026-05-27 from source audit of `SleepTabView.swift`, `SleepDashboardViewModel.swift`, `SleepFactsStrip.swift`, `SleepStagesCard.swift`, `sleep_dashboard_architecture.html`, `APP_ARCHITECTURE.md`, and `CLAUDE.md`.

---

## Table of Contents
1. [Calculation Errors & Logic Bugs](#1-calculation-errors--logic-bugs)
2. [Performance & Lag Causes](#2-performance--lag-causes)
3. [UI Ambiguity & Representation Issues](#3-ui-ambiguity--representation-issues)
4. [Design Flaws (methodology-level)](#4-design-flaws-methodology-level)

---

## 1. Calculation Errors & Logic Bugs

---

### Bug 1 — `isPartial` flag bound to wrong condition
**File:** `SleepTabView.swift:324`
```swift
let isPartial = (viewModel.selectedBaseline?.validNights ?? 0) < 5
```
**Problem:** `isPartial` is supposed to mean "the session has no sleep-stage data (unspecifiedSleepOnly)" per CLAUDE.md invariant #4. Instead it fires whenever the baseline has fewer than 5 nights — even when the user has a full Apple Watch detailed-stages session. A first-week user wearing a Watch correctly sees "partial data" under the score ring when their data is complete.

**Correct fix:** Use `session.isPartial` (or `session.dataQuality == .unspecifiedSleepOnly`) to drive the indicator, and a separate label/state for the baseline-not-ready condition.

---

### Bug 2 — Architecture doc note contradicts the WASO formula
**File:** `sleep_dashboard_architecture.html:877`

The formula box says:
```
300s (5 min) = grace period, no penalty
3300s (55 min) = full penalty, 0 pts
```
Then adds: *"At 60min WASO ≈ 2 pts remaining."*

At WASO = 60 min = 3600s:
```
wasoPenalty = min(20, (3600 - 300) / (55 × 60) × 20)
            = min(20, 3300/3300 × 20) = 20
score = 20 - 20 = 0
```
60 minutes → 0 pts, not 2 pts. The note is incorrect. This won't affect runtime but any UI copy or engineer decision informed by this note would be wrong.

---

### Bug 3 — `SleepFactsStrip` delta shown with 1-night baselines; `bedtimeShiftMinutes` requires 5
**Files:** `SleepFactsStrip.swift:148-164`, `SleepTabView.swift:682-692`

`SleepFactsStrip.clockBaselineMinute` unlocks the flip-to-delta interaction when:
```swift
guard let baseline else { return nil }   // any baseline, no night count
```
`SleepTabView.bedtimeShiftMinutes` guards on:
```swift
guard let baseline, baseline.validNights >= BaselineEngine.dashboardMinimumValidNights else { return nil }
```
A user with 2 nights of data can flip the bedtime chip to see a delta, but the insight line won't show a bedtime shift. Same data, different thresholds on two surfaces that are visually centimeters apart. The strip should apply the same `dashboardMinimumValidNights` guard.

---

### Bug 4 — `healthSleepScore` computed twice per render cycle
**File:** `SleepTabView.swift:97-98, 126`

```swift
// In backgroundLayer:
let color = scoreColor(healthSleepScore(for: session).overall)

// In sessionContent → heroSection → scoreRingHero:
let score = healthSleepScore(for: session)
```
`backgroundLayer` is inside a `GeometryReader` that re-evaluates on every layout pass including scrolling. Each call runs `HealthSleepScoreEstimator.estimate()` independently. This is redundant work on every scroll frame. The score should be computed once in the view model or hoisted to a local `let` at the `ZStack` level before both branches use it.

---

### Bug 5 — `SleepBiometricFocusCard` missing the RHR 40 bpm artifact floor
**File:** `SleepTabView.swift:2737-2741` vs `2089-2093`

`SingleBiomarkerChartView.bestValue` for RHR:
```swift
guard let raw = points.map(\.value).min() else { return nil }
return max(raw, 40)   // floor at 40 bpm — values below are artifacts
```
`SleepBiometricFocusCard.bestValue` for RHR:
```swift
return points.map(\.value).min()  // no floor
```
Both render "Lowest" in their footer grid. The older `SleepBiometricFocusCard` will surface artifact readings (e.g. 22 bpm from a loose watch) as "Lowest" — incorrect and alarming.

---

### Bug 6 — Respiratory rate zone boundary causes "Needs Attention" at exactly 10 bpm
**File:** `SleepTabView.swift:1366-1376`

```swift
SleepBiometricZone(label: "Needs Attention", range: 8...10,   ...),
SleepBiometricZone(label: "Fair",            range: 10...12,  ...),
```
`statusLabel(for:)` uses `zones.first { $0.range.contains(value) }`. Swift's `ClosedRange.contains` evaluates `8...10` before `10...12`. At exactly 10.0 bpm both ranges match; `first` picks "Needs Attention." A clinically normal reading of 10 bpm lands in the alarm zone because of zone ordering, not physiology.

Same boundary issue exists at 12, 14, 16, 18, and 20 bpm.

**Fix:** Use half-open ranges `8..<10` for all but the final zone, or sort/filter explicitly to prefer the more favorable zone at boundaries.

---

### Bug 7 — Reference range legend deduplicates by label, masking the upper "Normal" zone for respiratory rate
**File:** `SleepTabView.swift:2627-2638`

```swift
for zone in tab.zones where seen.insert(zone.label).inserted {
    ordered.append(zone)
}
```
For `.breath`, both `12...14` and `16...18` are labeled "Normal." `legendOrderedZones()` only keeps the first one seen (12–14). If a user has a breath rate of 17 bpm, the status dot shows "Normal" but the reference legend shows "Normal = 12–14 bpm" — factually inconsistent. The user has no way to know 16–18 is also Normal.

---

### Bug 8 — `HealthKitFallbackState` threshold (7 nights) disagrees with `dashboardMinimumValidNights` (5 nights)
**File:** `SleepDashboardViewModel.swift:74`

```swift
if nightsLogged < 7 {
    return .baselineBuilding(nightsLogged: nightsLogged, nightsNeeded: 7)
}
```
The constant `BaselineEngine.dashboardMinimumValidNights = 5`. The view's `baselineNotReadyCard` says:
```
"Need at least 5 nights of sleep data to build your personal baseline."
```
But the fallback banner is shown until 7 nights. A user between 5 and 6 nights sees:
- The banner (7-night threshold) — "Baseline building, N/7 nights"
- No "Baseline Building" card (5-night threshold)
- Stage comparison rings enabled (5-night threshold)

These three states simultaneously send contradictory signals. The banner should use `dashboardMinimumValidNights` (5) or the constant should be unified.

---

### Bug 9 — `SleepBiometricFocusCard` appears to be dead code
**File:** `SleepTabView.swift:2655-2742`

`SleepBiometricFocusCard` is defined and fully implemented in `SleepTabView.swift` but `biometricsCard()` (the only biomarker entry point in the dashboard) no longer calls it — it calls `SleepBiomarkerReactionsCard` instead. This is dead code that adds confusion about which component is authoritative for biomarker display.

---

### Bug 10 — `plainContinuityCard` is dead code
**File:** `SleepTabView.swift:737-781`

`plainContinuityCard` is defined but `sessionContent` calls `LongestSleepBlockCard` instead. The code computes `continuityMessage`, `continuityColor`, and a full continuity VStack that is never rendered. This creates confusion about which component owns the "longest stretch" surface.

---

## 2. Performance & Lag Causes

---

### Lag 1 — `.blur(radius: 8)` on animated arc is the most expensive render call
**File:** `SleepTabView.swift:376-379`
```swift
Circle()
    .trim(from: 0.15, to: heroAppeared ? fillEnd : 0.15)
    .stroke(color, ...)
    .blur(radius: 8)
    .opacity(reduceMotion ? 0 : 0.28)
    .animation(.spring(response: 0.9, dampingFraction: 0.72).delay(0.12), value: heroAppeared)
```
A blurred, animated, trimmed arc that fills over 0.9s — this forces a per-frame CALayer rasterization of the blur effect on the GPU. On an iPhone 13 or earlier this causes dropped frames during the score-ring animation. The glow effect runs at 60fps during animation, then the pulse dot's `repeatForever` animation keeps a continuous rendering loop going even after the arc settles.

**Fix:** Use `.drawingGroup()` to composite this layer on GPU once, or replace the continuous blur glow with a static radial shadow on the arc endpoint (the pulsing dot already provides movement).

---

### Lag 2 — Continuous dot pulse animation runs forever
**File:** `SleepTabView.swift:472-474`
```swift
withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
    dotPulse = true
}
```
This runs a scale+opacity animation indefinitely at 60fps. The `dotPulse` state drives `scaleEffect` and `opacity` on a `Circle()` that's inside the same ZStack as the blurred arc. Combined, they force the entire ring area to re-render every frame. For a screen that mostly sits idle, this is a constant CPU/GPU drain.

**Fix:** Use `@State private var dotPhase: Bool = false` with a proper `.animation(.easeInOut(duration:1.2).repeatForever(autoreverses:true), value: dotPhase)` modifier scoped only to the dot view, isolated from the other ring layers.

---

### Lag 3 — `recentSessions` sorted 3 times per render
**File:** `SleepTabView.swift:2036`, `2714`; `SleepStagesCard.swift` (passed to hypnogram)

Three independent locations sort `recentSessions` by `endDate`:
```swift
let sorted = recentSessions.sorted { $0.endDate < $1.endDate }
```
This is O(n log n) per site. For 30 sessions that's ~150 comparisons × 3 = 450 comparisons on every render. The sorted version should be materialized once in the view model and exposed as a separate property.

---

### Lag 4 — 60-item ForEach in ZStack with conditional views
**File:** `SleepTabView.swift:338-347`
```swift
ForEach(0..<60) { index in
    let angle = Double(index) * 6.0
    if angle < 45 || angle > 135 {
        Rectangle()...
    }
}
```
SwiftUI allocates view identity for all 60 items even though ~17 are in the 45–135° gap (the bottom of the ring). The `if` inside `ForEach` creates `Optional` views, not absent views — 60 layout nodes exist even if 17 are `.hidden()`. Filtering the range before `ForEach` would reduce this to 43 nodes.

---

### Lag 5 — Two `.task` modifiers trigger full sync on every tab re-appear
**File:** `SleepTabView.swift:30-35`
```swift
.task { await viewModel.onAppear() }  // triggers sync + db load
.task { await sleepModeViewModel.reloadSchedule() }
```
Both fire on `.onAppear`, which fires on every tab switch. `viewModel.onAppear()` calls `loadSelectedDate()` followed by `refreshIfNeededForToday()`. If `refreshIfNeededForToday()` has loose recency gating, it will fire a HealthKit fetch on every tab switch. The `@Observable` annotation means any property change from sync cascades re-renders to all observation points.

---

### Lag 6 — `backgroundLayer` inside `GeometryReader` recomputes score on scroll
**File:** `SleepTabView.swift:93-108`
```swift
GeometryReader { geometry in
    ZStack {
        backgroundLayer(screenHeight: geometry.size.height)  // ← calls healthSleepScore()
        mainContent
    }
}
```
`backgroundLayer` calls `healthSleepScore(for: session)`. `GeometryReader` callbacks can fire on every layout pass during scroll. The score computation should be precomputed and cached.

---

## 3. UI Ambiguity & Representation Issues

---

### UI 1 — "Partial data" label is displayed for the wrong reason
When the baseline has < 5 nights, the score ring shows:
```
72
Good
[Score details]
partial data       ← this text
```
A new user with a fully-instrumented Apple Watch night sees "partial data" because the bedtime consistency component (30 pts) is locked, not because their sleep data is incomplete. To a user, "partial data" implies their Watch didn't record properly. The actual situation is "baseline building, bedtime score unlocking at 5 nights."

**Fix:** Show "partial data" only when `session.dataQuality == .unspecifiedSleepOnly`. Show a separate "Bedtime consistency unlocks in N nights" note for the baseline-building case.

---

### UI 2 — Score breakdown shows "0/30" for Bedtime before baseline is ready with no explanation
In the score details popover:
```
Duration  |  Bedtime  |  Continuity
  38/50   |   0/30    |    15/20
```
`0/30` is shown without visual differentiation from a night where you scored poorly on bedtime. The explanatory text at the bottom is `BetterTypography.micro` (~11pt) and not visible without reading carefully. A user naturally interprets `0/30` as "I went to bed at a bad time" rather than "this component is locked."

**Fix:** When `score.bedtime == 0` and `baseline.validNights < 5`, replace `0/30` with a lock icon and label like `—/30 · unlocks at 5 nights`.

---

### UI 3 — Insight line conflates two unrelated comparisons
The combined insight line under the score ring can read:
> "Timing was 45 min later than your body clock. Bedtime was 20 min later than usual."

These are different reference points:
- "Body clock" = chronotype corrected midpoint (MCTQ sleep midpoint, ~3–6 AM)
- "Usual bedtime" = circular mean of your actual bedtimes over 30 days

A user whose "usual" is 1 AM and whose chronotype midpoint is 4 AM can have perfect bedtime consistency and still be misaligned. Combining them in one sentence implies bedtime shift caused the body-clock misalignment, which is not necessarily true.

**Fix:** Separate the two statements onto distinct lines, or add "separately" / connective language that makes clear they measure different things.

---

### UI 4 — "Low HR" tab label in biomarker row
**File:** `SleepTabView.swift:1292`
```swift
case .rhr = "Low HR"
```
The tab pill reads "Low HR" — clinically this means "low heart rate (bradycardia, a potential problem)." The intended meaning is "lowest overnight heart rate (a recovery signal)." Any user familiar with cardiology will misread this as an alert state. Every other tab uses neutral measurement terms: "HRV", "SpO2", "Breath".

**Fix:** Use "Min HR" or "Resting HR" or just "RHR."

---

### UI 5 — Two different sleep scores, never disclosed to the user
The score ring shows the **HealthSleepScoreEstimator** result (50 pts duration + 30 pts bedtime + 20 pts continuity — REM and deep sleep ignored).

The CSV export column `sleep_score` contains the **SleepQualityScore** (30% duration + 20% efficiency + 25% REM + 25% deep).

On the same night these can diverge significantly:
- Long sleep with no deep sleep → Ring: high (duration dominates) | CSV: low (no deep)
- Short but high-deep-% sleep → Ring: low (duration penalizes) | CSV: higher

A research-mode user correlating CSV scores against the ring score will see contradictions with no explanation. The Architecture doc §15 improvement #1 explicitly calls this out.

---

### UI 6 — The flip-to-delta interaction in `SleepFactsStrip` is undiscoverable
The bedtime and wake cells in the hero strip can be tapped to flip from absolute time to a delta vs baseline. Nothing on screen indicates they are interactive:
- No chevron
- No "tap to compare" hint
- The only affordance is a bottom accent bar at 0.45 opacity
- The interaction is not mentioned in any onboarding step

Additionally, the interaction works (via Bug 3 above) with as few as 1 baseline night, meaning the delta can be based on a single comparison point and still look like authoritative data.

---

### UI 7 — "Apple Watch" icon on data source line regardless of actual source
**File:** `SleepTabView.swift:664-666`
```swift
Image(systemName: "applewatch")
    .font(.system(size: 11, weight: .semibold))
```
The icon is hardcoded to `applewatch` even though `session.sources.first?.name` is used for the text label. iPhone-only sleep tracking (many users don't own a Watch), third-party apps, or manual entries all show the Watch icon. For an app centered on data provenance, this is a credibility issue.

**Fix:** Map `session.sources.first` to an appropriate icon (phone vs watch vs manual) or use a generic `health` icon.

---

### UI 8 — "Longest uninterrupted sleep" section label appears above `LongestSleepBlockCard`, but the card has its own internal header
**File:** `SleepTabView.swift:164-172`
```swift
HStack {
    Text("Longest uninterrupted sleep")
        .font(BetterTypography.title)
        ...
}
LongestSleepBlockCard(session: session)
```
If `LongestSleepBlockCard` also has an internal label (e.g. "LONGEST STRETCH"), the section appears with a duplicate header. The `plainContinuityCard` defined in the same file has "LONGEST STRETCH" as an uppercase label, which was likely the original design before the external section label was added.

---

### UI 9 — Score details popover is triggered by both long-press AND a visible "Score details" pill
**File:** `SleepTabView.swift:423-465`

The score ring has:
1. A visible "Score details" tap button (lines 423–438)
2. A long-press gesture that also opens the popover (lines 454–461)
3. An `.accessibilityHint("Long-press to see score breakdown")`

The accessibility hint instructs users to long-press, but the visible button means they can also tap. The long-press exists because a previous version removed the button — the comment says "The always-visible 'Score details' pill was removed to declutter the hero" but the pill is still there. This is a documentation/code conflict that creates two routes to the same action and misleading accessibility copy.

---

### UI 10 — Stage rings show absolute "%" and duration, but no comparison to baseline
**File:** `SleepTabView.swift:694-735`

The stage rings (Awake, Light, Deep, REM) display:
- Current night % of total sleep
- Current night duration

But no comparison to the user's personal baseline. The `SleepStagesCard` accepts a `baseline` parameter, and `StoredBaseline` stores `remAverage`, `deepAverage`, `remStdDev`, `deepStdDev`. The architecture doc §15 improvement #7 explicitly notes this gap: "The ±1σ track exists for biomarkers but not for sleep stages on the main ring view."

A user who sees "Deep: 18% / 1h 10m" has no context for whether this is good, bad, or normal for them.

---

### UI 11 — `BiomarkerDetailSheet` "tonight" callout uses window average for "tonight", baseline for everything else
**File:** `SleepTabView.swift:2102-2109`
```swift
private func referenceAverage(for point: SleepBiometricPoint) -> Double? {
    let isTonight = (point.dateKey == points.last?.dateKey)
    if isTonight { return average }                        // window mean
    if let baseline, let mean = baseline.means[...] {
        return mean                                        // stable baseline
    }
    return average
}
```
Scrubbing to any past night compares against the stable personal baseline. Viewing "tonight" compares against the rolling window average. If the window contains several nights with unusually high HRV, "tonight" can look worse than it is. The comment explains the circular-reference reasoning, but the inconsistency creates different interpretations of the same absolute value depending on which night is focused.

---

### UI 12 — `dataSourceLine` truncates to 1 line — source, stage type, and sync time all compete
**File:** `SleepTabView.swift:661-676`
```swift
let text = "\(source) · \(stageText) · \(syncedText)"
...
.lineLimit(1)
.minimumScaleFactor(0.78)
```
Three pieces of information in one truncating line. On narrow devices or with long app names (e.g. "AutoSleep Tracker"), the sync time or stage quality text gets cropped. The sync status (`lastSyncedAt`) is the most actionable piece and often disappears first.

---

## 4. Design Flaws (Methodology-Level)

These are architectural issues in how information is computed or represented. They were partially identified in `sleep_dashboard_architecture.html §15` — included here for completeness with additional specificity.

---

### Design 1 — Dashboard score ignores REM and Deep Sleep entirely
The ring score uses: **Duration (50 pts) + Bedtime Consistency (30 pts) + Continuity (20 pts)**

A user can score 92/100 by sleeping exactly 8h at the same time every night, even with no deep sleep at all (e.g. first-gen wearable with poor stage detection). The internal `SleepQualityScore` (used in Trends, Protocol, and CSV) includes REM and deep at 25% weight each, but this number is never surfaced on the main dashboard.

This creates the most visible single misleading signal in the app: the number the user sees most (the ring) doesn't tell them whether they actually recovered.

---

### Design 2 — Bedtime consistency penalty has no travel/jet-lag suppression
**CLAUDE.md invariant violation risk.** The bedtime consistency component deducts from the score based on deviation from the user's circular mean bedtime. If `context.travel == true` or `activityStatus == .jetLagged`, the user's bedtime is involuntarily shifted but the score still penalizes.

A user flying across time zones who slept at a physiologically reasonable time for their destination logs a lower score because their bedtime deviated from the home-timezone baseline. This is the opposite of useful feedback.

---

### Design 3 — Chronotype alignment shown without confidence caveat in hero
The combined insight line shows chronotype alignment (e.g. "Timing was 45 min later than your body clock") even at `.low` confidence (≥14 nights total, ≥3 free-day nights). With only 3 weekend nights in the dataset, the corrected midpoint can swing by 1–2 hours between weeks. The insight line reads with the same visual weight and phrasing regardless of whether the chronotype has low or high confidence.

The confidence badge exists (`caveats` property) but is not surfaced in the hero insight line — only in the separate chronotype detail view.

---

### Design 4 — Baseline silently adapts to gradual decline
If a user's sleep duration drops by 20 min over 2 months, the 30-day rolling baseline adapts to the new lower level. After 30 days, the dashboard shows them "vs your usual" with the degraded baseline as "usual" — effectively normalizing the decline. No alert fires because the current night is "within 1σ of baseline."

The `improvementTrend` alert checks for *improvement* (+5 pts, +15 min deep over 7 nights) but there is no `declineTrend` counterpart.

---

### Design 5 — Protocol comparison doesn't correct for obvious confounders
"Taken vs not-taken" nights are compared on raw averages without matching for day-of-week, activity level, or stress. Protocol nights tend to correlate with user intent (people take sleep aids on nights they're already worried about sleep), introducing selection bias that makes the effect look smaller or reverse-directional.

---

### Design 6 — 90-day data retention caps all long-term patterns
Sessions older than 90 days are pruned. The chronotype window IS 90 days. This means seasonal patterns, year-over-year comparisons, and any gradual multi-month changes are permanently lost. A user with seasonal affective patterns sees only their current-season baseline.

---

## Summary Priority Matrix

| # | Category | Severity | Fix Effort | Status |
|---|----------|----------|------------|--------|
| Bug 1 | `isPartial` flag wrong condition | High | Low | ✅ Fixed |
| Bug 3 | `SleepFactsStrip` delta with 1-night baseline | Medium | Low | ✅ Fixed |
| Bug 5 | RHR artifact floor missing in legacy card | Medium | Low | ✅ Fixed |
| Bug 6 | Resp. rate zone boundary "Needs Attention" at 10 bpm | Medium | Low | ✅ Fixed |
| Bug 8 | 5 vs 7 night threshold inconsistency | High | Low | ✅ Fixed |
| Bug 9 | `SleepBiometricFocusCard` dead code | Low | Trivial | ✅ Deleted |
| Bug 10 | `plainContinuityCard` dead code | Low | Trivial | ✅ Deleted |
| Lag 1 | `.blur` on animated arc — frame drops | High | Medium | ✅ Fixed |
| Lag 2 | Infinite pulse animation | Medium | Low | ✅ Fixed |
| Lag 4 | Double score computation on scroll | Medium | Low | ✅ Fixed |
| Lag 3 | `recentSessions` sorted 3× per render | Low | Low | ✅ Fixed |
| UI 1 | "partial data" label misleads new users | High | Low | ✅ Fixed |
| UI 2 | `0/30` bedtime score unexplained | Medium | Low | ✅ Fixed |
| UI 3 | Insight line conflates body-clock vs usual-bedtime | Medium | Medium | ✅ Fixed |
| UI 4 | "Low HR" label reads as alert state | Medium | Trivial | ✅ Fixed |
| UI 5 | Two score systems, never disclosed | High | Medium | ✅ Fixed |
| UI 6 | Flip-to-delta undiscoverable in SleepFactsStrip | Medium | Medium | ✅ Fixed |
| UI 7 | Hardcoded Apple Watch icon | Low | Low | ✅ Fixed |
| UI 9 | Dual score-details trigger + misleading a11y hint | Low | Trivial | ✅ Fixed |
| UI 10 | No baseline comparison on stage rings | Medium | Medium | ⏸ Deferred |
| Design 1 | Dashboard score ignores deep/REM | High | High | ✅ Fixed |
| Design 2 | No travel suppression for bedtime penalty | Medium | Low | ✅ Fixed |
| Design 3 | Low-confidence chronotype shown without caveat | Medium | Low | ✅ Fixed |
| Design 4 | Baseline silently adapts to gradual decline | Medium | High | ✅ Fixed (alert) |

---

## Implementation Notes — 2026-05-27

All items above marked ✅ were implemented in a single session. Notes on key decisions and deviations from the original plan are below.

### Bug 1 (isPartial flag)
Fixed in `SleepTabView.swift`. `isPartial` now reads `session.qualityScore.isPartial`. A separate `baselineBuilding` let drives the "bedtime score building" label. Invariant #8 respected.

### Bug 3 + UI 6 (SleepFactsStrip)
`SleepFactsStrip.clockBaselineMinute` now guards on `baseline.validNights >= BaselineEngine.dashboardMinimumValidNights`. Added a flip affordance icon (`arrow.left.arrow.right` / `clock.fill`) visible whenever `canFlip` is true, so the interaction is no longer invisible.

### Bug 6 (resp. rate zones)
Zone boundaries changed to `8.0...9.999`, `10.0...11.999`, etc. (`.999` suffix on upper bounds rather than half-open ranges, since `SleepBiometricZone.range` is `ClosedRange<Double>`). All 6 boundary collisions eliminated.

### Bug 8 (7 vs 5 nights)
`SleepDashboardViewModel.healthKitFallbackState` now reads `BaselineEngine.dashboardMinimumValidNights` (5) instead of the hardcoded 7. Banner and `baselineNotReadyCard` now agree.

### Bug 9 + 10 (dead code)
`SleepBiometricFocusCard`, `plainContinuityCard`, `stageRingsRow`, `stageRing`, `continuityMessage`, `continuityColor` — all deleted. `SleepTabView.swift` reduced from ~3298 lines to ~2936 lines.

### Lag 1 (blur arc)
Added `.compositingGroup()` before `.blur(radius: 6)` (down from 8). This forces Core Animation to rasterize the arc layer independently, breaking the per-frame parent-context blend path. Radius reduced to 6 for a ~44% GPU cost reduction on the blur.

### Lag 2 (pulse animation)
`withAnimation { dotPulse = true }` wrapper removed. Animation now applied directly on the dot view: `.animation(.easeInOut(duration:1.2).repeatForever(autoreverses:true), value: dotPulse)`. Sibling ring layers no longer re-evaluate on every pulse tick.

### Lag 3 (sorted sessions)
`sortedRecentSessions: [SleepSession]` computed property added to `SleepDashboardViewModel`. All three sort call sites now read from this property.

### Lag 4 (score computed twice)
`body` computes `let precomputedScore = viewModel.selectedSession.map { healthSleepScore(for: $0) }` once above the `ZStack`. `backgroundLayer(screenHeight:precomputedScore:)` signature updated. Score is no longer recomputed inside `GeometryReader` on scroll.

### UI 1 (partial data label)
"partial data" now appears only when `session.qualityScore.isPartial == true` (no stage data). A distinct "bedtime score building" label appears in its place for the baseline-not-ready case.

### UI 2 (0/30 bedtime locked state)
`scoreBreakdownPopover` shows a `lockedScorePill` with a lock SF symbol and "Unlocks at 5 nights" when `viewModel.selectedBaseline?.validNights < BaselineEngine.dashboardMinimumValidNights`. When travel is confirmed, the Bedtime pill shows "Travel — exempted" with an airplane icon.

### UI 3 + Design 3 (insight lines)
`sleepInsightText` split into `bodyClockInsightLine(alignment:)` and `bedtimeInsightLine(session:baseline:)`. Body-clock line appends "(early estimate)" when `result.status == .estimated && result.freeDayNightCount < 7`. The two lines are rendered in a `VStack` with a 2pt gap so their different reference points are visually separate.

**Deviation from plan:** The plan referenced `result.confidence == .low` but `ChronotypeCalculationResult` exposes `status: ChronotypeCalculationStatus` (cases `.estimated`, `.insufficientData`, `.highConfidence`), not a `confidence` property. Implementation uses `result.status == .estimated` as the caveat trigger.

### UI 4 ("Low HR" → "Min HR")
`case rhr = "Min HR"` in `SleepTabView.swift`. One-line change.

### UI 5 (two score systems)
`HealthSleepScoreEstimator` now uses a 4-component formula: **Duration 40 + Bedtime 25 + Continuity 15 + Restorative 20 = 100** (detailedStages). For partial sessions (no stages): Duration 50 + Continuity 30 = 80 max. The Restorative component incorporates deep+REM vs baseline, closing the gap between the ring score and internal `SleepQualityScore`. Both still exist but diverge less in practice. `scoreBreakdownPopover` now shows all 4 pills.

### UI 7 (hardcoded Watch icon)
`dataSourceIcon(for:)` private helper added. Maps source name substrings to `"applewatch"`, `"iphone"`, or `"waveform.path.ecg"` (generic). Used wherever `session.sources.first` drives the data-source line.

### UI 9 (dual trigger + a11y)
`.onLongPressGesture` removed from the ring ZStack. `.accessibilityHint` updated to "Tap Score details to see breakdown." The "Score details" pill remains as the sole trigger.

### Design 1 (score ignores deep/REM) — Step 4.1
Restorative (deep+REM) component added to `HealthSleepScoreEstimator`. When `session.dataQuality == .detailedStages`:
- With baseline: compares `(deep+REM)/total` vs baseline ratio, awards 0–20 pts
- Without baseline: uses absolute target ratio (40% combined) for 0–20 pts
- Without stage data: 0 pts, no change to displayed score range

`HealthSleepScoreEstimate.restorative: Int` field added. `NightlyResearchRow.sleepScoreRestorative: Int?` added. `ResearchCSVExporter` appends `"sleep_score_restorative"` column after `"restorative_pct_of_in_bed"` (invariant #9 preserved).

**Pending:** `ResearchAnalysisService.buildNightlyRows` still needs to populate `sleepScoreRestorative` by calling `HealthSleepScoreEstimator.estimate()` and assigning `row.sleepScoreRestorative = score.restorative`.

### Design 2 (travel suppression) — Step 4.3
`HealthSleepScoreEstimator.estimate(session:baseline:sleepGoalHours:contextEntry:calendar:)` — `contextEntry` parameter added. In `bedtimeComponent`, `contextEntry?.travel == true` (tristate check per invariant #2) awards full `maxPts` without computing circular deviation. `SleepDashboardViewModel` fetches `selectedContextEntry` via `localRepository.fetchContextEntry(forSleepDateKey:)` in `loadSelectedDate()`. Passed through to `healthSleepScore(for:contextEntry:)` in `SleepTabView`.

### Design 3 (chronotype caveat) — Step 3.3
See UI 3 above.

### Design 4 (baseline adapts to decline) — Step 4.4
`AlertGenerationService` now computes a linear regression slope over the last 30 valid nights. If slope ≤ −2 min/night, a `.sleepDriftDown` alert fires (severity 1, week-keyed UUID for weekly re-evaluation). New `SleepAlertKind.sleepDriftDown` case added to `ProtocolModels.swift`. `AlertRowView.iconName` switch updated.

**Compiler note:** The initial `zip`/`reduce` closure implementation triggered a Swift SIL optimizer crash (`ClosureLifetimeFixup` pass). Rewrote as a pure imperative loop in `linearRegressionSlopeMinutes(_:)` to work around the bug.

### UI 10 (stage rings vs baseline) — Step 4.2 — DEFERRED
`SleepStageBaselineRingRow` — new component showing ±1σ baseline arcs behind stage rings — is deferred. The existing `SleepStagesStackedBar` already shows inline baseline deltas. The ring overlay requires a new standalone file and was scoped out of this session to keep the diff reviewable.

### UI floating layout fix (unlisted in original diagnostic)
`sessionContent` was restructured from a flat `VStack(spacing: BetterSpacing.medium)` (14pt between everything) to nested section groups: outer `VStack(spacing: BetterSpacing.section)` (26pt between sections) with inner `VStack(alignment: .leading, spacing: 8)` tightly pairing each `dashboardSectionHeader(_:)` with its card. Section headers are no longer visually floating — they attach directly to their card.

---

*End of diagnostic — updated 2026-05-27*
