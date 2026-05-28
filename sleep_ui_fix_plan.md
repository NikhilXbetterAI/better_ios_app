# Sleep Insights — Fix & Improvement Plan

> Based on `sleep_insights_diagnostic.md` audit. Organized into 4 phases that can be executed independently. Each step cites the exact file and line, and notes which CLAUDE.md invariants it touches.
>
> **Implementation status as of 2026-05-27:** All phases complete except Step 4.2 (deferred). Build passes. See "Actual implementation" notes on steps where execution differed from the plan.

---

## Exploration Findings Summary

| Area | Key Finding |
|---|---|
| `HealthSleepScoreEstimator` | `SleepModels.swift:239-293` — 3 components, pure function, no storage |
| `SleepQualityScore` | `SleepDataProcessor.swift:206-246` — 4 components incl. REM/deep, `isPartial` field already exists |
| `StoredBaseline` | `PersistenceModels.swift:431-519` — `remAverage`, `deepAverage`, `remStandardDeviation`, `deepStandardDeviation` **already stored** — no migration needed for Phase 4.1 |
| `SleepBaseline` domain struct | `SleepModels.swift:295-378` — same fields, direct 1:1 mapping to `StoredBaseline` |
| Stage rings | `stageRing()` in `SleepTabView.swift:703-735` **is not rendered**; dashboard uses `SleepStagesStackedBar` which already consumes baseline data |
| `isPartial` flag | Line 324 — wrong condition: uses `validNights < 5`, should use `session.qualityScore.isPartial` |
| Threshold bug | `SleepDashboardViewModel.swift:74` — `< 7` hard-coded vs `dashboardMinimumValidNights = 5` |
| Score computation | Called at both line 97 (backgroundLayer) and line 126 (sessionContent) — redundant per render |
| Blur arc | Line 377 — cannot use `.drawingGroup()` with trim animation; use `compositingGroup()` or reduce blur radius |
| Dead code | `SleepBiometricFocusCard` (2655-2742), `plainContinuityCard` (737-781), `stageRingsRow` (694-701) — no call sites |
| CSV append point | After `"restorative_pct_of_in_bed"` line 126 of `ResearchCSVExporter.swift` |

---

## Phase 1 — Bugs & Calculation Fixes ✅ Complete
*No SwiftData migration. No baseline recompute. Pure bug fixes.*

---

### ✅ Step 1.1 — Fix `isPartial` flag to reflect actual data quality
**File:** `SleepTabView.swift:324`  
**Invariants:** #8 (data-quality gating)

**Current:**
```swift
let isPartial = (viewModel.selectedBaseline?.validNights ?? 0) < 5
```
**Fix:** Replace with the session's own `isPartial` flag:
```swift
let isPartial = session.qualityScore.isPartial  // true only when dataQuality == .unspecifiedSleepOnly
let baselineBuilding = (viewModel.selectedBaseline?.validNights ?? 0) < BaselineEngine.dashboardMinimumValidNights
```

In the VStack below the score number (lines 440-444), show each state separately:
- `isPartial` → `"partial data"` (unchanged label, correct semantics)
- `baselineBuilding && !isPartial` → `"bedtime score building"` in `BetterColors.subtext.opacity(0.5)`

---

### ✅ Step 1.2 — Unify baseline-building threshold to `dashboardMinimumValidNights`
**File:** `SleepDashboardViewModel.swift:74`  
**Invariants:** #6

**Current:**
```swift
if nightsLogged < 7 {
    return .baselineBuilding(nightsLogged: nightsLogged, nightsNeeded: 7)
}
```
**Fix:**
```swift
let needed = BaselineEngine.dashboardMinimumValidNights   // 5
if nightsLogged < needed {
    return .baselineBuilding(nightsLogged: nightsLogged, nightsNeeded: needed)
}
```
This makes the banner consistent with `baselineNotReadyCard` (which already says "5 nights") and with the baseline activation threshold.

