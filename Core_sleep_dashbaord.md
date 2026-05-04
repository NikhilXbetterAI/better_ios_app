# Better Sleep Dashboard - Verified Production Implementation Plan

Last updated: 2026-05-04

## Purpose

This document verifies and updates the existing implementation plan for the Better iOS sleep dashboard. It is based on:

- The current local Xcode project at `/Users/nikhilkhatale/Documents/Better`
- The downloaded Figma Make prototype source in `Sleep Tracking iOS App/`
- Apple's current HealthKit and BackgroundTasks requirements
- A production-oriented Apple Health sync model for reading wearable sleep data and presenting it in SwiftUI

The original phase structure is sound. The main changes needed are around HealthKit correctness, background delivery, source deduplication, authorization semantics, explicit Info.plist setup, and explicit mapping from HealthKit data to UI cards.

## Current Project Verification

The repo started as a fresh SwiftUI Xcode template, and Phase 0 now adds the production configuration needed for the sleep dashboard:

```text
Better/
├── Better.xcodeproj/
├── Better/
│   ├── App/
│   │   ├── AppTab.swift
│   │   ├── AppEnvironment.swift
│   │   ├── BetterApp.swift
│   │   └── RootTabView.swift
│   ├── Better.entitlements
│   ├── Info.plist
│   └── Assets.xcassets/
├── BetterTests/
├── BetterUITests/
├── current_completed_phase.md
└── Sleep Tracking iOS App/
```

Current verification notes:

- `IPHONEOS_DEPLOYMENT_TARGET = 26.2` exists in the project-level Debug and Release configs.
- `IPHONEOS_DEPLOYMENT_TARGET = 26.2` exists in the app, unit-test, and UI-test target configs.
- The app target now uses an explicit `Better/Info.plist` and entitlements file.
- The template entry points have been replaced by the Phase 1 app shell under `Better/App/`.
- `xcodebuild` could not be run from this shell because the active developer directory is Command Line Tools, not full Xcode. Local verification should run after selecting Xcode with `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`.

The downloaded Figma prototype includes real implementation references:

- `Sleep Tracking iOS App/src/app/data/sleepData.ts`
- `Sleep Tracking iOS App/src/app/components/SleepTab.tsx`
- `Sleep Tracking iOS App/src/app/components/TrendsTab.tsx`
- `Sleep Tracking iOS App/src/app/components/ProtocolTab.tsx`
- `Sleep Tracking iOS App/src/app/components/AlertsTab.tsx`
- `Sleep Tracking iOS App/src/app/components/SettingsTab.tsx`

The prototype's strongest UI concepts should be preserved:

- Dark palette: `#080812`, `#11112A`, `#191932`, `#22224A`, brand indigo `#6366F1`
- Five tabs: Sleep, Insights/Trends, Protocol, Alerts, Settings
- Sleep score ring
- Baseline comparison card
- Sleep stage timeline and stage bars
- Heart rate and HRV summary
- Respiratory rate summary
- Schedule consistency
- Protocol adherence and protocol impact
- Smart alerts and notification settings

## Verdict on the Original Plan

The original plan is directionally correct and worth keeping:

- iOS 26.2 is an acceptable baseline if the app is intentionally limited to the current OS generation.
- MVVM plus repository protocols is appropriate.
- `SleepDataProcessor` as pure logic is the right test seam.
- SwiftData should cache computed sessions, baselines, alerts, profile, and adherence.
- Swift Charts is suitable for hypnograms and trends.
- The 5-minute minimum sleep filter is correct as a product rule.
- Rolling personal baseline is the correct framing for research and consumer use.

The plan needs these production corrections:

- Add `com.apple.developer.healthkit.background-delivery` to entitlements if using HealthKit background delivery on iOS 15+.
- `requestAuthorization` returning `true` means the authorization request completed, not that every read permission was granted. The UI must handle "authorized but no readable data" separately.
- HealthKit read permissions are intentionally opaque. Do not build logic that expects an exact read-authorization status per type.
- Observer queries must always call their completion handler after processing updates.
- Observer queries should be registered early in app startup if relying on background delivery.
- Use an `HKAnchoredObjectQuery` for incremental fetches after observer notifications; observer queries tell you that something changed, not exactly what changed.
- Do not double-count overlapping HealthKit sleep samples. `inBed` commonly overlaps stage samples.
- Sleep stage composition must count asleep stages only: `asleepUnspecified`, `asleepCore`, `asleepDeep`, `asleepREM`. `inBed` is not sleep.
- `awake` should contribute to wake-after-sleep-onset and efficiency only when it falls inside the selected sleep window.
- Source handling must prefer high-fidelity staged Apple Watch data, but must not blindly discard all other samples if they fill gaps.
- Background sync cannot be considered validated on Simulator. HealthKit background delivery must be tested on a physical iPhone paired with Apple Watch.
- Generated Info.plist build settings can become awkward for arrays. For production clarity, use an explicit `Info.plist` instead of relying only on `INFOPLIST_KEY_*` settings.

## Apple Health Data Model

### HealthKit Types To Read

Required:

```swift
HKCategoryType(.sleepAnalysis)
```

Recommended for the dashboard:

```swift
HKQuantityType(.heartRate)
HKQuantityType(.heartRateVariabilitySDNN)
HKQuantityType(.oxygenSaturation)
HKQuantityType(.respiratoryRate)
```

Optional later:

```swift
HKQuantityType(.restingHeartRate)
HKQuantityType(.appleSleepingWristTemperature)
HKQuantityType(.environmentalAudioExposure)
```

Do not request write access for sleep in the first version. This app reads Apple Watch and Health data, computes local insights, and stores derived records in SwiftData. Requesting write permissions increases user concern and review surface without helping the initial dashboard.

### Sleep Stage Mapping

Use `HKCategoryValueSleepAnalysis(rawValue:)` rather than hardcoding integer switches wherever possible.

The effective mapping is:

| HealthKit value | App stage | Counts as asleep | UI usage |
|---|---:|---:|---|
| `.inBed` | `inBed` | No | Time in bed, sleep window boundary |
| `.asleepUnspecified` / deprecated `.asleep` raw value | `unspecified` | Yes | Total asleep, excluded from stage-quality composition if no detailed stages |
| `.awake` | `awake` | No | WASO, efficiency, hypnogram |
| `.asleepCore` | `core` | Yes | Total asleep, stage charts |
| `.asleepDeep` | `deep` | Yes | Total asleep, deep sleep, quality score |
| `.asleepREM` | `rem` | Yes | Total asleep, REM sleep, quality score |

Important rule: a session with only `inBed` and no asleep samples is not a sleep session. A session with only `asleepUnspecified` is valid for total asleep duration but should have `stageDetailQuality = unspecifiedOnly`, and REM/deep insights should be hidden or marked unavailable.

### Quantity Units

Use explicit HealthKit units:

```swift
heartRate: HKUnit.count().unitDivided(by: .minute()) // BPM
hrvSDNN: HKUnit.secondUnit(with: .milli)             // ms
oxygenSaturation: HKUnit.percent()                  // 0.95, display as 95%
respiratoryRate: HKUnit.count().unitDivided(by: .minute()) // breaths/min
```

For SpO2, multiply by 100 for display if using `.percent()` values.

### Sleep Window

Use an evening-based sleep day:

- A sleep session that starts after noon belongs to the following morning's sleep date.
- A sleep session that starts before noon belongs to that same calendar date.
- The dashboard title should show "Last Night's Sleep" after a completed morning session and "Tonight's Sleep" if a current in-bed/sleep session is in progress.

Persist both:

- `startDate` and `endDate` for exact timeline rendering
- `sleepDateKey` for fast "night of" queries and charts

## How Data Flows Into The UI

### Sleep Tab

| UI element | Backing source | Computation |
|---|---|---|
| Sleep score ring | `SleepSession.qualityScore.overall` | duration 30%, efficiency 20%, REM 25%, deep 25%; mark partial if detailed stages unavailable |
| Time asleep | HealthKit sleep stage intervals | Sum `asleepUnspecified + core + deep + rem`, after overlap cleanup |
| Time in bed | HealthKit `inBed` when available, otherwise session span | Prefer `inBed`; fallback to earliest asleep/awake start through latest end |
| Efficiency | Derived | `totalAsleep / timeInBed`, capped 0...1 |
| Latency | Derived | First asleep start minus first in-bed start, if inBed exists |
| WASO | HealthKit awake intervals | Sum awake intervals between first asleep and final wake/end |
| Bed/wake time | Session boundaries | Bed = first inBed or first stage; wake = final stage end |
| Baseline comparison | SwiftData cached baseline | Compare latest session against 15/30-day personal rolling baseline |
| Sleep timeline/hypnogram | `SleepSession.stages` | Render cleaned intervals with Swift Charts `RectangleMark` |
| Stage bars | Stage totals | Deep, core, REM, awake percentages; hide detailed percentages when only unspecified data exists |
| Heart rate card | HK heart-rate samples inside sleep window | Average/min/max and optional sparkline |
| HRV row | HK HRV SDNN samples inside sleep window | Average or median overnight HRV |
| Respiratory rate | HK respiratory samples inside sleep window | Average breaths/min |
| Schedule consistency | Cached sessions | Standard deviation of bedtime and wake time over selected baseline window |

### Trends Tab

| UI element | Backing source | Computation |
|---|---|---|
| 7/14/30-day selector | Cached `SleepSession` rows | Query by date range |
| Score chart | Cached sessions | Daily quality score |
| Duration chart | Cached sessions | Total asleep hours |
| Stage stacked bars | Cached sessions | Percent or minutes by stage |
| HRV trend | Cached biometrics summary | Nightly HRV average/median |
| WASO/latency chart | Derived from sessions | WASO minutes and latency minutes |
| Baseline line | `SleepBaseline` | RuleMark at personal average |
| Protocol impact | Sessions + adherence rows | Compare adherent vs non-adherent nights; label as correlation, not causation |

### Protocol Tab

| UI element | Backing source | Computation |
|---|---|---|
| Active protocol card | Seed JSON + SwiftData profile/adherence | Current protocol item and dose/instructions |
| Mark taken | SwiftData adherence row | Save timestamp and `taken = true` |
| Streak | Adherence rows | Consecutive nights with `taken = true` |
| 21-day heatmap | Adherence rows | Boolean day cells |
| Protocol impact | Sessions joined to adherence | Compare selected metrics on taken vs missed nights |

### Alerts Tab

| UI element | Backing source | Computation |
|---|---|---|
| Analysis ready notification | Latest processed session | Created after successful sync and scoring |
| Low score alert | Session + threshold | Score below user setting, default `< 70` |
| Low deep / REM alert | Session + baseline | Below absolute or baseline-adjusted threshold |
| Sleep debt warning | Last 7 days vs goal | Accumulated deficit exceeds threshold |
| Irregular schedule | Baseline sessions | Bed/wake variability exceeds threshold |
| Missed protocol | Adherence | No protocol log by configured cutoff |
| Reminder toggles | Profile/settings | Schedule/cancel local notifications |

