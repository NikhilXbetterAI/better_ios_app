# Cronotype Product Research and UI Improvement Plan

Last updated: 2026-05-28

## Executive Summary

Cronotype should not be shown as a personality label like "morning person" or "night owl" and then left there. For Better, it should become a daily sleep timing coach:

- What is my best sleep window?
- How far was my usual sleep from that window?
- When should I take Better Sleep Formula?
- What should I avoid tonight?
- What happened to my sleep score, restorative sleep, deep sleep, REM sleep, wake time, and duration when I slept inside the window?

The most useful user-facing idea is:

> Your body has a best time to sleep. Better compares that best window with when you actually slept, then shows what changed.

This is easier to understand than "chronotype," and it connects directly to Better's product: helping people sleep better with tracking, timing, and a sleep supplement sachet.

## What The Science Says

### 1. Chronotype is real, but the app should make it practical

Chronotype describes when a person's body naturally tends to sleep and feel alert across the day. Roenneberg's Munich Chronotype work uses sleep timing on workdays and free days to estimate chronotype, with correction for sleep debt on free days. The key finding for product design is that people differ widely in sleep timing, and late chronotypes often build sleep debt during workdays and compensate on free days.

Product implication:

- Do not only say "You are Intermediate."
- Say "Your best sleep window is 1:26 AM-7:56 AM."
- Then compare that with "You usually sleep 1:12 AM-8:28 AM."
- The label is secondary. The window and gap are the useful parts.

Source:

- [Life between Clocks: Daily Temporal Patterns of Human Chronotypes](https://journals.sagepub.com/doi/10.1177/0748730402239679)

### 2. Sleep timing and regularity matter beyond sleep duration

The National Sleep Foundation consensus statement concluded that consistency of sleep onset and wake timing is important for health, safety, and performance. The panel reviewed sleep timing variability and found support for regular schedules across outcomes such as alertness, metabolic health, cardiovascular health, inflammation, mental health, and performance.

Product implication:

- The Cronotype tab should not only optimize "how long did you sleep?"
- It should explain "how close was your sleep timing to your body clock?"
- The primary score should be an alignment score or gap, not a dense scientific explanation.

Sources:

- [The importance of sleep regularity: a consensus statement of the National Sleep Foundation sleep timing and variability panel](https://www.sciencedirect.com/science/article/pii/S2352721823001663)
- [National Sleep Foundation sleep timing guideline summary](https://www.thensf.org/sleep-schedules-sleep-timing-guideline/)

### 3. Misalignment is the risk signal users can understand

The strongest product concept is not "chronotype impacts sleep" in the abstract. It is "misalignment impacts sleep." Misalignment means the user's real sleep happens far away from the window their body seems to prefer.

Examples:

- Best window: 12:30 AM-8:00 AM
- Actual sleep: 2:45 AM-8:15 AM
- Gap: 2h 15m late
- Likely user meaning: harder sleep onset, less total sleep, more wake time, worse morning energy

Product implication:

- Use "gap" language:
  - "You slept 2h 15m late."
  - "That often makes mornings harder."
  - "Try moving 15-20 min earlier tonight."
- Avoid moral language:
  - Do not say "bad chronotype."
  - Do not blame the user for late sleep.

Sources:

- [Chronotype and Health Outcomes: An Update](https://link.springer.com/article/10.1007/s40675-026-00366-y)
- [Chronotype, sleep timing, sleep regularity, and cancer risk: A systematic review](https://academic.oup.com/sleep/article/48/6/zsaf059/8069141)

### 4. Light is one of the strongest behavior levers

AASM circadian rhythm guidance describes light as a major timing signal. Morning light can shift the body clock earlier, while evening light before the body's low-temperature point can shift timing later. The exact timing depends on the person, but the app can safely present simple behavioral guidance.

Product implication:

- For late sleepers trying to shift earlier:
  - "Get bright light soon after waking."
  - "Dim lights 1-2 hours before your best sleep window."
- For early sleepers who wake too early:
  - "Avoid very bright light too early if you are trying to sleep later."
  - "Use evening light carefully."
- Keep this educational, not medical treatment.

Source:

- [AASM Clinical Practice Guideline for Intrinsic Circadian Rhythm Sleep-Wake Disorders](https://aasm.org/resources/clinicalguidelines/crswd-intrinsic.pdf)

### 5. Melatonin timing is timing-sensitive

If Better Sleep Formula contains melatonin, the app should treat timing as more important than "take it whenever." AASM notes that melatonin can shift circadian timing and that timing is more important than dose for circadian effects. Meta-analyses show melatonin can modestly reduce sleep onset latency and increase total sleep time, but effects vary by population, dose, timing, and sleep problem.

Product implication:

- Current v1 rule, 60 minutes before the best sleep window, is good for simple user guidance.
- Future rule should become ingredient-aware:
  - If formula includes melatonin and the goal is "sleep now": 30-60 min before target sleep start.
  - If formula includes melatonin and the goal is "shift earlier": consider an earlier circadian-timing protocol only with careful product/legal review.
  - If formula is magnesium/glycine/theanine-style relaxation support: 30-60 min before target sleep start is a simpler fit.
- Never imply the supplement "fixes" circadian rhythm by itself.

Sources:

- [AASM Clinical Practice Guideline for Intrinsic Circadian Rhythm Sleep-Wake Disorders](https://aasm.org/resources/clinicalguidelines/crswd-intrinsic.pdf)
- [Meta-Analysis: Melatonin for the Treatment of Primary Sleep Disorders](https://journals.plos.org/plosone/article?id=10.1371/journal.pone.0063773)
- [Melatonergic agents influence the sleep-wake and circadian rhythms: systematic review and meta-analysis](https://www.nature.com/articles/s41386-022-01278-5)

### 6. REM and deep sleep are timing-sensitive, but app claims must stay observational

Wearable studies suggest that sleep timing, chronotype, sleep debt, and workday/free-day mismatch can relate to REM timing, REM fragmentation, and sleep architecture. However, a consumer app should avoid saying "sleeping in your window causes more REM." Better can safely say:

> In your data, nights inside your best window had 24 min more deep sleep on average.

Product implication:

- Use user-specific comparisons:
  - Inside best window vs outside best window.
  - Require enough nights in each group.
  - Label the result as a pattern, not a guarantee.
- Show stage deltas only when Better has detailed stage data.

Sources:

- [Chronotype-Dependent Sleep Loss Is Associated with Higher REM Fragmentation](https://pmc.ncbi.nlm.nih.gov/articles/PMC10605513/)
- [Timing of Deep and REM Sleep Based on Fitbit Sleep Staging](https://pmc.ncbi.nlm.nih.gov/articles/PMC10968898/)

### 7. Oura's lesson: visual comparison beats text

Oura's Body Clock uses a 24-hour clock face to compare the user's current sleep schedule against an optimal sleep window. The key UX lesson is not to copy the visual exactly; it is to make alignment instantly visible.

Product implication:

- Better should show:
  - Bright arc: best sleep window.
  - Soft arc: user's usual sleep.
  - Gap marker: "33 min late."
  - Confidence: "High confidence, 45 valid nights."
- The first screen should answer the question before the user reads anything.

Source:

- [Oura Body Clock and Chronotype Help](https://support.ouraring.com/hc/en-us/articles/14594974129555-Body-Clock-and-Chronotype)

## Better's Product Positioning

Better is not only a tracker. Better sells a sleep supplement sachet and uses the app to help users sleep better. Cronotype can connect these two sides without becoming spammy:

- The app finds the user's best sleep window.
- The app recommends when to take Better Sleep Formula.
- The app checks whether timing improved sleep that night.
- The app learns whether the user's window, formula timing, or evening habits need adjustment.

The right product promise:

> Better helps you sleep at the time your body is most ready for sleep.

Avoid this promise:

> Better can change your chronotype or guarantee deeper sleep.

## Best User Mental Model

Use this simple hierarchy:

1. Body clock: your natural sleep timing.
2. Best sleep window: when your body seems most ready to sleep.
3. Usual sleep: when you actually slept.
4. Gap: how far usual sleep is from the best window.
5. Impact: what changed in your sleep data when you hit or missed the window.
6. Tonight's plan: what to do next.

Sixth-grade copy examples:

- "Your body clock is a little late."
- "Your best sleep window starts around 1:26 AM."
- "You usually start sleep 33 min earlier."
- "You are close to your window."
- "Take Better Sleep Formula around 12:26 AM."
- "Try to avoid starting sleep before 11:26 PM or after 3:26 AM."
- "When you slept near your window, wake time was 18 min lower."

## Recommended Cronotype Screen Architecture

### First viewport: visual answer

Goal: user understands their body clock in under 5 seconds.

Components:

- Header: "Cronotype"
- Confidence chip: "Stable · 38 nights"
- Large 24-hour body clock dial
- Center text:
  - "Intermediate body clock"
  - "Best sleep: 1:26 AM-7:56 AM"
- Below dial:
  - "You usually sleep 14 min earlier."
  - "Try to start sleep near 1:26 AM tonight."

Visual design:

- Dark calm background.
- Circular day/night dial.
- Night segment: deep blue.
- Pre-dawn segment: cool blue.
- Morning segment: warm amber.
- Day segment: muted gray.
- Bright main arc: best sleep window.
- Thin secondary arc: actual/usual sleep.
- Markers:
  - Moon: bedtime.
  - Dot: midpoint.
  - Sunrise/sun: wake.
  - Bed icon: user's usual sleep start.

### Second viewport: tonight's timing

Goal: turn insight into action.

Rows:

- Better Sleep Formula
  - "Take it around 12:26 AM."
  - "This is about 1 hour before your best sleep window."
- Avoid sleep
  - "Avoid starting sleep before 11:26 PM or after 3:26 AM."
  - "Far outside your window can make sleep lighter."
- Light plan
  - "Get bright light after waking."
  - "Dim lights 1 hour before your formula time."
- Caffeine/activity plan, if data exists
  - "Keep caffeine away from your last 8 hours before sleep."
  - "Move hard workouts earlier if they show up on poor nights."

### Third viewport: impact

Goal: prove why the window matters using the user's data.

Show:

- "When you slept near your window..."
- Delta chips:
  - Sleep score: +8 pts
  - Deep sleep: +24 min
  - REM sleep: about the same
  - Wake time: -18 min
  - Total sleep: +31 min

Rules:

- Require at least 3 in-window and 3 outside-window nights.
- Prefer 5+ and 5+ for stronger language.
- Use "in your data" or "on average."
- Do not use guaranteed/causal language.

### Fourth viewport: best and worst nights

Goal: explain the pattern through examples.

Show a compact comparison:

| Best night | Worst night |
|---|---|
| Score 93 | Score 36 |
| 1:12 AM-9:27 AM | 3:40 AM-10:39 AM |
| 8h 12m | 5h 37m |
| "You slept long and stayed asleep." | "You slept outside your best window." |

Add a small "Why" chip:

- Best night matched window.
- Worst night was 2h 14m late.
- Worst night had 47 min more wake time.

### Final viewport: learn more

Keep educational content collapsed by default.

Sections:

- "How Better knows your body clock"
- "Why your window matters"
- "Can your body clock change?"
- "How to move your sleep earlier or later"

Each section should use short paragraphs and visuals. No wall of text.

## Best Visuals To Explain Cronotype

### 1. Body Clock Dial

Purpose: explain "best window vs actual sleep" instantly.

Elements:

- 24-hour ring.
- Best window arc.
- Actual window arc.
- Moon/sun markers.
- Alignment gap label.

This should be the primary visual.

### 2. Sleep Window Ladder

Purpose: show "too early, best, too late."

Visual:

```text
Too early       Best window                 Too late
|-------------|===========================|-------------|
11:26 PM      1:26 AM                    3:26 AM
```

Use for "when to avoid sleep."

### 3. Impact Chips

Purpose: show why the window matters.

Example:

```text
Inside your window
+8 score   +24m deep   REM same   -18m wake
```

This is better than a table because it is fast to scan.

### 4. Seven-Night Alignment Strip

Purpose: make behavior feel changeable.

Visual:

```text
Mon  Tue  Wed  Thu  Fri  Sat  Sun
●    ●    ○    ●    ○    ○    ●
```

Legend:

- Green dot: slept near best window.
- Amber dot: a little early/late.
- Red dot: far outside window.

This helps the user see consistency.

### 5. Chronotype Day Map

Purpose: expand beyond sleep.

Segments:

- Wake and light
- Best focus
- Exercise
- Wind-down
- Formula
- Best sleep window

This can become a future "body clock day plan."

## Data We Should Use From Better

### Already available or partly available

From `SleepSession`:

- Sleep onset
- Wake time
- Total sleep time
- Deep sleep
- REM sleep
- Restorative sleep
- WASO / awake time
- Sleep latency
- Efficiency
- Sleep score estimate
- Data quality
- Sleep stages
- Source metadata
- Biometrics:
  - HRV
  - heart rate
  - respiratory rate
  - oxygen saturation

From context and activity:

- Caffeine late
- Alcohol
- Screen time late
- Travel
- Jet lag
- Exercise minutes
- Activity status
- Formula taken/missed, if tied through protocol data

### Derived metrics to add

#### Sleep Window Alignment

For each night:

- `optimalStartMinute`
- `optimalEndMinute`
- `actualStartMinute`
- `actualWakeMinute`
- `startDeltaMinutes`
- `midpointDeltaMinutes`
- `alignmentCategory`
  - on track: within 30 min
  - close: 31-60 min
  - off: 61-120 min
  - far off: 120+ min

Use start delta for simple user copy. Use midpoint delta for scientific alignment.

#### Social Jetlag

Calculate:

- Workday sleep midpoint
- Free-day sleep midpoint
- Absolute difference

User copy:

- "Your weekend sleep is 1h 40m later than weekdays."
- "That can make Monday mornings harder."

#### Sleep Regularity

Calculate:

- Bedtime standard deviation.
- Wake time standard deviation.
- Midpoint standard deviation.
- Last 7-day consistency streak.

User copy:

- "Your bedtime moved by about 74 min this week."
- "A steadier bedtime helps your body clock."

#### Formula Timing Alignment

For nights with formula usage:

- Formula taken time.
- Delta from recommended formula time.
- Delta from actual sleep onset.
- Sleep score / onset latency / WASO comparison.

Groups:

- On-time formula: within -30 to +45 min of recommended formula minute.
- Late formula: after target sleep start or within 30 min of sleep.
- Early formula: more than 2 hours before best sleep window.
- No formula.

User copy:

- "On nights you took Formula near your target time, you fell asleep 12 min faster."
- "More nights needed to compare Formula timing."

#### Light and Wind-Down Proxy

If explicit light data is not available, use context proxies:

- screenTimeLate
- Sleep Mode started
- red light filter used
- phone/sleep mode engagement

User copy:

- "Late screen nights were linked with 22 min more wake time."

## Backend And Calculation Improvements

### Current v1

The current local-first v1 is acceptable:

- Calculate chronotype from 7-90 days.
- Use MSFsc/body-clock method.
- Require 7 valid wearable nights minimum.
- Use confidence labels from early estimate to high confidence.
- Compare inside-window vs outside-window nights.

### Recommended v2

Add a separate "CronotypeEvidenceSummary" layer:

```swift
struct CronotypeEvidenceSummary {
    var validNightCount: Int
    var confidence: BodyClockReadiness
    var bestSleepWindow: SleepWindowRecommendation
    var actualSleepWindow: SleepWindowRecommendation?
    var startDeltaMinutes: Int?
    var midpointDeltaMinutes: Int?
    var socialJetlagMinutes: Int?
    var bedtimeVariabilityMinutes: Int?
    var wakeVariabilityMinutes: Int?
    var formulaTimingSummary: FormulaTimingSummary?
    var behaviorFlags: [CronotypeBehaviorFlag]
    var stageImpact: SleepWindowImpactSummary?
}
```

Add behavior flags:

```swift
enum CronotypeBehaviorFlag {
    case lateCaffeineNearWindow
    case alcoholOnPoorWindowNight
    case screenTimeNearWindow
    case highExerciseLate
    case travelOrJetLagExcluded
    case insufficientStageData
    case irregularWeek
    case weekendShiftLarge
}
```

### Recommended v3

Add adaptive recommendations:

- If user is consistently late by 60-120 min:
  - suggest shifting 15-20 min earlier for 3 nights.
- If user is consistently early:
  - suggest keeping wake time steady and not starting sleep too early.
- If user has good sleep outside the calculated window:
  - lower confidence in the recommendation and explain that Better is still learning.
- If supplement timing is late:
  - move formula reminder earlier.
- If sleep latency is low but WASO high:
  - focus less on sleep onset and more on alcohol, temperature, stress, or late exercise.

## Supplement Timing Strategy

### V1 rule

Keep:

```text
recommendedFormulaMinute = optimalSleepWindow.startMinute - 60 min
```

Copy:

> Take Better Sleep Formula around 12:26 AM, about 1 hour before your best sleep window.

### V2 ingredient-aware rule

If formula ingredients are available in code:

- Relaxation formula without melatonin:
  - 30-60 min before target sleep start.
- Melatonin formula:
  - default: 60 min before target sleep start.
  - advanced protocol: only after product/legal review, because circadian phase shifting can need different timing than sleepiness support.
- Digestive-sensitive formula:
  - 60-90 min before target sleep start if user reports stomach discomfort.

### V3 closed-loop rule

Use the user's own response:

- If formula on-time nights improve sleep latency and WASO, keep timing.
- If formula on-time nights show no change, do not over-promote.
- If formula too-late nights are worse, show:
  - "Formula may work better when you take it before your sleep window, not after you already feel tired."

## User Education Strategy

### Explain this first

> Your body clock is your natural sleep timing. Better uses your wearable sleep to find when your body seems most ready for sleep.

### Then explain why it matters

> When sleep happens far outside your window, sleep can feel lighter and mornings can feel harder.

### Then show personal proof

> In your data, nights near your window had 18 min less wake time.

### Then give one action

> Tonight, try starting sleep near 1:26 AM. Take Formula around 12:26 AM.

## Claims And Safety Boundaries

Safe claims:

- "Based on your wearable sleep."
- "In your data."
- "On average."
- "May help."
- "Can make sleep feel lighter."
- "Better is still learning."

Avoid:

- "This will fix your sleep."
- "This causes more REM."
- "Your chronotype is unhealthy."
- "Take more supplement if you miss your window."
- "Ignore your doctor or prescribed schedule."

Medical caveats:

- Shift workers need a separate flow.
- Users with insomnia, delayed sleep-wake phase disorder, advanced sleep-wake phase disorder, bipolar disorder, pregnancy, medication interactions, or diagnosed sleep disorders need careful language.
- If formula contains melatonin, safety copy and ingredient-specific guidance must be reviewed.

## Implementation Roadmap

### Phase 1: Make the current Cronotype tab understandable

- Keep the visual dial as the hero.
- Add alignment gap as the main text.
- Replace long body copy with one-line recommendation.
- Put formula timing and avoid window directly below the hero.
- Keep education collapsed.

### Phase 2: Add stronger data storytelling

- Add seven-night alignment strip.
- Add social jetlag card.
- Add bedtime variability card.
- Improve best/worst night reasons with exact deltas.
- Add "why this night was bad" using ranked contributors:
  - too short
  - too late/early
  - high WASO
  - low restorative sleep
  - late caffeine/alcohol/screen/travel

### Phase 3: Better Formula integration

- Add Formula timing accuracy.
- Add reminder scheduling tied to best sleep window.
- Add formula response comparison:
  - on-time formula
  - late formula
  - missed formula
  - no formula
- Keep claims observational.

### Phase 4: Body Clock Day Plan

- Add personalized timing for:
  - wake
  - morning light
  - caffeine cutoff
  - exercise
  - wind-down
  - formula
  - sleep window
- This becomes a premium daily coaching loop.

## Suggested Copy For Better

### Hero

```text
Your body clock: Intermediate
Best sleep window: 1:26 AM-7:56 AM
You usually sleep 14 min earlier.
Try to start sleep near 1:26 AM tonight.
```

### Formula

```text
Take Better Sleep Formula around 12:26 AM.
That is about 1 hour before your best sleep window.
```

### Avoid

```text
Avoid starting sleep before 11:26 PM or after 3:26 AM.
Sleeping far outside your window can make sleep lighter.
```

### Impact

```text
When you slept near your window, you got 24 min more deep sleep on average.
Wake time was 18 min lower.
REM sleep was about the same.
```

### Insufficient data

```text
More sleep data needed.
Better needs at least 7 wearable nights to estimate your body clock.
Wear your device for a few more nights.
```

### Early estimate

```text
This is an early estimate from 9 nights.
It can change as Better learns your sleep.
```

## Design Principles

- One strong visual first.
- One action for tonight.
- Personal data before science lessons.
- Plain language over clinical language.
- Compare best window and usual sleep everywhere.
- Use confidence clearly.
- Keep supplement timing helpful, not sales-heavy.
- Avoid causal claims unless backed by Better's own controlled evidence.

## References

- Roenneberg T, Wirz-Justice A, Merrow M. [Life between Clocks: Daily Temporal Patterns of Human Chronotypes](https://journals.sagepub.com/doi/10.1177/0748730402239679). Journal of Biological Rhythms. 2003.
- Sletten TL, Weaver MD, Foster RG, et al. [The importance of sleep regularity: a consensus statement of the National Sleep Foundation sleep timing and variability panel](https://www.sciencedirect.com/science/article/pii/S2352721823001663). Sleep Health. 2023.
- National Sleep Foundation. [Consistent Sleep Schedules with New Consensus Guideline](https://www.thensf.org/sleep-schedules-sleep-timing-guideline/). 2023.
- Partonen T. [Chronotype and Health Outcomes: An Update](https://link.springer.com/article/10.1007/s40675-026-00366-y). Current Sleep Medicine Reports. 2026.
- Durrani S, et al. [Chronotype, sleep timing, sleep regularity, and cancer risk: A systematic review](https://academic.oup.com/sleep/article/48/6/zsaf059/8069141). Sleep. 2025.
- Auger RR, Burgess HJ, Emens JS, et al. [AASM Clinical Practice Guideline for Intrinsic Circadian Rhythm Sleep-Wake Disorders](https://aasm.org/resources/clinicalguidelines/crswd-intrinsic.pdf). Journal of Clinical Sleep Medicine. 2015.
- Ferracioli-Oda E, Qawasmi A, Bloch MH. [Meta-Analysis: Melatonin for the Treatment of Primary Sleep Disorders](https://journals.plos.org/plosone/article?id=10.1371/journal.pone.0063773). PLOS ONE. 2013.
- Fatemeh G, Sajjad M, Niloufar R, et al. [Melatonergic agents influence the sleep-wake and circadian rhythms: systematic review and meta-analysis](https://www.nature.com/articles/s41386-022-01278-5). Neuropsychopharmacology. 2022.
- Oura. [Body Clock and Chronotype](https://support.ouraring.com/hc/en-us/articles/14594974129555-Body-Clock-and-Chronotype).