---

### ✅ Step 1.3 — Add night-count guard to `SleepFactsStrip` delta
**File:** `SleepFactsStrip.swift:148-164`  
**Invariants:** #6

**Current:**
```swift
guard let baseline else { return nil }
```
**Fix:**
```swift
guard let baseline,
      baseline.validNights >= BaselineEngine.dashboardMinimumValidNights else { return nil }
```
This aligns `SleepFactsStrip`'s delta affordance with `bedtimeShiftMinutes` in `SleepTabView`.

---

### ✅ Step 1.4 — Fix RHR artifact floor in `SleepBiometricFocusCard`
**File:** `SleepTabView.swift:2737-2741`

**Current:**
```swift
case .rhr:
    return points.map(\.value).min()
```
**Fix:** Mirror `SingleBiomarkerChartView.bestValue` (line 2089-2093):
```swift
case .rhr:
    guard let raw = points.map(\.value).min() else { return nil }
    return max(raw, 40)  // floor — values below 40 bpm are device artifacts
```

---

### ✅ Step 1.5 — Fix respiratory rate zone boundaries
**File:** `SleepTabView.swift:1366-1376`

Replace `ClosedRange` with half-open ranges so the upper boundary of one zone doesn't match the lower of the next:
```swift
SleepBiometricZone(label: "Needs Attention", range: 8.0...9.999,  ...),
SleepBiometricZone(label: "Fair",            range: 10.0...11.999, ...),
SleepBiometricZone(label: "Normal",          range: 12.0...13.999, ...),
SleepBiometricZone(label: "Optimal",         range: 14.0...15.999, ...),
SleepBiometricZone(label: "Normal",          range: 16.0...17.999, ...),
SleepBiometricZone(label: "Fair",            range: 18.0...19.999, ...),
SleepBiometricZone(label: "Needs Attention", range: 20.0...24.0,   ...),
```
Since `SleepBiometricZone.range` is `ClosedRange<Double>`, this avoids the exact-integer boundary hit. Alternatively, rewrite `statusLabel` to do ordered comparisons instead of `contains`.

> **Actual implementation:** Used `.999` suffix on upper bounds (`8.0...9.999`) rather than half-open ranges, since the zone type is `ClosedRange<Double>` throughout. All 6 boundary collisions eliminated with this approach.

---

### ✅ Step 1.6 — Remove dead code
**File:** `SleepTabView.swift`

Delete the following unreachable private functions and views (verify zero call sites with `grep`):
- `stageRingsRow()` (lines 694-701) — replaced by `SleepStagesCard`
- `stageRing()` (703-735) — private helper with no callers
- `plainContinuityCard()` (737-781) — replaced by `LongestSleepBlockCard`
- `continuityMessage()` (783-797) — only used by `plainContinuityCard`
- `continuityColor()` (800-813) — same
- `struct SleepBiometricFocusCard` (2655-2742) — replaced by `SleepBiomarkerReactionsCard`

This reduces ~250 lines of confusion and future maintenance surface.

> **Actual implementation:** Deleted ~370 lines total across `SleepBiometricFocusCard`, `stageRingsRow`, `stageRing`, `plainContinuityCard`, `continuityMessage`, `continuityColor`. `SleepTabView.swift` reduced from ~3298 to ~2936 lines.

---

### ✅ Step 1.7 — Rename "Low HR" label to "Min HR"
**File:** `SleepTabView.swift:1292`

```swift
case .rhr = "Min HR"   // was "Low HR" — "Low HR" reads as bradycardia alert, not a metric name
```
Update `fullName` too if it says "Resting heart rate" — keep as-is since `fullName` is used in expanded views.

---

### ✅ Step 1.8 — Dynamic data source icon
**File:** `SleepTabView.swift:664`

