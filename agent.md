# Better Project Agent Guide

This file is the working guide for coding agents contributing to the Better iOS app. Read it before editing code or plans in this repository.

## Project Summary

Better is an iOS sleep tracking app built with SwiftUI. It reads sleep and biometric data from Apple Health, processes wearable sleep samples into nightly sessions, and shows users whether their sleep and protocol adherence are improving over time.

The app has two audiences:

- End users who want an understandable sleep dashboard.
- Researchers or protocol operators who need consistent derived sleep metrics, adherence tracking, and CSV export.

The app should feel like a polished native iOS health dashboard, not a generic web app port.

## Current Repository State

Root:

```text
/Users/nikhilkhatale/Documents/Better
```

Important files and folders:

```text
Better.xcodeproj/                 Xcode project
Better/                           SwiftUI app source
BetterTests/                      Unit tests
BetterUITests/                    UI tests
Sleep Tracking iOS App/           Downloaded Figma Make prototype source
Core_sleep_dashbaord.md           Verified implementation plan
agent.md                          This guide
```

The Swift app currently started as a fresh Xcode template. The implementation plan in `Core_sleep_dashbaord.md` is the source of truth for the sleep dashboard buildout.

## Design Reference

Primary design reference:

```text
Sleep Tracking iOS App/
```

Key prototype files:

```text
Sleep Tracking iOS App/src/app/data/sleepData.ts
Sleep Tracking iOS App/src/app/components/SleepTab.tsx
Sleep Tracking iOS App/src/app/components/TrendsTab.tsx
Sleep Tracking iOS App/src/app/components/ProtocolTab.tsx
Sleep Tracking iOS App/src/app/components/AlertsTab.tsx
Sleep Tracking iOS App/src/app/components/SettingsTab.tsx
Sleep Tracking iOS App/src/app/App.tsx
```

Preserve the prototype's hierarchy and visual direction:

- Dark sleep aesthetic
- Compact iOS dashboard cards
- Sleep score ring
- Baseline comparison
- Sleep stages timeline
- Heart rate, HRV, respiratory summaries
- Protocol adherence and protocol impact
- Smart alerts and reminders

Use native SwiftUI and Swift Charts patterns rather than trying to mechanically copy React components.

## Product Principles

- Apple Health is the source for raw sleep and biometric samples.
- SwiftData is the app's local source of truth for processed sessions, baselines, alerts, adherence, and profile.
- UI should render from cached domain data first, then refresh after sync.
- Do not show fake precision. If REM/deep data is unavailable, say stage detail is unavailable.
- Protocol impact should be framed as correlation unless a proper study design proves causality.
- Health data should stay local unless the user explicitly exports it.
- Research mode must be opt-in.

## Model Selection

Use the strongest available coding model for correctness-sensitive phases:

- Best model: HealthKit processing, SwiftData persistence mapping, sync coordination, background delivery, alert generation, and final test verification.
- Mid-tier model: domain models, app shell, view models, and reusable UI components.
- Lower-cost model: configuration-only work, documentation updates, copy changes, preview scaffolding, and simple placeholder views.

If a phase touches HealthKit sample interpretation, incremental sync, or persistence upsert logic, do not optimize for cost. Those changes are easier to get subtly wrong than they are to review later.

## Architecture

Use this high-level flow:

```text
SwiftUI Views
  -> @Observable ViewModels
  -> Repository Protocols
  -> HealthKitRepository / LocalDataRepository
  -> SleepDataProcessor
  -> SwiftData cache
```

Expected directories:

```text
Better/
├── App/
├── Core/
│   ├── Models/
│   ├── Persistence/
│   ├── DesignSystem/
│   ├── Repositories/
│   ├── Processors/
│   ├── Services/
│   └── Data/
├── Features/
│   ├── Onboarding/
│   ├── Sleep/
│   ├── Trends/
│   ├── Protocol/
│   ├── Alerts/
│   └── Settings/
└── Shared/
    ├── Components/
    └── Extensions/
```

Use MVVM with protocol-based dependency injection. Keep HealthKit, SwiftData, and notification code out of SwiftUI views.

## Platform And Frameworks

Target:

- iOS 26.2+
- SwiftUI
- Observation
- SwiftData
- HealthKit
- Swift Charts
- BackgroundTasks
- UserNotifications

No external dependencies unless the user explicitly approves them. Prefer Apple frameworks.

## HealthKit Rules

HealthKit correctness is the highest-risk part of this app. Follow these rules exactly:

- Request read access only for the initial version.
- Required sleep type: `HKCategoryType(.sleepAnalysis)`.
- Recommended biometric types:
  - heart rate
  - HRV SDNN
  - oxygen saturation
  - respiratory rate
- Use `HKCategoryValueSleepAnalysis(rawValue:)` for sleep stage mapping.
- `inBed` is not sleep. Never count it as total asleep time.
- Count asleep duration only from:
  - `asleepUnspecified`
  - `asleepCore`
  - `asleepDeep`
  - `asleepREM`
- Count `awake` as WASO only inside the sleep session window.
- Resolve overlapping samples before calculating totals.
- Do not directly sum raw HealthKit sample durations.
- Use observer queries for change notifications.
- Use anchored object queries for incremental changes.
- Always call the HealthKit observer completion handler after processing.
- Include `com.apple.developer.healthkit.background-delivery` if enabling background delivery.
- Test real HealthKit background delivery on a physical iPhone. The Simulator is not sufficient.

HealthKit read permissions are privacy-preserving and partly opaque. Do not build UI that claims exact read permission status for each read type. Treat successful authorization as "request completed," then verify by querying data.

## Sleep Processing Rules

