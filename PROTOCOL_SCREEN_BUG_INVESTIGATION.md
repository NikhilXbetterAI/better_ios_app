# Protocol Screen Bug Investigation

Date: 2026-05-23

Scope: investigation, fix plan, and implementation tracking for the Protocol screen bugs.

## Fix Plan

1. Separate percentage-point deltas from relative-percent improvement in the display layer.
2. Reject or omit implausible restorative-percent values before they enter baselines, rollups, charts, or rankings.
3. Make baseline readiness copy explain the 90-day pre-protocol window and qualifying staged-sleep count.
4. Sanitize metric values before SwiftUI chart/bar layout to prevent crashes from `NaN`, `infinity`, or negative values.
5. Remove unused relative-percent helper fields that could be wired into UI incorrectly later.
6. Add regression tests for the 14-night Protocol baseline threshold, readiness counts, `pp` display semantics, and impossible 100% restorative percentages.

## Implemented Fixes In This Pass

- Added `ProtocolFormulaMetric.deltaUnit`, with restorative percent deltas displayed as `pp`.
- Updated Home, All Metrics, Impact Detail, Version Dive, and shared comparison strips to use delta units for deltas.
- Changed Home copy from generic baseline-building text to 90-day pre-protocol staged-sleep readiness copy.
- Extended `ProtocolBaselineReadiness` with total cached, qualifying, and excluded candidate-night counts.
- Added finite/non-negative sanitization before Protocol metric bars, sparklines, charts, StageBar, snapshots, and baseline aggregation.
- Rejected implausible restorative percentages above `70%` as suspect source/denominator data.
- Removed unused `deepPctVsBaseline`/relative-lift fields from Home view model.
- Updated `ProtocolFormulaTrackingTests` for the 14-night threshold, readiness counts, `pp` delta unit, and impossible 100% restorative-percent rejection.

## User-Reported Bugs

1. Protocol impact UI shows a `100% improvement` style result that is not credible.
2. Baseline appears to be calculated from only 6 nights. Baseline should prioritize the last 90 days and use a flexible fallback, not treat 6 nights as meaningful.
3. Protocol page crashed while investigating the bad impact data. Audit likely crash paths in the Protocol screen.

## Current Implementation References

- Spec/reference doc: `PROTOCOL_FORMULA_FUNCTIONS.html`
- Repo guidance: `CLAUDE.md`
- Baseline generation: `Better/Core/Services/ProtocolBaselineService.swift`
- Impact aggregation: `Better/Core/Services/ProtocolFormulaAnalysisService.swift`
- Home screen view model: `Better/Features/ProtocolFormula/Home/ProtocolFormulaHomeViewModel.swift`
- Metric display atoms: `Better/Features/ProtocolFormula/Components/ProtocolFormulaAtoms.swift`
- Impact detail sheet: `Better/Features/ProtocolFormula/Home/ImpactMetricDetailSheet.swift`
- All metrics screen: `Better/Features/ProtocolFormula/AllMetrics/ProtocolAllMetricsView.swift`
- Timeline screen: `Better/Features/ProtocolFormula/Timeline/ProtocolTimelineView.swift`

## Key Findings

### P0: Percent Delta Is Displayed Ambiguously As Percent Improvement

Evidence:

- `ProtocolMetricComparisonStrip` computes `delta = yourValue - baselineValue`.
- `DeltaBadge` renders that numeric delta with `metric.unit`.
- For `restorativePct`, `metric.unit == "%"`, so a percentage-point difference is shown as a percent value.
- `ImpactMetricDetailSheet.improvedText` then says this delta is `better` or `worse` than baseline.

Why this can produce misleading UI:

- If baseline restorative percent is `20%` and protocol average is `40%`, the real absolute delta is `+20 percentage points`.
- The relative improvement is `+100%` because `(40 - 20) / 20 = 100%`.
- The current UI does not consistently distinguish:
  - absolute metric value: `40% restorative`
  - absolute delta: `+20 percentage points`
  - relative lift: `+100% relative to baseline`
- This can make the screen look like it is claiming a `100% improvement` even when the safest interpretation should be `+20 pp vs baseline`, observed not causal.

Likely affected call sites:

- Home impact grid through `ProtocolMetricComparisonStrip`.
- Home hero baseline pill for `restorativePct`.
- All Metrics best formula card and chart inspector.
- Impact detail sheet delta badge and narrative.

Later fix plan:

1. Add a metric display layer that distinguishes `valueUnit`, `absoluteDeltaUnit`, and `relativeLiftUnit`.
2. Render restorative percent deltas as `+X.X pp vs baseline`, not `+X.X%`, unless explicitly showing relative lift.
3. If relative lift is shown, label it as `relative lift` and show the math in detail view.
4. Add tests for `20 -> 40` rendering as `+20.0 pp`, not an unqualified `+100% improvement`.

### P0: Restorative Percent Can Reach 100% From Questionable Denominators

Evidence:

- `ProtocolFormulaMetricMath.restorativePctOfInBed` calculates `restorativeSleepDuration / denominator * 100`.
- The denominator is `max(totalInBedTime, totalSleepTime + awakeDuration)`.
- It only rejects denominator values below restorative duration.
- It does not cap the returned percent at `100`, validate realistic stage composition, or flag sessions where the denominator has been repaired.

Why this matters:

- A HealthKit/session parsing issue where `totalInBedTime` and stage-derived in-bed time equal restorative duration can produce `100%`.
- That value can then be used in baseline, rollups, trend charts, and best-version ranking.
- Even if mathematically bounded, `100% restorative sleep` is clinically implausible for real sleep and should be treated as suspicious data quality.

Later fix plan:

1. Add instrumentation that logs numerator, raw denominator, stage-derived denominator, data source, and sleep date for any restorative percent above a sanity threshold such as `70%`.
2. Add a data-quality guard for implausible stage compositions.
3. Decide product behavior for suspicious nights: exclude from protocol impact, show as low-confidence, or include but flag.
4. Add tests for malformed sessions where denominator equals restorative duration.

### P0: Baseline UX Is Confusing Around 6 Qualifying Nights

Evidence:

- `ProtocolBaselineService.windowDays == 90`.
- `ProtocolBaselineService.maxNights == 30`.
- `ProtocolBaselineService.minimumPersistedNightCount == 14`.
- Candidate sessions are filtered to `.detailedStages` or `.mixedSources`, then `sleepDateKey < cutoffKey`, sorted newest first, and capped to 30.
- When fewer than 14 qualifying nights exist, `freezeBaseline` returns `nil`; `readiness` can report values like `6/14`.

Interpretation:

- The code does use a 90-day candidate window.
- The reported `6 nights` likely means only 6 qualifying detailed/mixed sleep-stage sessions were found before the first protocol date, not that the window is 6 days.
- However, the user-facing result is still wrong if the screen makes 6 nights look like a calculated baseline or uses impact cards alongside that state.

Later fix plan:

1. Change the baseline readiness model to expose:
   - candidate window start/end
   - total cached nights in window
   - qualifying detailed/mixed nights
   - excluded partial/no-data nights
   - required minimum
2. Update UI copy from generic `Baseline building: 6/14 qualifying nights` to a clearer message:
   - `Found 6 qualifying staged-sleep nights in the 90-day pre-protocol window. Need 14 before impact is calculated.`
3. Add a flexible fallback policy only after product decision:
   - preferred: 90-day window, up to 30 qualifying nights
   - acceptable fallback: 60-day or 30-day if enough valid nights exist
   - never acceptable: compute impact from 6 nights without a low-confidence block
4. Add regression tests for 6, 13, 14, 30, and 90-day candidate windows.

### P1: Frozen Baseline May Not Recover After More Historical Data Arrives

Evidence:

- A valid frozen baseline is reused if `existing.isInsufficient == false`.
- Protocol baseline snapshots are intentionally frozen and not recomputed.
- `force` exists but normal home refresh does not use it.

Risk:

- If a baseline was frozen with the minimum 14 nights, later HealthKit sync may add more pre-protocol history, but the baseline remains from the original subset.
- This preserves the frozen-baseline invariant, but conflicts with the current product expectation to prioritize the strongest 90-day baseline.

Later fix plan:

1. Decide whether Protocol baseline should be truly immutable or upgradeable until first impact is shown.
2. If upgradeable, add explicit versioning/audit metadata:
   - original frozen snapshot
   - upgraded snapshot
   - reason: `more pre-protocol HealthKit history available`
3. Never silently replace baseline after user-facing impact has been shown without surfacing provenance.

### P1: Last-Night Delta Helpers Compute Relative Percent But UI Mostly Uses Absolute Deltas

Evidence:

- `lastNightVsBaselineDeltas` computes both minute deltas and `PctVsBaseline` relative deltas.
- The home metric tiles pass only minute deltas to `ProtocolMetricComparisonStrip`.
- The relative percent fields appear unused or partially orphaned.

Risk:

- Future UI changes could accidentally wire `deepPctVsBaseline` or similar into `DeltaBadge` and create another `100% improvement` style bug.

Later fix plan:

1. Remove unused relative-percent fields, or wrap them in a type named `RelativeLiftPercent`.
2. Avoid raw `Double` for display-critical deltas.
3. Add tests that prevent relative-lift values from being rendered as absolute metric deltas.

## Crash Investigation Findings

### P0: Width Calculations Can Receive Invalid Values From Bad Metric Data

Evidence:

- `ProtocolMetricComparisonStrip` computes bar width with:
  - `(value ?? 0) / scaleMax`
  - `CGFloat(...)`
  - `.frame(width: max(4, ...))`
- If `yourValue`, `baselineValue`, or their derived scale is `NaN`, `infinity`, negative, or otherwise malformed, SwiftUI layout can become unstable.
- Similar chart code exists in All Metrics, Version Dive, and the restore sparkline.

Likely trigger:

- Bad HealthKit-derived values or corrupted persisted metric JSON.
- A malformed baseline with impossible values.
- Negative or non-finite durations entering chart or bar layout.

Later fix plan:

1. Add a `FiniteMetricValue` or sanitizer layer before UI rendering.
2. Clamp chart/bar values to finite non-negative ranges.
3. Log and omit non-finite or impossible values instead of rendering them.
4. Add unit tests for `NaN`, `infinity`, negative minutes, and `restorativePct > 100`.

### P1: Static UUID Precondition Is A Deliberate Crash Site

Evidence:

- `ProtocolFormulaCatalog.staticUUID` uses `preconditionFailure` for invalid catalog UUID literals.

Risk:

- Low runtime likelihood because literals are currently hardcoded and valid.
- Still worth tracking as an intentional launch-crash path in Protocol Formula code.

Later fix plan:

1. Keep if the team accepts fail-fast behavior for invalid static catalog data.
2. Otherwise convert to non-crashing validation in debug/test and safe omission in production.

### P1: Silent Decode Dropping Can Hide Data Corruption Before UI Fails Later

Evidence:

- Repository fetches often use `compactMap { try? $0.toDomain() }`.
- This prevents direct crashes on bad persisted rows but can silently remove sessions, logs, or baselines from calculations.

Risk:

- The UI may show low-data or strange impact values without explaining that data was dropped.
- A partial data set can make baseline counts look unexpectedly low.

Later fix plan:

1. Add repository-level corruption diagnostics.
2. Surface a non-blocking data repair message when records are skipped.
3. Add inventory counters for skipped/decode-failed Protocol records.

## Debug Plan Before Fixing

1. Reproduce on the same user data set, ideally on device/simulator with logs enabled for `subsystem=Better category=ProtocolFormula`.
2. Capture a Protocol Formula diagnostic snapshot:
   - active version ID and label
   - first protocol date/cutoff key
   - cached session count in 90-day pre-protocol window
   - qualifying detailed/mixed count
   - baseline snapshot values
   - impact rollup values per version
   - top 10 suspicious nights by restorative percent
3. Verify if the `100%` value is:
   - a real absolute restorative percent
   - an absolute delta mislabeled as percent improvement
   - a relative lift calculation
   - a corrupt denominator/data-quality issue
4. Verify baseline `6 nights` by comparing:
   - all cached sessions in window
   - sessions excluded by data quality
   - sessions excluded by cutoff date
   - sessions excluded because not cached due to retention/sync
5. Reproduce crash with the same navigation path:
   - Protocol Home
   - impact detail sheet
   - All Metrics chart
   - Timeline
   - Version Dive
6. Keep targeted regression tests covering:
   - baseline does not persist below threshold
   - readiness reports candidate counts correctly
   - impact UI does not show unqualified `%` for percentage-point deltas
   - restorative percent rejects implausible denominator cases
   - UI metric sanitization handles non-finite values

## Verification Blocker

Attempted command:

```bash
xcodebuild -scheme Better -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 16' test -only-testing:BetterTests/ProtocolFormulaTrackingTests
```

Result:

```text
xcode-select: error: tool 'xcodebuild' requires Xcode, but active developer directory '/Library/Developer/CommandLineTools' is a command line tools instance
```

To verify this fix locally, switch the active developer directory to Xcode and run:

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
xcodebuild -scheme Better -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 16' test -only-testing:BetterTests/ProtocolFormulaTrackingTests
```

## Remaining Follow-Up

1. Add a user/exportable Protocol Formula diagnostics snapshot so bad HealthKit-derived inputs can be inspected without attaching a debugger.
2. Decide whether Protocol baselines should remain immutable forever or be upgradeable until first user-facing impact is shown.
3. Decide whether the `70%` restorative-percent sanity threshold should be product-configurable after reviewing real user data.
4. Run the targeted Xcode test command above after selecting Xcode.