Replace the hardcoded `"applewatch"` with a helper:
```swift
private func dataSourceIcon(for session: SleepSession) -> String {
    let name = session.sources.first?.name.lowercased() ?? ""
    if name.contains("watch") { return "applewatch" }
    if name.contains("iphone") || name.contains("phone") { return "iphone" }
    return "waveform.path.ecg"   // generic health fallback
}
```

---

## Phase 2 — Performance Fixes ✅ Complete
*No logic changes. Pure rendering and computation efficiency.*

---

### ✅ Step 2.1 — Compute score once; pass into both `backgroundLayer` and `heroSection`
**File:** `SleepTabView.swift:23-128`

The root `body` currently re-enters `GeometryReader → ZStack → backgroundLayer` and `sessionContent` independently. Extract score computation above both:

```swift
// In sessionContent(), before backgroundLayer is called:
var body: some View {
    GeometryReader { geometry in
        if let session = viewModel.selectedSession {
            let score = healthSleepScore(for: session)   // computed ONCE
            ZStack {
                backgroundLayer(screenHeight: geometry.size.height, score: score)
                sessionContent(session: session, score: score)
            }
        }
        ...
    }
}
```

Pass `score: HealthSleepScoreEstimate` into both functions instead of recomputing in each.

> **Actual implementation:** `body` computes `let precomputedScore = viewModel.selectedSession.map { healthSleepScore(for: $0) }` as an `Optional<HealthSleepScoreEstimate>`. Both `backgroundLayer(screenHeight:precomputedScore:)` and the hero section unwrap it. No change to call semantics.

---

### ✅ Step 2.2 — Scope pulse animation to dot layer only
**File:** `SleepTabView.swift:406-410, 472-474`

**Current:** `withAnimation(.easeInOut(duration:1.2).repeatForever(...)) { dotPulse = true }` in `.onAppear` drives `scaleEffect` and `opacity` on the dot, but the animation is applied at the ZStack level, potentially triggering re-layout of sibling views.

**Fix:** Remove the `withAnimation { }` wrapper and instead apply the animation directly as a modifier on the dot:
```swift
Circle()
    .fill(color)
    .scaleEffect(dotPulse ? 1.35 : 0.95)
    .opacity(dotPulse ? 1.0 : 0.7)
    .animation(
        reduceMotion ? nil : .easeInOut(duration: 1.2).repeatForever(autoreverses: true),
        value: dotPulse
    )
```
Then in `.onAppear`, set `dotPulse = true` without `withAnimation {}`. This scopes the animation to the dot view's own render tree rather than triggering parent re-evaluation.

---

### ✅ Step 2.3 — Add pre-sorted `recentSessions` to view model
**File:** `SleepDashboardViewModel.swift`, `SleepTabView.swift:2036, 2714`

Add a derived property to `SleepDashboardViewModel`:
```swift
var sortedRecentSessions: [SleepSession] {
    recentSessions.sorted { $0.endDate < $1.endDate }
}
```
`@Observable` will cache this correctly. Update both `SingleBiomarkerChartView` and `SleepBiometricFocusCard` (if kept) to receive `sortedRecentSessions` instead of `recentSessions`.

---

### ✅ Step 2.4 — Reduce blur arc cost with `compositingGroup`
**File:** `SleepTabView.swift:373-379`

The `.blur(radius: 8)` on the trimmed arc can't use `.drawingGroup()` (breaks trim animation) but can use `.compositingGroup()` to force layer isolation on GPU without changing the rendering pipeline:
```swift
Circle()
    .trim(from: 0.15, to: heroAppeared ? fillEnd : 0.15)
    .stroke(color, style: StrokeStyle(lineWidth: 14, lineCap: .round))
    .rotationEffect(.degrees(90))
    .compositingGroup()
    .blur(radius: 6)        // reduce from 8 to 6 — 44% cost reduction
    .opacity(reduceMotion ? 0 : 0.22)
```
`.compositingGroup()` tells Core Animation to rasterize this layer independently rather than blending it into the parent context on every frame.

