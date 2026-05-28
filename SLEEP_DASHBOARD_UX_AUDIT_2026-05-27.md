# Sleep Dashboard UX Audit - 27 May 2026

## Overall Verdict

**Needs refinement.**

The app has a strong dark-mode visual direction and the sleep score is visible within 3 seconds, but the dashboard is not yet production-test ready without targeted cleanup. The biggest risks are unclear health language, chart comprehension, over-dense visual treatment, hidden tap affordances, and the floating bottom navigation covering real content. A user can tell "I scored 68" quickly, but they will struggle to understand why, what to trust, what changed, and what to do next.

Screens reviewed:

- `/Users/nikhilkhatale/Downloads/WhatsApp Image 2026-05-27 at 11.11.24.jpeg`
- `/Users/nikhilkhatale/Downloads/WhatsApp Image 2026-05-27 at 11.11.24 (1).jpeg`
- `/Users/nikhilkhatale/Downloads/WhatsApp Image 2026-05-27 at 11.11.25.jpeg`
- `/Users/nikhilkhatale/Downloads/WhatsApp Image 2026-05-27 at 11.11.25 (1).jpeg`

Likely implementation files:

- `Better/Features/Sleep/SleepTabView.swift`
- `Better/Features/Sleep/SleepStagesCard.swift`
- `Better/Features/Sleep/SleepHypnogramView.swift`
- `Better/Features/Sleep/LongestSleepBlockCard.swift`
- `Better/Features/Sleep/SleepQualityRingView.swift`
- `Better/Core/DesignSystem/BetterTypography.swift`
- `Better/Core/DesignSystem/BetterColors.swift`

## Top 10 UX And Design Flaws

### 1. Floating bottom navigation blocks important content

**Problem:** The bottom nav overlaps the Sleep Stages chart in screenshot 2 and covers the lower biomarker card in screenshot 4. The "Longest uninterrupted sleep" card is also partially hidden in screenshot 1.

**Why it matters:** Users lose access to information at the exact point they are scrolling through dense health data. It also makes the app feel fragile and prototype-level because content appears to slide underneath controls without enough safe area.

**Specific fix:** Add a bottom safe-area spacer that equals the tab bar height plus 24-32 px. Anchor the tab bar outside scroll content, not visually on top of unread content. Test on iPhone SE, regular, and Pro Max heights. In `SleepTabView.swift`, replace the current `Spacer(minLength: 140)` guess with a measured `safeAreaInset(edge: .bottom)` or a shared tab bar height token.

**Priority:** Critical

### 2. Sleep score is prominent, but the reason for the score is not legible enough

**Problem:** The large "68 FAIR" is clear, but the explanation below is crammed into a pill and truncates: "Aim withi..." in screenshot 2. The visible summary says timing was late, but does not clearly explain the major score drivers.

**Why it matters:** Users will ask, "Why did I get 68?" If the answer is truncated or hidden behind a long-press, the score feels arbitrary and trust drops.

**Specific fix:** Directly under the score, show a 2-3 item score breakdown: `Duration 7h 20m`, `Timing +2h 37m late`, `Continuity 1 long stretch`. Make "Why 68?" an explicit tap target, not a long-press-only interaction. Keep the insight to two lines max and never truncate action text.

**Priority:** Critical

### 3. Health and sleep jargon appears before user education

**Problem:** Terms such as "Fair", "body clock", "usual range", "sleep stretch", "sync pending", "sleep stages estimated", "30n/30D", and "Coverage" appear without context. Screenshot 4 shows "1 sleep stretch"; screenshot 3 shows "Coverage 30/30"; screenshot 2 shows "sync pending".

**Why it matters:** Normal users do not know whether these are good, bad, incomplete, or technical states. "Sync pending" can sound like data is unreliable, while "sleep stages estimated" sounds like a warning but is styled like metadata.

**Specific fix:** Replace ambiguous text with plain language:

- `Fair` -> `Fair - timing lowered your score`
- `usual range` -> `your normal 30-night range`
- `sleep stretch` -> `uninterrupted sleep block`
- `sync pending` -> `latest device sync still finishing`
- `Coverage 30/30` -> `30 of 30 nights with data`
- `30D` -> `30 days`

Add info buttons for score label, estimated stages, usual range, and biomarker confidence.

**Priority:** High

### 4. Sleep Stages section is visually dense and hard to decode

**Problem:** The hypnogram has four bright stage colors, vertical connectors, grid lines, stage blocks, axis labels, bottom times, a stacked percentage bar, delta chips, and four tappable legend cards. In screenshot 1 the chart is striking but visually busy.

**Why it matters:** Sleep stages are already difficult for users to interpret. The current design asks users to decode too many chart systems at once.

**Specific fix:** Make the default Sleep Stages card answer one question first: "How was my night distributed?" Keep the hypnogram, then simplify the distribution bar to one compact legend row: `Awake 1m`, `Light 4h 9m`, `Deep 1h 9m`, `REM 2h`. Move baseline deltas (`+36m`, `+19m`) into the detail sheet or a collapsed "vs usual" row. Reduce chart glow/shadows and show a small "Tap chart to scrub" hint only if first-time.

**Priority:** High

### 5. Biomarker cards mix status, value, trend, and navigation into one crowded row

**Problem:** In screenshot 4, each biomarker row contains icon, name, micro range bar, current value, unit, gray dot, "30n", and chevron. The respiratory row truncates "usua..." and "in ra...".

**Why it matters:** Biomarkers are high-trust health data. Truncation and overloaded rows make the data feel less reliable and create accessibility failures.

**Specific fix:** Use a two-line row pattern:

Line 1: `Blood oxygen` + `98%` + status pill `In normal range`.

Line 2: `Your usual: 97%` + mini range bar or `30 nights`.

Remove the gray dot unless it has a clear meaning. Replace `30n` with `30 nights`. Increase row height enough to prevent truncation.

**Priority:** High

### 6. Tappable affordances are inconsistent and partly hidden

**Problem:** Some cards have chevrons, some rows are tappable without obvious affordance, the score breakdown is activated by long-press, and the date selector uses a small chevron. Screenshot 3 uses a modal with `Done`, but dashboard cards do not consistently signal tap behavior.

**Why it matters:** Users will miss detail screens and assume charts are static. Long-press is especially low-discoverability for a core explanation like score details.

**Specific fix:** Use consistent affordances:

- Explicit button: `Why this score?`
- Chevron only for navigational rows.
- Scrubbable charts should show a subtle first-use callout or visible selected point.
- Cards that expand should have `Show details` or a chevron state.
- Keep minimum tap targets at 44 x 44 pt.

**Priority:** High

### 7. Color carries too much meaning without enough non-color support

**Problem:** Sleep stages and biomarker statuses depend heavily on color. Light sleep blue and REM cyan are close. Brand purple, blue, cyan, orange, green, pink, and teal all compete on the same screen.

**Why it matters:** Color-blind users and low-vision users may not distinguish stage categories. Even users with normal vision may see the screen as noisy rather than informative.

**Specific fix:** Add non-color encoding: labels inside stage segments when space allows, distinct symbols or patterns in accessibility/differentiate-without-color mode, and text status next to biomarker values. Reduce the active palette per screen: sleep stages use stage colors, biomarkers use semantic status colors, not both at full saturation everywhere.

**Priority:** High

### 8. Visual hierarchy is weakened by too many high-emphasis surfaces

**Problem:** The hero gauge, glowing insight pill, metric cards, chart colors, bright stacked bar, biomarker icons, green continuity number, and floating nav all compete. Card corner radius and border/glow treatment vary between sections.

**Why it matters:** On a health dashboard, users need quick prioritization: score first, reason second, details third. Too many bright treatments flatten the hierarchy.