### Settings Tab

| UI element | Backing source | Notes |
|---|---|---|
| Health status | HealthKit availability + last successful query | Do not claim exact read permission status |
| Connected devices | `HKSourceRevision` from recent sleep samples | Display source name/product type when available |
| Sleep goal slider | `UserProfile.sleepGoalHours` | Affects score and sleep debt |
| Baseline window picker | `UserProfile.baselineWindowDays` | 15 or 30 days |
| Research mode | `UserProfile.isResearchMode` | Unlocks export and more detailed protocol charts |
| CSV export | Cached sessions + adherence | No raw HealthKit identifiers; include derived nightly rows |

## Updated Phase Plan

## Phase 0 - Project Configuration And Build Unblock

Goal: make the project compile on iOS 26.2+ and configure HealthKit correctly before app code is added.

Files:

- `Better.xcodeproj/project.pbxproj`
- `Better/Better.entitlements`
- `Better/Info.plist`

Tasks:

1. Set every app/test deployment target to `26.2`.
2. Add HealthKit capability entitlement:

```xml
<key>com.apple.developer.healthkit</key>
<true/>
```

3. Add HealthKit background delivery entitlement:

```xml
<key>com.apple.developer.healthkit.background-delivery</key>
<true/>
```

4. Link entitlements in app target Debug and Release:

```text
CODE_SIGN_ENTITLEMENTS = Better/Better.entitlements
```

5. Prefer an explicit `Better/Info.plist` for production clarity, with:

```xml
<key>NSHealthShareUsageDescription</key>
<string>Better reads your sleep, heart, HRV, oxygen saturation, and respiratory data from Apple Health to show sleep trends and protocol insights.</string>
<key>BGTaskSchedulerPermittedIdentifiers</key>
<array>
    <string>ai.better-health.Better.sleep-sync</string>
</array>
<key>UIBackgroundModes</key>
<array>
    <string>fetch</string>
</array>
```

6. Set:

```text
GENERATE_INFOPLIST_FILE = NO
INFOPLIST_FILE = Better/Info.plist
```