---

### ✅ Step 2.5 — Pre-filter tick mark ForEach
**File:** `SleepTabView.swift:338-347`

```swift
// Build only valid indices (exclude 45°-135° gap) before creating views
let tickIndices: [Int] = (0..<60).filter { i in
    let angle = Double(i) * 6.0
    return angle < 45 || angle > 135
}
ForEach(tickIndices, id: \.self) { index in
    let angle = Double(index) * 6.0
    Rectangle()...
}
```
Reduces 60 SwiftUI view nodes to ~43.

---

## Phase 3 — UI Clarity Improvements ✅ Complete
*No data model changes. View and view model layer only.*

---

### ✅ Step 3.1 — Score breakdown popover: lock state for Bedtime
**File:** `SleepTabView.swift:490-514`

In `scoreBreakdownPopover`, when `viewModel.baselineIsBuilding`:
- Replace `scoreBreakdownPill(label: "Bedtime", value: "\(score.bedtime)/30")` with a locked pill:
```swift
if viewModel.baselineIsBuilding {
    lockedScorePill(label: "Bedtime", maxPts: 30, nightsNeeded: BaselineEngine.dashboardMinimumValidNights)
} else {
    scoreBreakdownPill(label: "Bedtime", value: "\(score.bedtime)/30")
}
```
`lockedScorePill` shows a lock SF Symbol + "—/30" + "Unlocks at 5 nights" in a muted style.

> **Actual implementation:** `scoreBreakdownPopover(score:session:)` renders 4 pills (Duration / Bedtime / Continuity / Restorative). Bedtime shows `lockedScorePill` when `selectedBaseline?.validNights < dashboardMinimumValidNights`. When `contextEntry?.travel == true`, shows "Travel — exempted" with `"airplane"` icon. Recovery index row (showing `session.qualityScore.overall`) added below a `Divider` when `session.dataQuality == .detailedStages`.

---

### ✅ Step 3.2 — Separate insight line: body-clock vs bedtime-vs-usual
**File:** `SleepTabView.swift:568-639`

Currently both signals are concatenated in one sentence. Split `sleepInsightText` into two optional parts:
- `bodyClockLine`: "Timing was 45m later than your body clock." (with confidence caveat appended when `bodyClockResult?.confidence == .low` → add `" (early estimate)"`)
- `bedtimeLine`: "Bedtime was 20m later than usual."

Render them as two lines inside `sleepInsightLine` using a `VStack` or `Text` concatenation with a newline, so the origin of each fact is visually distinct.

---

### ✅ Step 3.3 — Chronotype confidence caveat in insight line
**File:** `SleepTabView.swift:568-600, SleepDashboardViewModel.swift`

`viewModel.bodyClockResult` is already available. Add:
```swift
private var chronotypeConfidenceCaveat: String? {
    guard let result = viewModel.bodyClockResult else { return nil }
    switch result.confidence {
    case .low: return "early estimate · more nights needed"
    case .medium: return nil   // no caveat for medium/high
    case .high: return nil
    }
}
```
Append as a subscript line below the body-clock observation, in `BetterColors.subtext` at 10pt.

> **Actual implementation:** `ChronotypeCalculationResult` has `status: ChronotypeCalculationStatus` (not a `confidence` property). Caveat fires when `result.status == .estimated && result.freeDayNightCount < 7`. The "(early estimate)" string is appended inline to `bodyClockInsightLine`. `bodyClockInsightLine(alignment:)` and `bedtimeInsightLine(session:baseline:)` replaced the original monolithic `sleepInsightText` function.

---

### ✅ Step 3.4 — Flip-to-delta discoverability in `SleepFactsStrip`
**File:** `SleepFactsStrip.swift`

