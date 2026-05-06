# Future Improvement Plan For Better

Last updated: 2026-05-05

## Summary

This document is the current source of truth for improving Better after the verified sleep dashboard implementation. It supersedes `suggested_improvements.md`, which contains useful historical notes but is now partly stale because several Biology and Research issues listed there have already been addressed in the current code.

The next improvement work should focus on two tracks:

1. Fix correctness bugs that can damage user trust.
2. Remove mobile UI lag in the sleep dashboard before adding new features.

## Current Verified Setup

Better is a native iOS app built with SwiftUI, HealthKit, SwiftData, Observation, Swift Charts, BackgroundTasks, and UserNotifications. The codebase uses MVVM with protocol-based repositories and local dependency injection through `AppEnvironment`.

The current app already includes:

- HealthKit sleep and biometric sync through `HealthKitRepository` and `SyncCoordinator`.
- Processed sleep sessions, baselines, alerts, adherence, and profile storage through SwiftData.
- A sleep dashboard with score, baseline comparison, sleep stages, heart rate, respiratory rate, schedule consistency, and history selection.
- Trends, protocol, biology, activity, alerts, settings, onboarding, research analysis, and CSV export surfaces.
- Unit tests for the core processor, local repository, research analysis, alert generation, and related model logic.

The React/Figma Make prototype remains a design reference only. Production work should continue using native SwiftUI patterns and Apple frameworks rather than porting React layout decisions directly.

## Known Bugs And Risks

### Build Verification Blocker

`xcodebuild` currently cannot run in this shell because the active developer directory is:

```text
/Library/Developer/CommandLineTools
```

`xcodebuild` requires full Xcode. Before build or test verification, select Xcode:

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

Then verify with:

```bash
xcodebuild -list -project Better.xcodeproj
```

### Sleep Dashboard Refresh Behavior

`SleepTabView` starts work from `.task { await viewModel.onAppear() }`. `SleepDashboardViewModel.onAppear()` currently resets `selectedSleepDateKey` to today and immediately performs a foreground HealthKit refresh.

Risk:

- Returning to the Sleep tab can reset a manually selected history date.
- The same view task can trigger a full refresh more often than the user expects.
- `isLoading`, `selectedSession`, `selectedBaseline`, `recentSessions`, `selectedMonthSummaries`, `lastSyncedAt`, and `authorizationState` updates can invalidate a large dashboard tree.

Fix direction:

- Split first-load behavior from refresh behavior.
- Preserve explicit history selection unless the user taps Today.
- Gate foreground refreshes so view appearance does not always perform sync work.

### Research Confounder Note Mismatch

`ResearchAnalysisService.effectSummary()` uses `isConfounded` for adjusted analysis and confidence calculations. `buildInsightSummary()` still counts only `isTravelConfounded` when building the exported confounder note.

Risk:

- The export can under-report sick and injured nights in the human-readable summary even though the statistical confidence path treats them as confounders.

Fix direction:

- Update the insight note to count all `isConfounded` rows.
- Keep wording broad: "travel, jet-lag, sick, or injured context."
- Add a test covering sick and injured nights in the exported confounder note.

### Stale Improvement Document

`suggested_improvements.md` is no longer fully accurate. Some issues it lists, especially in Biology and Research, appear already fixed in the current code.

Risk:

- Future agents may rework solved problems or miss the newer mobile performance priority.

Fix direction:

- Keep `suggested_improvements.md` as a historical audit.
- Use this file for current prioritization.

## Mobile Performance Plan

Mobile dashboard responsiveness is the highest-priority product improvement. The Sleep tab currently renders a large, card-heavy scroll hierarchy with broad observation reads and repeated derived calculations inside SwiftUI bodies.

### 1. Make The Sleep Scroll Lazy

Replace `ScrollView + VStack` in `SleepTabView` with `ScrollView + LazyVStack`.

Acceptance criteria:

- Offscreen dashboard sections are not eagerly laid out.
- Visual spacing remains unchanged.
- Pull-to-refresh still works.
- Expanded card state remains stable while scrolling.

### 2. Stop Building Collapsed Card Content Eagerly

`SleepMetricCard` stores `summary()` and `content()` results during initialization. Change the card so heavy expanded content is built only when the card is expanded.

Acceptance criteria:

- Collapsed cards should build only their header and summary.
- Expanded cards should still animate open and closed.
- No public behavior changes to card call sites unless needed for performance.

### 3. Add A Dashboard Snapshot Model

Introduce a lightweight `SleepDashboardViewState` or equivalent snapshot. It should hold display-ready values instead of forcing the view tree to derive them repeatedly.

Precompute:

- Header title and selected date label.
- Sleep score estimate and score breakdown.
- Stage rows, stage summary text, and hypnogram-renderable stage segments.
- Baseline comparison values and "What Changed" items.
- Biometric trend points for heart rate, respiratory rate, HRV, and SpO2 where available.
- Schedule consistency chart metrics.
- Month calendar days and `summaryByKey` lookup data.

Acceptance criteria:

- SwiftUI views receive narrow value inputs instead of reading the full `SleepDashboardViewModel`.
- Repeated `filter`, `sorted`, `Dictionary`, `map`, and formatter work is removed from hot render paths.
- Snapshot recomputation happens only when selected session, baseline, recent sessions, selected month, summaries, or profile settings change.

### 4. Batch View Model State Updates

Refactor `SleepDashboardViewModel.loadSelectedDate()` so repository calls complete first, then observable state is assigned in a tight batch.

Acceptance criteria:

- Avoid partial UI invalidations after each individual field changes.
- Preserve error handling and loading states.
- Keep SwiftData and HealthKit work out of SwiftUI views.

### 5. Precompute Calendar Sheet Data

`SleepHistoryCalendarSheet` currently derives `monthDays`, `summaryByKey`, and future-date checks from computed properties used by the grid.

Fix direction:

- Build a calendar view state when `selectedMonth`, `selectedSleepDateKey`, or summaries change.
- Pass day cell models into the grid.

Acceptance criteria:

- Opening the calendar sheet does not rebuild dictionaries per cell.
- Changing months recomputes only the month state.
- Day cell identity uses stable date keys.

### 6. Move Chart Calculations Out Of Body

Move repeated calculations out of these render paths:

- `ScheduleConsistencyView`: `SleepScheduleChartMetrics` should be passed in or precomputed once.
- `BiometricTrendChart`: bounds, average, line points, and normal range geometry should be derived from a precomputed chart model where practical.
- `SleepHypnogramView`: lane index and frame inputs should be precomputed from cleaned stage segments.
- `SleepStageGridView`: stage item percentages and formatted durations should be precomputed.

Acceptance criteria:

- Chart bodies primarily render already-shaped data.
- Instruments shows less CPU work during scroll and card expansion.
- Empty states still render correctly when no history is available.

### 7. Profile And Validate On Device

Use Instruments after the code changes. Profile:

- Sleep tab initial render.
- Scrolling through the full dashboard.
- Expanding and collapsing Sleep Stages, Heart Rate, Respiratory Rate, and Schedule Consistency cards.
- Opening the sleep history calendar.

Success criteria:

- Reduced frame hitches during dashboard scrolling.
- No visible delay when expanding collapsed cards.
- No unexpected HealthKit refresh while browsing historical dates.

## Product Improvement Roadmap

### Near Term

- Fix Sleep tab refresh and history-date reset behavior.
- Remove mobile dashboard lag.
- Make HealthKit sync states explicit without claiming exact read-permission status.
- Improve empty, missing-data, and sync-error states.
- Add tests around dashboard first load, manual history selection, and confounder notes.

### Mid Term

- Improve trend insights so users can understand what changed week over week and month over month.
- Clarify research export metadata, especially missing biometrics and confounded nights.
- Explain protocol timing buckets in the Protocol and Research flows.
- Improve alert quality by reducing duplicate or low-confidence alerts.
- Add direct tests for view model-derived chart and dashboard state.

### Later

- Use onboarding answers to personalize dashboard explanations and protocol recommendations.
- Validate HealthKit background delivery on a physical iPhone paired with Apple Watch.
- Add privacy-first export controls with clear local-only language.
- Expand research mode with stronger caveats, confidence explanation, and user-controlled export ranges.
- Consider richer personalization only after data correctness and mobile performance are stable.

## Tests And Verification

After selecting full Xcode, run:

```bash
xcodebuild -list -project Better.xcodeproj
xcodebuild test -project Better.xcodeproj -scheme Better -destination 'platform=iOS Simulator,name=iPhone 16'
```

If the destination name differs locally, use `xcrun simctl list devices available` and choose an available iPhone simulator.

Add or update tests for:

- `SleepDashboardViewModel.onAppear()` does not reset a manually selected history date unexpectedly.
- Loading a selected date does not perform unnecessary duplicate profile, month, or baseline fetches.
- `ResearchAnalysisService.buildInsightSummary()` includes sick and injured nights in confounder notes.
- Schedule and biometric chart helper models produce stable values for empty, one-point, and 30-point inputs.
- Calendar sheet state produces correct leading blanks, future-date disabled states, selected date state, and summary lookup.

Manual verification:

- Launch app with cached preview data.
- Open Sleep tab and scroll from top to bottom.
- Expand and collapse every Sleep dashboard card.
- Select a historical date, leave the tab, return, and confirm selection is preserved unless Today is tapped.
- Pull to refresh and confirm loading state is visible but not disruptive.
- Open the history calendar, navigate months, and select a date.

## Assumptions And Defaults

- This plan uses `FUTURE_IMPROVEMENT_PLAN.md` as the current planning source.
- `suggested_improvements.md` remains in the repo as historical context, but future implementation work should start here.
- Do not add external dependencies for these improvements.
- Keep architecture aligned with native SwiftUI, HealthKit, SwiftData, repository protocols, and `@Observable` view models.
- Prioritize mobile lag and trust-affecting correctness bugs before new feature work.
