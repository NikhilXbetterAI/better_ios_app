# Sleep Chronotype Calculation Implementation Plan

Last updated: 2026-05-18

## Goal

Calculate each user's estimated sleep chronotype from recent wearable sleep data using the provided MSFsc method:

- Use the last 30-90 days of sleep sessions.
- Split nights into workdays and free days.
- Exclude travel/time-zone disruption, poor-quality wearable data, and implausible durations.
- Calculate MSW, MSF, SDw, SDf, SDweek, corrected MSFsc, chronotype bucket, and an optimal sleep window.
- Keep the implementation local-first and consistent with Better's existing HealthKit, SwiftData, service, and view-model architecture.

For team-wide analysis, Better currently has no backend/team data store in the app architecture. The safe path is:

- In-app: calculate chronotype per user on-device from cached `SleepSession` data.
- Team cohort: calculate from consented research exports or local developer/test datasets, using the same pure calculation logic ported to a small batch tool or exposed through the existing export pipeline.

## Current Architecture Fit

| Existing area | Current role | Chronotype addition |
|---|---|---|
| `Better/Core/Models/SleepModels.swift` | Owns `SleepSession`, `SleepDataQuality`, source metadata, onset/end/duration | Add chronotype domain models in a new file, not inside the large sleep model file. |
| `Better/Core/Services/BaselineEngine.swift` | Defines validity filtering and confidence patterns | Reuse the concept, but implement chronotype-specific validity: 3-12h, no in-bed-only/no-data, travel excluded. |
| `Better/Core/Services/ResearchAnalysisService.swift` | Joins sleep, context, activity status, and protocol data | Reuse the same repository joins for travel and jet-lag exclusion. Optionally append chronotype fields to export. |
| `Better/Core/Repositories/LocalDataRepository.swift` | Fetches cached sleep sessions, context entries, and activity logs | Use existing fetch methods first. Persisting chronotype can be added later only if UI performance requires it. |
| `Better/Features/Sleep/SleepDashboardViewModel.swift` | Loads recent sleep state for Sleep tab | Add a small chronotype summary after the service exists. |
| `Better/Features/Trends/` | Shows longer-term sleep trends | Best long-term home for chronotype trend/history. |
| `Better/Features/Onboarding/SleepAssessmentQuestion.swift` | Captures self-reported sleep timing and energy patterns | Do not use for this wearable-only estimate. It can be shown later only as a comparison or validation signal. |
| `Better/Core/Services/ResearchCSVExporter.swift` | Exports nightly research data | Append chronotype export fields for backward compatibility; do not reorder existing columns. |
| `BetterTests/` | Unit tests around processors/services/repositories | Add focused chronotype service tests before UI work. |

Recommended placement:

```text
Better/
├── Core/
│   ├── Models/
│   │   └── ChronotypeModels.swift
│   └── Services/
│       └── ChronotypeCalculationService.swift
└── Features/
    ├── Sleep/
    │   └── ChronotypeSummaryCardView.swift
    └── Trends/
        └── ChronotypeDetailView.swift              # optional later phase

BetterTests/
└── ChronotypeCalculationServiceTests.swift
```

## Calculation Contract

### Inputs

Use cached `SleepSession` rows from the last 30-90 days.

For every candidate night, derive:

- Sleep onset: first sleep-stage start in `session.stages` where `stage.type.isSleep`; fall back to `session.startDate` only when stages are unavailable.
- Wake time: final sleep-stage end in `session.stages` where `stage.type.isSleep`; fall back to `session.endDate` only when stages are unavailable.
- Sleep duration: `session.totalSleepTime`
- Sleep date key: `session.sleepDateKey`
- Data quality: `session.dataQuality`
- Travel/time-zone disruption:
  - `SleepContextEntry.travel == true`
  - `ActivityStatusLog.status == .traveling`
  - `ActivityStatusLog.status == .jetLagged`

### Workday / Free-Day Definition

Use the user's local calendar.

- Workday nights: Sunday through Thursday nights.
- Free-day nights: Friday and Saturday nights.

Implementation detail: classify by the local weekday of sleep onset, not by `sleepDateKey`.

This matters because `SleepDateKey.sleepDateKey(forSessionStart:)` assigns sessions starting after noon to the next calendar date. If chronotype used `sleepDateKey`, Thursday night would look like Friday and Saturday night would look like Sunday, which would corrupt the workday/free-day split.