**Specific fix:** Establish three elevation levels:

- Level 1: hero score and one primary insight.
- Level 2: key metrics and abnormal biomarkers.
- Level 3: detailed charts, history, and education.

Normalize cards to one corner radius family, one border opacity, and limited glow. Reserve bright color for abnormal states or primary score, not every decorative accent.

**Priority:** Medium

### 9. Biomarker detail chart needs clearer axes, ranges, and confidence

**Problem:** Screenshot 3 shows a blood oxygen trend with colored bands, a line, a "Your usual 97.5" label, a selected point, stats, and a 7D/30D/60D switcher. It is polished, but users cannot quickly tell what the colored bands mean or whether 96% on 20 May is concerning.

**Why it matters:** Biomarker trends can create anxiety if the app does not explain normal variation and data confidence. A 1.2% difference is shown with precision but lacks confidence or sample quality context.

**Specific fix:** Add explicit axis labels and a concise chart legend: `Normal personal range`, `Tonight`, `Your 30-day average`. Rename `Best` for SpO2 to `Highest` to avoid moralizing health data. Add a confidence label: `High confidence - 30 of 30 nights with data` or `Limited data`.

**Priority:** Medium

### 10. Missing and partial states are not visible enough for production testing

**Problem:** The reviewed screens show some handling for baseline building, sync pending, and partial score, but production-critical states are not visible in the UI hierarchy: no device connected, Health permissions denied, sync failed, partial stages, missing biomarkers, first-night user, abnormal biomarker, and stale data.

**Why it matters:** User testing will include incomplete data. If these states are hidden, testers will hit confusing dashboards and attribute the problem to the product.

**Specific fix:** Define explicit empty/loading/error/partial states for:

- No wearable connected.
- Health permission denied.
- Sync failed or stale data.
- No sleep stages, only in-bed time.
- Biomarkers missing for one or more metrics.
- Baseline not ready.
- Abnormal biomarker requiring cautious language.

Each state should say what is missing, why it matters, and what the user can do.

**Priority:** Critical

## 5 Quick Wins

1. Add bottom scroll padding or `safeAreaInset` so the floating nav never covers Sleep Stages, Longest uninterrupted sleep, or Biomarkers.
2. Replace all abbreviated labels: `30n` -> `30 nights`, `30D` -> `30 days`, `br/min` -> `breaths/min`, `Coverage 30/30` -> `30 of 30 nights`.
3. Make `Score details` visible as a normal tap target under the score; remove long-press as the only path.
4. Stop truncating biomarker row text by increasing row height and moving "usual / in range" to a second line.
5. Rewrite the sync/source line into user language: `Zepp data - sleep stages estimated - latest sync finishing`.

## 5 Deeper Improvements For Production Quality

1. Create a health-data confidence system. Every major metric should have a confidence state: `Complete`, `Estimated`, `Partial`, `Stale`, or `Missing`.
2. Redesign the dashboard around "score, reason, action" before charts. Users should know what happened and what to do before seeing detailed stage timelines.
3. Build a consistent chart grammar across sleep stages and biomarkers: same time-window controls, same selected-point behavior, same legend placement, same baseline language.
4. Add a biomarker education and safety layer. Explain that sleep and biomarker data are estimates, not diagnosis, and give "seek medical advice" language only for repeated abnormal patterns.
5. Add accessibility QA gates: Dynamic Type up to at least Accessibility Medium, differentiate-without-color mode, VoiceOver labels for charts, contrast checks, and one-handed reach testing.

## Main Sleep Dashboard: Recommended Screen-Level UX Hierarchy

### First: Immediate Night Summary

Show this in the first viewport:

- Date selector: `27 May 2026`
- Sleep score: `68`
- Score label with reason: `Fair - timing lowered your score`
- Sleep duration: `7h 20m`
- Bedtime and wake time: `3:22 AM - 11:05 AM`
- Data confidence: `Zepp data - stages estimated - sync finishing`

