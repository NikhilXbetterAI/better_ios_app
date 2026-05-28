# Sleep Insights — UX/Product/Performance Teardown
**Date:** 2026-05-27  
**Branch:** fix/sleep-dashboard-critical-high  
**Reviewer:** Principal UX + Engineering Audit

---

## TL;DR Verdict

The Insights screen tries to say everything and ends up communicating nothing. It stacks ~10 independent cards with no narrative thread, uses labels that require a PhD to decode, and renders the full card tree on every scroll tick. Users open it, see a wall of numbers, scroll for 3 seconds, and close it. It feels like a data dump, not an insight surface. The ONE biggest mistake: **the page has no focal point — no single clear answer to "how am I sleeping?"**

---

## 1. Information Architecture Problems

### What should NOT exist (cut immediately)
| Section | Why |
|---|---|
| "What changed" — three sub-cards with CHANGED / USUAL / DATA | Truncated labels, cryptic values ("6.8h now vs 6.2h p..."), `27 current /...` is unreadable mid-scroll |
| "Best Night in last 30D" card | Management feedback confirmed this is not useful. A user cannot act on their best night from 2 weeks ago |
| "THIS PERIOD / CHANGE / PREVIOUS" night-count strip under the chart | 3 identical grey boxes showing "27n / +9% / 27n" — numerically identical values with no clear meaning |
| Body Clock weekday/weekend timestamps in the metric strip | "2:11 AM" vs "3:00 AM" communicates nothing without context of what "normal" is for the user |
| `InsightsBestSleepCard` | Redundant with the trend chart — the best night is already a point on the line |

### What is redundant
- `TrendWindowPickerView` appears at the top-level AND inside `StageDurationCompositionView` — the user sees two independent window pickers on the same screen, for different sections. They will set one and not understand why the other doesn't change.
- Sleep Score appears in: sparkline, ring gauge in `InsightsOverviewCard`, `InsightsBestSleepCard` score ring, the trend line chart (when "Sleep Score" metric is selected), AND the `InsightsSleepInsightsCard` — five times.
- "27 nights tracked" badge appears in both the overview card and the stage composition section.

### What order actually makes sense psychologically
Human reading pattern (F-pattern, emotional → analytical → comparative):

```
1.  HERO: "Your sleep this period" — Score ring + one-line verdict
2.  TREND CHART (default: Total Sleep, switchable to Deep/REM/Score)
3.  CHRONOTYPE — clock visual only (no metric strip with timestamps)
4.  WEEKDAY vs WEEKEND — right after Chronotype (management confirmed)
5.  SLEEP SCHEDULE (bedtime consistency bar, avg bedtime/wake)
6.  STAGE COMPOSITION — for users who want to go deeper
7.  RECOVERY INSIGHTS — the 4-item list (duration changed, REM shifted, etc.)
```

Everything else (Best Night, WASO details, "USUAL"/"DATA" mini-cards) is either cut or moved to a drill-down sheet.

---

## 2. Data Presentation Critique

### Charts
- **TrendLineChartView**: The tooltip shows "In bed: 8h 3m / Efficiency: 96%" — good. But the tooltip position logic (`tooltipPosition()`) can clip at screen edges and the 132pt fixed width truncates values like "8h 03m".
- **StageStackedBarView**: Bars are good but the 7D/30D/60D picker is a second window picker duplicated from the top of the page. It should not exist as a separate control — it should respond to the global window.
- **InsightsOverviewCard sparkline**: 27-point sparkline is unreadable at the size it renders. It looks decorative, not informative.

### Labels that fail
| Label | Problem |
|---|---|
| `"6.8h now vs 6.2h p..."` | Truncated. The string is cut off because BetterHealthCard has fixed width. User never sees the full context. |
| `"27 current / ..."` | Same truncation problem. |
| `"Usual not ready"` | State fallback copy that appears in the USUAL card — users think something is broken. |
| `"Latest night vs 14-night usual"` | What is a "14-night usual"? Non-technical user has no idea. |
| `"WASO"` in the metric selector | Zero users know what WASO is. Label should read "Wake Time" or "Awakenings". |
| `"br/min"` | Should be "Breaths/min". |
| `"SpO2"` | Should be "Blood Oxygen". |
| `"Corrected midpoint"` in Body Clock | This is academic jargon. Should be "Your sleep center" or just hidden. |

