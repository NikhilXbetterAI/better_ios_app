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
│              SLEEP TAB                                   │
│                                                         │
│  ┌─────────────────┐   ← SleepQualityRingView           │
│  │    Score: 84    │     Score = 30% duration            │
│  │   ●●●●●●●●○     │            + 20% efficiency         │
│  └─────────────────┘            + 25% deep sleep        │
│                                 + 25% REM sleep         │
│  Hypnogram (stage timeline) ← SleepHypnogramView        │
│  ████░░██████░░░░████  (Awake/Core/Deep/REM bars)       │
│                                                         │
│  vs. Your Baseline  ← SleepVsBaselineView               │
│  Deep sleep:  +12 min  ▲                                │
│  Total sleep: -18 min  ▼                                │
│  HRV:         +4 ms    ▲                                │
│  (baseline = rolling 15-day average of valid nights)    │
│                                                         │
│  Biometrics  ← BiometricSummaryView                     │
│  HR avg: 52 bpm  |  HRV: 68 ms  |  SpO2: 97%           │
│                                                         │
│  Schedule Consistency ← ScheduleConsistencyView         │
│  Bedtime variance: ±23 min                              │
│  Wake time variance: ±31 min                            │
│                                                         │
│  [Calendar] ← tap to browse any historical night        │
└─────────────────────────────────────────────────────────┘
```

### How SleepDashboardViewModel loads data

```
User opens Sleep tab
        │
        ▼
SleepDashboardViewModel.onAppear()
        │
        ├──▶ LocalDataRepository.fetchLatestSession()
        │         Returns: today's SleepSession
        │
        ├──▶ LocalDataRepository.fetchLatestBaseline()
        │         Returns: most recent SleepBaseline
        │
        └──▶ SyncCoordinator.performForegroundRefresh()
                  (fetches last 36 hours from HealthKit,
                   re-processes, updates DB if changed)

User taps a calendar date
        │
        ▼
SleepDashboardViewModel.selectDate(key:)
        │
        ├──▶ LocalDataRepository.fetchSession(for date)
        └──▶ LocalDataRepository.fetchLatestBaseline()
                  (baseline is computed from all nights up to that point)
```

### Baseline selection logic

```
BaselineEngine.selectBaseline()

  ALL stored nights
        │
        ▼
  Filter valid nights:
  • Sleep duration 2–14 hours
  • Data quality is not "in-bed only" or "no data"
        │
        ▼
  Compute 3 windows simultaneously (suffix of valid sessions sorted by date):
  ┌─────────────┬─────────────────────────────────┐
  │ 30-day      │ Stable context (computed if ≥1) │
  │ 14-day      │ Primary active baseline (≥14)   │
  │  7-day      │ Recent fallback (≥7)            │
  └─────────────┴─────────────────────────────────┘
        │
        ▼
  Active baseline = primary (14-day) ?? recent (7-day)
  Confidence:
  • ≥14 valid nights → HIGH
  •  7–13            → MEDIUM
  •  3–6             → LOW   (still uses 7-day if available)
  •  < 3             → UNAVAILABLE
