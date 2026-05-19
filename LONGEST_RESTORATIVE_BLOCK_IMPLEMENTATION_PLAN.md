# Longest Restorative Block Implementation Plan

Date: 2026-05-18
Project: Better iOS app
Scope: Apple HealthKit sleep continuity metric, SwiftUI visualization, Trends support, CSV export, and verification plan.

## Goal

Add a second sleep insight alongside restorative sleep amount.

- Existing/restorative amount: `REM + deep`
- New continuity metric: `Longest Restorative Block`
- Purpose: answer "What was the longest stretch where recovery remained uninterrupted?"

This metric measures continuity, not total sleep and not time in bed.

## Product Definition

### Metric Name

Longest Restorative Block, abbreviated internally as `LRB` only where concise naming is useful.

### User-Facing Definition

The longest continuous period of sleep without a meaningful interruption.

### Split Rule

Create sleep blocks from the stage timeline.

- Sleep stages that continue the current block: `core`, `deep`, `rem`, `unspecified`
- Non-sleep stages: `awake`, `inBed`
- Ignore awake periods shorter than 3 minutes.
- Start a new block when an awake period is at least 5 minutes.
- Awake periods from 3 minutes to less than 5 minutes should remain visible as wake noise, but should not split the continuity block.

### Interpretation Bands

| Longest block | Category | User-facing interpretation |
| --- | --- | --- |
| `> 5h` | Exceptional continuity | Your body maintained an exceptional uninterrupted recovery stretch. |
| `4-5h` | Strong continuity | Your body maintained one strong recovery period. |
| `3-4h` | Good continuity | Your body maintained one solid recovery period before interruptions. |
| `2-3h` | Moderately fragmented | Your sleep had moderate fragmentation overnight. |
| `< 2h` | Highly fragmented | Your recovery was highly fragmented overnight. |
| No usable sleep stages | Unavailable | Not enough sleep-stage data to calculate continuity. |

### Example 1

Input:

```text
11:00-2:50 sleep
2:50-2:57 awake
2:57-4:20 sleep
4:20-4:25 awake
4:25-6:45 sleep
```

Blocks:

```text
Block 1 = 3h50m
Block 2 = 1h23m
Block 3 = 2h20m
```

Result:

```text
Longest restorative block = 3h50m
Category = Good continuity
```

### Example 2

Input:

```text
12:00-1:40 sleep
1:40-1:45 awake
1:45-3:10 sleep
3:10-3:15 awake
3:15-5:10 sleep
5:10-5:20 awake
5:20-7:00 sleep
```

Blocks:

```text
Block 1 = 1h40m
Block 2 = 1h25m
Block 3 = 1h55m
Block 4 = 1h40m
```

Result:

```text
Longest restorative block = 1h55m
Category = Highly fragmented
```

## Current Architecture Findings

Relevant files:

- `Better/Core/Repositories/HealthKitRepository.swift`
  - Fetches `HKCategorySample` values for Apple HealthKit sleep analysis.
  - `fetchSleepSamples(from:to:)` returns raw HealthKit samples.
  - `fetchSleepSessions(from:to:)` is a convenience wrapper.
- `Better/Core/Services/SyncCoordinator.swift`
  - Production sync path fetches HealthKit samples and calls `SleepDataProcessor.process(samples:)`.
- `Better/Core/Processors/SleepDataProcessor.swift`
  - Converts HealthKit sleep samples into `SleepSession`.
  - Resolves overlaps using stage/source priority.
  - Splits full sleep sessions on gaps greater than 30 minutes.
  - Computes stage durations, WASO, latency, efficiency, and sleep score.
- `Better/Core/Models/SleepModels.swift`
  - Defines `SleepStageType`, `SleepStage`, `SleepSession`, `SleepBaseline`.
- `Better/Core/Persistence/PersistenceModels.swift`
  - `StoredSleepSession` already persists encrypted `stagesData`.
  - No persistence schema migration is needed if LRB is derived from `session.stages`.