### Data users cannot act on
- Best Night from 14 days ago — no actionable path
- "THIS PERIOD: 27n / PREVIOUS: 27n" — same numbers, no insight
- Body Clock midpoint timestamps without a comparison to "ideal" — what should the user do with "3:51 AM midpoint"?

---

## 3. Body Clock Section — Specific Failures

### Why it fails now
The `ChronotypeMetricStripView` shows three values:  
`Weekdays: 2:11 AM | Weekends: 3:00 AM | Sleep avg: 6h 28m`

**Problem 1 — Wrong mental model.** When users hear "Body Clock" they expect to see: "you are a Night Owl" or "you are a Morning Person" + a visual showing your natural sleep window on a 24h clock. They get a timestamp strip that means nothing without knowing what a "midpoint" is.

**Problem 2 — The timestamps are midpoints of sleep, not bedtimes.** A user who goes to bed at 12 AM and wakes at 7 AM has a midpoint of 3:30 AM. Showing "3:30 AM" looks alarming (they think they're awake at 3:30 AM).

**Problem 3 — No reference point.** What is the "ideal" midpoint for an intermediate chronotype? Without a target range shown, the number is meaningless.

**Problem 4 — The clock visual is beautiful but confusing.** The arc shows the "optimal sleep window" but the legend at the bottom has 4 items (Sleep window / Corrected / Weekdays / Weekends) with no inline labels on the clock itself. Users must memorize the color mapping.

### How it should work — Oura/Rise pattern
```
╔════════════════════════════════════╗
║  🌙  Night Owl                     ║
║  Your natural bedtime: 12:30–1:30 AM ║
║                                    ║
║  [24h arc showing 12 AM–8 AM zone] ║
║                                    ║
║  Weekdays sleep 49 min later than  ║
║  weekends → social jet lag risk    ║
╚════════════════════════════════════╝
```

- Show chronotype label prominently (Night Owl, Morning Lark, Intermediate)
- Show a single "your natural bedtime window" in plain English
- If weekday vs weekend drift > 60 min, surface a "social jet lag" warning
- Remove the academic "corrected midpoint" terminology entirely from the main card
- The detail sheet (already exists via `ChronotypeDetailExplorationView`) is the right place for the technical breakdown

---

## 4. Interaction & UI Problems

### Horizontal scroll — Root Cause (code analysis)
Looking at `TrendsTabView.swift` line 9: `ScrollView(.vertical, showsIndicators: false)` — the outer scroll is vertical only. **But `TrendMetricSelectorView.swift` line 8 has `ScrollView(.horizontal, showsIndicators: false)` embedded inside.** When the user swipes horizontally anywhere on the metrics chip row area, the horizontal ScrollView captures it. iOS's gesture recognizer then propagates a partial horizontal bounce through the parent vertical ScrollView, which causes the entire page to "shimmy" left/right.

**The fix:** add `.scrollClipDisabled(false)` to the horizontal metric selector and add a gesture disambiguation:

```swift
// In TrendMetricSelectorView body:
ScrollView(.horizontal, showsIndicators: false) {
    HStack(spacing: BetterSpacing.small) { ... }
}
.scrollBounceBehavior(.basedOnSize, axes: .horizontal)  // prevents over-bounce
```

And in `TrendsTabView`, add to the outer ScrollView:
```swift
ScrollView(.vertical, showsIndicators: false) { ... }
.scrollBounceBehavior(.basedOnSize, axes: .vertical)    // already there
// Add:
.onScrollPhaseChange { old, new in ... }                // iOS 18
```

Actually the cleanest fix: wrap `TrendMetricSelectorView` with `.scrollTargetBehavior(.viewAligned)` and prevent the scroll container from propagating gestures upward. In iOS 18:

```swift
ScrollView(.horizontal, showsIndicators: false) { ... }
.scrollClipDisabled(false)
.simultaneousGesture(DragGesture().onChanged { _ in }) // blocks gesture passthrough
```

### Additional interaction problems
- **Chart drag gesture vs page scroll**: `TrendLineChartView` uses `DragGesture(minimumDistance: 0)`. When the user tries to scroll vertically through the chart area, every vertical drag first fires `onChanged` in the chart. This creates the "sticky" feeling on the chart. Fix: use `DragGesture(minimumDistance: 8)` and add a coordinate check.
- **Cards have no tap affordance**: Most cards are tappable (`ChronotypeInsightCardView` has `.contentShape(Rectangle()).onTapGesture`) but there's no visual indicator (no chevron, no pressed state). Users won't discover the drill-down.
- **"Explore Details & Calculation Insights" button**: This label is too long and too low-contrast. Users skip it.
- **Refresh-to-reload**: `TrendsTabView` has `.refreshable` — good, but there's no loading skeleton, so after pull-to-refresh the screen goes blank for 1-3s before data appears.

---

## 5. Dark Theme Consistency

### Problems visible in the screenshots
- **Screen 4 (InsightsOverviewCard)**: The "What changed" card has three nested `BetterHealthCard` inside a `BetterHealthCard`. That's four levels of card nesting, each with its own background layer. On dark backgrounds this creates muddy overlapping greys with no clear elevation hierarchy.
- **"CHANGED / USUAL / DATA" sub-cards**: These inner cards have `BetterColors.card` background inside a `BetterHealthCard` that itself uses `BetterColors.card`. The result is a flat grey-on-grey grid with no depth perception.
- **Sleep Score trend sparkline area**: The sparkline area fill uses `BetterColors.brand.opacity(0.18)` — this nearly disappears on the dark background in certain lighting conditions.
- **Stage composition section (Screen 2)**: The selected date pill at the bottom axis uses a solid purple, which is the one visually clear element — this is good. The rest of the chart has good contrast.
- **InsightsSleepInsightsCard (Screen 5)**: The insight rows use grey icons for "Schedule varied recently" and "Efficiency was close to normal" — these icons are the same grey as the background card surface. On device at low brightness they disappear.

### What premium dark means (Oura / Apple Health standard)
- One background color: near-black (`#0D0D12`)
- Cards: exactly 6–8pt lighter (`#16161E`)
- Active/highlight cards: 10–12pt lighter (`#1E1E2A`)
- Borders: 1px at 8–12% white opacity
- Text: 3 levels — primary white, secondary 60% white, muted 35% white
- Accent: one brand color (purple/indigo), sparingly
- No nested cards. Cards contain content, not other cards.

---

## 6. Self-Explanatory UX Audit — Violations

Every item below requires cognitive work from a non-technical user:

| Element | Violation | Fix |
|---|---|---|
| "WASO" metric chip | Unknown acronym | "Wake Time" |
| "SpO2" metric chip | Medical jargon | "Blood Oxygen" |
| "Longest Block" metric chip | Ambiguous — longest block of what? | "Longest Sleep Stretch" |
| "Corrected midpoint" | Academic term | Remove from main card, keep in detail sheet |
| "27n" in summary strip | "n" means nights? Not obvious | "27 nights" or "27 nts" |
| "+9%" in sparkline badge | 9% better than what? Which time period? | "+9% vs last month" |
| Body Clock metric strip timestamps | Midpoint of sleep looks like "you were awake at 3 AM" | Replace with "Bedtime" range in plain English |
| "Usual not ready" fallback | Sounds like an error | "Keep tracking — 7 nights needed" |
| "Valid wearable nights" | What makes a night invalid? | "Nights tracked" |
| "14-night usual" in detail text | What is a 14-night usual? | "Your typical sleep (14-night average)" |
| Score breakdown in tooltip: "Duration: 42, Efficiency: 18, REM: 12, Deep: 0" | Four raw numbers with no context | Show as progress bars with labels |

---

## 7. Performance & Lag Analysis

### Root causes identified in code

**1. Full card tree renders on every `@Observable` update** (`TrendsTabView.swift`)  
The `TrendsViewModel` has 15+ `@Observable` properties. Any single property change (e.g., `isLoading`) triggers a re-render of the entire `TrendsTabView` body, which includes:
- `InsightsOverviewCard` (sparkline + ring)
- `ChronotypeInsightCardView` (clock arc with `drawingGroup()`)
- `TrendLineChartView` (full `GeometryReader` + Path recalculation)
- `StageStackedBarView`
- `InsightsBestSleepCard`
- `InsightsWeekdayWeekendCard`
- `BaselineComparisonChartView`

All at once, on the main thread.

**2. `ChronotypeClockView` uses `drawingGroup()` only for tick marks** (line 332)  
The `.drawingGroup()` only wraps the 24-tick `ForEach` but NOT the arc and markers. The arc uses `AngularGradient` + `.shadow()` outside the drawing group. Each scroll tick recomposites the shadow layers.

**3. `TrendLineChartView` recalculates `chartPath(size:)` inside `GeometryReader`**  
The path is recomputed every time the view is laid out. On a 30D window with 30 data points this is cheap, but on 60D with protocol dots + the stage composition chart simultaneously, layout passes compound.

**4. `InsightsOverviewCard` with sparkline + arc ring + nested cards = heavy first render**  
The overview card has a `SparklineView`, a gauge ring, and 3 nested metric cells. When the page first appears, all of this must be laid out before the first frame.

**5. `updateLatestInsights()` creates a new `SleepInsightService()` on every `loadData()` call**  
`TrendsViewModel.swift` line 363: `let insightService = SleepInsightService()`. This allocates a new service on every data refresh.

**6. Nested `BetterHealthCard` in `insightFramingCard`**  
`TrendsTabView` line 124–177: A `BetterHealthCard` wraps three more `BetterHealthCard`s. `BetterHealthCard` likely applies `.background()` with a material or gradient. Four nested material backgrounds = 4 layer compositing passes.

### Fixes

```swift
// 1. Split ViewModel into focused sub-ViewModels to limit re-render scope
// Chronotype state → ChronotypeViewModel (separate @Observable)
// Chart state → ChartViewModel
// Overview metrics → computed only once, cached

// 2. Add .equatable() or use @State local caches for chart data
// The chartPoints array should only change when window/metric changes, 
// not on every loadData tick

// 3. Fix the SleepInsightService allocation:
// Before (broken):
let insightService = SleepInsightService()
// After:
private let insightService = SleepInsightService()  // instance var, not local

// 4. Apply drawingGroup() to the entire ChronotypeClockView ZStack:
ZStack { ... }
.drawingGroup()  // offscreen render entire clock to one Metal texture

// 5. Replace nested BetterHealthCard with flat layout:
// No cards inside cards. Use Divider() or padding for grouping.

// 6. Lazy-render below-the-fold sections:
// Wrap stageSection + BaselineComparisonChartView in LazyVStack
LazyVStack(alignment: .leading, spacing: BetterSpacing.section) {
    stageSection
    BaselineComparisonChartView(...)
}

// 7. Add skeleton loading instead of blank state:
// Currently: isLoading = true → whole screen is empty
// Fix: show TrendsDashboardSkeletonView (shimmer placeholders)
// while real data loads in background
```

---

## 8. The Horizontal Scroll Bug — Precise Fix

**Root cause:** `TrendMetricSelectorView` uses `ScrollView(.horizontal)` nested inside the outer `ScrollView(.vertical)`. In iOS, when you start a drag inside a nested horizontal scroll view, UIKit/SwiftUI uses gesture competition. If your horizontal drag starts near the boundary of the chip row (or if the drag is slightly diagonal), the gesture bubbles up to the outer scroll view and causes the vertical scroll view to "shimmy" horizontally (rubber-band bounce without actual offset change).

**This is not the page scrolling horizontally — it is the rubber-band elastic bounce.** The ScrollView(.vertical) is bouncing on a horizontal axis because the gesture propagated.

**Fix in `TrendMetricSelectorView.swift`:**
```swift
var body: some View {
    ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: BetterSpacing.small) {
            ForEach(TrendMetric.allCases) { metric in
                // ... chip buttons
            }
        }
        .padding(.horizontal, 1) // prevent clip edge artifact
    }
    .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
    .scrollClipDisabled(false)
}
```

**And in `TrendsTabView.swift`, on the outer ScrollView:**
```swift
ScrollView(.vertical, showsIndicators: false) {
    // ...
}
.scrollBounceBehavior(.basedOnSize, axes: .vertical)
.scrollDisabled(false)
// Add this modifier to prevent horizontal bounce passthrough:
.contentMargins(.horizontal, 0, for: .scrollContent)
```

On iOS 18+ the definitive fix is:
```swift
ScrollView(.vertical, showsIndicators: false) { ... }
.scrollBounceBehavior(.basedOnSize)  // applies to BOTH axes — kills horizontal bounce
```

---

## 9. Interactive Playground — Architecture Recommendation

The user wants a "playground to compare metrics like Deep, REM, Sleep Score, Stage Composition in a rich, functional, interactive UI."

### Ideal implementation: `InsightsExplorerView`

This replaces the current disconnected sections with a **unified interactive comparison surface**:

```
┌─────────────────────────────────────────┐
│  COMPARE METRICS                        │
│  [Deep Sleep ▼]  vs  [REM Sleep ▼]      │  ← Two metric pickers
│                                         │
│  ╔═══════════════════════════════════╗  │
│  ║  Dual-line chart                  ║  │  ← Both metrics overlaid
│  ║  Deep: ──── (purple)              ║  │
│  ║  REM: - - - (cyan)                ║  │
│  ║  [tap any dot = detail tooltip]   ║  │
│  ╚═══════════════════════════════════╝  │
│                                         │
│  AVERAGES           7D    30D    60D    │  ← Period comparison table
│  Deep Sleep        1h2m  1h9m  1h11m   │
│  REM Sleep         1h8m  2h0m  1h55m   │
│  Sleep Score          72    71     69   │
│                                         │
│  ████████████████░░░░░░  Deep 16%       │  ← Stage composition bars
│  ████████████████████░░  Light 56%      │    (same data, clearer)
│  ████████████████████░░  REM 27%        │
│  ░░  Awake 0%                           │
└─────────────────────────────────────────┘
```

**SwiftUI architecture for this:**
```swift
// New file: Features/Trends/InsightsExplorerView.swift

struct InsightsExplorerView: View {
    @State private var primaryMetric: TrendMetric = .totalSleep
    @State private var secondaryMetric: TrendMetric? = .deepSleep
    @State private var selectedWindow: TrendWindow = .month
    let sessions: [SleepSession]
    let baseline: SleepBaseline?
    
    var body: some View {
        VStack(spacing: 0) {
            // Metric pickers (horizontal chip rows)
            metricPickers
            
            // Dual-overlay chart
            DualMetricChartView(
                sessions: sessions,
                primary: primaryMetric,
                secondary: secondaryMetric,
                window: selectedWindow
            )
            .frame(height: 220)
            
            // Period comparison table
            PeriodComparisonTableView(
                sessions: sessions,
                metrics: [primaryMetric, secondaryMetric].compactMap { $0 }
            )
            
            // Stage composition strip
            if hasStageData {
                StageCompositionStripView(sessions: filteredSessions)
            }
        }
    }
}
```

**Key interactions to implement:**
- Tap metric chip → primary metric changes, chart animates with `.spring(response: 0.45, dampingFraction: 0.82)`
- Long-press metric chip → set as secondary overlay
- Tap chart point → show detail card sliding up from bottom (`.safeAreaInset(edge: .bottom)`)
- Swipe chart left/right → advance/retreat through time (pan gesture on chart)
- Period buttons (7D/30D/60D) affect ALL charts simultaneously via shared `selectedWindow` binding

---

## 10. Recommended Final Section Order

```
TrendsTabView layout (proposed):

1. Header ("Sleep Insights")
2. Window picker [7D / 30D / 60D]  ← ONE picker, governs everything below
3. InsightsOverviewCard             ← Score + trend sparkline + verdict text only
4. InsightsExplorerView             ← NEW: interactive metric playground
5. ChronotypeInsightCardView        ← Body Clock (simplified, no metric strip)
6. InsightsWeekdayWeekendCard       ← Immediately after Chronotype (management request)
7. InsightsBedtimeCard              ← Schedule consistency only
8. InsightsSleepInsightsCard        ← 4-item insight list (last, after context is built)
9. [Cut]: InsightsBestSleepCard
10. [Cut]: insightFramingCard (CHANGED/USUAL/DATA triple)
11. [Cut]: summaryStrip (THIS PERIOD/CHANGE/PREVIOUS)
12. [Move to explorer]: StageStackedBarView
13. [Move to explorer]: BaselineComparisonChartView
```

**Why this order works:**
- User sees their score first (emotional grounding)
- Then they get the chart to understand the trend (analytical)
- Then the playground to explore specific metrics (engagement)
- Then chronotype + weekday/weekend gives behavioral insight (contextual)
- Then schedule data (prescription)
- Then the insight list (diagnosis) — the most cognitively demanding section is last, when the user has context to understand it

---

## 11. Priority Implementation Checklist

### P0 — Bugs (do first)
- [ ] Fix horizontal scroll rubber-band: `.scrollBounceBehavior(.basedOnSize)` on outer ScrollView
- [ ] Fix chart `DragGesture` stealing vertical scroll: change `minimumDistance: 0` → `minimumDistance: 8`
- [ ] Fix `SleepInsightService` being re-allocated on every `loadData()` — make it an instance var
- [ ] Fix truncated label strings in the "What changed" triple-card

### P1 — Dark theme consistency
- [ ] Remove nested `BetterHealthCard` in `insightFramingCard` — flatten to a single card with internal layout
- [ ] Audit all fallback icon colors — `InsightsSleepInsightsCard` grey icons disappear on dark bg
- [ ] Apply consistent card elevation: `BetterColors.card` for cards, `BetterColors.cardSecondary` for inner sections, never nest both

### P2 — IA cleanup (cut sections)
- [ ] Remove `InsightsBestSleepCard` entirely
- [ ] Replace triple CHANGED/USUAL/DATA card with a single clean `ComparisonBannerView` (one line: "You slept +36m more than your 30-day average")
- [ ] Remove duplicate window picker from `StageDurationCompositionView` — bind it to the global `selectedWindow`
- [ ] Rename metric labels: WASO → "Wake Time", SpO2 → "Blood Oxygen", "Longest Block" → "Longest Sleep Stretch"

### P3 — Interactive playground
- [ ] Build `InsightsExplorerView` with dual-metric overlay chart
- [ ] Replace the `trendChartSection` + `stageSection` + `BaselineComparisonChartView` with the explorer
- [ ] Add period comparison table (7D vs 30D vs 60D averages per metric)

### P4 — Performance
- [ ] Apply `.drawingGroup()` to full `ChronotypeClockView`
- [ ] Wrap below-fold sections in `LazyVStack`
- [ ] Add skeleton loading state (shimmer cards during `isLoading`)
- [ ] Add `.equatable()` conformance to chart data structs to prevent unnecessary re-renders

---

## Appendix — Code Locations

| Problem | File | Line |
|---|---|---|
| Horizontal bounce bug | `TrendsTabView.swift` | 9, 69 |
| Metric selector horizontal scroll | `TrendMetricSelectorView.swift` | 8 |
| Chart gesture stealing scroll | `TrendLineChartView.swift` | 68 |
| SleepInsightService allocation | `TrendsViewModel.swift` | 363 |
| Nested card layout | `TrendsTabView.swift` | 116–181 |
| Duplicate window picker | `StageStackedBarView.swift` (in `StageDurationCompositionView`) | — |
| Body Clock metric strip timestamps | `ChronotypeInsightCardView.swift` | 416–461 |
| Best Night card (cut this) | `InsightsBestSleepCard.swift` | — |
| CHANGED/USUAL/DATA truncation | `TrendsTabView.swift` | 125–177 |