Do not put detailed charts above this. The first screen should answer: "How did I sleep, and can I trust this data?"

### Second: Why The Score Changed

Show a compact breakdown directly below the hero:

- `Duration: good`
- `Timing: 2h 37m later than body clock`
- `Continuity: 1 uninterrupted block`
- Primary recommendation: `Try moving bedtime 30 minutes earlier tonight.`

This should replace the truncated pill and hidden score explanation.

### Third: Sleep Stages Summary

Show:

- One simplified hypnogram.
- Four stage totals: Awake, Light, Deep, REM.
- Optional `vs your usual` row if baseline exists.

Hide detailed trend charts, stage education, and baseline deltas behind taps on each stage.

### Fourth: Continuity

Show:

- `Longest uninterrupted sleep block: 7h 20m`
- `1 block, 0 meaningful wake-ups`
- One plain-language interpretation.

Use "block" instead of "sleep stretch" unless research proves users understand "stretch."

### Fifth: Biomarkers

Show only the status summary first:

- `Biomarkers: all in your normal range`
- Rows for RHR, HRV, SpO2, and respiratory rate.
- Each row should show current value, status, and baseline in plain text.

Hide detailed trend charts, 7/30/60 day controls, education, and coverage stats behind each biomarker row.

### Sixth: Trends And History

Keep multi-day trends behind the detail screens or an Insights tab. The main dashboard should not make users interpret 30-day charts before understanding last night.

## Fix Plan

### Phase 1 - Pre-Test Critical Cleanup

Target files:

- `Better/Features/Sleep/SleepTabView.swift`
- `Better/Features/Sleep/SleepStagesCard.swift`
- `Better/Features/Sleep/SleepHypnogramView.swift`

Actions:

- Fix bottom nav overlap with a measured bottom inset.
- Make score explanation visible and tappable.
- Replace ambiguous abbreviations and jargon.
- Prevent truncation in insight, source, and biomarker rows.
- Add clear partial/sync/stale copy.

Acceptance criteria:

- No content is hidden by the tab bar on small or large iPhones.
- A user can answer "why did I get this score?" from the first screen.
- No key label truncates at default text size.

### Phase 2 - Chart And Biomarker Comprehension

Target files:

- `Better/Features/Sleep/SleepStagesCard.swift`
- `Better/Features/Sleep/SleepHypnogramView.swift`
- biomarker detail components inside `Better/Features/Sleep/SleepTabView.swift`

Actions:

- Simplify the default Sleep Stages card.
- Move dense baseline deltas into detail views.
- Add plain chart legends and axis labels for biomarker trend screens.
- Replace `Best` with metric-specific labels such as `Lowest`, `Highest`, or `Best recovery signal`.
- Add confidence and coverage language in detail screens.

Acceptance criteria:

- A new user can identify Light, Deep, REM, and Awake without relying only on color.
- Biomarker detail explains whether a value is normal, unusual, missing, or low-confidence.

### Phase 3 - Production Health UX States

Target files:

- `Better/Features/Sleep/SleepDashboardViewModel.swift`
- `Better/Features/Sleep/SleepTabView.swift`
- `Better/Features/Sleep/HealthKitPermissionBannerView.swift`
- biomarker baseline/readiness models in `Better/Core/Models/BiomarkerBaseline.swift`

Actions:

- Define and design missing states for no device, permission denied, sync failed, partial data, missing stages, missing biomarkers, abnormal biomarker, and first-time user.
- Add responsible health language and disclaimers in metric detail screens.
- Add VoiceOver labels and accessibility values for charts and tappable rows.

Acceptance criteria:

- Every common data failure has a visible explanation and next action.
- The app avoids medical certainty and frames insights as estimates.
- Charts and status rows remain usable with VoiceOver and differentiate-without-color enabled.