- `Better/Features/Sleep/SleepTabView.swift`
  - Main sleep dashboard.
  - Restorative sleep amount is currently calculated in UI as `session.deepDuration + session.remDuration`.
- `Better/Features/Sleep/SleepHypnogramView.swift`
  - Existing stage timeline visualization.
- `Better/Features/Trends/TrendsViewModel.swift`
  - Existing trend metric registry.
- `Better/Core/Models/ResearchAnalysisModels.swift`
  - Defines `NightlyResearchRow`.
- `Better/Core/Services/ResearchAnalysisService.swift`
  - Builds nightly export rows from sessions, adherence, activity, context, and baseline.
- `Better/Core/Services/ResearchCSVExporter.swift`
  - Writes `nightly_research_rows.csv`, `protocol_effect_summary.csv`, and `export_metadata.csv`.

## Apple HealthKit Constraints To Respect

Sources checked on 2026-05-18:

- Apple Developer Documentation: `HKCategoryTypeIdentifierSleepAnalysis`
- Apple Developer Documentation: `HKCategoryValueSleepAnalysis`
- Apple Health PDF: `Estimating Sleep Stages from Apple Watch`, October 2025

Important constraints:

- Sleep data arrives as `HKCategorySample`, not quantity samples.
- Sleep stage values include `inBed`, `awake`, `asleepUnspecified`, `asleepCore`, `asleepDeep`, and `asleepREM`.
- `inBed` samples may overlap detailed sleep stage samples.
- Apple notes that detailed samples may not exist for the full beginning or ending of an in-bed sample.
- Apple Watch sleep staging is epoch-like and may create short awake intervals that should not be treated as true fragmentation.
- Third-party or manual sources may create overlapping, duplicate, or lower-resolution records.

The app already handles part of this through `SleepDataProcessor.cleanedIntervals(from:)`, source priority, and data quality flags. The LRB calculator should operate after that cleanup on `SleepSession.stages`.

## Proposed Data Model

Add to `Better/Core/Models/SleepModels.swift` or a new dedicated file:

```swift
nonisolated enum SleepContinuityCategory: String, Codable, CaseIterable, Hashable, Sendable, Identifiable {
    case unavailable
    case exceptional
    case strong
    case good
    case moderatelyFragmented
    case highlyFragmented

    var id: String { rawValue }
}
```

```swift
nonisolated struct SleepContinuityBlock: Codable, Hashable, Sendable, Identifiable {
    var id: UUID
    var index: Int
    var startDate: Date
    var endDate: Date
    var sleepDuration: TimeInterval
    var includedShortAwakeDuration: TimeInterval
    var shortAwakeningCount: Int
}
```

```swift
nonisolated struct SleepContinuitySummary: Codable, Hashable, Sendable {
    var blocks: [SleepContinuityBlock]
    var longestBlockDuration: TimeInterval
    var longestBlockIndex: Int?
    var meaningfulAwakeningCount: Int
    var continuityCategory: SleepContinuityCategory
}
```

Add convenience accessors:

```swift
extension SleepSession {
    var restorativeSleepDuration: TimeInterval {
        deepDuration + remDuration
    }

    var continuitySummary: SleepContinuitySummary {
        SleepContinuityCalculator.summary(for: stages)
    }
}
```

Do not store these fields on `StoredSleepSession` initially. They are deterministic derived values from already persisted `stagesData`.

## Calculator Design

Create:

```text
Better/Core/Processors/SleepContinuityCalculator.swift
```

Suggested constants:

```swift
enum SleepContinuityCalculator {
    static let ignoredAwakeThreshold: TimeInterval = 180
    static let meaningfulAwakeThreshold: TimeInterval = 300
}
```

Algorithm:

1. Sort stages by `startDate`, then `endDate`.
2. Drop invalid stages where `endDate <= startDate`.
3. Ignore `.inBed` for block construction.
4. Start a block at the first sleep stage.
5. Continue the current block for sleep stages.
6. When `.awake` is encountered:
   - `< 180s`: ignore; do not count; do not split.
   - `180s..<300s`: count as short wake noise inside the block; do not split.
   - `>=300s`: close current block at awake start, increment meaningful awakening count, start the next block at the next sleep stage.
