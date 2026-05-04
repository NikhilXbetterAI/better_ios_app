# Baseline And Historical Dashboard Implementation

Last updated: 2026-05-04

This document describes how Better should use older Apple Health data to calculate a personal sleep baseline and let users view older dashboard dates without moving focus away from today.

## Goal

Better should calculate a useful baseline even for a new user when Apple Health already has sleep history on device. After authorization, the app should backfill the last 30 days by default, keep enough cached history for weekly and monthly comparisons, and show the dashboard for today by default with an optional date/month selector for older days.

Recommended product behavior:

- Today is always the default dashboard date.
- Baseline is calculated from previous nights, not the currently selected/current sleep session.
- Recent comparison means selected sleep session compared to the user's rolling 15 or 30 day baseline.
- Daily comparison means selected day compared to its own as-of baseline.
- Weekly comparison means this week compared to last week.
- Monthly comparison means this month compared to last month.
- Older dates are a secondary viewing mode, similar to the attached Apple Health calendar pattern.

## Official Apple References

Apple's HealthKit documentation supports this approach:

- [HealthKit](https://developer.apple.com/documentation/healthkit) is the central repository for iPhone and Apple Watch health data. Apple notes that HealthKit apps read data with user permission and must handle data changes made outside the app.
- [Reading data from HealthKit](https://developer.apple.com/documentation/healthkit/reading-data-from-healthkit) describes queries as snapshots of requested HealthKit data and long-running queries as a way to receive updates.
- [HKCategoryValueSleepAnalysis](https://developer.apple.com/documentation/healthkit/hkcategoryvaluesleepanalysis) documents sleep analysis values including `inBed`, `awake`, `asleepCore`, `asleepDeep`, `asleepREM`, and `asleepUnspecified`. Apple also states that in-bed samples and detailed stage samples can overlap, so Better must not directly sum raw sample durations.
- [HKAnchoredObjectQuery](https://developer.apple.com/documentation/healthkit/hkanchoredobjectquery) returns changes in the HealthKit store and provides an anchor so later queries can fetch only newer saved or deleted objects.
- [HKAnchoredObjectQueryDescriptor init](https://developer.apple.com/documentation/healthkit/hkanchoredobjectquerydescriptor/init%28predicates%3Aanchor%3Alimit%3A%29) says passing a nil anchor returns all matching samples and recently deleted objects currently in the HealthKit store. This is useful for initial historical backfill.
- [Executing Observer Queries](https://developer.apple.com/documentation/healthkit/executing-observer-queries) says observer queries notify the app when matching samples are saved or deleted and that the app must call the update completion handler after processing.
- [enableBackgroundDelivery](https://developer.apple.com/documentation/healthkit/hkhealthstore/enablebackgrounddelivery%28for%3Afrequency%3Awithcompletion%3A%29) says iOS 15 and later requires the `com.apple.developer.healthkit.background-delivery` entitlement for HealthKit background delivery.

## Current Codebase Fit

The current architecture already has most of the required pieces:

- `Better/Core/Repositories/HealthKitRepository.swift` reads HealthKit samples.
- `Better/Core/Processors/SleepDataProcessor.swift` converts raw sleep samples into normalized `SleepSession` values and computes `SleepBaseline`.
- `Better/Core/Repositories/LocalDataRepository.swift` caches sessions, baselines, biometrics, adherence, alerts, and sync anchors in SwiftData.
- `Better/Core/Services/SyncCoordinator.swift` performs initial sync, foreground refresh, incremental refresh, baseline computation, and alert generation.
- `Better/Features/Sleep/SleepDashboardViewModel.swift` currently loads the latest cached session.
- `Better/Features/Trends/TrendsViewModel.swift` already works from cached sessions and can become the source for weekly/monthly comparisons.

The important gap is not HealthKit capability. The gap is that baseline and dashboard state need to be date-aware.

## Data Windows

Use three separate windows:

| Window | Purpose | Recommended range |
| --- | --- | --- |
| Initial backfill | Get enough history after first permission grant | 45 days minimum, 75 days preferred |
| Rolling baseline | Personal average used for comparison | User setting: 15 or 30 previous valid nights |
| Dashboard history | User-selectable older dates and calendar rings | Last 90 days cached locally |

Why 75 or 90 days cached:

- 30 day baseline needs previous 30 valid nights.
- Monthly comparison needs this month and last month.
- Users may miss nights or have watch/data gaps.
- A larger local cache avoids repeated expensive HealthKit reads when browsing history.

## Recommended Approach

Use HealthKit as the raw source and SwiftData as the app's dashboard source of truth.

1. On authorization, run a historical backfill query from `now - 90 days` to `now + 2 hours`.
2. Process all returned sleep samples through `SleepDataProcessor`.
3. Store one derived `SleepSession` per `sleepDateKey`.
4. Attach biometrics for each sleep session window.
5. Compute baselines as of each relevant dashboard date, excluding the selected/current session.
6. Use observer and anchored queries only for updates after the historical backfill.
7. Render dashboard, weekly, and monthly views from SwiftData, not direct HealthKit queries.

This is the safest approach because HealthKit remains the raw input layer and the UI uses deterministic cached derived data.

## Baseline Calculation Rules

Baseline should be calculated as of a target sleep date:

```swift
baseline(for sleepDateKey: String, windowDays: Int)
```

For a selected session with `sleepDateKey = 2026-03-18`, the baseline window should use valid sessions before `2026-03-18`, not including `2026-03-18`.

Rules:

- Include only sessions with at least 5 minutes of actual asleep time.
- Exclude `.inBedOnly` and `.noData`.
- Use `.unspecifiedSleepOnly` for total sleep, efficiency, latency, and WASO.
- Exclude `.unspecifiedSleepOnly` from REM/deep averages because stage detail is unavailable.
- Require at least 5 valid nights before showing baseline comparison.
- Show confidence labels:
  - 5-9 valid nights: warming up
  - 10-14 valid nights: usable
  - 15+ valid nights: reliable
- Prefer median or trimmed mean later if outliers become a problem, but keep the first implementation as mean plus standard deviation because the current model already supports it.

Current issue to fix:

`SyncCoordinator.performSyncHealthRange` computes the latest baseline from cached sessions ending at the sync end date. For current-night comparison, that can include the session being compared. Add date-aware baseline computation so each dashboard date compares against only earlier sessions.

## Daily, Weekly, And Monthly Comparisons

### Daily

For the selected date:

- Fetch session by `sleepDateKey`.
- Fetch baseline as of that `sleepDateKey`.
- Compare total sleep, score, efficiency, REM, deep, WASO, HRV, respiratory rate, and oxygen saturation.
- Display "vs 30-day avg" or "vs 15-day avg" based on profile setting.

### Weekly

Use ISO week or app-local calendar weeks consistently. Recommended: current calendar with user's locale and timezone.

For "this week compared to last week":

- This week: start of week through today or selected date.
- Last week: full equivalent previous week, or same number of elapsed days for fair mid-week comparison.
- Compare averages for score, total sleep, efficiency, REM, deep, WASO, HRV, and adherence.
- Also show count of valid nights so users understand partial weeks.

Recommended mid-week rule:

- If today is Wednesday, compare Sunday-Wednesday this week against Sunday-Wednesday last week.
- In a historical completed week, compare full week against previous full week.

### Monthly

For "this month compared to last month":

- Current month: start of month through today or selected date.
- Previous month: same day-count slice from the previous month for fair in-progress comparison.
- If the selected month is fully in the past, compare full selected month to full previous month.
- Compare averages and valid night counts.

## Historical Dashboard UX

Default state:

- Dashboard opens to today.
- Primary header says "Today" or "Last Night's Sleep" depending on session timing.
- If no session exists for today, show no-data state and last successful sync.

Optional history state:

- Add a compact date control in the Sleep tab header.
- Tapping it opens a monthly sheet/calendar.
- User can move month backward/forward.
- Each day shows a small ring or dot using cached score/data quality:
  - score ring for valid sleep session
  - dim empty ring for no data
  - partial marker for unspecified sleep only
- Selecting a day updates the dashboard to that date.
- Add a visible "Today" button when viewing any older date.

Do not make history the main dashboard. It should be an add-on view for browsing already cached sessions.

## Data Model And Repository Changes

Add repository methods:

```swift
func fetchSession(forSleepDateKey key: String) async throws -> SleepSession?
func fetchSessions(sleepDateKeys: ClosedRange<String>) async throws -> [SleepSession]
func fetchSessions(beforeSleepDateKey key: String, limit: Int) async throws -> [SleepSession]
func fetchAvailableSleepDates(from key: String, to: String) async throws -> [SleepDaySummary]
func fetchBaseline(asOfSleepDateKey key: String, windowDays: Int) async throws -> SleepBaseline?
```

Add a lightweight summary model:

```swift
struct SleepDaySummary: Codable, Hashable, Sendable, Identifiable {
    var id: String { sleepDateKey }
    var sleepDateKey: String
    var score: Double?
    var totalSleepTime: TimeInterval?
    var dataQuality: SleepDataQuality
    var hasSession: Bool
}
```

Recommended persistence change:

- Keep `StoredSleepSession.sleepDateKey` unique.
- Add indexed fields later if SwiftData query performance becomes an issue: `sleepDateKey`, `startDate`, `endDate`.
- Store generated baseline snapshots by `(windowDays, asOfSleepDateKey)` rather than only "latest baseline".

Baseline snapshot model:

```swift
struct SleepBaseline {
    var windowDays: Int
    var generatedAt: Date
    var asOfSleepDateKey: String
    var validNights: Int
    ...
}
```

If avoiding a migration now, compute historical baselines on demand from cached sessions and continue storing only the latest baseline. That is acceptable for the first implementation.

## Sync Changes

Update `SyncCoordinator`:

```swift
func performInitialSync(now: Date = Date()) async {
    let startDate = calendar.date(byAdding: .day, value: -90, to: now) ?? now.addingTimeInterval(-90 * 86_400)
    let endDate = now.addingTimeInterval(2 * 3_600)
    await syncHealthRange(from: startDate, to: endDate)
}
```

Recommended behavior:

- Initial sync: 90 days.
- Foreground refresh: 48 hours for latest updates, plus historical backfill if the app has never completed it.
- Incremental refresh: anchored query first, then expanded reprocess around changed samples.
- If HealthKit returns deleted objects, reprocess a wider range because deleted sleep samples can change derived sessions.
- Save a `historicalBackfillCompletedAt` flag in profile or a sync metadata model.

Important HealthKit rule:

- Use an observer query for updates.
- Call the observer completion handler only after processing and saving the affected range.
- If processing fails, still call completion after recording the error; otherwise HealthKit can stop delivering updates after repeated failures.

## View Model Changes

Replace `todaySession`-only state with date-aware state:

```swift
var selectedSleepDateKey: String
var selectedSession: SleepSession?
var selectedBaseline: SleepBaseline?
var selectedDaySummaries: [SleepDaySummary]
var isViewingToday: Bool
```

Methods:

```swift
func onAppear() async
func refresh() async
func selectDate(_ sleepDateKey: String) async
func jumpToToday() async
func loadMonth(_ month: Date) async
```

Default:

- `selectedSleepDateKey = todaySleepDateKey`
- `selectedSession = fetchSession(forSleepDateKey: todaySleepDateKey)`
- If today's session is missing, optionally fall back to latest completed sleep session in a secondary card, but keep the selected date as today.

## UI Implementation

Sleep tab header:

- Current title: "Today" or formatted selected date.
- Small calendar button or month label.
- Chevron controls only inside the monthly sheet, not always on the main dashboard.
- "Today" button appears only when selected date is not today.

Monthly sheet:

- Month title, previous/next buttons.
- Tabs or segmented picker for Strain, Recovery, Sleep, Stress, Energy can be future work. For this app, start with Sleep only.
- 7-column day grid.
- Ring per date using `SleepDaySummary.score`.
- Disabled future days.
- Empty/dim state for no cached session.

Avoid:

- Making older dates look like the primary user journey.
- Triggering HealthKit reads every time a user taps a calendar date.
- Showing exact read-permission claims. Query results are the truth for display.

## Best Approach

Recommended first implementation:

1. Increase historical backfill to 90 days after authorization.
2. Add date-key repository methods for sessions and day summaries.
3. Add date-aware baseline calculation that excludes the selected date.
4. Update `SleepDashboardViewModel` from latest-session state to selected-date state.
5. Add a compact Sleep history calendar sheet.
6. Add weekly/monthly comparison helpers in the Trends feature from cached sessions.
7. Add unit tests for baseline exclusion, week/month windows, and missing-data behavior.

This approach is best because it uses Apple's intended HealthKit query model, keeps HealthKit reads out of the UI, works with historical Apple Watch data already on device, and does not require a backend.

## Alternative Approaches

### Minimal Patch

Only change initial sync from 45 days to 90 days and compute latest baseline from cached sessions.

Pros:

- Fastest.
- Low code change.

Cons:

- Baseline can still be wrong for selected/current date.
- No correct historical dashboard behavior.
- Weekly/monthly comparisons remain ad hoc.

Not recommended except as a temporary debug step.

### Store Every Baseline Snapshot

Generate and persist a baseline for every date during sync.

Pros:

- Fast dashboard date switching.
- Reproducible historical comparisons.

Cons:

- More storage.
- More migration work.
- More sync complexity.

Recommended later if history browsing becomes a core feature.

## Test Plan

Unit tests:

- Initial baseline excludes the selected/current session.
- 15-day and 30-day windows use only earlier valid nights.
- Baseline returns not-ready when fewer than 5 valid nights exist.
- `.unspecifiedSleepOnly` contributes to total sleep but not REM/deep averages.
- Week-to-week comparison uses equal elapsed day counts for in-progress weeks.
- Month-to-month comparison uses equal elapsed day counts for in-progress months.
- Missing day appears as empty in `SleepDaySummary`.
- Future day is disabled in calendar UI.

Integration tests:

- Seed SwiftData with 60 days of sessions and verify today's dashboard loads today, not latest historical session by accident.
- Select an older date and verify session, baseline, and header update.
- Tap "Today" and verify dashboard returns to today's date.

Physical-device validation:

- Install on iPhone paired with Apple Watch.
- Authorize HealthKit sleep and biometric reads.
- Confirm initial backfill imports older Apple Health sleep samples.
- Confirm background delivery updates after a new sleep session appears.

## Implementation Checklist

- [ ] Add `SleepDaySummary`.
- [ ] Add date-key helpers for today, week, and month windows.
- [ ] Add date-based local repository fetch methods.
- [ ] Increase initial historical backfill to 90 days.
- [ ] Add a persisted or computed baseline `asOfSleepDateKey`.
- [ ] Update `SleepDashboardViewModel` to `selectedSleepDateKey`.
- [ ] Add monthly sleep history sheet.
- [ ] Add daily, weekly, monthly comparison functions.
- [ ] Add tests for baseline and comparison windows.
- [ ] Validate HealthKit historical reads on physical device.
