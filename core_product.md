# Better — Core Product

## What Is This App

Better is an iOS health optimization app that tracks sleep and measures how daily behaviors (supplements, activity, travel, illness) actually affect it. It reads biometric data from Apple HealthKit, processes it into meaningful sleep sessions, runs statistical analysis against logged protocols (supplements/interventions), and surfaces research-grade insights — not just raw numbers.

The underlying philosophy: *observational data over time, with explicit confidence levels, so the user understands when a correlation is real vs noise.* The app stays local-first and keeps sensitive health data encrypted on device.

---

## Five Core Areas

### 1. Sleep Dashboard
Displays the most recent sleep session with full breakdown:
- Total sleep, time in bed, sleep efficiency
- Stage breakdown: Awake, REM, Core, Deep (from Apple Watch)
- Sleep quality ring score (multi-factor calculation — see below)
- Biometric overlay: HRV, resting HR, O2 saturation, respiratory rate
- 30-day calendar heatmap showing quality per night

### 2. Trends / Insights
Charts sleep metrics over 7/30/90-day windows:
- Stacked bar chart for sleep stage composition per night
- Line charts for sleep duration, efficiency, WASO, latency, HRV
- Comparison windows (this week vs last week, etc.)

### 3. Protocol Tracker
Tracks supplement / intervention adherence:
- Log what you took, when, notes
- Explicit protocol usage state per sleep night: taken, not taken, or unknown
- Daily streak tracking
- 30-day impact summary per protocol
- Research-grade statistical comparison: nights taken vs not taken, with unknown nights excluded from the comparison

### 4. Biology Tab
Biometric history and trends:
- HRV baseline, resting heart rate, VO2 max, respiratory rate, blood oxygen
- Each metric shows rating (Good / Fair / Low), trend direction, and history sparkline

### 5. Activity Tab
Daily movement context:
- Steps, active energy, exercise minutes, stand hours, flights climbed, distance
- Manual activity status logging: Active / Traveling / Jet-lagged / Sick / Injured
- Status feeds directly into the research analysis as a confounding variable

### 6. Privacy & Settings
User controls for data and health permissions:
- **Data Inventory** — See what's stored: count of sleep nights, baselines, alerts, adherence logs
- **Delete All Local Data** — Permanent deletion of all sleep summaries, baselines, onboarding answers, and protocol data. Apple Health data is never touched. App resets to onboarding state.
- **Re-sync from Apple Health** — Full refresh of sleep data from HealthKit (useful after app crashes or manual HealthKit edits)
- **HealthKit Permission Status** — View current authorization state and re-request permissions if needed
- **HealthKit Fallback States** — If permission is denied, data is insufficient, or only "in bed" logs exist, the dashboard shows contextual fallback messages (not generic errors)

---

## The Intelligent Layer

### A. Sleep Data Processor (`SleepDataProcessor`)

The core engine. Takes raw HealthKit samples and produces clean, analyzed sleep sessions.

**What it does:**

1. **Interval conflict resolution** — Apple Watch + iPhone can both log overlapping sleep stages. The processor resolves conflicts using a source priority order, keeps the highest-priority segment for each overlapping region.

2. **Session grouping** — Fragments separated by more than 30 minutes of wake time are split into separate sessions (e.g., a nap vs. main sleep).

3. **Sleep Quality Score (0–100)** — Weighted multi-factor calculation:
   - Duration score: 30% weight, linear toward an 8-hour goal
   - Efficiency score: 20% weight (actual sleep ÷ time in bed)
   - REM score: 25% weight, optimal at 20–25% of total sleep
   - Deep sleep score: 25% weight, optimal at 13–23% of total sleep
   - Unspecified sleep (no stage breakdown) gets neutral REM/Deep scores, not penalized

4. **Baseline computation** — Rolling N-day window statistics:
   - Mean and standard deviation for: total sleep, REM, deep, efficiency, WASO, sleep latency, HRV, respiratory rate, O2
   - **Circular statistics** for bedtime and wake time (handles midnight wraparound correctly — standard mean/std would break for times like 11pm vs 1am)
   - Quality-gated: only sessions with at least some real sleep count toward baselines
   - Phase 2.1 baseline selection prefers 14 valid nights, falls back to 7 valid nights, and keeps 30-day stable context for trend/export use
   - Invalid nights are excluded explicitly: short sleep, impossible time-in-bed relationships, missing sleep dates, obvious naps, and no-data/in-bed-only sessions

5. **Biometric summarization** — Aggregates HR, HRV, O2, respiratory from the sleep window into min/max/average/median per session.

### B. Research Analysis Service (`ResearchAnalysisService`)

Takes the processed sleep data and protocol adherence logs and determines if a supplement is actually helping.

**Statistical approach:**