7. Close the final block at the last sleep stage end.
8. Calculate `sleepDuration` per block as the sum of sleep-stage durations inside the block, not including awake duration.
9. Longest block is the block with max `sleepDuration`.

Design note:

Use `sleepDuration` for the metric. Keep `startDate` and `endDate` for visualization. This avoids inflating LRB when a 3-4 minute short wake event is tolerated inside a continuous block.

## HealthKit Edge Cases And Expected Behavior

| Edge case | Risk | Expected behavior |
| --- | --- | --- |
| Overlapping `inBed` and stage samples | Double counting | Ignore `inBed` for LRB; use cleaned `SleepSession.stages`. |
| Detailed stages do not cover full in-bed window | False long or short block | Only build blocks from sleep-stage samples. Do not infer sleep from `inBed`. |
| Only `asleepUnspecified` data | Missing REM/deep but valid continuity | Include `.unspecified` as sleep for continuity. LRB can still be calculated. |
| `inBedOnly` session | No real sleep stages | Return empty blocks, LRB `0`, category `unavailable`, and show "Not enough stage data". |
| Awake before first sleep | Latency, not fragmentation | Do not count as LRB split. Sleep latency remains separate. |
| Awake after final sleep | Morning wake, not fragmentation | Do not create empty trailing block. |
| Awake exactly 3 minutes | Wearable noise threshold | Count as short wake noise, do not split. |
| Awake exactly 5 minutes | Meaningful interruption | Split. |
| Multiple short awake events close together | Artificial continuity inflation | If contiguous/adjacent awake intervals combine to at least 5 minutes after cleanup, split. Verify cleaned intervals merge adjacent awake stages. |
| Gaps between stage samples with no explicit awake | Missing HealthKit data | If gap is under 5 minutes, bridge. If gap is 5 minutes or more, treat as unknown interruption only if no sleep stage covers it; flag in tests. |
| Duplicate samples from Apple Watch and iPhone | Conflicting stages | Rely on existing `SleepDataProcessor` source priority before LRB calculation. |
| Manual entries | Low fidelity | LRB can be calculated if stages exist; otherwise show unavailable. |
| Multiple sessions in one night | Naps or split sleep | Existing processor creates separate `SleepSession`s on 30-minute gaps. Calculate LRB per stored session. |
| DST transition | Duration errors | Always use `Date.timeIntervalSince`, never wall-clock subtraction. |
| Travel/time zone changes | Date grouping ambiguity | Use existing `SleepDateKey` session grouping; do not re-key inside calculator. |
| Negative/zero duration samples | Bad data | Drop invalid intervals. |
| Stage order not sorted | Wrong block boundaries | Sort before calculation. |
| Very short sleep session | Noise | Existing `minimumSleepDuration` filters sessions under 5 minutes. Calculator still handles empty/short inputs safely. |

## SwiftUI UI Plan

Skill guidance used: `build-ios-apps:swiftui-ui-patterns`.

Relevant patterns:

- Keep the calculator outside `body`.
- Use small focused subviews.
- Use stable identity for `ForEach`.
- Add deterministic `#Preview` fixtures.
- Keep UI state local; the block chart is pure input-driven and does not need a view model.

### Sleep Dashboard Placement

In `SleepTabView.sessionContent(session:)`, add the new card after `stagesCard(session:)` and before latency/baseline cards.

Reason:

- The user sees the hypnogram first.
- LRB is a direct interpretation of that timeline.
- Latency and baseline comparison remain secondary.

### New View

Create:

```text
Better/Features/Sleep/SleepContinuityCardView.swift
```

Inputs:

```swift
struct SleepContinuityCardView: View {
    let summary: SleepContinuitySummary
    let restorativeSleepDuration: TimeInterval
}
```

Content:

- Header:
  - Icon: `waveform.path.ecg` or `rectangle.split.3x1`
  - Title: `Sleep continuity`
