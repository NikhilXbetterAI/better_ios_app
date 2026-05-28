# Better — App Architecture Visual Guide

> A plain-English map of every component, how they talk to each other, what data they store, and how the key flows (Sleep Dashboard, Insights, Protocol, CSV Export) work end-to-end.

---

## Table of Contents

1. [The Big Picture](#1-the-big-picture)
2. [Layer Map — How the App is Organized](#2-layer-map)
3. [Data Flow: Apple Health → Your Screen](#3-data-flow-apple-health--your-screen)
4. [What Data We Store & Where](#4-what-data-we-store--where)
5. [Sleep Dashboard — Deep Dive](#5-sleep-dashboard--deep-dive)
6. [Insights / Trends — Deep Dive](#6-insights--trends-deep-dive)
7. [Protocol Section — Deep Dive](#7-protocol-section--deep-dive)
8. [CSV Export — Deep Dive](#8-csv-export--deep-dive)
9. [Security & Encryption](#9-security--encryption)
10. [Component Directory](#10-component-directory)
11. [Metric Calculation Reference](#11-metric-calculation-reference) — **how every UI number is computed**

---

## 1. The Big Picture

```
╔══════════════════════════════════════════════════════════════════╗
║                        YOUR IPHONE                               ║
║                                                                  ║
║   ┌──────────────┐        ┌─────────────────────────────────┐   ║
║   │ Apple Health │──read──▶  Better App                     │   ║
║   │  (HealthKit) │        │                                  │   ║
║   └──────────────┘        │  ① Fetch raw sleep + biometrics │   ║
║                           │  ② Process & score it            │   ║
║                           │  ③ Save encrypted to device      │   ║
║                           │  ④ Analyse with your protocols   │   ║
║                           │  ⑤ Show insights on your screen  │   ║
║                           │  ⑥ Let you export a research ZIP │   ║
║                           └─────────────────────────────────┘   ║
║                                                                  ║
║   Nothing leaves your device except the ZIP you choose to share ║
╚══════════════════════════════════════════════════════════════════╝
```

**One-line summary of each tab:**

| Tab | What it shows |
|-----|---------------|
| 💤 Sleep | Last night's sleep — score, stages, biometrics, vs. your baseline |
| 📈 Insights | 7/15/30-day trend charts for sleep quality, deep sleep, HRV, etc. |
| 💊 Protocol | Your supplement/habit tracker + how each one affects your sleep |
| 🧬 Biology | Biometric trends (HRV, VO2Max, weight, SpO2, body temp, etc.) |
| 🏃 Activity | Daily activity log (steps, calories) + status (sick/traveling/etc.) |
| 🔔 Alerts | Smart notifications about trends and missed protocols |
| ⚙️ Settings | Profile, privacy controls, and research CSV export |

---

## 2. Layer Map

The app is split into 4 clean layers. Data only flows **downward** through them.

```
┌─────────────────────────────────────────────────────────────────┐
│  LAYER 4 — UI (what you see)                                    │
│                                                                  │
│  SleepTabView  TrendsTabView  ProtocolTabView  SettingsTabView  │
│       │               │              │               │          │
│  ViewModel       ViewModel      ViewModel       ViewModel       │
│  (holds state,   (holds state,  (holds state,  (holds state,    │
│   reads data)     reads data)    reads data)    reads data)     │
└──────────────────────────┬──────────────────────────────────────┘
                           │  ViewModels call services/repos
┌──────────────────────────▼──────────────────────────────────────┐
│  LAYER 3 — SERVICES (business logic)                            │
│                                                                  │
│  SyncCoordinator          ← orchestrates everything             │
│  BaselineEngine           ← picks your comparison baseline      │
│  ProtocolComparisonService ← taken vs. not-taken analysis       │
│  ResearchAnalysisService  ← builds the full nightly data rows   │
│  ResearchCSVExporter      ← generates the ZIP file              │
│  AlertGenerationService   ← creates smart alerts                │
│  PrivacyDataService       ← data deletion + inventory           │
│  BackgroundTaskService    ← wakes app every 6 hours             │
└──────────────────────────┬──────────────────────────────────────┘
                           │  Services call repositories
┌──────────────────────────▼──────────────────────────────────────┐
│  LAYER 2 — REPOSITORIES (data access)                           │
│                                                                  │
│  HealthKitRepository      ← reads from Apple Health             │
│  LocalDataRepository      ← reads/writes to on-device storage   │
└──────────────────────────┬──────────────────────────────────────┘
                           │  Repos talk to storage/HealthKit
┌──────────────────────────▼──────────────────────────────────────┐
│  LAYER 1 — DATA (storage + processing)                          │
│                                                                  │
│  Apple HealthKit          ← read-only source of truth           │
│  SleepDataProcessor       ← converts raw HK samples → sessions  │
│  SwiftData (SQLite)       ← AES-256 encrypted on-device DB      │
│  iOS Keychain             ← stores the encryption key           │
└─────────────────────────────────────────────────────────────────┘
```

---

## 3. Data Flow: Apple Health → Your Screen

### Step-by-step pipeline

```
  Apple HealthKit
       │
       │  Raw HKCategorySamples (start/end time + sleep stage type)
       │
       ▼
  HealthKitRepository
       │  • Requests authorization once during onboarding
       │  • Runs observer query — wakes app when new sleep data lands
       │  • Incremental anchored queries (only fetches what's new)
       │
       ▼
  SleepDataProcessor                          ← stateless, pure logic
       │  • Step 1: Resolve overlaps
       │    If Apple Watch + iPhone both reported the same hour,
       │    pick the one with higher priority (Watch wins)
       │
       │  • Step 2: Split into sessions
       │    If there's a >30 min awake gap, that's two separate nights
       │
       │  • Step 3: Score each session (0–100)
       │    ┌─────────────────────────────┐
       │    │  Sleep Quality Score        │
       │    │  30%  — Duration            │
       │    │  20%  — Efficiency          │
       │    │  25%  — Deep sleep %        │
       │    │  25%  — REM sleep %         │
       │    └─────────────────────────────┘
       │
       │  • Step 4: Compute baseline (rolling 14 or 7-day window; 30-day stable context kept separately)
       │    Uses circular statistics for bedtime/wake time
       │    (so midnight doesn't mess up the average)
       │
       ▼
  SyncCoordinator                             ← orchestrator / traffic cop
       │  • Calls processor → saves results → triggers alerts
       │  • Runs on first launch (60-day history), foreground refresh,
       │    and every 6 hours in the background
       │
       ▼
  LocalDataRepository
       │  • Translates domain structs → SwiftData models
       │  • Encrypts complex fields (AES-256-GCM) before writing
       │  • Stores in SQLite with iOS file protection (locked when device locked)
       │
       ▼
  On-Device SwiftData Database
       │  (encrypted, never leaves your phone unless you export)
       │
       ├──▶  ViewModels read sessions/baselines → Sleep tab
       ├──▶  ViewModels read trends → Insights tab
       ├──▶  ViewModels read adherence → Protocol tab
       └──▶  ResearchAnalysisService reads everything → CSV export
```

---

## 4. What Data We Store & Where

### Storage locations

| Where | What's stored | Encrypted? |
|-------|--------------|------------|
| **SwiftData (SQLite)** | All health + protocol data | Yes — AES-256-GCM |
| **iOS Keychain** | The encryption key itself | Yes — device-level protection |
| **UserDefaults** | Non-sensitive settings (theme, notifications, migration version) | No (not sensitive) |
| **Apple HealthKit** | Sleep + biometric raw data | Apple manages this |
| **Temp folder** | ZIP file during export (deleted after share) | No (temporary) |

### What we store in the database

```
SwiftData Database
│
├── SleepSession (one per night)
│   ├── Date + start/end times
│   ├── Sleep stages timeline (hypnogram)
│   ├── Quality score (0–100) + component breakdown
│   ├── Data quality flag (detailed stages / unspecified / in-bed only)
│   └── Biometric summary for that night:
│       ├── Heart rate (avg / min / max)
│       ├── HRV (avg / median)
│       ├── Blood oxygen SpO2 (avg / minimum)
│       └── Respiratory rate (avg)
│
├── SleepBaseline (rolling window summary)
│   ├── Which window (14-day primary, 7-day fallback, 30-day stable context)
│   ├── Valid night count + confidence level
│   └── Averages + standard deviations for:
│       total sleep, efficiency, deep sleep, REM, WASO, latency,
│       HRV, SpO2, respiratory rate, bedtime, wake time
│
├── ProtocolAdherence (one row per protocol per day)
│   ├── Protocol ID + date
│   ├── taken / not-taken / UNKNOWN (unknown ≠ not-taken!)
│   └── Time taken + optional note
│
├── SleepContextEntry (nightly context journal)
│   ├── Behavioral: caffeine late, alcohol, late meal, workout,
│   │              high stress, screen time late, nap, travel
│   ├── Self-report: perceived sleep quality, morning energy
│   └── Free-text notes
│       (every field is tristate: true / false / unknown)
│
├── ActivityStatusLog (nightly)
│   └── Status: active / traveling / sick / jet-lagged / injured
│
├── DailyActivitySummary
│   └── Steps, active energy, exercise minutes, stand hours,
│       flights climbed, distance
│
├── SleepAlert (smart notifications)
│   └── Kind, title, body, severity, read/unread, timestamp
│
├── UserProfile
│   └── Sleep goal, baseline window, research mode toggle,
│       onboarding completion, sleep assessment answers
│
└── SyncAnchor
    └── HealthKit position marker for incremental queries
```

---

## 5. Sleep Dashboard — Deep Dive

### What you see & where each number comes from

```
┌─────────────────────────────────────────────────────────┐
│              SLEEP TAB  (redesigned 2026-05)             │
│                                                         │
│  ┌─────────────────────────────────────────────────┐   │
│  │  72pt score numeral inside 240° gauge arc       │   │
│  │  Tick-mark dial · pulsing tip dot               │   │
│  │  Score label ("GOOD") + tap → breakdown sheet  │   │
│  └────────── scoreRingHero ──────────────────────┘    │
│                                                         │
│  combinedInsightLine  ← body-clock or bedtime line      │
│  dataSourceLine       ← "Apple Watch · stages · 11:02"  │
│  SleepFactsStrip      ← Total sleep | Bedtime | Wake    │
│  (tap Bedtime or Wake to flip to ±min vs usual)         │
│                                                         │
│  SleepModeLauncherView  ← long-press → edit schedule    │
│                                                         │
│  "Sleep Stages" header                                  │
│  SleepStagesCard                                        │
│    • SleepHypnogramView (lane-labeled, scrub)           │
│    • SleepStagesStackedBar (tap segment → detail sheet) │
│    • 2×2 LegendChip grid (each tappable → detail sheet) │
│    • Latency row (tappable → detail sheet)              │
│    SleepStageDetailSheet shows 60-night history bars    │
│                                                         │
│  "Longest uninterrupted sleep" header                   │
│  LongestSleepBlockCard                                  │
│                                                         │
│  BiometricsCard (HR avg / HRV / SpO2 / RR)             │
│                                                         │
│  [Calendar] ← tap to browse any historical night        │
└─────────────────────────────────────────────────────────┘
```

**Removed components (2026-05 redesign):**
- `SleepVsBaselineView` — deleted; replaced by `SleepStagesCard` inline baseline bars and `SleepFactsStrip` flip-to-delta
- `SleepContinuityCardView` — absorbed into `LongestSleepBlockCard`
- `SleepModeEntryCard` — replaced by `SleepModeLauncherView`
- `quickStatsStrip`, `bodyClockAlignmentPill`, `viewMoreCard` — removed

### How SleepDashboardViewModel loads data

```
User opens Sleep tab
        │
        ▼
SleepDashboardViewModel.onAppear()
        │
        ├──▶ SyncCoordinator.performForegroundRefresh()
        │         (fetches last 36 hours from HealthKit, re-processes)
        │
        ├──▶ LocalDataRepository.fetchSession(forSleepDateKey:)
        │         Returns: today's SleepSession
        │
        ├──▶ LocalDataRepository.fetchProfile()
        │         Returns: sleepGoalHours, baselineWindowDays (used only
        │         for Trends/Protocol — dashboard ignores it)
        │
        ├──▶ LocalDataRepository.fetchCachedSessions(from: -60d, to: date)
        │    → BaselineEngine.selectDashboardBaseline(...)
        │         30-day primary / 60-day fallback; ≥5 valid nights
        │
        ├──▶ LocalDataRepository.fetchSessions(beforeSleepDateKey:, limit: 59)
        │         → 60 recent sessions for SleepStagesCard history
        │
        └──▶ BiomarkerBaselineService.currentBaseline()
                  (7-day TTL cache; mirrors dashboard 30/60 window)
                  → biomarkerReactions, biomarkerReadiness, biomarkerProvenance

User taps a calendar date
        │
        ▼
SleepDashboardViewModel.selectDate(key:)
        │
        └──▶ Same pipeline as above, relative to selected date
```

### Baseline selection logic (dashboard)

```
BaselineEngine.selectDashboardBaseline()   ← dashboard only

  Sessions from last 60 days
        │
        ▼
  Filter valid nights (same as standard):
  • Sleep duration 2–14 hours
  • Data quality ≠ inBedOnly / noData
        │
        ▼
  Try 30-day primary window (≥5 valid nights required):
  ┌─────────────┬─────────────────────────────────────┐
  │ 30-day      │ Primary — "your usual sleep"        │
  │ 60-day      │ Fallback if 30-day has <5 nights    │
  └─────────────┴─────────────────────────────────────┘
        │
        ▼
  Active baseline = primary ?? fallback
  Dashboard shows "vs your usual sleep" (no window number in copy)
  baselineIsBuilding = true when validNights < 5

Standard selectBaseline() path (Trends / Protocol / Research / CSV):
  • 14-day primary (≥14 nights) ?? 7-day fallback (≥7 nights)
  • 30-day = stable context only (never active comparator)
```

### HealthKit fallback states (when data is missing)

| State | What's shown |
|-------|-------------|
| `permissionDenied` | Banner: "Grant HealthKit access in Settings" |
| `baselineBuilding` | Banner: "Still building your baseline (N/5 nights)" |
| `noSleepStages` | Banner: "Only 'in bed' data found — wear your Watch to sleep" |
| `noData` | Banner: "No sleep data for this date" |
| Normal | Full dashboard |

### Wake time display — Bug A2 fix

`SleepSession.displayWakeDate` (extension in `SleepModels.swift`):
```swift
var displayWakeDate: Date { inBedEndDate ?? endDate }
```
All wake-time display (hero chip, hypnogram x-axis, facts strip) now uses this instead of `endDate` to prevent the last sleep stage ending before the user physically got out of bed from producing an earlier-than-actual wake time.

---

## 6. Insights / Trends — Deep Dive

### What you see

```
┌──────────────────────────────────────────────────────────┐
│              INSIGHTS TAB  (redesigned 2026-05)           │
│                                                          │
│  [7d]  [15d]  [30d]  ← TrendWindowPickerView            │
│                                                          │
│  "What changed" framing card  ← insightFramingCard       │
│  ┌─────────────┬──────────────┬──────────────┐          │
│  │ CHANGED     │ USUAL        │ DATA         │          │
│  │ +0.4h       │ +12 min      │ 22n          │          │
│  │ 7.1h vs 6.7 │ vs 30d usual │ 18 cur/12 pr │          │
│  └─────────────┴──────────────┴──────────────┘          │
│                                                          │
│  Overview score sparkline + period summary               │
│                                                          │
│  Metric: [Deep Sleep ▼]  ← TrendMetricSelectorView      │
│                                                          │
│  Line chart  ← TrendLineChartView                        │
│  90┤                          ●                          │
│  75┤      ●   ●         ●   ●   ●                        │
│  60┤  ●     ●   ●   ●                                    │
│    └────────────────────────── days                      │
│                                                          │
│  Stage bar chart  ← StageStackedBarView                  │
│                                                          │
│  Body Clock card  ← ChronotypeInsightCardView            │
│  (tap → ChronotypeDetailExplorationView full sheet)      │
│                                                          │
│  Protocol impact ← ProtocolImpactView                    │
└──────────────────────────────────────────────────────────┘
```

**"What changed" framing card (`insightFramingCard` in `TrendsTabView.swift`):**
- **Changed**: signed delta (currentAverage − previousAverage) for selected metric vs prior equivalent window
- **Usual**: signed delta between latest night and the stored `SleepBaseline` value for that metric
- **Data**: night count in current window / prior window

**Chronotype deep-dive sheet (`ChronotypeDetailExplorationView.swift`):**
- Tapping the Body Clock card opens a full `NavigationStack` sheet
- Shows large dial, nightly scatter plot of actual vs optimal bedtime, weekday/weekend comparison, raw chronotype calculation details
- Only opens when `result.estimate != nil` (≥ valid wearable nights)
- Computation stays offloaded via `Task.detached` in `TrendsViewModel.calculateChronotype()`

### What metrics are available

| Metric | What's measured |
|--------|----------------|
| Total Sleep | Hours of actual sleep (not time in bed) |
| Sleep Score | 0–100 quality composite |
| Deep Sleep | Time in deep/slow-wave sleep |
| REM Sleep | Time in REM stage |
| HRV | Heart rate variability average |
| WASO | Wake After Sleep Onset (nighttime wake minutes) |
| Sleep Latency | Minutes to fall asleep |
| Respiratory Rate | Breaths per minute during sleep |
| SpO2 | Blood oxygen saturation minimum |

### How TrendsViewModel computes chart data

```
TrendsViewModel.loadData()
        │
        ▼
LocalDataRepository.fetchCachedSessions(last N days)
        │
        ▼
For each session → extract the selected metric value
        │
        ▼
Build TrendChartPoint[] (date, value)
        │
        ▼
Calculate:
  • Moving average (smoothed line)
  • Min / max / mean for the window
  • Baseline overlay (from stored SleepBaseline)
```

---

## 7. Protocol Section — Deep Dive

### What you see

```
┌──────────────────────────────────────────────────────────┐
│              PROTOCOL TAB                                 │
│                                                          │
│  Protocol header + enable toggle                         │
│  Days on protocol + today's taken state                  │
│                                                          │
│  Timeline strip                                           │
│  Recent adherence dots: green=taken, red=missed         │
│                                                          │
│  Impact dashboard                                         │
│  Protocol Impact                                          │
│  [7d] [15d] [30d]                                         │
│  [Score] [Duration] [Deep] [REM]                         │
│  Deep sleep since starting                                │
│  +0.4h vs baseline                                        │
│  ┌ Baseline ────────┐  ┌ After protocol ───────┐         │
│  │ avg + night cnt  │  │ avg + night cnt       │         │
│  └──────────────────┘  └───────────────────────┘         │
│  Off nights appear only when data exists                  │
│                                                          │
│  Change visual                                            │
│  Baseline ●───────● After protocol                        │
│                                                          │
│  Recent nights strip                                      │
│  Green filled dots = protocol, gray hollow = off        │
│                                                          │
│  Tonight's journal                                        │
│  One-question-at-a-time cards with large Yes / No        │
│  answers and autosave on each tap                         │
└──────────────────────────────────────────────────────────┘
```

### The "taken vs. not-taken" analysis

This is the core research engine. It answers: **"Does this protocol actually improve my sleep?"**

```
ProtocolComparisonService.compare()

  Inputs:
  • SleepSession[] (last 30 days)
  • ProtocolAdherence[] (per night per protocol)

  Step 1: Group nights into 3 buckets
  ┌──────────────┬──────────────────────────────────────┐
  │ TAKEN        │ You logged that you took it that day  │
  │ NOT TAKEN    │ You explicitly logged NOT taking it   │
  │ UNKNOWN      │ No entry for that day                 │
  │              │ (IMPORTANT: unknown ≠ not taken!)     │
  └──────────────┴──────────────────────────────────────┘

  Step 2: Compare TAKEN vs NOT TAKEN only
  • Average deep sleep on taken nights
  • Average deep sleep on not-taken nights
  • Delta = taken − not-taken

  Step 3: Assign confidence (based on min(taken, not-taken))
  ┌───────────────────────────────────────────────────┐
  │  min ≥ 7   → HIGH                                 │
  │  min 4–6   → MEDIUM                               │
  │  min 2–3   → LOW                                  │
  │  min < 2   → UNAVAILABLE                          │
  └───────────────────────────────────────────────────┘

  Output: ProtocolEffectSummary per protocol
```

### Context entries — the tristate system

Every context field (caffeine, alcohol, stress, etc.) stores **three states**, not two:

```
true    = "Yes, I did this"
false   = "No, I did not do this"
nil     = "I didn't fill this in / don't know"

Why? Because nil and false are VERY different:
• false means "I confirmed I had no caffeine" → valid data point
• nil means "I forgot to fill it in"          → NOT a valid data point

The analysis engine NEVER treats nil as false.
```

---

## 7b. Protocol Formula Tracking — Deep Dive

**Protocol Formula Tracking** is the active Protocol tab. It reframes the domain around named formula versions (V1 → V2 …) with per-night logs and a frozen baseline of pre-protocol nights. The legacy `ProtocolTabView` / `ProtocolViewModel` code paths remain in the repo but are unreachable — `RootTabView` unconditionally routes the Protocol tab to `ProtocolFormulaTabView`.

### Domain identity

- **`ProtocolFormulaVersion`** — UUID identity. `displayLabel` (user-editable) + derived `ordinalLabel` ("V1", "V2"). `formulaText` is immutable after the first `ProtocolNightLog` references the version (one exception: `isImportedPlaceholder == true` versions allow exactly one backfill). Subsequent changes require "Make a new version".
- **`ProtocolNightLog`** — `sleepDateKey` unique. `status ∈ {.taken, .skipped, .unknown}`. `.skipped` rows still record `versionID` so we can answer "how many V2 nights did the user skip?". Each log carries `formulaSnapshotHash` (SHA-256 of formula text + sorted components) captured at log time.
- **`ProtocolLogEdit`** — append-only audit row written every time a night log is edited. Kept forever.
- **`ProtocolBaselineSnapshot`** — singleton. Frozen once at protocol start using up to 30 most-recent qualifying nights (detailed/mixed stages) from the 90-day window before `firstVersion.shippedOn`. **Never recomputed** on HealthKit resync. `<7 valid nights → isInsufficient`; `0 valid nights → no snapshot stored`.

### Reuse rules — no duplicate restorative math

The analysis service composes one struct per night by reading existing `SleepSession` fields:

| Snapshot field | Source |
|----------------|--------|
| `restorativeSleepMinutes` | `session.restorativeSleepDuration / 60` (only when `dataQuality ∈ {.detailedStages, .mixedSources}`) |
| `restorativePctOfInBed` | `restorativeSleepDuration / totalInBedTime * 100` (same gating) |
| `longestRestorativeBlockMinutes` | `session.continuitySummary.longestBlockDuration / 60` |
| `continuityCategory` | `session.continuitySummary.continuityCategory` |

`SleepContinuityCalculator` is **never** re-run inside Protocol Formula code.

### Schema migration

Persistence now uses `VersionedSchema`:

- `BetterSchemaV1` — the original 14 models.
- `BetterSchemaV2` — V1 + `StoredProtocolFormulaVersion`, `StoredProtocolNightLog`, `StoredProtocolLogEdit`, `StoredProtocolBaselineSnapshot`.
- `BetterMigrationPlan` — single `.lightweight` stage (additive only).

The container factory no longer silently wipes on init failure. WAL-corruption recovery is gated behind explicit user action ("Reset all local data" in Settings).

### Legacy migration

`ProtocolAdherenceMigrationService` is one-shot. When V2 schema is online and no `StoredProtocolFormulaVersion` rows exist but `StoredProtocolAdherence` rows do, it:

1. Derives a start date: `UserDefaults better.protocol.startDate` → earliest `taken == true` row → otherwise defer to onboarding.
2. Creates a single V1 version with `isImportedPlaceholder = true` (empty formula text — user is prompted to backfill).
3. Collapses legacy `(protocolID, dateKey)` rows to one `ProtocolNightLog` per `sleepDateKey`: any `taken == true` → `.taken`; else any `taken == false` → `.skipped`; absent date → `.unknown` (no row).
4. Attempts to freeze the baseline; if 0 qualifying nights exist, no snapshot is stored.

The service sets a UserDefaults flag and never re-runs.

### Home screen layout

**HOME A (Last night segment):**
1. `lastNightHeroCard` — restorative % ring; formula taken badge (`✓` green / `?` orange "Not logged")
2. `lastNightMetricsGrid` — 2×2 deep / REM / awake / duration cards, each showing last-night actual vs frozen baseline mean (`lastNightVsBaselineDeltas`)
3. `impactComparisonCard` — all-time formula average vs baseline
4. `tonightCompactCard`, `trendSection`, `protocolSummarySection`
5. `quickNavRow` (always rendered, outside the active-version guard) — Timeline / All Metrics / Version Dive / Edit Log tiles

**HOME B (Tonight segment):** tonight hero → last-night recap → impact → `quickNavRow` → trend → trial progress.

**No active formula — two states:**
- `versions.isEmpty` → "No formula yet" card + "Add a formula" CTA
- `versions` non-empty, none active → "Which formula are you on?" card with one-tap formula picker; tapping calls `viewModel.setActive(_:)` and the home refreshes into the normal data view

### Active-formula management

`ProtocolFormulaVersion.isActive` is a singleton enforced by `LocalDataRepository.saveFormulaVersion` — saving any version with `isActive: true` automatically clears the flag on all other rows. Two surfaces expose activation:

| Surface | Affordance |
|---------|------------|
| Home screen | One-tap formula card in the "Which formula are you on?" empty state |
| Formula Setup screen | "Set as Current" button on any non-active version row |

### Files

- `Core/Models/ProtocolFormulaModels.swift` — domain types.
- `Core/Persistence/PersistenceModels.swift` — schema chain + 4 new `@Model` classes.
- `Core/Repositories/LocalDataRepository.swift` — formula/log/edit/snapshot CRUD; active-singleton enforcement.
- `Core/Services/ProtocolBaselineService.swift` — bounded-window freeze.
- `Core/Services/ProtocolAdherenceMigrationService.swift` — one-shot legacy import.
- `Core/Services/ProtocolFormulaAnalysisService.swift` — snapshot, rollup, impact summary.
- `Features/ProtocolFormula/` — view + view-model layer (always active; no flag).

---

## 8. CSV Export — Deep Dive

### How to trigger it

Protocol tab → `Export Data` button, or Settings → Research Export

### What gets generated

```
ResearchCSVExporter.writeZIP()
        │
        ├── nightly_research_rows.csv      ← one row per night
        ├── protocol_effect_summary.csv    ← one row per protocol
        └── export_metadata.csv            ← export info + version
```

### What's in nightly_research_rows.csv

Every night becomes one row with 60+ columns:

```
IDENTITY
  sleep_date_key, session_id, data_quality

SLEEP METRICS (raw)
  total_sleep_minutes, time_in_bed_minutes, sleep_efficiency
  deep_sleep_minutes, rem_sleep_minutes, core_sleep_minutes
  awake_minutes (WASO), sleep_latency_minutes
  sleep_score (0–100)

SLEEP STAGE %
  deep_sleep_pct, rem_sleep_pct, core_sleep_pct

BIOMETRICS (during sleep)
  hr_avg, hr_min, hr_max
  hrv_avg, hrv_median
  spo2_avg, spo2_min
  respiratory_rate_avg

BASELINE CONTEXT
  baseline_window_days, baseline_valid_nights, baseline_confidence
  baseline_total_sleep_avg, baseline_deep_avg, baseline_rem_avg, ...
  delta_total_sleep, delta_deep_sleep, delta_rem, delta_hrv, ...
  (delta = tonight − your baseline average)

PROTOCOL ADHERENCE (one column per protocol)
  protocol_{id}_status  → "taken" / "not_taken" / "unknown"
  protocol_{id}_taken_at

ACTIVITY STATUS
  activity_status (active/traveling/sick/jet_lagged/injured)
  steps, active_energy_kcal, exercise_minutes, stand_hours
  flights_climbed, distance_km

CONTEXT FACTORS (Phase 3 journal)
  caffeine_late, alcohol, late_meal, workout_today
  high_stress, screen_time_late, nap_today, travel_day
  perceived_sleep_quality, morning_energy
  context_notes
```

### What's in protocol_effect_summary.csv

```
protocol_id, protocol_name
taken_night_count, not_taken_night_count
avg_total_sleep_taken, avg_total_sleep_not_taken, delta_total_sleep
avg_deep_sleep_taken, avg_deep_sleep_not_taken, delta_deep_sleep
avg_rem_taken, avg_rem_not_taken, delta_rem
avg_hrv_taken, avg_hrv_not_taken, delta_hrv
confidence_level, caveats
```

### The full export pipeline

```
User taps "Export Data"
        │
        ▼
ProtocolViewModel.exportResearchData()
        │
        ▼
ResearchAnalysisService.buildExportPackage(last 60 days)
        │
        ├──▶ Fetch SleepSessions  (LocalDataRepository)
        ├──▶ Fetch ProtocolAdherence  (LocalDataRepository)
        ├──▶ Fetch ActivityStatusLogs  (LocalDataRepository)
        ├──▶ Fetch SleepContextEntries  (LocalDataRepository)
        ├──▶ Fetch DailyActivitySummaries  (LocalDataRepository)
        ├──▶ Fetch Stored Baseline + profile (LocalDataRepository)
        ├──▶ Fetch ProtocolItems  (ProtocolCatalog)
        │
        ├──▶ BaselineEngine.selectBaseline()
        │         → picks the best baseline for comparison
        │
        ├──▶ ProtocolComparisonService.compare() per protocol
        │         → computes taken/not-taken deltas
        │
        └──▶ Build NightlyResearchRow[] (one per night)
                  Join: session + adherence + activity + context + baseline deltas
        │
        ▼
ResearchCSVExporter.writeZIP(package)
        │
        ├── Write nightly_research_rows.csv  (60+ columns × N nights)
        ├── Write protocol_effect_summary.csv
        ├── Write export_metadata.csv
        └── Pack into .zip → return temp URL
        │
        ▼
iOS Share Sheet  (you choose where to send it)
```

---

## 9. Security & Encryption

```
┌─────────────────────────────────────────────────────────────┐
│                  SECURITY LAYERS                             │
│                                                              │
│  Layer 1: iOS File Protection                                │
│  SQLite files use .complete protection                       │
│  → Files are LOCKED when device is locked                   │
│                                                              │
│  Layer 2: AES-256-GCM Encryption                            │
│  Complex data fields (sleep stages, quality scores,         │
│  biometric samples) are encrypted before being written      │
│  to the database.                                           │
│                                                              │
│  Layer 3: iOS Keychain Key Storage                          │
│  The encryption key is stored in the Keychain with          │
│  kSecAttrAccessibleWhenUnlockedThisDeviceOnly                │
│  → Key is only readable when device is unlocked             │
│  → Key cannot be copied to another device                   │
│                                                              │
│  Transparent migration:                                      │
│  PersistenceJSON.decode() auto-detects old plain-text        │
│  records and can read them during migration, then           │
│  re-saves them encrypted. No data loss.                     │
└─────────────────────────────────────────────────────────────┘
```

**What's encrypted:** Sleep sessions, biometrics, baselines, protocol adherence, activity logs, context entries, user profile, onboarding answers.

**What's NOT encrypted:** App settings (theme, notification preferences) — not sensitive, kept fast.

---

## 10. Component Directory

A full lookup table of every important file.

### App Shell

| File | What it does |
|------|-------------|
| [`App/BetterApp.swift`](Better/App/BetterApp.swift) | App entry point. Boots `AppEnvironment`, registers background handlers, starts HealthKit observers |
| [`App/RootTabView.swift`](Better/App/RootTabView.swift) | Root navigation. Shows onboarding if new user, else the 5-tab main app |
| [`App/AppEnvironment.swift`](Better/App/AppEnvironment.swift) | Dependency injection container. Creates and wires all services and repositories |
| [`App/AppTab.swift`](Better/App/AppTab.swift) | Enum defining the 5 main tabs (title, icon, color) |

### Data Models

| File | What it defines |
|------|----------------|
| [`Core/Models/SleepModels.swift`](Better/Core/Models/SleepModels.swift) | `SleepSession` (+ `displayWakeDate` ext), `SleepBaseline`, `HealthSleepScoreEstimator`, `HealthSleepScoreEstimate`, `SleepStage`, `SleepSource` |
| [`Core/Models/ProtocolModels.swift`](Better/Core/Models/ProtocolModels.swift) | `ProtocolItem`, `ProtocolAdherence`, `SleepAlert`, `UserProfile` |
| [`Core/Models/ResearchAnalysisModels.swift`](Better/Core/Models/ResearchAnalysisModels.swift) | `NightlyResearchRow`, `ProtocolEffectSummary`, `ResearchExportPackage` |
| [`Core/Models/BiometricModels.swift`](Better/Core/Models/BiometricModels.swift) | `BiometricSample`, `BiologyMetric`, `NightlyBiometricSummary` |
| [`Core/Models/ActivityStatusModels.swift`](Better/Core/Models/ActivityStatusModels.swift) | `ActivityStatusLog`, `UserActivityStatus`, `DailyActivitySummary` |
| [`Core/Models/SleepContextEntry.swift`](Better/Core/Models/SleepContextEntry.swift) | `SleepContextEntry` — 8 tristate behavioral fields + self-report |
| [`Core/Models/BiomarkerBaseline.swift`](Better/Core/Models/BiomarkerBaseline.swift) | `BiomarkerKey` (rhr/hrv/spo2/breath), `BiomarkerBaseline`, `BiomarkerBaselineReadiness`, `BiomarkerProvenance`, `SleepBiomarkerReaction` — dashboard-only biometric baseline |
| [`Core/Models/SleepUsualComparison.swift`](Better/Core/Models/SleepUsualComparison.swift) | `SleepVerdict`, `SleepRowStatus` — comparison helpers used by stage detail sheets |
| [`Core/Models/SleepBiomarkerSummary.swift`](Better/Core/Models/SleepBiomarkerSummary.swift) | Per-night biometric summary scoped to dashboard display |

### Storage

| File | What it does |
|------|-------------|
| [`Core/Persistence/PersistenceModels.swift`](Better/Core/Persistence/PersistenceModels.swift) | SwiftData schema: 11 `@Model` classes. Factory for live + preview containers |

### Repositories (Data Access)

| File | What it does |
|------|-------------|
| [`Core/Repositories/RepositoryProtocols.swift`](Better/Core/Repositories/RepositoryProtocols.swift) | Protocol contracts for both repositories (used in tests for mocking) |
| [`Core/Repositories/HealthKitRepository.swift`](Better/Core/Repositories/HealthKitRepository.swift) | Reads sleep samples and biometrics from Apple HealthKit |
| [`Core/Repositories/LocalDataRepository.swift`](Better/Core/Repositories/LocalDataRepository.swift) | All SwiftData CRUD: save, fetch, delete, encrypt/decrypt |

### Processors

| File | What it does |
|------|-------------|
| [`Core/Processors/SleepDataProcessor.swift`](Better/Core/Processors/SleepDataProcessor.swift) | Converts raw HealthKit samples → `SleepSession[]`. Scores, deduplicates, splits sessions. Computes baselines |

### Services

| File | What it does |
|------|-------------|
| [`Core/Services/SyncCoordinator.swift`](Better/Core/Services/SyncCoordinator.swift) | Orchestrates HealthKit → process → save → alert pipeline. Manages sync phases |
| [`Core/Services/BackgroundTaskService.swift`](Better/Core/Services/BackgroundTaskService.swift) | Schedules 6-hour background syncs via `BGTaskScheduler` |
| [`Core/Services/BaselineEngine.swift`](Better/Core/Services/BaselineEngine.swift) | Picks the best comparison baseline (15-day vs 7-day, with confidence) |
| [`Core/Services/ProtocolComparisonService.swift`](Better/Core/Services/ProtocolComparisonService.swift) | Compares sleep on taken vs. not-taken nights per protocol |
| [`Core/Services/ResearchAnalysisService.swift`](Better/Core/Services/ResearchAnalysisService.swift) | Joins all data into `NightlyResearchRow[]` for export |
| [`Core/Services/ResearchCSVExporter.swift`](Better/Core/Services/ResearchCSVExporter.swift) | Writes the 3-file ZIP for download |
| [`Core/Services/AlertGenerationService.swift`](Better/Core/Services/AlertGenerationService.swift) | Creates smart in-app and push notification alerts from sync results |
| [`Core/Services/PrivacyDataService.swift`](Better/Core/Services/PrivacyDataService.swift) | Data inventory, full deletion, re-sync from Apple Health |
| [`Core/Services/BiomarkerBaselineService.swift`](Better/Core/Services/BiomarkerBaselineService.swift) | Dashboard-only: caches biometric baseline (RHR/HRV/SpO₂/breath) with 7-day TTL; mirrors dashboard 30/60-day window |

### Security

| File | What it does |
|------|-------------|
| [`Core/Security/EncryptionService.swift`](Better/Core/Security/EncryptionService.swift) | AES-256-GCM encrypt/decrypt. Caches key in memory with a lock |
| [`Core/Security/KeychainService.swift`](Better/Core/Security/KeychainService.swift) | Store/load/delete the encryption key in iOS Keychain |
| [`Core/Security/DataMigrationService.swift`](Better/Core/Security/DataMigrationService.swift) | One-shot migration of old unencrypted records to encrypted storage |

### Feature ViewModels

| File | What it does |
|------|-------------|
| [`Features/Sleep/SleepDashboardViewModel.swift`](Better/Features/Sleep/SleepDashboardViewModel.swift) | State for Sleep tab: selected date, sessions, dashboard baseline (30/60d), biomarker reactions, fallback state |
| [`Features/Sleep/SleepStagesCard.swift`](Better/Features/Sleep/SleepStagesCard.swift) | Hypnogram + stacked stage bar + 2×2 legend grid + latency row; each chip taps to `SleepStageDetailSheet` |
| [`Features/Sleep/LongestSleepBlockCard.swift`](Better/Features/Sleep/LongestSleepBlockCard.swift) | Shows longest uninterrupted sleep block from `SleepSession.continuitySummary` |
| [`Features/Sleep/SleepFactsStrip.swift`](Better/Features/Sleep/SleepFactsStrip.swift) | 3-chip hero row: total sleep · bedtime · wake; tap bedtime/wake to flip to ±min-vs-baseline delta |
| [`Features/Trends/TrendsViewModel.swift`](Better/Features/Trends/TrendsViewModel.swift) | Computes chart data points for selected metric and window |
| [`Features/Protocol/ProtocolViewModel.swift`](Better/Features/Protocol/ProtocolViewModel.swift) | Adherence checklist, streak, chart points, and research export entry point |
| [`Features/Protocol/ProtocolComparisonDashboardViewModel.swift`](Better/Features/Protocol/ProtocolComparisonDashboardViewModel.swift) | Windowed protocol effect summaries with counts, insights, and confidence |
| [`Features/Protocol/ProtocolImpactChartView.swift`](Better/Features/Protocol/ProtocolImpactChartView.swift) | Protocol impact summary, before/after improvement chart, and night history strip |
| [`Features/Protocol/ContextFactorDashboardViewModel.swift`](Better/Features/Protocol/ContextFactorDashboardViewModel.swift) | Context journal form and insights |
| [`Features/Settings/SettingsViewModel.swift`](Better/Features/Settings/SettingsViewModel.swift) | Profile settings, export logic, research insight summary |

---

## Quick Reference: Key Formulas

```
Sleep Quality Score — detailedStages (max 100):
  Duration     40 pts  = clamp(totalSleep / goalSecs × 40, 0, 40)
  Bedtime      25 pts  = clamp((1 − circDev/166) × 25, 0, 25); 0 if <5 baseline nights
  Continuity   15 pts  = clamp(15 − (waso−5min)/(55min) × 15, 0, 15)
  Restorative  20 pts  = baseline-relative deep+REM ratio (10 at parity, +50×delta)

Sleep Quality Score — unspecifiedSleepOnly / isPartial (max 80):
  Duration     50 pts  = clamp(totalSleep / goalSecs × 50, 0, 50)
  Continuity   30 pts  = clamp(30 − (waso−5min)/(55min) × 30, 0, 30)
  Bedtime/Restorative = 0 pts

Session split threshold:     > 30 minutes awake gap → new session
Data retention:              60 days
Background sync interval:    every 6 hours
Baseline — standard:         14-day primary (fallback: 7-day; 30-day = stable context only)
Baseline — dashboard:        30-day primary (fallback: 60-day); min 5 valid nights
Baseline min nights (std):   14 → high, 7–13 → medium, 3–6 → low confidence
Protocol confidence levels:  min(taken,notTaken) ≥7 → high, 4–6 → medium, 2–3 → low
Encryption:                  AES-256-GCM, key in iOS Keychain
Wake time display:           session.displayWakeDate = inBedEndDate ?? endDate
```

---

## 11. Metric Calculation Reference

This section is the **authoritative map from each number you see in the UI back to the exact code that produces it**. Every formula is sourced from real files — paths and line numbers are included so you can jump in.

---

### 11.1 Sleep Quality Score (0–100)

**Where it's shown:** Sleep tab ring (72pt numeral), Trends "Sleep Score" line chart, Protocol Impact "Score" band, every nightly CSV row. Tap the score inside the ring to open a breakdown sheet.

**Code:** [`Core/Models/SleepModels.swift`](Better/Core/Models/SleepModels.swift) — `HealthSleepScoreEstimator.estimate()` (lines ~253–289); sub-components `durationComponent`, `bedtimeComponent`, `interruptionsComponent`, `restorativeComponent` (~291–356).

**Inputs:** `SleepSession` (totalSleepTime, waso, deepDuration, remDuration, dataQuality, inBedStartDate), `SleepBaseline?`, `sleepGoalHours` from `UserProfile` (default 8h), `SleepContextEntry?` (for travel exemption), `Calendar`.

**Formula — detailedStages / mixedSources sessions:**

```
Duration      40 pts  = clamp(totalSleepTime / (goalHours×3600) × 40, 0, 40)
                        linear ramp — 0 pts at 0 h, 40 pts at or above goal

Bedtime       25 pts  = clamp((1 − deviation/166) × 25, 0, 25)
                        deviation = circularMinuteDistance(bedMinute, baseline.bedtimeMinuteAverage)
                        → 0 pts when baseline.validNights < 5
                        → 25 pts (full) when contextEntry.travel == true (travel exemption)
                        166-minute boundary: at ≥2h46m deviation component reaches 0

Continuity    15 pts  = clamp(15 − wasoPenalty, 0, 15)
                        wasoPenalty = min(15, max(0, (waso − 5×60) / (55×60) × 15))
                        → full 15 pts at ≤5 min WASO; 0 pts at ≥60 min WASO

Restorative   20 pts  = baseline-relative mode (when baseline.validNights ≥ 5):
                          ratio = (deepDuration + remDuration) / totalSleepTime
                          baselineRatio = (baseline.deepAverage + baseline.remAverage) / baseline.totalSleepAverage
                          pts = clamp(10 + (ratio − baselineRatio) × 50, 0, 20)
                        absolute fallback (baseline not ready):
                          pts = clamp(ratio / 0.40 × 20, 0, 20)
                          (target = 40 % combined deep+REM)

overall = duration + bedtime + continuity + restorative   (max 100)
```

**Formula — unspecifiedSleepOnly (isPartial = true):**

```
Duration      50 pts  = clamp(totalSleepTime / (goalHours×3600) × 50, 0, 50)
Bedtime        0 pts  (maxPts=0 for partial sessions)
Continuity    30 pts  = clamp(30 − wasoPenalty, 0, 30)
Restorative    0 pts  (no stage data)

overall = duration + continuity   (max 80 pts)
isPartial = true — UI shows a "partial" badge
```

**HealthSleepScoreEstimate struct fields:**
```
overall:       Int   // 0–100 (0–80 for partial)
duration:      Int   // 0–40 (or 0–50 partial)
bedtime:       Int   // 0–25 (or 0 partial)
interruptions: Int   // 0–15 (or 0–30 partial)
restorative:   Int   // 0–20 (or 0 partial)
```

---

### 11.2 Session Construction (raw HealthKit → SleepSession)

**Code:** [`SleepDataProcessor.swift:259–402`](Better/Core/Processors/SleepDataProcessor.swift).

**Pipeline:**

1. **Parse raw samples** (`rawInterval`, L350–376). Each `HKCategorySample` gets a `sourceQuality` score:
   - `manual entry` → 0
   - Apple Watch + detailed stage → 4
   - Any detailed stage → 3
   - Apple Watch + unspecified → 2
   - Else → 1

2. **Overlap resolution** (`cleanedIntervals`, L273–312). Collects every start/end boundary, sorts them, and for each minimal sub-interval keeps the overlapping raw interval with highest
   `resolutionPriority = stagePriority·10 + sourceQuality`
   where stagePriority: deep/rem/core = 4, awake = 3, unspecified = 2, inBed = 1. Adjacent equal-stage+source segments are merged.

3. **Session grouping** (`groupSessions`, L314–334). Sorted intervals start a **new session** when gap from previous end > **1800s (30 min)**.

4. **Per-session metrics** (`makeSession`, L103–204). Requires `totalSleepTime ≥ 300s` (else discarded). Computes:
   - `inBedDuration` = union of `.inBed` intervals clipped to session bounds (falls back to `end − start`)
   - `sleepLatency` = `firstAsleepStart − inBedStart`, floored at 0
   - `waso` = sum of `.awake` intervals strictly between first and final asleep moment
   - `efficiency` = `min(1, totalSleep / totalInBed)`

5. **`dataQuality` flag** (L378–402): `detailedStages` > `unspecifiedSleepOnly` > `mixedSources` (>1 source on sleep stages) > `inBedOnly` > `noData`.

---

### 11.3 Per-Night Biometric Summary

**Where it's shown:** Sleep tab "Biometrics" row (HR / HRV / SpO2), Biology tab freshness, CSV columns.

**Code:** [`SleepDataProcessor.swift:67–90`](Better/Core/Processors/SleepDataProcessor.swift); median helper L490–499.

For each metric, samples filtered by HK type within the session window:

| Metric | Aggregation |
|---|---|
| Heart Rate | average, min, max |
| HRV (SDNN) | average + **median** (middle of sorted list, or mean of two middles) |
| SpO2 | average, min (no max) |
| Respiratory Rate | average only |

All use `averageOrNil` (returns nil on empty input). **No outlier filtering** — raw HealthKit values are used.

---

### 11.4 Baseline (Rolling 7 / 14 / 30 Day)

**Where it's shown:** Sleep tab stage bars (SleepStagesCard), SleepFactsStrip flip deltas, Trends charts dashed reference, deltas in every CSV row.

**Code:** [`BaselineEngine.swift`](Better/Core/Services/BaselineEngine.swift) — `selectBaseline()` (standard) and `selectDashboardBaseline()` (dashboard); [`SleepDataProcessor.swift`](Better/Core/Processors/SleepDataProcessor.swift) — `computeBaseline()` for the math.

**Valid-night filter** (`isValidNight`): valid `sleepDateKey`, `2h < totalSleepTime ≤ 14h`, `totalInBedTime ≥ totalSleepTime`, dataQuality ≠ `inBedOnly`/`noData`, all durations ≥ 0, efficiency ∈ [0,1], `startDate < endDate`.

**Window selection — standard path (Trends / Protocol / Research / CSV):**
- `primary` = `suffix(14)` only if there are ≥14
- `recent` = `suffix(7)` only if there are ≥7
- `stable` = `suffix(30)` — stable context column only, never active comparator
- `activeBaseline = primary ?? recent`

**Window selection — dashboard path (`selectDashboardBaseline`):**
- `primary` = 30-day window, ≥ 5 valid nights
- `fallback` = 60-day window, ≥ 5 valid nights (used only when primary unavailable)
- Copy reads "your usual sleep" — no window length shown to user
- `baselineIsBuilding = validNights < 5`

**Computation per window** (`computeBaseline`):
- Further drops `inBedOnly`/`noData`/`totalSleepTime < 300s`
- Stage averages (REM, Deep) computed **only over `detailedSessions`** — `unspecifiedSleepOnly` is excluded to avoid skewing
- Mean + **population std dev** (variance ÷ N) for: totalSleep, REM, Deep, efficiency, WASO, latency, HRV avg, RR avg, SpO2 avg
- **Circular statistics** for bedtime / wake (L464–488): minute-of-day → angle `θ = m · 2π/1440`, average sin & cos, `atan2` → mean angle → back to minutes. Std dev uses `circularMinuteDistance` = `min(|Δ|, 1440 − |Δ|)` so midnight crossings don't break the average.

---

### 11.5 "vs Baseline" Deltas (Sleep Tab)

`SleepVsBaselineView.swift` was **deleted** in the 2026-05 redesign. Baseline deltas are now surfaced in two places:

**`SleepFactsStrip` (bedtime / wake flip interaction):**
- Tap Bedtime chip → shows signed minute delta vs `baseline.bedtimeMinuteAverage` (circular wrap ±720 min; negative = earlier, positive = later)
- Tap Wake chip → shows signed minute delta vs `baseline.wakeMinuteAverage`
- Only available when `baseline.validNights ≥ dashboardMinimumValidNights (5)`

**`SleepStagesStackedBar` inside `SleepStagesCard`:**
Each stage segment shows a baseline-length marker bar so you can visually compare tonight vs usual.

**`SleepUsualComparison` helpers (`Core/Models/SleepUsualComparison.swift`):**
```
rowStatus(value:baselineAverage:baselineStdDev:lowerIsBetter:isAwakeMetric:)
  → .moreThanUsual / .aboutUsual / .lessThanUsual / .fewerWakeUps
  band = stdDev × 0.5 (fallback: 10% of average when stdDev == 0)

isFavorable(status:lowerIsBetter:) → Bool?   used for green/red coloring
```

**Trends insightFramingCard "Usual" cell:**
- `latestValue − baselineMetricValue(baseline)` for the selected metric
- Baseline lookup delegates to `viewModel.baseline` (14/7-day standard path)

---

### 11.6 Schedule Consistency Variance

**Code:** baseline std devs from §11.4; UI in [`ScheduleConsistencyView.swift:203–238`](Better/Features/Sleep/ScheduleConsistencyView.swift).

```
displayedVariation = max(baseline.bedtimeMinuteStdDev,
                         baseline.wakeMinuteStdDev)
shown as "±N min variation"
```

Per-night chart points use a view-local `circularVariation` (RMS of `signedMinuteDistance` from the circular mean) — same circular math as the baseline.

---

### 11.7 Trends Line Chart

**Code:** [`TrendsViewModel.swift:246–445`](Better/Features/Trends/TrendsViewModel.swift); render in [`TrendLineChartView.swift:12–129`](Better/Features/Trends/TrendLineChartView.swift).

- **Load:** `LocalDataRepository.fetchCachedSessions(from: startDate, to: now)` over selected `TrendWindow` (7 / 30 / 60 days).
- **Point value** (`metricValue(for:)` L445) — switches on `selectedMetric`:

| Metric | Source |
|---|---|
| `totalSleep` / `deep` / `rem` / `longestRestorativeBlock` | seconds ÷ 3600 (hours) |
| `score` | `session.qualityScore.overall` |
| `hrv` / `respRate` / `oxygenSaturation` | `session.biometrics.*` |
| `waso` / `latency` | seconds ÷ 60 (minutes) |

Stage metrics require `dataQuality == .detailedStages`; sessions without stages are nil-dropped from the series.

- **Y-axis scaling:** `min = values.min()`, `max = values.max()`, normalized as `(v − min) / max(0.1, max − min)`. No moving average — the chart connects raw points.
- **Period-over-period summary** (`updateComparisonSummary` L363): averages current window vs equivalent prior window; `percentChange = (current − previous) / previous`. nil if either side empty or previous == 0.

**Baseline overlay** (`BaselineComparisonChartView.swift` L13–42) is a **separate** card — horizontal bars comparing latest session vs `SleepBaseline` for totalSleep / deep / REM / HRV. Bar width = `value / max(current, baseline, 0.1) · 260`.

**Stage composition** (L343): per-night percentages = `stageDuration / (deep + core + rem + awake)`; only emitted for `detailedStages` nights.

---

### 11.8 Protocol Impact (Taken vs Not-Taken)

**Code:** [`ProtocolComparisonService.swift:63–116`](Better/Core/Services/ProtocolComparisonService.swift); UI in [`ProtocolImpactChartView.swift`](Better/Features/Protocol/ProtocolImpactChartView.swift).

1. **Eligibility:** sessions pass `BaselineEngine.isValidNight` and lie in selected window (`last7Days` / `15` / `30` / `all`).
2. **Per-night status** (`status(for:)` L111):
   - no adherence row for that `sleepDateKey` → `.unknown`
   - any taken=true → `.taken`
   - else → `.notTaken`
   - **Unknown nights are excluded entirely** from the averages.
3. **Deltas** = `avg(taken) − avg(notTaken)` for `totalSleepTime`, `efficiency`, `awakeDuration`. For **deep/rem**, only sessions with `detailedStages` or `mixedSources` AND nonzero stage duration contribute (`stageAverage`).
4. **Confidence** (based on `min(takenCount, notTakenCount)`):

   | min | Level |
   |---|---|
   | ≥ 7 | HIGH |
   | 4–6 | MEDIUM |
   | 2–3 | LOW |
   | < 2 | UNAVAILABLE |

**ProtocolImpactChartView** renders a 3-bar band [Baseline | Protocol | Off-Protocol]. `baselineAverage` is a `SleepPeriodSummary` over pre-protocol nights. Requires ≥3 protocol nights and ≥2 off nights to render. `baselineDelta = protocolAverage − baselineAverage` — positive → green, negative → red.

---

### 11.9 Context Factor Insights (Journal Tristate)

**Code:** [`ContextComparisonService.swift:134–277`](Better/Core/Services/ContextComparisonService.swift); UI driver [`ContextFactorDashboardViewModel.swift:56`](Better/Features/Protocol/ContextFactorDashboardViewModel.swift).

- Each factor (`caffeineLate`, `alcohol`, `workout`, `lateMeal`, `highStress`, `screenTimeLate`, `nap`, `travel`, plus synthetic `.protocolTaken`) is a `Bool?` on `SleepContextEntry`. **`nil` is preserved as "unknown" and NOT coerced to false.**
- Sessions grouped by `Bool?` → yes / no / unknown buckets. Unknown excluded from deltas.
- Per-factor deltas: `durationDelta`, `efficiencyDelta`, `deepDelta` (stage-filtered), `remDelta`, `awakeDelta` = `avg(yes) − avg(no)`.
- Reuses `ProtocolComparisonService.confidence` (same 7 / 4 / 2 thresholds).
- `hasMeaningfulDifference` (L277): true when any |delta| ≥ a threshold in `SleepAnalysisThresholds`.
- Dashboard probes `.last30Days` first; if no meaningful signal, falls back to `.all`. Shows top 3 meaningful factors.

---

### 11.10 Biology Tab Metrics

**Code:** [`BiologyViewModel.swift:41–290`](Better/Features/Biology/BiologyViewModel.swift).

- **Window:** last 30 days of HealthKit biometrics + cached sessions.
- **Per-metric value** (`makeMetrics` L114):

| Metric | Latest value source | History |
|---|---|---|
| VO2Max, Weight, LeanMass, BodyFat, BodyTemp, RHR | newest HealthKit sample by `endDate` | last 12 samples sorted |
| HRV | `latestSession.biometrics.hrvAverage` → falls back to `baseline.hrvAverage` | last 12 sessions' `hrvAverage` |
| Blood O2 (SpO2) | session → baseline fallback; if value ≤ 1, multiplied by 100 | same |
| Respiratory rate | session → baseline fallback | same |

- **Trend label** (`trendFromValues` L252): compares first vs last in 12-sample window — `last > first·1.02` → "Increasing", `last < first·0.98` → "Decreasing", else "Stable".
- **Rating bands** (hard-coded L267–290):

| Metric | Bands |
|---|---|
| VO2Max | <35 Low · <45 Fair · <55 Good · else Excellent |
| HRV | ≥60 Strong · ≥40 Stabilizing · else Low |
| RHR | ≤58 Good · ≤68 Fair · else Elevated |
| SpO2 | ≥95 Good · else Watch |

- **Manual entries** (`mergeManualEntries` L218): `ManualBiologyEntry` fills only when the HealthKit value is nil (HK takes precedence).

---

### 11.11 Alerts Generation

**Code:** [`AlertGenerationService.swift:192`](Better/Core/Services/AlertGenerationService.swift) — `buildAlerts`. Defaults in `AlertGenerationSettings.default` (L19).

| Alert kind | Rule |
|---|---|
| `analysisReady` | always (severity 0) |
| `lowScore` | `qualityScore.overall < 70` |
| `sleepDebt` | `goalSeconds − totalSleepTime > 1h` |
| `lowDeepSleep` | detailedStages AND (deep < 60min OR deep < `baseline.deepAverage − deepStdDev`) |
| `lowRemSleep` | detailedStages AND (rem < 75min OR rem < `remAvg − remStdDev`) |
| `highWASO` | `waso > 45min` |
| `lowHRV` | `hrvAvg < baseline.hrvAverage · 0.80` |
| `lowOxygenSaturation` | `avgSpO2 < 0.94` OR `minSpO2 < 0.90` |
| `irregularSchedule` | `bedtimeMinuteStdDev > 60` OR `wakeMinuteStdDev > 60` |
| `improvementTrend` | over last 7 nights: score gained ≥5 OR deep gained ≥15min |
| `missedProtocol` | after cutoff hour 22, no adherence row with `taken=true` for that date |

Alert IDs are **deterministic** (`deterministicUUID("kind|sleepDateKey")`) so re-running the same date+kind dedupes. Local notifications are gated by `localNotificationsEnabled` + authorization, with one digest per `sleepDateKey`.

---

### 11.12 Activity Tab

**Code:** [`ActivityViewModel.swift:64–91`](Better/Features/Activity/ActivityViewModel.swift).

- **Daily activity** (`fetchActivitySummary`): HealthKit sums over `[startOfDay, +1d)` for `stepCount`, `activeEnergyBurned`, `appleExerciseTime`, `appleStandTime` (÷60 → hours), `flightsClimbed`, `distanceWalkingRunning`. Persisted to `DailyActivitySummary`.
- **Status logging** (`saveStatus`): writes `ActivityStatusLog(dateKey, status, note)` with `UserActivityStatus` (sick / injured / traveling / jetLagged / normal).
- **Influence on analysis:** `ResearchAnalysisService` attaches status to each nightly row; nights are flagged `isTravelConfounded` (jetLagged/traveling) and `isConfounded` (those + sick/injured). Confounded nights are NOT removed from the primary delta — they're excluded only from `jetLagAdjustedSleepDifferenceHours` and they **reduce confidence**.

---

### 11.13 Research Analysis — Nightly Rows & Effect Summary

**Code:** [`ResearchAnalysisService.swift`](Better/Core/Services/ResearchAnalysisService.swift).

- **`buildExportPackage` (L20):** capped at 60 days. Fetches sessions, baseline (`BaselineEngine.selectBaseline` with stored fallback), adherence, status logs, daily activity, context entries.
- **`buildNightlyRows` (L89):** joins by `sleepDateKey` → one row with:
  - Raw session metrics (totalSleep h, in-bed h, efficiency %, stage hours, WASO min, latency min, score sub-components, biometrics)
  - **Baseline deltas (L167–173):** `(session.totalSleepTime − baseline.totalSleepAverage)/3600`, efficiency delta in pp, WASO/latency in min, HRV delta
  - **Protocol timing (L117):** `minutesFromProtocolToSleep = (sleepStart − adherence.takenAt) / 60` per taken protocol
  - Activity, status flags, full context tristate fields
- **`effectSummary` (L235):** per protocol — `taken` rows where `protocolIDsTaken.contains(id)`, `notTaken` symmetric. Delta = `avg(taken) − avg(missed)` for sleep h, score, efficiency pp, WASO min, latency min, HRV. The **jet-lag-adjusted** delta uses only `!isConfounded` rows.
- **`timingBuckets` (L282):** minutes from dose to sleep → `>180` early, `60–180` optimal, `<60` late. Only emitted when bucket size ≥5 AND missed ≥5.
- **`confidence` (L436):** requires ≥5 taken AND ≥5 missed (else `insufficient`).

  | Tier | Requirement |
  |---|---|
  | **Strong** | ≥20 taken AND ≥20 missed AND confounderFraction < 0.15 AND ≤1 caveat |
  | **Moderate** | ≥10/10 AND confounderFraction < 0.30 |
  | **Low** | otherwise |

- **`caveats` (L406):** appends strings for low sample (<5), travel/jet-lag presence, sick/injured, missing protocol timing, missing biometrics, non-detailed-stage nights, mixed/in-bed-only nights.
- **`buildInsightSummary` (L302):** ranks protocols where `confidence ≠ insufficient` and `sleepDifferenceHours > 0`, sorted desc — drives Settings "research insight" card.

---

---

## 12. Performance Audit (2026-05-28)

Known hot-spots and sub-optimal patterns. Not regressions — just work to schedule.

### 12.1 Main-thread chart recomputation (medium)

`TrendsViewModel.loadData()` runs `updateChartPoints()` × 4, `recomputeDerivedMetrics()`, and `updateComparisonSummary()` synchronously on `@MainActor`. These iterate over up to 91 days of sessions. On metric/window changes (`selectMetric()`, `selectWindow()`) the same batch runs again.

**Location:** `TrendsViewModel.swift` — `loadData()`, `selectMetric()`, `selectWindow()`.  
**Fix direction:** move point-building loops to a `Task.detached` and publish results back via `@MainActor`; or memoize `metricValue(for:)` per session ID (the cache exists but is cleared on every `loadData()`).

### 12.2 `sortedRecentSessions` re-sorted on every read (low)

`SleepDashboardViewModel.sortedRecentSessions` is a computed property that calls `.sorted { }` on a 60-element array every time the view reads it. Multiple subviews (`SleepStagesCard`, `SleepStageDetailSheet`, biometrics chart) all call this independently in the same render pass.

**Location:** `SleepDashboardViewModel.swift:44`.  
**Fix:** store a sorted copy when `recentSessions` is set; computed property just returns it.

### 12.3 `BiomarkerBaselineService.currentBaseline()` on every data load (low–medium)

Called after every `loadData()` (foreground appearance, every date navigation). Even on a cache hit, the function does an `await loadCached()` DB read. On a miss it runs two `fetchCachedSessions()` queries.

**Location:** `SleepDashboardViewModel.swift` — `refreshBiomarkerBaseline()`.  
**Fix:** keep the baseline in memory on the service; invalidate it only on `SyncCoordinator` post-sync notifications (already has a hook). Read from the in-memory copy on repeated `loadData()` calls within the same session.

### 12.4 TrendsViewModel fetches 91 days on every tab appear (medium)

`loadData()` computes `fetchStart = min(comparisonStart, chronotypeStart)` where `chronotypeStart` is always −91 days. This makes every Trends tab appearance fetch 91 days of sessions even when the user just switched back from another tab with no new data.

**Location:** `TrendsViewModel.swift:289–292`.  
**Fix:** cache `fetchedSessions` and invalidate only when `SyncCoordinator` signals a new sync completed; skip refetch if selected window + metadata unchanged.

### 12.5 `SleepHypnogramView` draws 60 tick-mark Rectangles per render (low)

The `ForEach(0..<60)` tick loop in the redesigned hypnogram creates 60 `Rectangle` views in the layout tree each render. These are purely decorative.

**Location:** `SleepTabView.swift` — `scoreRingHero` ZStack tick block.  
**Fix:** replace with a single `Canvas { }` draw call for the ticks; zero layout nodes.

### 12.6 `SleepTabView` is 2977 lines with no LazyVStack (low)

The main scroll content uses a plain `VStack` inside `ScrollView`. Layout passes are O(N) in view count. With the redesigned cards this is not expensive yet, but the file is approaching maintainability limits.

**Fix direction:** extract hero section, stages section, and block section into separate `@ViewBuilder` functions in separate files (already partially done with `SleepStagesCard`, `LongestSleepBlockCard`). No `LazyVStack` needed for this few cards; main gain is compile time and readability.

### 12.7 No `drawingGroup()` on custom chart views (low)

`SleepHypnogramView`, `SleepStagesStackedBar`, and the Trends `TrendLineChartView` are pure CoreGraphics-style Shape/Path views. Adding `.drawingGroup()` moves compositing to Metal and reduces CPU overdraw during scroll.

---

*Generated: 2026-05-06 · Last refresh: 2026-05-28 (§5/6/11 redesign, §12 perf audit) | Better iOS App*