### Exclusions

Chronotype should use stricter validity than the current baseline engine:

- Exclude `totalSleepTime < 3h`.
- Exclude `totalSleepTime > 12h`.
- Exclude `dataQuality == .inBedOnly` or `.noData`.
- Exclude travel or jet-lag nights from context/activity logs.
- Exclude sessions with invalid dates, negative durations, or `startDate >= endDate`.

Keep `unspecifiedSleepOnly` only if it came from a wearable source and has a real sleep duration. Do not use stage-specific fields for chronotype.

### Nightly Midpoint

For each valid night:

```swift
sleepOnset = firstSleepStageStart ?? session.startDate
midpoint = sleepOnset + (session.totalSleepTime / 2)
```

The midpoint must be converted to "minutes since local midnight" using circular time handling. This avoids bad medians around midnight, for example 23:50 and 00:10.

### Aggregates

Calculate:

- `MSW`: circular median midpoint of workday nights.
- `MSF`: circular median midpoint of free-day nights.
- `SDw`: median sleep duration on workday nights.
- `SDf`: median sleep duration on free-day nights.
- `SDweek = ((5 * SDw) + (2 * SDf)) / 7`
- `MSFsc = MSF - ((SDf - SDweek) / 2)` only when `SDf > SDw`; otherwise `MSFsc = MSF`.

Implementation detail: `MSF`, `MSW`, and `MSFsc` are minutes-of-day. `SDw`, `SDf`, and `SDweek` are `TimeInterval` seconds in Swift. Convert the correction term from seconds to minutes before subtracting:

```swift
let correctionMinutes = ((freeMedianDuration - weeklyAverageDuration) / 2) / 60
let correctedMidpointMinute = normalizeMinute(freeMidpointMinute - correctionMinutes)
```

Chronotype bucket:

| Corrected midpoint | Bucket |
|---|---|
| `< 03:00` | Early |
| `03:00-03:59` | Early-intermediate |
| `04:00-04:59` | Intermediate |
| `05:00-05:59` | Late-intermediate |
| `>= 06:00` | Late |

### Minimum Data Rules

Use explicit confidence rather than silently returning a label:

- Minimum viable result: at least 14 valid nights total, at least 6 workday nights, and at least 3 free-day nights.
- Low confidence: 14-20 valid nights or only 3-4 free-day nights.
- Medium confidence: 21-44 valid nights with at least 5 free-day nights.
- High confidence: 45+ valid nights with at least 8 free-day nights and fewer than 20% excluded nights.

If the user has fewer than the minimum viable inputs, return an `.insufficientData` result with counts and exclusion reasons.

## Domain Models

Create `Better/Core/Models/ChronotypeModels.swift`.

Suggested model shape:

```swift
enum ChronotypeBucket: String, Codable, CaseIterable, Hashable, Sendable {
    case early
    case earlyIntermediate
    case intermediate
    case lateIntermediate
    case late
}

enum ChronotypeExclusionReason: String, Codable, Hashable, Sendable {
    case tooShort
    case tooLong
    case poorDataQuality
    case travelOrJetLag
    case invalidTiming
}

enum ChronotypeDayType: String, Codable, Hashable, Sendable {
    case workday
    case freeDay
}

struct SleepWindowRecommendation: Codable, Hashable, Sendable {
    var startMinute: Int
    var endMinute: Int
    var duration: TimeInterval
}

struct ChronotypeNight: Codable, Hashable, Sendable {
    var sleepDateKey: String
    var dayType: ChronotypeDayType
    var onset: Date
    var wake: Date
    var duration: TimeInterval
    var midpointMinute: Int
}

struct ChronotypeEstimate: Codable, Hashable, Sendable {
    var bucket: ChronotypeBucket
    var correctedMidpointMinute: Int
    var workdayMidpointMinute: Int
    var freeDayMidpointMinute: Int
    var workdayMedianDuration: TimeInterval
    var freeDayMedianDuration: TimeInterval
    var weeklyAverageDuration: TimeInterval
    var validNightCount: Int
    var excludedNightCount: Int
    var confidence: ComparisonConfidence
    var optimalSleepWindow: SleepWindowRecommendation
}
```

Do not add SwiftData persistence in the first pass. The result is cheap to recompute from 30-90 sessions and related logs. Persist later only if product needs historical chronotype trend tracking.

## Service Design

Create `Better/Core/Services/ChronotypeCalculationService.swift` as a pure, synchronous service:

```swift
nonisolated struct ChronotypeCalculationService: Sendable {
    func estimate(
        sessions: [SleepSession],
        contextEntries: [SleepContextEntry],
        activityLogs: [ActivityStatusLog],
        windowDays: Int = 90,
        endingAt: Date = Date(),
        calendar: Calendar = .current
    ) -> ChronotypeCalculationResult
}
```

Keep repository access out of this service. That makes it easy to test, reuse in exports, and reuse in a team batch tool.

Important implementation details:

- Clamp `windowDays` to 30...90.
- Filter by sleep onset date before calculating, with an inclusive date-key range for repository fetches so boundary nights are not dropped.
- Build `contextByDateKey` and `activityByDateKey` dictionaries, matching the pattern in `ResearchAnalysisService`.
- Use small local helpers for median duration and circular median minute. `SleepDataProcessor` already has circular mean helpers for baseline timing; either keep chronotype helpers private or deliberately extract shared circular-time utilities with tests.
- Implement circular median by anchoring around the circular mean, unwrapping all minutes to a continuous range near that anchor, taking the normal median, then normalizing back to `0..<1440`.
- Return a typed result with included nights, excluded counts by reason, and confidence.

## Likely Bugs / iOS Failure Points

These are the main errors to avoid during implementation:

- Do not classify workday/free-day from `sleepDateKey`. Better shifts sessions starting after noon to the next date, so Thursday night would become Friday and Saturday night would become Sunday.
- Do not use `inBedStartDate` for sleep onset. Chronotype needs sleep onset; use first actual sleep stage when available.
- Do not subtract a `TimeInterval` directly from a minute-of-day. Convert seconds to minutes first.
- Do not average clock times with a normal arithmetic median/mean around midnight. Use circular time handling.
- Do not assume HealthKit can identify travel or time-zone changes. Better can only exclude explicit app context/status flags unless a future feature adds location/time-zone history.
- Be careful with historical time zones. `Date` stores instants, not the user's time zone at that night. The first version should use the current user calendar consistently and exclude known travel/jet-lag nights.
- Do not string-match source names alone to prove wearable data. Prefer `SleepSource.isManualEntry == false` plus `productType`/`bundleIdentifier` heuristics, and keep the rule conservative.
- Do not add stored SwiftData models in Phase 1. A new persisted model means schema/versioning and migration work for a value that is cheap to recompute.
- Do not insert chronotype columns into the middle of `nightly_research_rows.csv`; append or create a separate `chronotype_summary.csv` to preserve export compatibility.
- Do not treat missing context as proof of no travel. Missing context should remain unknown; only explicit travel/jet-lag flags should exclude a night.

## Repository / View-Model Integration

Add a thin async loader where the UI needs it, likely in `SleepDashboardViewModel` first:

1. Fetch sessions from `selectedDate - 90 days` to selected date with `fetchCachedSessions(from:to:)`.
2. Fetch context entries and activity logs over the same date-key range.
3. Call `ChronotypeCalculationService`.
4. Expose `chronotypeEstimate` and `chronotypeUnavailableReason` to the Sleep tab.

This keeps the existing dependency direction intact:

```text
ViewModel -> LocalDataRepositoryProtocol -> ChronotypeCalculationService -> domain result
```

Do not make `ChronotypeCalculationService` depend directly on repositories.

## UI Plan

Phase 1 UI should be compact:

- Add `ChronotypeSummaryCardView` to the Sleep tab or Trends tab.
- Show:
  - Estimated Chronotype: `Intermediate`
  - Corrected midpoint: `4:39 AM`
  - Optimal sleep window: `11:45 PM-7:45 AM`
  - Confidence label and valid-night count
- If insufficient data, show the concrete missing requirement, for example `Need at least 3 free-day nights`.

Optimal sleep window recommendation:

- Default duration should use `SDweek`, rounded to the nearest 15 minutes.
- Center the window around the corrected midpoint:
  - `recommendedStart = MSFsc - SDweek / 2`
  - `recommendedEnd = MSFsc + SDweek / 2`
- Clamp display only for formatting; do not clamp the underlying circular minutes.

Use existing design tokens from `Better/Core/DesignSystem/` and keep the card small. This is a metric, not a new primary workflow.

## Research Export / Team Calculation

For team-level analysis, use consented exports instead of hidden app-side aggregation.

Phase 1:

- Append chronotype fields to `ResearchExportPackage` summary metadata or add a `chronotype_summary.csv`.
- Include only derived values and counts by default:
  - bucket
  - corrected midpoint
  - MSW/MSF
  - SDw/SDf/SDweek
  - valid nights
  - excluded nights by reason
  - confidence

Phase 2:

- Add a local command-line or script-based batch calculator that reads multiple exported ZIP/CSV packages and produces a team CSV.
- Use the same formulas and thresholds as the Swift service.
- Do not include raw sleep onset/wake rows in team output unless users explicitly consented to share detailed sleep timing.

Suggested output columns:

```text
participant_id,
window_start,
window_end,
chronotype_bucket,
corrected_midpoint_local,
msw_local,
msf_local,
sdw_hours,
sdf_hours,
sdweek_hours,
valid_nights,
workday_nights,
free_day_nights,
excluded_travel_or_jetlag,
excluded_poor_quality,
excluded_duration,
confidence
```

## Testing Plan

Add `BetterTests/ChronotypeCalculationServiceTests.swift`.

Test cases:

- Calculates the provided example: MSW 04:00, MSF 05:00, SDweek 7.3h, corrected midpoint about 04:39, bucket `.intermediate`.
- Handles midnight wraparound when onset/midpoint crosses calendar days.
- Classifies Sunday-Thursday as workday nights and Friday-Saturday as free nights.
- Applies catch-up correction only when `SDf > SDw`.
- Does not apply catch-up correction when `SDf <= SDw`.
- Excludes `<3h` and `>12h` nights.
- Excludes `.inBedOnly` and `.noData`.
- Excludes context travel, activity traveling, and activity jet-lagged nights.
- Returns insufficient data when free-day nights are missing.
- Produces stable optimal sleep window formatting around midnight.

Use fixed calendars/time zones in tests, for example `Calendar(identifier: .gregorian)` with `timeZone = TimeZone(secondsFromGMT: 0)!`, so day classification and midpoint assertions do not vary by developer machine.

## Implementation Phases

### Phase 1 - Pure Calculation

- Add chronotype models.
- Add `ChronotypeCalculationService`.
- Add unit tests for formulas, circular time, exclusions, and confidence.
- No persistence and no UI.

Exit criteria:

- Service returns the correct result for known fixtures.
- Tests pass with deterministic calendar/time-zone behavior.

### Phase 2 - In-App User Result

- Load the last 90 days in `SleepDashboardViewModel` or a dedicated Trends view model.
- Add a compact summary card.
- Add insufficient-data states.
- Keep all calculation local.

Exit criteria:

- A user with enough cached wearable sleep data sees a chronotype and sleep window.
- A user without enough data sees actionable missing counts.

### Phase 3 - Research Export

- Add chronotype summary fields to research export output.
- Include exclusion counts and confidence.
- Add exporter tests so CSV column order remains stable.

Exit criteria:

- A researcher can export derived chronotype values without raw timing rows unless detailed export is explicitly intended.

### Phase 4 - Team Batch Analysis

- Build a local batch script/tool over exported CSV/ZIP files.
- Generate one row per participant.
- Validate Swift service and batch output against the same fixture dataset.

Exit criteria:

- Team-level chronotype distribution can be calculated from consented exports.
- No app architecture change is required for centralized storage.

## Engineering Guardrails

- Keep chronotype calculation pure and independently testable.
- Do not use stage-level sleep data for chronotype; onset, wake, duration, quality flags, and travel flags are enough.
- Do not treat missing context as "no travel"; only exclude explicit travel/jet-lag flags. Report unknown context coverage in confidence or caveats later if needed.
- Do not mix team aggregation into the iOS app without a product/privacy decision.
- Do not persist derived chronotype until there is a clear need for history or performance.
- Use existing repository protocols for testability.
- Use circular time math for all clock-time medians and sleep-window formatting.
- Avoid changing `SleepDataProcessor` unless a reusable circular median helper is deliberately extracted and covered by tests.

## Open Decisions

- Whether `unspecifiedSleepOnly` should be considered good enough for chronotype when source metadata indicates a wearable.
- Whether a team export should use participant IDs from research mode, a manual pseudonym, or generated export IDs.
- Whether the UI belongs first in Sleep as a current summary or Trends as a longer-term trait.
- Whether the calculation window should default to 60 days or 90 days. Recommendation: default to 90 days and show the actual valid-night count.