- Primary metric:
  - Label: `Longest restorative block`
  - Value: `3h 50m`
  - Category pill: `Good continuity`
- Secondary metric:
  - `Restorative sleep: 2h 05m`
  - This connects LRB to existing REM + deep.
- Block chart:
  - Horizontal scroll or fixed stack depending block count.
  - Each block row shows:
    - `Block 1`
    - duration
    - proportional bar width
  - Highlight longest block.
  - Use `BetterColors.stageDeep`, `BetterColors.stageREM`, `BetterColors.success`, and `BetterColors.cardSecondary`.
- Insight sentence:
  - Pick from interpretation table.

### Visual Layout

Use the existing `BetterHealthCard` style. Avoid nested cards.

Suggested layout:

```text
BetterHealthCard
  VStack
    HStack icon/title/category
    HStack metric/restorative total
    VStack block rows
    Text insight
```

### Accessibility

Add accessibility labels:

- Card: `Sleep continuity`
- Primary value: `Longest restorative block, 3 hours 50 minutes`
- Block rows: `Block 1, 3 hours 50 minutes`

### Preview Coverage

Add previews:

- `Fragmented`: four blocks, longest under 2 hours.
- `Strong`: one block over 4 hours.
- `Unavailable`: no blocks.

Use deterministic dates and no repository dependencies.

## Trends Plan

Update `Better/Features/Trends/TrendsViewModel.swift`.

Add:

```swift
case longestRestorativeBlock
```

Display:

- Label: `Longest Block`
- Unit: `hrs`
- Value: `session.continuitySummary.longestBlockDuration / 3_600`

Trend chart behavior:

- Include only sessions with non-empty continuity blocks.
- For `inBedOnly` or no stages, omit point or use nil depending existing trend model pattern.
- Tooltip should format as duration, like total sleep.

## CSV Export Plan

Update `NightlyResearchRow` with appended continuity fields:

```swift
var restorativeSleepHours: Double?
var longestRestorativeBlockHours: Double?
var longestRestorativeBlockMinutes: Double?
var sleepContinuityCategory: String?
var sleepBlockCount: Int
var meaningfulAwakeCount: Int
var sleepBlockDurationsMinutes: [Double]
var sleepBlockStartISO: [Date]
var sleepBlockEndISO: [Date]
```

Populate in `ResearchAnalysisService.buildNightlyRows(...)`:

```swift
let continuity = session.continuitySummary
let hasContinuity = !continuity.blocks.isEmpty
```

Append CSV columns at the end of `nightly_research_rows.csv`:

```text
restorative_sleep_hrs
longest_restorative_block_hrs
longest_restorative_block_min
sleep_continuity_category
sleep_block_count
meaningful_awake_count
sleep_block_durations_min
sleep_block_start_iso
sleep_block_end_iso
```

Encoding conventions:

- Numeric missing value: `NA`
- Empty arrays: empty string
- Arrays: pipe-delimited, matching existing export style
- Keep columns appended for backward compatibility

Bump:

```swift
ResearchExportPackage.schemaVersion = "2"
```

## Implementation Order

1. Add `SleepContinuityCategory`, `SleepContinuityBlock`, and `SleepContinuitySummary`.
2. Add `SleepContinuityCalculator`.
3. Add `SleepSession.restorativeSleepDuration` and `SleepSession.continuitySummary`.
4. Add unit tests for calculator edge cases.
5. Extend `NightlyResearchRow`.
6. Populate continuity fields in `ResearchAnalysisService`.
7. Append CSV columns in `ResearchCSVExporter`.
8. Add CSV/export tests.
9. Add `SleepContinuityCardView`.
10. Insert card into `SleepTabView`.
11. Add trend metric.
12. Run full tests and one simulator UI smoke pass.

## Test Plan

### Unit Tests

Create:

```text
BetterTests/SleepContinuityCalculatorTests.swift
```

Cases:

- Example 1 returns three blocks and longest `3h50m`.
- Example 2 returns four blocks and longest `1h55m`.
- Awake `2m59s` is ignored and does not split.
- Awake exactly `3m` does not split but increments short wake noise.
- Awake `4m59s` does not split.
- Awake exactly `5m` splits.
- Consecutive awake intervals that are cleaned/merged to `>=5m` split.
- Awake before first sleep does not count as meaningful interruption.
- Awake after final sleep does not create trailing block.
- `asleepUnspecified` counts as sleep.
- `inBed` does not count as sleep.
- Empty stages returns empty summary and zero duration.
- Unsorted stages still produce correct blocks.
- Zero/negative duration stages are ignored.
- DST crossing uses absolute intervals correctly.

### Export Tests

Update `BetterTests/ResearchAnalysisServiceTests.swift`:

- Nightly row includes restorative sleep hours.
- Nightly row includes longest block minutes.
- Block count and meaningful awake count are correct.
- In-bed-only session exports `NA` for LRB and `0` block count.

Add or update CSV exporter tests if a test file exists:

- Header includes appended continuity fields.
- Values are pipe-delimited for block arrays.
- Schema version is `2`.

### SwiftUI Verification

- `#Preview("Fragmented")` renders without repository dependencies.
- `#Preview("Strong")` renders with highlighted longest block.
- `#Preview("Unavailable")` shows a clear unavailable state.
- Dynamic Type does not clip the primary duration.
- Small screen width does not cause text overlap.
- Long block labels do not resize the bar layout.

### Simulator Smoke Test

Use Xcode or XcodeBuildMCP:

1. Build the app.
2. Run tests.
3. Launch simulator.
4. Verify Sleep tab loads.
5. Verify continuity card appears for preview/local data.
6. Verify Trends metric selector includes `Longest Block`.
7. Trigger export and inspect generated ZIP contents.

Commands:

```bash
xcodebuild -scheme Better -configuration Debug test
```

If using XcodeBuildMCP, first call `session_show_defaults`, then build/run with the configured scheme and simulator.

## Bug Risks And Mitigations

| Risk | Likely symptom | Mitigation |
| --- | --- | --- |
| LRB differs from Apple Health app | User distrust | Explain that LRB is a Better-specific continuity metric using explicit 5-minute interruption threshold. |
| Tiny Apple Watch awake samples fragment sleep | Too many short blocks | Ignore `<3m`; split only `>=5m`. |
| Missing detailed stage samples at session edges | LRB undercounts | Do not infer from `inBed`; show unavailable or lower confidence when stage data is incomplete. |
| In-bed-only data creates fake long block | False positive | Never count `.inBed` as sleep. |
| Short tolerated awake time inflates duration | LRB too high | Metric uses summed sleep duration inside block, not wall-clock block span. |
| CSV arrays become hard to parse | Research friction | Use pipe delimiter consistently and document in metadata if needed. |
| SwiftUI body recomputes summary repeatedly | Jank in Sleep tab | Compute once in local `let summary = session.continuitySummary` before passing to card, or keep calculator lightweight and pure. |
| Trends recomputes for many sessions | Jank in Insights | Calculate values once while building chart points in `TrendsViewModel`. |
| SwiftData migration from new stored fields | Store compatibility risk | Do not persist derived fields initially. |

## Acceptance Criteria

- LRB matches both product examples.
- Awake periods `<3m` do not fragment the metric.
- Awake periods `>=5m` split blocks.
- Sleep tab shows a polished continuity card with block visualization.
- Trends can chart LRB over time.
- CSV export includes continuity fields in `nightly_research_rows.csv`.
- Existing export files still generate.
- No SwiftData schema migration is required.
- Unit tests cover HealthKit-specific edge cases.
- Full test suite passes.

## Future Enhancements

- Add a per-user threshold setting if data shows 5 minutes is too strict or too loose.
- Add baseline comparison for LRB once enough nights exist.
- Add confidence label based on data quality:
  - High: detailed stages
  - Medium: unspecified sleep stages
  - Low/unavailable: in-bed-only or sparse stage coverage
- Overlay block boundaries directly on `SleepHypnogramView`.
- Add a research CSV metadata row documenting continuity thresholds.