```

### HealthKit fallback states (when data is missing)

| State | What's shown |
|-------|-------------|
| `permissionDenied` | Banner: "Grant HealthKit access in Settings" |
| `baselineBuilding` | Banner: "Still building your baseline (N/14 nights)" |
| `noSleepStages` | Banner: "Only 'in bed' data found — wear your Watch to sleep" |
| `noData` | Banner: "No sleep data for this date" |
| Normal | Full dashboard |

---

## 6. Insights / Trends — Deep Dive

### What you see

```
┌──────────────────────────────────────────────────────────┐
│              INSIGHTS TAB                                 │
│                                                          │
│  [7d]  [15d]  [30d]  ← TrendWindowPickerView            │
│                                                          │
│  Metric: [Deep Sleep ▼]  ← TrendMetricSelectorView      │
│                                                          │
│  Line chart  ← TrendLineChartView                        │
│  90┤                          ●                          │
│  75┤      ●   ●         ●   ●   ●                        │
│  60┤  ●     ●   ●   ●                                    │
│    └────────────────────────── days                      │
│    ---- baseline average (grey dashed line)              │
│                                                          │
│  Baseline delta chart ← BaselineComparisonChartView      │
│  Shows: how each night compared to YOUR baseline         │
│                                                          │
│  Stage bar chart  ← StageStackedBarView                  │
│  Shows: REM / Deep / Core / Awake per night              │
│                                                          │
│  Protocol impact ← ProtocolImpactView                    │
│  Shows: nights where you took magnesium vs. didn't       │
└──────────────────────────────────────────────────────────┘
```

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

## 7b. Protocol Formula Tracking (V1) — Deep Dive

Layered on top of the legacy Protocol tab, **Protocol Formula Tracking** reframes the domain around named formula versions (V1 → V2 …) with per-night logs and a frozen baseline of pre-protocol nights. The V1 surface is gated behind the `better.protocol.useFormulaTrackingUI` UserDefaults flag — legacy Protocol tab is the default.

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

### Files (V1)

- `Core/Models/ProtocolFormulaModels.swift` — domain types.
- `Core/Persistence/PersistenceModels.swift` — schema chain + 4 new `@Model` classes.
- `Core/Repositories/LocalDataRepository.swift` — formula/log/edit/snapshot CRUD.
- `Core/Services/ProtocolBaselineService.swift` — bounded-window freeze.
- `Core/Services/ProtocolAdherenceMigrationService.swift` — one-shot legacy import.
- `Core/Services/ProtocolFormulaAnalysisService.swift` — snapshot, rollup, impact summary.
- `Features/ProtocolFormula/` — view + view-model layer, gated behind the flag.

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
| [`Core/Models/SleepModels.swift`](Better/Core/Models/SleepModels.swift) | `SleepSession`, `SleepBaseline`, `SleepQualityScore`, `SleepStage`, `SleepSource` |
| [`Core/Models/ProtocolModels.swift`](Better/Core/Models/ProtocolModels.swift) | `ProtocolItem`, `ProtocolAdherence`, `SleepAlert`, `UserProfile` |
| [`Core/Models/ResearchAnalysisModels.swift`](Better/Core/Models/ResearchAnalysisModels.swift) | `NightlyResearchRow`, `ProtocolEffectSummary`, `ResearchExportPackage` |
| [`Core/Models/BiometricModels.swift`](Better/Core/Models/BiometricModels.swift) | `BiometricSample`, `BiologyMetric`, `NightlyBiometricSummary` |
| [`Core/Models/ActivityStatusModels.swift`](Better/Core/Models/ActivityStatusModels.swift) | `ActivityStatusLog`, `UserActivityStatus`, `DailyActivitySummary` |
| [`Core/Models/SleepContextEntry.swift`](Better/Core/Models/SleepContextEntry.swift) | `SleepContextEntry` — 8 tristate behavioral fields + self-report |

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

### Security

| File | What it does |
|------|-------------|
| [`Core/Security/EncryptionService.swift`](Better/Core/Security/EncryptionService.swift) | AES-256-GCM encrypt/decrypt. Caches key in memory with a lock |
| [`Core/Security/KeychainService.swift`](Better/Core/Security/KeychainService.swift) | Store/load/delete the encryption key in iOS Keychain |
| [`Core/Security/DataMigrationService.swift`](Better/Core/Security/DataMigrationService.swift) | One-shot migration of old unencrypted records to encrypted storage |

### Feature ViewModels

| File | What it does |
|------|-------------|
| [`Features/Sleep/SleepDashboardViewModel.swift`](Better/Features/Sleep/SleepDashboardViewModel.swift) | State for Sleep tab: selected date, sessions, baseline, fallback state |
| [`Features/Trends/TrendsViewModel.swift`](Better/Features/Trends/TrendsViewModel.swift) | Computes chart data points for selected metric and window |
| [`Features/Protocol/ProtocolViewModel.swift`](Better/Features/Protocol/ProtocolViewModel.swift) | Adherence checklist, streak, chart points, and research export entry point |
| [`Features/Protocol/ProtocolComparisonDashboardViewModel.swift`](Better/Features/Protocol/ProtocolComparisonDashboardViewModel.swift) | Windowed protocol effect summaries with counts, insights, and confidence |
| [`Features/Protocol/ProtocolImpactChartView.swift`](Better/Features/Protocol/ProtocolImpactChartView.swift) | Protocol impact summary, before/after improvement chart, and night history strip |
| [`Features/Protocol/ContextFactorDashboardViewModel.swift`](Better/Features/Protocol/ContextFactorDashboardViewModel.swift) | Context journal form and insights |
| [`Features/Settings/SettingsViewModel.swift`](Better/Features/Settings/SettingsViewModel.swift) | Profile settings, export logic, research insight summary |

---

## Quick Reference: Key Formulas

```
Sleep Quality Score (0–100)
  = (duration_score × 0.30)
  + (efficiency_score × 0.20)
  + (deep_sleep_score × 0.25)
  + (rem_sleep_score × 0.25)