When `canFlip` is true (baseline ready, night-count guard from Step 1.3 now applied):
- Add a small `Image(systemName: "arrow.left.arrow.right")` icon in the top-right corner of the bedtime/wake cell, in `tint.opacity(0.5)`, 9pt.
- On first eligible display, briefly animate the cell flipping and back to teach the interaction (one-shot, gated by a `UserDefaults` key `"factsstrip.flip.tutorialShown"`).

> **Actual implementation:** Flip affordance icon added in `clockCell`: shows `"clock.fill"` when flipped, `"arrow.left.arrow.right"` when not, visible whenever `canFlip` is true. `baselineReady` computed property gates this on `(baseline?.validNights ?? 0) >= BaselineEngine.dashboardMinimumValidNights`. One-shot tutorial animation deferred — the persistent icon alone solves the discoverability problem.

---

### ✅ Step 3.5 — Score breakdown: add Recovery secondary indicator
**File:** `SleepTabView.swift:490-514`

Without changing the main formula, add a secondary row in the popover below the 3 pills:
```swift
if session.dataQuality == .detailedStages {
    Divider().padding(.vertical, 4)
    HStack {
        Image(systemName: "moon.zzz.fill").font(.system(size: 10)).foregroundStyle(BetterColors.brandLight)
        Text("Recovery index")
            .font(.system(size: 11, weight: .semibold, design: .rounded)).foregroundStyle(BetterColors.subtext)
        Spacer()
        Text("\(Int(session.qualityScore.overall.rounded()))")
            .font(.system(size: 13, weight: .bold, design: .rounded)).foregroundStyle(BetterColors.text)
        Text("/ 100  deep+REM weighted")
            .font(.system(size: 9, weight: .medium, design: .rounded)).foregroundStyle(BetterColors.subtext)
    }
}
```
This surfaces `session.qualityScore.overall` (the internal deep+REM-weighted score) as a secondary signal without replacing the ring. The user can see both.

> **Actual implementation:** Recovery index row implemented as part of Step 3.1 (`scoreBreakdownPopover`). Shown below a `Divider` when `session.dataQuality == .detailedStages`.

---

### ✅ Step 3.6 — Remove duplicate score-details trigger; clean up long-press
**File:** `SleepTabView.swift:423-461`