7. Add framework usage in code only; SwiftPM dependencies are not needed.
8. Verify in Xcode:

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
xcodebuild -project Better.xcodeproj -scheme Better -destination 'platform=iOS Simulator,name=iPhone 15 Pro' build
```

Acceptance criteria:

- Project builds with placeholder UI.
- App target has HealthKit and background delivery entitlements.
- Info.plist contains Health usage string and background task identifier.

## Phase 1 - Domain Models, Persistence, Design System, App Shell

Goal: create the app skeleton and all core types without touching HealthKit yet.

### Domain Models

Create `Better/Core/Models/`.

Required types:

- `SleepStageType`
- `SleepStage`
- `SleepSession`
- `SleepBaseline`
- `SleepQualityScore`
- `BiometricType`
- `BiometricSample`
- `NightlyBiometricSummary`
- `SleepAlert`
- `ProtocolItem`
- `ProtocolAdherence`
- `UserProfile`
- `SleepSource`
- `SleepDataQuality`

Production additions to the original plan:

```swift
enum SleepDataQuality: String, Codable, Sendable {
    case detailedStages
    case unspecifiedSleepOnly
    case inBedOnly
    case mixedSources
    case noData
}
```

```swift
struct SleepSource: Codable, Hashable, Sendable {
    var name: String
    var bundleIdentifier: String?
    var productType: String?
    var operatingSystemVersion: String?
}
```

`SleepSession` should include:

- `id`
- `sleepDateKey`
- `startDate`
- `endDate`
- `inBedStartDate`
- `inBedEndDate`
- `stages`
- `sources`
- `dataQuality`
- `totalInBedTime`
- `totalSleepTime`
- `awakeDuration`
- `coreDuration`
- `deepDuration`
- `remDuration`
- `unspecifiedSleepDuration`
- `sleepLatency`
- `waso`
- `efficiency`
- `qualityScore`
- `biometrics`

### SwiftData Persistence

Create `Better/Core/Persistence/PersistenceModels.swift`.

Use `@Model` classes:

- `StoredSleepSession`
- `StoredNightlyBiometricSummary`
- `StoredBaseline`
- `StoredProtocolAdherence`
- `StoredAlert`
- `StoredUserProfile`
- `StoredSyncAnchor`

Production additions:

- Persist `stagesData` as JSON `Data`.
- Persist `sourcesData` as JSON `Data`.
- Persist `biometricsData` as JSON `Data`.
- Add uniqueness fields:
  - `StoredSleepSession.id`
  - `StoredSleepSession.sleepDateKey`
  - `StoredProtocolAdherence.protocolID + dateKey`
  - `StoredSyncAnchor.typeIdentifier`
- Store HealthKit anchors for incremental queries. `HKQueryAnchor` conforms to secure coding and can be archived to `Data`.

### Design System

Create `Better/Core/DesignSystem/`.

Use the downloaded prototype palette as the starting point:

```swift
static let betterBackground = Color(hex: "#080812")
static let betterCard = Color(hex: "#11112A")
static let betterCardSecondary = Color(hex: "#191932")
static let betterCardTertiary = Color(hex: "#22224A")
static let betterBrand = Color(hex: "#6366F1")
static let betterText = Color.white
static let betterSubtext = Color(hex: "#8E8E9A")
static let betterBorder = Color(hex: "#222240")
static let stageDeep = Color(hex: "#5E5CE6")
static let stageCore = Color(hex: "#30B0C7")
static let stageREM = Color(hex: "#64D2FF")
static let stageAwake = Color(hex: "#636366")
```

Add:

- `Color+Hex.swift`
- `BetterColors.swift`
- `BetterTypography.swift`
- `BetterSpacing.swift`

### App Shell

Create:

- `Better/App/BetterApp.swift`
- `Better/App/RootTabView.swift`
- `Better/App/AppEnvironment.swift`

The Phase 1 shell now lives under `Better/App/` and replaces the template entry points.

Tabs:

- Sleep
- Insights
- Protocol
- Alerts
- Settings

Use SF Symbols:

- `moon.fill`
- `chart.bar.xaxis`
- `pills.fill`
- `bell.fill`
- `gearshape.fill`

Acceptance criteria:

- App builds.
- Five tabs render with placeholder content.
- SwiftData container initializes with full schema.
- Preview environment uses mock repositories.

## Phase 2 - HealthKit Sync And Sleep Processing

Goal: read Apple Health sleep samples, convert them into clean nightly sessions, attach biometrics, cache results, and update the UI from cached domain data.

### Repository Protocols

Create `Better/Core/Repositories/`.

```swift
protocol HealthKitRepositoryProtocol: Sendable {
    func isHealthDataAvailable() -> Bool
    func requestAuthorization() async throws -> HealthAuthorizationResult
    func fetchSleepSamples(from: Date, to: Date) async throws -> [HKCategorySample]
    func fetchSleepSessions(from: Date, to: Date) async throws -> [SleepSession]
    func fetchBiometrics(for type: BiometricType, from: Date, to: Date) async throws -> [BiometricSample]
    func fetchSourceSummaries(from: Date, to: Date) async throws -> [SleepSource]
    func startObservingSleepChanges() async throws -> AsyncStream<HealthKitChangeEvent>
    func fetchIncrementalSleepChanges(anchor: Data?) async throws -> HealthKitAnchoredResult
}
```

```swift
protocol LocalDataRepositoryProtocol: Sendable {
    func saveSessions(_ sessions: [SleepSession]) async throws
    func fetchCachedSessions(from: Date, to: Date) async throws -> [SleepSession]
    func fetchLatestSession() async throws -> SleepSession?
    func saveBiometricSummary(_ summary: NightlyBiometricSummary) async throws
    func saveBaseline(_ baseline: SleepBaseline) async throws
    func fetchLatestBaseline(windowDays: Int) async throws -> SleepBaseline?
    func saveAlerts(_ alerts: [SleepAlert]) async throws
    func fetchAlerts(unreadOnly: Bool) async throws -> [SleepAlert]
    func markAlertRead(id: UUID) async throws
    func saveAdherence(_ adherence: ProtocolAdherence) async throws
    func fetchAdherence(from: Date, to: Date) async throws -> [ProtocolAdherence]
    func saveProfile(_ profile: UserProfile) async throws
    func fetchProfile() async throws -> UserProfile
    func saveSyncAnchor(_ data: Data?, for typeIdentifier: String) async throws
    func fetchSyncAnchor(for typeIdentifier: String) async throws -> Data?
}
```

### Authorization Result

Do not model authorization as a single Boolean.

```swift
struct HealthAuthorizationResult: Sendable {
    var requestCompleted: Bool
    var healthDataAvailable: Bool
    var canQuerySleep: Bool
    var lastQueryReturnedSamples: Bool?
}
```

Notes:

- `requestAuthorization` success only confirms the request flow completed.
- HealthKit does not reveal exact read permission status for privacy reasons.
- If the user denies sleep read access, a sleep query usually returns no samples rather than a clean "denied" state.
- The UI should show:
  - "Connect Apple Health" before request
  - "No sleep data found" if authorized flow completed but query returns no samples
  - "Apple Health unavailable" on unsupported devices

### HealthKit Repository Implementation

Create `Better/Core/Repositories/HealthKitRepository.swift`.

Implementation requirements:

- Use one shared `HKHealthStore`.
- Call `HKHealthStore.isHealthDataAvailable()`.
- Request read access only.
- Bridge callback APIs with `withCheckedThrowingContinuation`.
- Use `HKSampleQuery` for range fetches.
- Use `HKAnchoredObjectQuery` for incremental fetches.
- Use `HKObserverQuery` only to be notified that data changed.
- Call the observer query completion handler after local processing.
- Call `enableBackgroundDelivery(for: sleepType, frequency: .immediate)`.
- Keep observer query references alive while the app is running.
- Register observers early in app startup through an app lifecycle coordinator.

Sleep sample predicate:

```swift
HKQuery.predicateForSamples(
    withStart: from,
    end: to,
    options: [.strictEndDate]
)
```

For sleep ranges, fetch a wider window than the requested chart range:

- Latest dashboard: now minus 36 hours to now plus 2 hours
- 7-day trends: requested start minus 12 hours to requested end plus 12 hours
- 30-day baseline: requested start minus 12 hours to requested end plus 12 hours

This prevents sessions crossing midnight from being truncated.

### Sleep Processing Algorithm

Create `Better/Core/Processors/SleepDataProcessor.swift`.

Core constants:

```swift
static let minimumSleepDuration: TimeInterval = 300
static let sessionGapThreshold: TimeInterval = 1800
```

Processing steps:

1. Convert `HKCategorySample` to intermediate `RawSleepInterval`.
2. Drop intervals with invalid or zero duration.
3. Mark source information using `sample.sourceRevision`.
4. Identify whether sample was manually entered via metadata. Manual entries should be lower priority than Apple Watch staged samples.
5. Split overlaps into non-overlapping timeline segments.
6. Resolve each segment using stage priority:
   - detailed asleep stage: `deep`, `rem`, `core`
   - `awake`
   - `asleepUnspecified`
   - `inBed`
7. Prefer higher quality sources when two samples of the same semantic type overlap:
   - Apple Watch staged data
   - other wearable staged data
   - Apple Watch unspecified sleep
   - manual/phone/inBed-only data
8. Group cleaned intervals into candidate sessions using the 30-minute gap threshold.
9. Compute total asleep duration from asleep intervals only.
10. Filter candidate sessions where total asleep duration is less than 5 minutes.
11. Compute session boundaries, latency, WASO, efficiency, and stage totals.
12. Assign evening-based `sleepDateKey`.
13. Compute score if enough data exists.
14. Mark data quality.

Do not sum raw HealthKit sample durations directly. Overlapping `inBed`, `awake`, and stage samples will otherwise inflate totals.

### Quality Score

Keep the original score structure, but make it data-quality aware:

```text
overall = durationScore * 0.30
        + efficiencyScore * 0.20
        + remScore * 0.25
        + deepScore * 0.25