1. **Nightly row construction** — For each night, a single row is built joining:
   - Sleep metrics (duration, efficiency, WASO, latency, quality score)
   - Biometrics (HRV, HR, O2, respiratory)
   - Protocol adherence (which protocols were taken, when, how close to sleep)
   - Protocol usage status per night: taken, not taken, or unknown
   - Baseline deltas (how much each metric deviates from the user's personal baseline)
   - Activity status (Active / Traveling / Sick etc.)

2. **Protocol effect summaries** — For each protocol, compare:
   - Average sleep metrics on **nights taken** vs **nights not taken**
   - Effect size: the raw difference (e.g., "+22 min total sleep")
   - Confounding adjustment: exclude travel/jet-lag nights from the adjusted analysis
   - Unknown nights are counted separately and excluded from the comparison

3. **Confidence scoring** — Explicit data sufficiency gates:
   - **Low**: ≥5 taken nights AND ≥5 not taken nights
   - **Moderate**: ≥10 of each
   - **Strong**: ≥20 of each + confounder fraction < 15% + ≤1 caveat flag

4. **Caveat detection** — Auto-flags:
   - Small sample size
   - High fraction of confounded nights (travel, illness)
   - Missing protocol timing data
   - Missing biometrics
   - Data from multiple sources (mixed-quality inputs)

5. **Insight generation** — Single human-readable statement like:
   *"Magnesium is associated with 28 more minutes of sleep on nights taken (Moderate confidence). Treat this as observational, not causal."*

### C. Research CSV Exporter (`ResearchCSVExporter`)

Full data export pipeline for power users or external analysis:
- `nightly_research_rows.csv` — one row per night, with appended protocol and baseline fields for external analysis
- `protocol_effect_summary.csv` — Effect sizes + confidence per protocol
- `export_metadata.csv` — Export parameters + insights
- Output: ZIP archive with all three CSVs, built without external dependencies (custom ZIP/CRC32 encoder)

New nightly export fields include:
- `baseline_window_used`
- `baseline_total_sleep_minutes`
- `duration_vs_baseline_minutes`
- `protocol_usage_status`
- `protocol_taken`
- `protocol_name`
- `protocol_timing`
- `data_quality_status`
- `comparison_confidence`

---

## Data Architecture

```
HealthKit (Apple Watch + iPhone)
       ↓
HealthKitRepository  →  raw HKSamples
       ↓
SleepDataProcessor   →  SleepSession + SleepBaseline
       ↓
LocalDataRepository  →  SwiftData persistence
       ↓
[Encryption Layer]   →  AES-256-GCM encryption
       ↓
[File Protection]    →  FileProtectionType.complete on SQLite files
       ↓
ViewModels           →  UI display
       ↓
ResearchAnalysisService → NightlyRow + ProtocolEffectSummary
      ↓
ResearchCSVExporter  →  ZIP export
```

**Persistence:** SwiftData with a full domain-model mapping layer. Anchored HealthKit syncs for incremental updates (doesn't re-fetch all history on every launch).

**Security:** Sensitive data (sleep sessions, baselines, onboarding answers, protocol adherence) is encrypted at rest using AES-256-GCM. The encryption key is stored in iOS Keychain with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` protection. SQLite files are also protected with `FileProtectionType.complete`. Non-sensitive settings (theme, notification toggles) remain unencrypted for faster access. Data is local-only — never sent to servers or cloud services.

**Architecture pattern:** MVVM + `@Observable`, repository pattern with protocol-based interfaces, full dependency injection for testability.

---

## Privacy & Security Design

Better is built with privacy-by-design principles:

1. **Local-first, no cloud** — All data stays on the device. No servers, no cloud sync, no accounts required.

2. **Transparent encryption** — Sensitive health data is encrypted at rest using device-level keys. Migration from unencrypted to encrypted storage is automatic and transparent.

3. **User control** — Users can see exactly what data is stored (inventory), delete all local data at any time, and re-sync from HealthKit if needed.

4. **No credential leakage** — Encryption keys are stored in iOS Keychain only, never in app preferences or shared across devices.

5. **Device-bound protection** — Files are protected with `FileProtectionType.complete`, requiring device unlock to access. Background sync is deliberately blocked when device is locked to maintain privacy.

6. **Graceful degradation** — If HealthKit permissions are denied or data is missing, the app shows clear fallback states instead of generic errors, helping users understand what to do.

7. **Deterministic protocol analysis** — Unknown protocol nights stay unknown instead of being silently treated as missed, so comparisons and exported analysis stay honest.

---

## Test Coverage

| Area | Status |
|------|--------|
| `SleepDataProcessor` | 11 tests — edge cases, circular stats, overlaps, gaps |
| `ResearchAnalysisService` | 4 tests — joining, summaries, confidence thresholds, CSV export |
| `LocalDataRepository` | 14 tests — persistence, fetch, sync, ViewModel integration |
| `EncryptionService` | 9 tests — encryption round-trip, Keychain persistence, key reset, disabled-mode passthrough, legacy fallback |
| `PrivacyDataService` | 10 tests — data deletion, inventory counts, migration idempotency, fallback states, mock repo methods |
| `BiologyViewModel` | Not tested |
| `ActivityViewModel` | Not tested |
| `TrendsViewModel` | Not directly tested |

---

## What Makes This Different

Most sleep apps show you the raw Apple Watch data and stop there. Better's value is in the analysis layer:

- Your sleep quality score is **personalized to your own baseline**, not a population average
- Protocol impact is measured against **your own miss nights** as the control group, not others
- Confidence levels prevent the app from claiming a supplement works when the data is insufficient
- Confounding variables (travel, illness) are explicitly identified and adjusted for
- The data is exportable for independent analysis

The core thesis: *better decisions from better evidence, at the individual level.*
