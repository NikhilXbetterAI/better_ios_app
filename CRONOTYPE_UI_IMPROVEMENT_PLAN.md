# Cronotype UI Improvement Plan

Last updated: 2026-05-28

## Product Goal

Make Cronotype feel like a high-touch sleep coach, not a data report. The user should feel:

- Better understands their real sleep pattern.
- The app is not judging them.
- The next action for tonight is obvious.
- The visual quality feels premium enough for a serious sleep company.

## Design Direction

Visual thesis:

Dark, calm, sleep-lab premium. One large body-clock visual leads the page, with short coaching copy and small data proof underneath.

Interaction thesis:

- Let the user tap the clock markers to understand bedtime, midpoint, wake, and usual sleep.
- Use a segmented control to compare best window, usual sleep, and impact.
- Keep education collapsed until the user asks for it.

## Screen Plan

### 1. Hero: Body Clock

Job:

Answer "when should I sleep?" in under five seconds.

Show:

- Chronotype label.
- Confidence and valid nights.
- 24-hour circular body clock.
- Best sleep window arc.
- Usual sleep arc.
- One recommendation for tonight.
- A coach note that says whether the user is on track, close, or drifting.
- Seven-night alignment strip so progress feels manageable.

### 2. Tonight's Timing

Job:

Turn the body-clock insight into a concrete plan.

Show:

- Sleep start zone ladder: too early, best start, too late.
- Better Sleep Formula timing.
- Avoid-sleep window.
- Morning light anchor.
- Wind-down start.

### 3. Window Impact

Job:

Prove why this matters with the user's data.

Show:

- Delta bars/chips for sleep score, restorative sleep, deep sleep, REM sleep, wake time, and total sleep.
- Keep the copy observational: "patterns from your data, not a guarantee."

### 4. Best And Worst Nights

Job:

Make the data feel real through examples.

Show:

- Best score, bedtime, wake, duration, reason.
- Worst score, bedtime, wake, duration, reason.

### 5. Learn More

Job:

Explain only when the user wants the details.

Show collapsed by default:

- How Better knows.
- Why it matters.
- Can it change?

## Implementation Status

Implemented in:

- `Better/Features/Cronotype/CronotypeTabView.swift`
- `Better/Features/Cronotype/CronotypeBodyClockDial.swift`

Current implementation includes:

- Visual body-clock hero.
- Tap-able clock markers.
- Best/usual/impact segmented control.
- Coach note based on alignment.
- Seven-night alignment strip.
- Sleep-window ladder.
- Better Sleep Formula timing.
- Avoid-sleep timing.
- Morning light and wind-down guidance.
- Impact bars.
- Collapsed education.

## Next Visual QA Checklist

- First screen answers the sleep-window question without scrolling.
- Large clock text does not wrap awkwardly on small phones.
- Clock labels do not overlap marker icons.
- Seven-night strip remains readable with 1-7 nights.
- Formula and avoid times do not collide with labels.
- Bottom tab does not cover best/worst night content.
- Early, late, and midnight-crossing windows all render correctly.

## 2026-05-28 Diagnostic Findings

The latest screenshot showed that the UI looked polished but did not explain itself well enough.

Problems found:

- `Best Window`, `Your Usual`, and `Impact` sounded like product jargon. A new user could not tell whether these were filters, charts, or actions.
- The three clock modes changed the visual but did not clearly say what changed.
- The colored dots under `Last sleep starts` had no legend, so amber/red/green carried no meaning.
- The dots looked decorative instead of interactive.
- The page still had too much card density below the hero, especially once the bottom tab covered lower content.

Fix direction:

- Rename mode labels to plain language:
  - `Best time` / `target`
  - `Your sleep` / `actual`
  - `What changed` / `results`
- Keep the blue best-window arc visible when showing actual sleep, so comparison remains clear.
- Add a dot legend:
  - Green = near
  - Amber = close
  - Red = far
- Make each dot tappable and show the selected night's start time plus how far it was from the best window.
- Keep the hero focused on one idea: target window vs real sleep.