```

If `dataQuality == .unspecifiedSleepOnly`:

- Compute duration and efficiency.
- Do not pretend REM/deep are zero.
- Return `SleepQualityScore.isPartial = true`.
- UI should show "Stage detail unavailable" instead of penalizing the user.

Recommended scoring targets:

- Duration target: user's `sleepGoalHours`
- Efficiency target: 90-95%
- REM target: 20-25% of asleep time
- Deep target: 13-23% of asleep time

### Baseline Computation

Create baselines from cached sessions, not directly from HealthKit every time.

Rules:

- Use the user's selected `baselineWindowDays`: 15 or 30.
- Exclude sessions below 5 minutes because they should not exist after processing.
- Exclude `inBedOnly`.
- Include `unspecifiedSleepOnly` for total sleep and efficiency baselines.
- Exclude `unspecifiedSleepOnly` from REM/deep baseline stats.
- Require at least 5 valid nights before showing a confident baseline.
- Store average and standard deviation for:
  - total sleep
  - REM
  - deep
  - efficiency
  - WASO
  - latency
  - HRV
  - respiratory rate
  - SpO2
  - bedtime minute-of-day
  - wake minute-of-day

### Biometrics Attachment

After sessions are stitched:

1. For each session, query biometrics from `session.startDate` to `session.endDate`.
2. Compute nightly summary:
   - HR average/min/max
   - HRV average/median
   - SpO2 average/min
   - Respiratory rate average
3. Attach summary to `SleepSession.biometrics`.
4. Persist `StoredNightlyBiometricSummary`.

Biometric queries should tolerate missing data. Many users will not have SpO2 or respiratory rate data depending on device, region, permissions, or watch settings.

Acceptance criteria:

- A physical iPhone can request Health permissions.
- Sleep samples can be fetched from Apple Health.
- Overlapping samples do not double-count duration.
- Latest session renders from processed cached data.
- Incremental anchor is saved and reused.

## Phase 3 - SwiftData Local Repository And Sync Coordinator

Goal: make the app resilient by treating SwiftData as the UI's source of truth and HealthKit as an external sync source.

### LocalDataRepository

Create `Better/Core/Repositories/LocalDataRepository.swift`.

Use a `@ModelActor`:

```swift
@ModelActor
actor LocalDataRepository: LocalDataRepositoryProtocol { }
```

Rules:

- Initialize from `ModelContainer`.
- Do not pass `ModelContext` across actors.
- Upsert by stable IDs.
- Keep domain structs separate from SwiftData classes.
- Encode/decode nested arrays with `JSONEncoder` and `JSONDecoder`.
- Write small mapping extensions:
  - `StoredSleepSession.init(domain:)`
  - `StoredSleepSession.toDomain()`

### SyncCoordinator

Create `Better/Core/Services/SyncCoordinator.swift`.

Responsibilities:

- Request HealthKit authorization when user taps connect.
- Perform initial sync for the last 45 days.
- Perform foreground refresh for the last 36 hours.
- Perform incremental anchored refresh after observer events.
- Recompute baseline after new sessions.
- Generate alerts after baseline recomputation.
- Publish main-thread state changes for view models.

Recommended flow:

```text
User opens app
  -> UI loads cached SwiftData immediately
  -> SyncCoordinator refreshes latest HealthKit data
  -> Processor creates/updates sessions
  -> LocalDataRepository persists sessions
  -> Baseline recomputes
  -> Alerts recompute
  -> ViewModels reload from cache
```

Background flow:

```text
HealthKit observer wakes app
  -> observer handler starts incremental sync
  -> anchored query fetches changed/deleted sleep samples
  -> local cache updates
  -> observer completion handler is called