Session split threshold:     > 30 minutes awake gap → new session
Data retention:              60 days
Background sync interval:    every 6 hours
Baseline preference:         14-day window (fallback: 7-day; 30-day = stable context)
Baseline min nights:         14 → high, 7–13 → medium, 3–6 → low confidence
Protocol confidence levels:  min(taken,notTaken) ≥7 → high, 4–6 → medium, 2–3 → low
Encryption:                  AES-256-GCM, key in iOS Keychain
```

---

## 11. Metric Calculation Reference

This section is the **authoritative map from each number you see in the UI back to the exact code that produces it**. Every formula is sourced from real files — paths and line numbers are included so you can jump in.

---

### 11.1 Sleep Quality Score (0–100)

**Where it's shown:** Sleep tab ring, Trends "Sleep Score" line chart, Protocol Impact "Score" band, every nightly CSV row.

**Code:** [`SleepDataProcessor.swift:206–246`](Better/Core/Processors/SleepDataProcessor.swift) — `computeQualityScore()`; helper `rangedScore` at lines 505–516.

**Inputs:** `totalSleepTime`, `efficiency`, `remDuration`, `deepDuration`, `dataQuality`, plus `sleepGoalHours` from `UserProfile` (default 8h).

**Sub-scores (each 0–100):**

```
durationScore   = clamp(totalSleepTime / (goalHours · 3600) · 100, 0, 100)
                  linear ramp to goal, capped at 100

efficiencyScore = clamp(efficiency / 0.92 · 100, 0, 100)
                  target efficiency = 92%

remScore        = rangedScore(remDuration / totalSleepTime, low=0.20, high=0.25)
deepScore       = rangedScore(deepDuration / totalSleepTime, low=0.13, high=0.23)
```

**`rangedScore(ratio, low, high)`** — returns:
- `100` if ratio is inside the [low, high] band
- `ratio / low · 100` if below the band
- `(1 − (ratio − high) / (high · 1.75)) · 100` if above the band, clamped to [0, 100]

**Composite:**

```
detailedStages session:
  overall = 0.30·duration + 0.20·efficiency + 0.25·rem + 0.25·deep

unspecifiedSleepOnly session (no stage breakdown):
  overall = 0.60·duration + 0.40·efficiency       (rem/deep forced to 0)
  isPartial = true                                (UI shows a "partial" badge)
```

Edge cases: `totalSleepTime == 0` → rem/deep ratios = 0; final value always clamped 0–100.

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

**Where it's shown:** "vs Baseline" cards on Sleep tab, dashed reference line on Trends charts, deltas in every CSV row.

**Code:** [`BaselineEngine.swift:36–110`](Better/Core/Services/BaselineEngine.swift) for selection; [`SleepDataProcessor.swift:27–65`](Better/Core/Processors/SleepDataProcessor.swift) (`computeBaseline`) for the math.

**Valid-night filter** (`isValidNight`, L85–108): valid `sleepDateKey`, `2h < totalSleepTime ≤ 14h`, `totalInBedTime ≥ totalSleepTime`, dataQuality ≠ `inBedOnly`/`noData`, all durations ≥ 0, efficiency ∈ [0,1], `startDate < endDate`.

**Window selection:** valid sessions sorted ascending by `sleepDateKey`, then:
- `stable` = `suffix(30)` if any exist
- `primary` = `suffix(14)` only if there are ≥14
- `recent` = `suffix(7)` only if there are ≥7
- `activeBaseline = primary ?? recent` (30-day stays as a separate "stable context" column, never the active comparator)

**Computation per window** (`computeBaseline`):
- Further drops `inBedOnly`/`noData`/`totalSleepTime < 300s`
- Stage averages (REM, Deep) computed **only over `detailedSessions`** — `unspecifiedSleepOnly` is excluded to avoid skewing
- Mean + **population std dev** (variance ÷ N) for: totalSleep, REM, Deep, efficiency, WASO, latency, HRV avg, RR avg, SpO2 avg
- **Circular statistics** for bedtime / wake (L464–488): minute-of-day → angle `θ = m · 2π/1440`, average sin & cos, `atan2` → mean angle → back to minutes. Std dev uses `circularMinuteDistance` = `min(|Δ|, 1440 − |Δ|)` so midnight crossings don't break the average.

---

### 11.5 "vs Baseline" Deltas (Sleep Tab)

**Code:** [`SleepVsBaselineView.swift`](Better/Features/Sleep/SleepVsBaselineView.swift) (lines 10–62, 160–183, 218–234).

| UI element | Formula |
|---|---|
| Total sleep diff | `(session.totalSleepTime − baseline.totalSleepAverage) / 60` minutes |
| Deep / REM / Latency cards | same: `(session − baseline.{deep,rem,latency}Average) / 60` |
| Efficiency diff | `(session.efficiency − baseline.efficiencyAverage) · 100` percentage points |
| Bedtime / wake row | `diff = sessionMinutes − baselineMinuteAverage`, wrapped to ±720 min for midnight crossings; "earlier" if diff<0, "later" if diff>0 |

Sign is mapped through each metric's `higherIsBetter` flag to color green (better) or red (worse).

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

*Generated: 2026-05-06 · Last refresh: 2026-05-19 (§11 added) | Better iOS App*