The pure sleep processing layer should live in:

```text
Better/Core/Processors/SleepDataProcessor.swift
```

Core product rules:

- Minimum valid sleep session: more than 5 minutes asleep.
- Session gap threshold: 30 minutes.
- Baseline window: user setting, usually 15 or 30 days.
- Sleep date key is evening-based, not midnight-naive.

Processing should:

1. Convert raw HealthKit samples to normalized intervals.
2. Drop invalid intervals.
3. Keep source metadata.
4. Resolve overlaps.
5. Prefer detailed wearable stage data over low-fidelity/manual data.
6. Group intervals into sessions.
7. Filter short sessions.
8. Compute duration, stage totals, efficiency, latency, WASO, and quality score.
9. Attach biometrics for the final sleep window.
10. Mark data quality.

Data-quality states should include:

- detailed stages
- unspecified sleep only
- in-bed only
- mixed sources
- no data

If only unspecified sleep exists, compute total sleep but do not penalize REM/deep as zero.

## UI Data Mapping

Every UI metric must come from a named domain field.

Sleep tab:

- Sleep score: `SleepSession.qualityScore.overall`
- Time asleep: asleep stage duration
- Time in bed: `inBed` duration or fallback session span
- Efficiency: asleep divided by in-bed time
- Latency: first asleep minus first in-bed
- WASO: awake intervals after sleep onset
- Stage chart: cleaned `SleepStage` intervals
- Baseline card: latest `SleepBaseline`
- Heart rate: average/min/max during sleep window
- HRV: overnight HRV summary
- Respiratory rate: overnight average
- Schedule consistency: baseline-window bedtime/wake variability

Trends tab:

- Query cached sessions by range.
- Show RuleMark or equivalent baseline line where useful.
- Do not chart missing biometrics as zero.

Protocol tab:

- Adherence is local SwiftData state.
- Protocol impact joins adherence rows to sleep sessions.
- Use "associated with" language for impact.

Alerts tab:

- Alerts are generated from processed sessions, baseline, thresholds, and adherence.
- Avoid duplicate alerts for the same session and rule.

Settings tab:

- Show last successful sync and connected Health sources.
- Export derived nightly rows only.

## Persistence Rules

Use SwiftData for local storage.

Keep domain structs separate from `@Model` persistence classes. Add mapping helpers rather than letting SwiftData classes spread through the UI.

Persist:

- processed sleep sessions
- nightly biometric summaries
- baselines
- protocol adherence
- alerts
- user profile
- HealthKit sync anchors

Use JSON `Data` for nested arrays like stages, sources, and biometrics. Use stable IDs and upserts to avoid duplicate rows.

## Background Sync Rules

Use two mechanisms:

- HealthKit observer query with background delivery for Health database changes.
- `BGAppRefreshTask` as an opportunistic backup.

Do not promise hourly background sync. iOS decides actual scheduling.

Task identifier:

```text
ai.better-health.Better.sleep-sync
```

Background task handlers must:

- Register early.
- Schedule the next refresh.
- Set an expiration handler.
- Complete with `setTaskCompleted(success:)`.
- Keep work bounded.

## Design System

Use the prototype palette as the initial native design system:

```text
Background: #080812
Card:       #11112A
Card 2:     #191932
Card 3:     #22224A
Text:       #FFFFFF
Subtext:    #8E8E9A
Border:     #222240
Brand:      #6366F1
Deep:       #5E5CE6
Core:       #30B0C7
REM:        #64D2FF
Awake:      #636366
Green:      #30D158
Orange:     #FF9F0A
Red:        #FF453A
Purple:     #BF5AF2
Teal:       #2DD4BF
```

Prefer native controls:

- `TabView` for tabs
- segmented pickers for windows and metrics
- `ShareLink` for exports
- Swift Charts for trends
- SF Symbols for icons

Avoid decorative UI that does not serve the dashboard. The app should feel dense, calm, and scan-friendly.

## Testing Expectations

Prioritize tests for pure processing and data correctness.

Unit tests should cover:

- HealthKit stage mapping
- overlapping samples
- `inBed` not counted as sleep
- 5-minute filtering
- 30-minute gap stitching
- midnight-crossing sleep date keys
- unspecified-only data
- source preference
- baseline computation
- alert generation
- CSV export

ViewModel tests should use mock repositories.

UI tests should run with:

```text
--uitesting
```

In UI testing mode, do not present real HealthKit permission prompts or schedule real notifications.

## Build And Verification

If `xcodebuild` fails with a Command Line Tools developer directory error, select full Xcode:

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

Typical build command:

```bash
xcodebuild -project Better.xcodeproj -scheme Better -destination 'platform=iOS Simulator,name=iPhone 15 Pro' build
```

Full HealthKit validation requires a physical iPhone paired with Apple Watch.

## Coding Guidelines

- Prefer small, focused Swift files.
- Keep views declarative and view models state-oriented.
- Keep processors pure and deterministic.
- Avoid ad hoc string parsing for data formats where typed APIs are available.
- Use `async/await` for repository APIs.
- Mark cross-actor types `Sendable` where appropriate.
- Do not pass `ModelContext` across actors.
- Use `@MainActor` explicitly for view models when helpful.
- Do not introduce third-party packages without approval.
- Do not rewrite unrelated files or generated project metadata unnecessarily.

## Documentation Source Of Truth

Use these files together:

- `Core_sleep_dashbaord.md` for the phase-by-phase implementation plan.
- `agent.md` for project conventions and agent operating rules.
- The downloaded prototype folder for UI reference and mock data shape.

When in doubt, preserve health-data correctness over UI convenience.