```

For deleted samples:

- `HKAnchoredObjectQuery` can return deleted objects.
- The simplest production-safe approach is to refetch and reprocess affected date ranges when deletions are seen.
- Do not ignore deletions; Apple Health edits can otherwise leave stale sessions.

Acceptance criteria:

- UI can load cached data with no network or HealthKit call.
- Pull-to-refresh updates the latest session.
- Deletions or edits in Health are reflected after a sync.
- Background delivery processing calls completion.

## Phase 4 - ViewModels

Goal: expose UI-ready state and keep views thin.

Create:

- `Better/Features/Sleep/SleepDashboardViewModel.swift`
- `Better/Features/Trends/TrendsViewModel.swift`
- `Better/Features/Protocol/ProtocolViewModel.swift`
- `Better/Features/Alerts/AlertsViewModel.swift`
- `Better/Features/Settings/SettingsViewModel.swift`

Use `@Observable`.

Because the project has `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, be explicit where helpful:

```swift
@MainActor
@Observable
final class SleepDashboardViewModel { }
```

### SleepDashboardViewModel State

```swift
var todaySession: SleepSession?
var baseline: SleepBaseline?
var dataQuality: SleepDataQuality = .noData
var authorizationState: HealthAuthorizationPresentationState = .notRequested
var isLoading = false
var errorMessage: String?
var lastSyncedAt: Date?
```

Methods:

- `onAppear()`
- `refresh()`
- `requestHealthKitAccess()`
- `loadCachedData()`

### TrendsViewModel State

- `sessions`
- `selectedWindow`
- `selectedMetric`
- `baseline`
- `chartPoints`
- `weekOverWeekChange`
- `stageCompositionPoints`

### ProtocolViewModel State

- `items`
- `todayAdherence`
- `adherenceStreak`
- `impactSummary`
- `selectedProtocol`

### AlertsViewModel State

- `alerts`
- `unreadCount`
- `dailyReminderSettings`
- `smartAlertSettings`
- `groupedAlerts`

### SettingsViewModel State

- `profile`
- `healthAvailability`
- `lastSuccessfulSync`
- `connectedSources`
- `exportURL`
- `isExporting`

Acceptance criteria:

- All tabs render from mock data.
- ViewModels can be unit tested with mock repositories.
- Views contain no HealthKit or SwiftData query logic.

## Phase 5 - Sleep Dashboard UI

Goal: build the highest-value user screen first and map every visual element to real processed data.

Create files under `Better/Features/Sleep/`:

- `SleepTabView.swift`
- `SleepQualityRingView.swift`
- `SleepHypnogramView.swift`
- `SleepMetricCardView.swift`
- `SleepVsBaselineView.swift`
- `StageBreakdownView.swift`
- `BiometricSummaryView.swift`
- `ScheduleConsistencyView.swift`
- `HealthKitPermissionBannerView.swift`

### Layout

Match the prototype's structure:

1. Header
2. Protocol badge if today's protocol was taken
3. Sleep score card
4. Baseline comparison card
5. What changed card
6. Sleep stages card
7. Heart rate / HRV card
8. Respiratory card
9. Schedule consistency card

Use SwiftUI cards with 12-16 px internal padding. Keep card radius moderate and consistent with iOS style.

### Hypnogram

Use Swift Charts when possible:

```swift
Chart(stageChartData) { entry in
    RectangleMark(
        xStart: .value("Start", entry.startDate),
        xEnd: .value("End", entry.endDate),
        y: .value("Stage", entry.stage.displayName),
        height: 28
    )
    .foregroundStyle(entry.stage.color)
    .cornerRadius(4)
}
```

For compact timeline style matching the prototype, a custom `GeometryReader` HStack can be simpler and more reliable than a full chart. Use Swift Charts for the detailed mode and a custom segmented bar for the card summary.

### Empty And Partial States

States to implement:

- Health unavailable
- Permission not requested
- Request completed but no sleep data found
- Latest session has no detailed stage data
- Biometrics missing
- Baseline not ready due to fewer than 5 valid nights
- Sync failed but cached data exists

Acceptance criteria:

- Sleep tab renders correctly with mock data.
- Sleep tab renders correctly with no data.
- Sleep tab does not show fake zero REM/deep when stages are unavailable.
- The UI matches the Figma prototype's hierarchy and color direction.

## Phase 6 - Trends, Protocol, Alerts, Settings

Goal: complete the remaining app surface after the sleep tab's data contract is stable.

### Trends

Create under `Better/Features/Trends/`:

- `TrendsTabView.swift`
- `TrendWindowPickerView.swift`
- `TrendMetricSelectorView.swift`
- `TrendLineChartView.swift`
- `StageStackedBarView.swift`
- `BaselineComparisonChartView.swift`
- `ProtocolImpactView.swift`

Metrics:

- Total sleep
- Sleep score
- Deep sleep
- REM sleep
- HRV
- WASO
- Latency
- Respiratory rate
- SpO2 when available

### Protocol

Create under `Better/Features/Protocol/`:

- `ProtocolTabView.swift`
- `ProtocolItemRowView.swift`
- `AdherenceHeatmapView.swift`
- `ProtocolImpactChartView.swift`
- `AdherenceStreakBannerView.swift`

Seed data:

- `Better/Core/Data/protocols.json`

Important production language:

- Protocol impact should say "associated with" or "on nights when followed."
- Do not claim causality unless the research design supports it.

### Alerts

Create under `Better/Features/Alerts/`:

- `AlertsTabView.swift`
- `AlertRowView.swift`
- `AlertDetailSheet.swift`
- `NotificationSettingsView.swift`
- `AlertThresholdsView.swift`