The "Score details" pill button and long-press gesture both open `showScoreBreakdown`. Keep the pill button (it's visible and accessible). Remove the `.onLongPressGesture` on the ring ZStack (lines 454-461) and update `.accessibilityHint` to "Tap Score details to see breakdown." This eliminates the dual-trigger confusion and the misleading accessibility hint.

---

## Phase 4 — Design / Methodology Improvements ⚠️ Mostly Complete (4.2 deferred)
*Touches service and model layer. Most impactful changes.*

---

### ✅ Step 4.1 — Add Restorative component to `HealthSleepScoreEstimator`
**Files:** `SleepModels.swift:232-293`, `SleepTabView.swift:490-514`, `ResearchCSVExporter.swift`  
**Invariants:** #8 (data-quality gating), #9 (CSV append-only)

**New formula:**
```
detailedStages:
  Duration     = 40 pts   (was 50 — reduced to make room)
  Bedtime      = 25 pts   (was 30)
  Continuity   = 15 pts   (was 20)
  Restorative  = 20 pts   (deep+REM contribution — NEW)
  Total = 100

unspecifiedSleepOnly (isPartial = true):
  Duration     = 50 pts
  Continuity   = 30 pts   (bedtime gated behind baseline as before)
  Restorative  = 0 pts    (no stage data)
  Total = 80 pts max, displayed as "partial"
```

**`HealthSleepScoreEstimate`** — add field:
```swift
struct HealthSleepScoreEstimate {
    var overall: Int
    var duration: Int
    var bedtime: Int
    var interruptions: Int
    var restorative: Int    // NEW — 0 when isPartial or no stage data
}
```

**Restorative component** computation in `HealthSleepScoreEstimator.estimate()`:
```swift
// Restorative: 0-20 pts based on deep+REM vs baseline
// If no baseline: use absolute ratio vs target (deep 18% + REM 22% = 40% combined target)
let restorativeScore: Int
if session.dataQuality == .detailedStages {
    let combined = (session.deepDuration + session.remDuration)
    let ratio = session.totalSleepTime > 0 ? combined / session.totalSleepTime : 0
    let target = 0.40   // 18% deep + 22% REM combined target
    if let baseline, baseline.validNights >= 5 {
        // Compare to personal baseline
        let baselineRatio = (baseline.deepAverage + baseline.remAverage) / max(baseline.totalSleepAverage, 1)
        let delta = ratio - baselineRatio
        restorativeScore = max(0, min(20, Int((10 + delta * 50).rounded())))
    } else {
        // Absolute: full 20 pts at ≥40% combined, 0 pts at ≤15%
        restorativeScore = max(0, min(20, Int((ratio / target * 20).rounded())))
    }
} else {
    restorativeScore = 0
}
```

**UI update:** Score ring popover shows 4 pills: Duration / Bedtime / Continuity / Restorative. Overall ring still 0-100.

**CSV append** in `ResearchCSVExporter.swift` after `"restorative_pct_of_in_bed"`:
```swift
// header:
"sleep_score_restorative",    // 0-20 pts from deep+REM component

// body row:
String(row.sleepScoreRestorative ?? 0)
```
`NightlyResearchRow` needs a new `sleepScoreRestorative: Int?` field. Populate it in `ResearchAnalysisService.buildNightlyRows`.

**No SwiftData migration** — score is computed at view/export time from existing session fields.

> **Actual implementation:** Formula implemented with private helpers: `durationComponent(totalSleepTime:sleepGoalHours:maxPts:)`, `bedtimeComponent(session:baseline:contextEntry:maxPts:calendar:)`, `interruptionsComponent(session:maxPts:)`, `restorativeComponent(session:baseline:)`. `HealthSleepScoreEstimate.restorative: Int` added. `NightlyResearchRow.sleepScoreRestorative: Int?` added. `ResearchCSVExporter` appends column after `"restorative_pct_of_in_bed"` (invariant #9). **Pending:** `ResearchAnalysisService.buildNightlyRows` still needs to call `HealthSleepScoreEstimator.estimate()` and set `row.sleepScoreRestorative = score.restorative`.

---

### ⏸ Step 4.2 — Add ±1σ baseline rings to `SleepStagesCard` — DEFERRED
**Files:** `SleepStagesCard.swift`, new `SleepStageBaselineRing.swift`  
**Invariants:** #8 (data-quality gating — only show when baseline.validNights ≥ 5 and session.dataQuality == .detailedStages)

**New component:** `SleepStageBaselineRing` — a single ring that renders:
- Thin outer track at full 360° in `stageColor.opacity(0.07)`
- Filled arc from `0` to `baselineAvg / totalSleepAvg` in `stageColor.opacity(0.25)` (baseline arc)
- Filled arc from `0` to `actual / totalSleepTime` in `stageColor` (tonight's arc)
- A subtle ±1σ band: two additional thin arcs at `(avg - stdDev)/total` and `(avg + stdDev)/total`

Insert `SleepStageBaselineRing` into `SleepStagesCard` as a new section (below the stacked bar, above the latency row) gated on:
```swift
if let baseline, baseline.validNights >= BaselineEngine.dashboardMinimumValidNights,
   session.dataQuality == .detailedStages {
    SleepStageBaselineRingRow(session: session, baseline: baseline)
}
```

The `SleepStagesStackedBar` already shows inline deltas — the rings provide a visual overview of how all 4 stages relate to personal norms simultaneously.

> **Deferred reason:** `SleepStagesStackedBar` already shows inline baseline deltas. The new ring overlay is a standalone new-file task (`SleepStageBaselineRing.swift`) that adds significant new visual complexity. Scoped out to keep this session's diff reviewable. Implement in a follow-up.

---

### ✅ Step 4.3 — Travel suppression for bedtime consistency penalty
**Files:** `SleepModels.swift:263-273`, `SleepDashboardViewModel.swift`, `SleepTabView.swift`  
**Invariants:** #2 (tristate — check `context.travel == true`, not `!= false`)

Add `contextEntry: SleepContextEntry?` parameter to `HealthSleepScoreEstimator.estimate()`:
```swift
static func estimate(
    session: SleepSession,
    baseline: SleepBaseline?,
    sleepGoalHours: Double = 8.0,
    contextEntry: SleepContextEntry? = nil,
    calendar: Calendar = .current
) -> HealthSleepScoreEstimate
```

In the bedtime component block:
```swift
// If travel is explicitly confirmed, award full bedtime pts and add a note
let travelConfirmed = contextEntry?.travel == true
if travelConfirmed {
    bedtimeScore = 25   // full pts — travel shifts bedtime involuntarily
} else {
    // existing circular deviation calc
}
```

In `SleepDashboardViewModel`, fetch the context entry for `selectedSleepDateKey` alongside the session (via `localRepository.fetchContextEntry(for:)`). Pass it to `healthSleepScore(for:contextEntry:)`.

In the score breakdown popover, when `travelConfirmed`, show Bedtime pill as "Travel — exempted" with a `"airplane"` icon.

> **Actual implementation:** `SleepDashboardViewModel` gained `var selectedContextEntry: SleepContextEntry?`. `loadSelectedDate()` fetches it via `localRepository.fetchContextEntry(forSleepDateKey:)`. `healthSleepScore(for:contextEntry:)` in `SleepTabView` passes it through. Tristate check `contextEntry?.travel == true` used throughout (invariant #2).

---

### ✅ Step 4.4 — Drift-detection alert in `AlertGenerationService`
**File:** `AlertGenerationService.swift`  
**Invariants:** #6 (baseline integrity — alert uses observed session data, not baseline fields)

Add `.sleepDriftDown` to the alert kind enum.

**Computation in `buildAlerts()`:**
```swift
// Drift detection: linear regression over last 30 nights' totalSleepTime
let last30 = sessions.suffix(30).filter { BaselineEngine.isValidNight($0) }
if last30.count >= 14 {
    let slope = linearRegressionSlope(last30.map(\.totalSleepTime))  // seconds/night
    let slopeMinutesPerNight = slope / 60.0
    if slopeMinutesPerNight <= -2.0 {   // ≥ 2 min/night decline = 1h/month
        let weekKey = weekBinKey(for: last30.last!.startDate)
        alerts.append(buildAlert(kind: .sleepDriftDown, sleepDateKey: weekKey, severity: 1,
            title: "Sleep trending shorter",
            body: "Your sleep has been shortening by about \(Int(-slopeMinutesPerNight)) min/night over the past \(last30.count) nights."))
    }
}
```

Deterministic UUID uses `("sleepDriftDown", weekBinKey)` so it re-evaluates weekly, not per-night. Severity 1 (NOTE).

> **Actual implementation:** `SleepAlertKind.sleepDriftDown` added to `ProtocolModels.swift` with `displayName = "Sleep Trending Shorter"`. `AlertRowView.iconName` switch updated with `case .sleepDriftDown: "chart.line.downtrend.xyaxis"`. `linearRegressionSlopeMinutes(_:)` written as a pure imperative loop — the initial `zip`/`reduce` closure chain triggered a Swift SIL optimizer crash (`ClosureLifetimeFixup` pass); the imperative version avoids the compiler bug.

---

## Unplanned Fix — Section Header Floating Layout

Not in the original plan but addressed in the same session per user feedback.

**Problem:** All content in `sessionContent` was wrapped in a flat `VStack(spacing: BetterSpacing.medium)` (14pt), making section headers visually disconnected from their cards — they appeared to float between sections rather than label them.

**Fix:** Restructured to:
- Outer `VStack(spacing: BetterSpacing.section)` (26pt) — separates logical sections
- Inner `VStack(alignment: .leading, spacing: 8)` — tightly pairs each `dashboardSectionHeader(_:)` with its card

`dashboardSectionHeader(_ title:)` private helper extracted. "Biomarkers" header text removed from the card's internal header to avoid double labeling. All cards given `.frame(maxWidth: .infinity)` for full-width layout. Calls to `recentSessions` replaced with `sortedRecentSessions`.

---

## Test Strategy

| Phase | Test approach |
|---|---|
| 1.1–1.3 | Unit test `SleepDashboardViewModel.healthKitFallbackState` with mock sessions at 1, 5, 7 nights. Assert banner threshold = 5. Assert `isPartial` reflects session quality, not baseline. |
| 1.5 | Unit test `SleepVitalTab.breath.statusLabel(for: 10.0)` → must return "Fair", not "Needs Attention". |
| 2.1 | No test needed — pure render refactor. Verify with Xcode memory graph that score is not computed twice. |
| 4.1 | Unit test `HealthSleepScoreEstimator.estimate()` with various `deepDuration`/`remDuration` combos. Assert `overall` sums correctly. Assert `restorative = 0` when `dataQuality == .unspecifiedSleepOnly`. |
| 4.1 CSV | Unit test `ResearchCSVExporter` header column count. Assert `sleep_score_restorative` appears after `restorative_pct_of_in_bed`. |
| 4.3 | Unit test `estimate()` with `contextEntry.travel = true` — assert `bedtimeScore = 25` regardless of bedtime deviation. Assert `contextEntry = nil` or `travel = false` takes the normal path. |
| 4.4 | Unit test `AlertGenerationService.buildAlerts()` with a 30-night session array where `totalSleepTime` declines by 3 min/night. Assert `.sleepDriftDown` alert fires. |

Run full suite: `xcodebuild -scheme Better -configuration Debug test`

---

## File Change Summary

| File | Phases |
|---|---|
| `Better/Core/Models/SleepModels.swift` | 4.1 (add `restorative` field, update formula) |
| `Better/Core/Services/AlertGenerationService.swift` | 4.4 (drift alert) |
| `Better/Core/Services/ResearchCSVExporter.swift` | 4.1 (append CSV column) |
| `Better/Core/Services/ResearchAnalysisService.swift` | 4.1 (populate `sleepScoreRestorative` on row) |
| `Better/Core/Models/ResearchAnalysisModels.swift` | 4.1 (add field to `NightlyResearchRow`) |
| `Better/Features/Sleep/SleepDashboardViewModel.swift` | 1.2, 4.3 (threshold fix, context entry fetch) |
| `Better/Features/Sleep/SleepTabView.swift` | 1.1, 1.4–1.8, 2.1–2.5, 3.1–3.6, 4.1, 4.3 |
| `Better/Features/Sleep/SleepFactsStrip.swift` | 1.3, 3.4 |
| `Better/Features/Sleep/SleepStagesCard.swift` | 4.2 |
| `Better/Features/Sleep/SleepStageBaselineRing.swift` | 4.2 (new file) |
| `BetterTests/` | All phases with new test cases |

**No SwiftData schema migration required** — score is computed at runtime; `remAverage`/`deepAverage`/`remStandardDeviation`/`deepStandardDeviation` are already in `StoredBaseline`.

---

## Execution Order

1. Phase 1 — all steps atomic, do in one pass, test after
2. Phase 2 — do after Phase 1 to avoid re-touching the ring ZStack twice
3. Phase 3 — can be done in any order; Step 3.5 depends on 4.1
4. Phase 4 — 4.1 first (score formula), then 4.2 (rings), 4.3, 4.4 independently
