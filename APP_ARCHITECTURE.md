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
       │  • Step 4: Compute baseline (rolling 15 or 7-day window)
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
│   ├── Which window (15-day primary or 7-day fallback)
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
  Compute 3 windows simultaneously:
  ┌─────────────┬─────────────────────────────────┐
  │ 30-day      │ Stable context (shown as grey)  │
  │ 15-day      │ Primary active baseline         │
  │ 7-day       │ Recent fallback                 │
  └─────────────┴─────────────────────────────────┘
        │
        ▼
  Pick active baseline:
  • 15+ valid nights in 15-day window? → use 15-day (HIGH confidence)
  •  7–14 valid nights?                → use 7-day  (MEDIUM confidence)
  •  3–6 valid nights?                 → use 7-day  (LOW confidence)
  •  < 3 valid nights?                 → no baseline (UNAVAILABLE)
```

### HealthKit fallback states (when data is missing)

| State | What's shown |
|-------|-------------|
| `permissionDenied` | Banner: "Grant HealthKit access in Settings" |
| `baselineBuilding` | Banner: "Still building your baseline (N/15 nights)" |
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

  Step 3: Assign confidence
  ┌───────────────────────────────────────────────────┐
  │  7+ nights taken AND 7+ not-taken   → HIGH        │
  │  4+ nights taken AND 4+ not-taken   → MEDIUM      │
  │  2+ nights taken AND 2+ not-taken   → LOW         │
  │  Fewer nights                      → UNAVAILABLE  │
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
Baseline preference:         15-day window (fallback: 7-day)
Baseline min nights:         15 for high confidence, 7 for medium, 3 for low
Protocol confidence levels:  7+ taken and 7+ not-taken → high, 4+ and 4+ → medium, 2+ and 2+ → low
Encryption:                  AES-256-GCM, key in iOS Keychain
```

---

*Generated: 2026-05-06 | Better iOS App*