Use `UNUserNotificationCenter` only after explicit notification permission.

### Settings

Create under `Better/Features/Settings/`:

- `SettingsTabView.swift`
- `HealthStatusView.swift`
- `ConnectedDevicesView.swift`
- `ResearchExportView.swift`
- `ProfileSettingsView.swift`

Health settings button:

- iOS does not provide a clean deep link to a specific Health permission page.
- Use app settings URL for app-level settings:

```swift
UIApplication.openSettingsURLString
```

Acceptance criteria:

- All tabs use cached domain data.
- Research export creates a CSV from local derived records.
- Alerts and reminders can be toggled and persisted.

## Phase 7 - Alert Engine And Notifications

Goal: generate useful local insights without over-notifying.

Create `Better/Core/Services/AlertGenerationService.swift`.

Use an `actor`.

Inputs:

- Latest `SleepSession`
- Current `SleepBaseline`
- User thresholds/settings
- Protocol adherence

Alert rules:

- Low score: score below threshold, default `< 70`
- Short sleep: total sleep below goal by more than 60 minutes
- Low deep: detailed deep sleep below baseline by more than 1 standard deviation or below absolute minimum
- Low REM: detailed REM below baseline by more than 1 standard deviation or below absolute minimum
- High WASO: WASO above threshold, default `> 45 min`
- Low HRV: HRV below 80% of baseline
- Low SpO2: average below 94% or minimum below user threshold, only if reliable SpO2 data exists
- Irregular schedule: bedtime or wake variability > 60 minutes
- Improvement trend: 7-day upward trend in score or deep sleep
- Protocol miss: no adherence by cutoff time

Notification policy:

- Only schedule local notifications for enabled categories.
- Default to quiet in-app alerts for non-critical insights.
- Avoid sending multiple smart alerts from one poor night. Group them into one "Sleep analysis ready" notification where possible.

Acceptance criteria:

- Alerts are deterministic and unit-tested.
- Duplicate alerts are not generated for the same session/rule.
- Notification permission is requested during onboarding or settings, not at first launch without context.

## Phase 8 - Background Refresh

Goal: support real-world HealthKit updates while respecting iOS background limits.

Create:

- `Better/Core/Services/BackgroundTaskService.swift`
- App lifecycle registration in `BetterApp`

Use two mechanisms:

1. HealthKit observer query + background delivery for Health database changes.
2. `BGAppRefreshTask` as a backup/opportunistic refresh.

Do not assume hourly execution. iOS decides when background refresh runs.

Task identifier:

```text
ai.better-health.Better.sleep-sync
```

Registration must happen early:

```swift
BGTaskScheduler.shared.register(
    forTaskWithIdentifier: "ai.better-health.Better.sleep-sync",
    using: nil
) { task in
    handleSleepRefresh(task: task as! BGAppRefreshTask)
}
```

Task handler requirements:

- Schedule the next refresh before finishing.
- Set `expirationHandler`.
- Mark success/failure with `task.setTaskCompleted(success:)`.
- Keep work bounded.
- Prefer incremental anchored query.

HealthKit observer requirements:

- Register observer query early.
- Enable background delivery.
- On callback, run sync.
- Always call the observer completion handler after processing.

Acceptance criteria:

- Foreground refresh works on Simulator with mock/empty data.
- HealthKit background delivery is tested on physical iPhone.
- BGTask registration does not fail due to missing permitted identifier.
- Background task does not perform unbounded work.

## Phase 9 - Onboarding And Permissions

Goal: ask for sensitive permissions only when users understand the value.

Create under `Better/Features/Onboarding/`:

- `OnboardingFlowView.swift`
- `WelcomeStepView.swift`
- `HealthPermissionStepView.swift`
- `SleepGoalStepView.swift`
- `NotificationPermissionStepView.swift`
- `ResearchModeStepView.swift`

Flow:

1. Welcome and value proposition
2. Apple Health connection
3. Sleep goal
4. Notification preferences
5. Research mode opt-in if relevant

Do not block the whole app forever if HealthKit is skipped. Show mock/empty states and allow the user to connect later in Settings.

Acceptance criteria:

- Onboarding completion persists.
- User can skip HealthKit and connect later.
- Notification permission is optional.

## Phase 10 - Mock Data, Previews, And Tests

Goal: make the pure sleep logic trustworthy and keep UI development fast.

### Mock Data

Create:

- `Better/Core/Repositories/MockHealthKitRepository.swift`
- `Better/Core/Repositories/MockLocalDataRepository.swift`
- `Better/Core/Data/PreviewData.swift`

Base preview data on `Sleep Tracking iOS App/src/app/data/sleepData.ts`.

Include preview cases:

- Normal detailed Apple Watch sleep
- No data
- Permission not requested
- Unspecified sleep only
- Low score night
- Missing biometrics
- No baseline yet

### Unit Tests

Create or update `BetterTests/`.

Required tests:

- HealthKit value mapping
- Overlap cleanup
- `inBed` not counted as asleep
- `awake` counted as WASO only inside session
- 5-minute filter
- 30-minute gap stitching
- Session crossing midnight gets correct `sleepDateKey`
- Unspecified-only score is partial
- REM/deep unavailable state is not scored as zero
- Source preference picks Apple Watch staged data over phone/manual in overlaps
- Baseline excludes unsuitable data from stage stats
- Alert rules avoid duplicate alerts
- CSV export formats rows correctly

### UI Tests

Use launch argument:

```text
--uitesting
```

In UI testing mode:

- Use mock repositories.
- Do not present real HealthKit permission prompts.
- Do not schedule real notifications.

Acceptance criteria:

- Processor tests are exhaustive and fast.
- ViewModel tests use protocol mocks.
- UI tests can run without HealthKit permissions.

## Recommended File Manifest

```text
Better/
├── App/
│   ├── AppTab.swift
│   ├── AppEnvironment.swift
│   ├── BetterApp.swift
│   └── RootTabView.swift
├── Core/
│   ├── Models/
│   │   ├── SleepModels.swift
│   │   ├── BiometricModels.swift
│   │   └── ProtocolModels.swift
│   ├── Persistence/
│   │   └── PersistenceModels.swift
│   ├── DesignSystem/
│   │   ├── BetterColors.swift
│   │   ├── BetterTypography.swift
│   │   ├── BetterSpacing.swift
│   │   └── Color+Hex.swift
│   ├── Repositories/
│   │   ├── HealthKitRepositoryProtocol.swift
│   │   ├── LocalDataRepositoryProtocol.swift
│   │   ├── HealthKitRepository.swift
│   │   ├── LocalDataRepository.swift
│   │   ├── MockHealthKitRepository.swift
│   │   └── MockLocalDataRepository.swift
│   ├── Processors/
│   │   └── SleepDataProcessor.swift
│   ├── Services/
│   │   ├── SyncCoordinator.swift
│   │   ├── AlertGenerationService.swift
│   │   ├── BackgroundTaskService.swift
│   │   └── NotificationService.swift
│   └── Data/
│       ├── protocols.json
│       └── PreviewData.swift
├── Features/
│   ├── Onboarding/
│   ├── Sleep/
│   ├── Trends/
│   ├── Protocol/
│   ├── Alerts/
│   └── Settings/
├── Shared/
│   ├── Components/
│   └── Extensions/
├── Better/Better.entitlements
└── Better/Info.plist
```

## Production Readiness Checklist

### HealthKit

- HealthKit read types are correct.
- No write permissions requested initially.
- `NSHealthShareUsageDescription` is clear.
- HealthKit background delivery entitlement is present.
- Observer completion handler is always called.
- Anchored queries are used for changed data.
- Deleted HealthKit samples are handled.
- Read permission opacity is reflected in UI copy.
- Physical-device testing is required.

### Data Correctness

- `inBed` is not counted as sleep.
- Overlaps are resolved before totals are computed.
- Sessions under 5 minutes asleep are filtered.
- Stage-unavailable nights are represented honestly.
- Baselines require enough nights and exclude bad data from stage stats.
- Protocol impact is presented as correlation.

### UI Correctness

- Every dashboard number maps to a real field.
- Missing data has explicit UI.
- Baseline unavailable state is handled.
- Dark theme matches prototype.
- Charts do not show fake zeros for missing metrics.

### App Store / Privacy

- Health data remains local unless user explicitly exports.
- Research mode is opt-in.
- CSV export contains derived nightly summaries, not raw HealthKit identifiers.
- Notifications are opt-in.
- Medical claims are avoided.

## Suggested Implementation Order

1. Phase 0: project config, entitlements, Info.plist, build unblock.
2. Phase 1: domain models, SwiftData schema, design tokens, tab shell.
3. Phase 2: pure `SleepDataProcessor` plus exhaustive unit tests.
4. Phase 3: local repository and mock repository.
5. Phase 4: HealthKit repository foreground fetch.
6. Phase 5: sync coordinator and cached dashboard loading.
7. Phase 6: Sleep tab UI from mocks, then cached data.
8. Phase 7: trends, protocol, alerts, settings.
9. Phase 8: background delivery and BGTask backup.
10. Phase 9: onboarding and permissions.
11. Phase 10: physical-device validation, UI tests, export tests.

This order reduces risk because the hardest correctness work, sleep sample processing, is finished and tested before the UI depends on it.

## Model Guidance

Use the strongest coding model for phases where correctness bugs are expensive or hard to recover from:

- Best model: Phase 2, Phase 3, Phase 7, Phase 8, and Phase 10.
- Reasonable strong model: Phase 1 and Phase 5, especially when wiring shared state or building reusable UI components.
- Lower-cost model: Phase 0, Phase 4, Phase 6, and Phase 9 when the work is mostly configuration, straightforward view-model plumbing, or mostly static UI.

Recommended interpretation:

- `Best model` means the highest-capability coding model available in the workspace.
- `Lower-cost model` is fine for file scaffolding, copy updates, simple SwiftUI shells, and test fixture generation.
- Do not use a lower-cost model for HealthKit processing, persistence mapping, background delivery, or alert logic because those phases have subtle correctness risks.

## External References

- Apple HealthKit sleep categories: https://developer.apple.com/documentation/healthkit/hkcategoryvaluesleepanalysis
- Apple HealthKit background delivery: https://developer.apple.com/documentation/healthkit/hkhealthstore/enablebackgrounddelivery%28for%3Afrequency%3Awithcompletion%3A%29
- Apple observer queries: https://developer.apple.com/documentation/healthkit/executing-observer-queries
- Apple BackgroundTasks permitted identifiers: https://developer.apple.com/documentation/BundleResources/Information-Property-List/BGTaskSchedulerPermittedIdentifiers
- Apple BGTaskScheduler registration: https://developer.apple.com/documentation/backgroundtasks/bgtaskscheduler
