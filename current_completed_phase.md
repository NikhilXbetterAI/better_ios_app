# Current Completed Phase

Last updated: 2026-05-04

## Phase 0

Status: completed with verification pending full Xcode build access.

What changed:

- Kept the project baseline at `iOS 26.2`.
- Added explicit app entitlements for HealthKit read access and HealthKit background delivery.
- Switched the app target away from generated Info.plist settings to an explicit `Better/Info.plist`.
- Added the BGTaskScheduler permitted identifier for future sleep sync work.
- Created this phase ledger for ongoing phase-by-phase implementation tracking.

Verification:

- Project configuration and documentation are updated.
- Full `xcodebuild` verification is still blocked until Xcode is selected instead of Command Line Tools.

Blockers:

- None for the repository changes themselves.
- Build verification requires switching the active developer directory to full Xcode.

## Phase 1

Status: completed with verification pending full Xcode build access.

What changed:

- Added the Phase 1 core domain models for sleep sessions, biometrics, baselines, alerts, protocols, user profile, sleep source, and data-quality state.
- Added the SwiftData persistence schema and local mapping helpers, including the sync anchor model for later incremental HealthKit work.
- Added semantic design tokens for the prototype palette and spacing/typography primitives.
- Replaced the template app entry points with a five-tab SwiftUI shell using independent navigation stacks and preview fixtures.
- Added phase-1 unit tests for Codable round-trips, SwiftData container creation, and shell metadata.

Verification:

- The new plist and entitlements remain valid.
- Phase 1 tests and the app shell are in place, but full `xcodebuild` verification is still blocked until Xcode is selected instead of Command Line Tools.

Blockers:

- None for the repository changes themselves.
- Build verification requires switching the active developer directory to full Xcode.

## Phase 2

Status: completed with verification pending full Xcode build access and device HealthKit validation.

Files changed:

- `Better/Core/Repositories/RepositoryProtocols.swift`
- `Better/Core/Repositories/HealthKitRepository.swift`
- `Better/Core/Processors/SleepDataProcessor.swift`
- `BetterTests/SleepDataProcessorTests.swift`
- `current_completed_phase.md`

What changed:

- Added Phase 2 repository contracts for HealthKit access, local data access, authorization presentation state, observer change events, and anchored sleep-query results.
- Added a live HealthKit repository that requests read-only sleep and biometric permissions, fetches sleep and biometric samples, maps source summaries, starts sleep observer queries, enables immediate background delivery, and encodes/reuses anchored-query anchors.
- Added a pure sleep data processor that cleans overlapping HealthKit sleep intervals, resolves stage/source priority, splits sessions by the 30-minute gap rule, filters sessions below 5 minutes, computes sleep totals, latency, WASO, efficiency, evening-based sleep date keys, data quality, partial-aware scores, baselines, and nightly biometric summaries.
- Added processor tests covering overlap de-duplication, short-session filtering, session splitting, WASO/efficiency, unspecified-only partial scores, sleep date assignment, baseline inclusion rules, and biometric summary statistics.

Verification:

- `plutil -p Better/Info.plist` passed.
- `plutil -p Better/Better.entitlements` passed.
- `swiftc -typecheck` passed for the Phase 2 model, repository, and processor source files available to the local compiler.
- `xcodebuild test -project Better.xcodeproj -scheme Better -destination 'platform=iOS Simulator,name=iPhone 17'` could not run because the active developer directory is still `/Library/Developer/CommandLineTools`.

Blockers and follow-ups:

- Full `xcodebuild test` verification requires selecting full Xcode with `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`.
- HealthKit permission prompts, physical Apple Health sleep sample reads, and background delivery behavior must be validated on a physical iPhone paired with Apple Watch.
- SwiftData local repository persistence, sync coordination, cached UI loading, and ViewModels remain intentionally deferred to later phases.

## Phase 3

Status: completed and verified in the iOS simulator.

Files changed:

- `Better.xcodeproj/project.pbxproj`
- `Better/App/BetterApp.swift`
- `Better/Core/Persistence/PersistenceModels.swift`
- `Better/Core/Processors/SleepDataProcessor.swift`
- `Better/Core/Repositories/RepositoryProtocols.swift`
- `Better/Core/Repositories/LocalDataRepository.swift`
- `Better/Core/Repositories/MockLocalDataRepository.swift`
- `Better/Core/Services/SyncCoordinator.swift`
- `BetterTests/LocalDataRepositoryTests.swift`
- `current_completed_phase.md`

What changed:

- Added a SwiftData-backed `@ModelActor` local repository that keeps domain structs separate from stored models, upserts stable records, replaces cached sessions by date range for HealthKit edit/deletion recovery, persists profiles, alerts, adherence, baselines, biometric summaries, and sync anchors.
- Added an in-memory mock local repository for tests and later view-model work.
- Added a main-actor observable sync coordinator that requests Health authorization, runs 45-day initial syncs, 36-hour foreground refreshes, anchored incremental refreshes, refetches affected ranges after changes/deletions, attaches nightly biometrics, recomputes baselines, saves generated alerts, and acknowledges observer events after processing.
- Added focused Phase 3 tests for SwiftData repository persistence/range replacement and coordinator initial sync through cached sessions, biometrics, baselines, and alerts.
- Fixed directly blocking earlier-phase issues discovered during verification: excluded `Better/Info.plist` from copied bundle resources, imported SwiftData where `modelContainer` is used, returned the stored sleep-session domain mapper result, and made sleep data quality prefer actual stage availability over synthetic mixed `inBed`/stage source noise.

Verification:

- `swiftc -typecheck Better/Core/Models/SleepModels.swift Better/Core/Models/BiometricModels.swift Better/Core/Models/ProtocolModels.swift Better/Core/Processors/SleepDataProcessor.swift Better/Core/Repositories/RepositoryProtocols.swift Better/Core/Repositories/HealthKitRepository.swift Better/Core/Repositories/MockLocalDataRepository.swift Better/Core/Services/SyncCoordinator.swift` passed.
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project Better.xcodeproj -scheme Better -destination 'platform=iOS Simulator,name=iPhone 17'` passed.

Blockers and follow-ups:

- Physical HealthKit authorization, Apple Health sleep reads, anchored deletion behavior, and background delivery still require validation on a physical iPhone paired with Apple Watch.
- Build logs still include Swift 6 migration warnings around default actor isolation; they do not block Phase 3 under the current Swift 5 build mode.

## Phase 5

Status: completed and verified in the iOS simulator.

Files changed:

- `Better/Core/DesignSystem/BetterColors.swift` (updated — added success/warning/danger/heartRate/hrv colors + SleepStageType.color extension)
- `Better/Core/Repositories/PreviewHealthKitRepository.swift` (new — null HealthKit implementation for previews)
- `Better/Core/Data/PreviewSleepData.swift` (new — preview fixtures: rich session from 3 days ago, baseline, biometrics, mock repository factory)
- `Better/App/AppEnvironment.swift` (updated — added syncCoordinator + localRepository; removed previewFixtures; wires live and preview repositories)
- `Better/Features/Sleep/SleepMetricCardView.swift` (new — expandable card + plain card reusable components)
- `Better/Features/Sleep/SleepQualityRingView.swift` (new — score ring + compact score badge)
- `Better/Features/Sleep/SleepHypnogramView.swift` (new — proportional stage timeline + legend)
- `Better/Features/Sleep/StageBreakdownView.swift` (new — stage bars with baseline ghost bars)
- `Better/Features/Sleep/SleepVsBaselineView.swift` (new — comparison bars + "What Changed" grid)
- `Better/Features/Sleep/BiometricSummaryView.swift` (new — HR avg/min/max, HRV row, SpO2 row, respiratory rate card)
- `Better/Features/Sleep/ScheduleConsistencyView.swift` (new — bed/wake consistency progress bars)
- `Better/Features/Sleep/HealthKitPermissionBannerView.swift` (new — all permission states + empty state view)
- `Better/Features/Sleep/SleepTabView.swift` (new — main tab composition: header, score card, baseline card, what changed, stages, HR, respiratory, consistency)
- `Better/App/RootTabView.swift` (updated — wires real SleepTabView for Sleep tab; other tabs show "Coming in Phase 6" placeholder)
- `BetterTests/BetterTests.swift` (updated — removed previewFixtures assertion; updated to check syncCoordinator)
- `BetterUITests/BetterUITests.swift` (updated — updated UI test to check real Sleep tab header "BETTER SLEEP" instead of Phase 1 placeholder accessibility ID)

What was implemented:

- Dark-palette Sleep dashboard UI matching the Figma prototype hierarchy and color direction.
- Sleep score card: animated ring showing 0–100 score with label (Excellent/Good/Fair/Poor), key metrics (time asleep, time in bed, efficiency, latency, bed/wake times), partial-score awareness.
- Baseline comparison card: summary banner (above/below average), dual-bar comparison for duration/deep/REM/WASO/HRV, "What Changed" 2×2 grid.
- Sleep stages card: proportional hypnogram timeline using GeometryReader, stage legend, stage bars with baseline ghost bars, stage detail unavailable banner.
- Heart rate card: avg/min/max stats, HRV row with baseline delta, SpO2 row.
- Respiratory rate card: normal range banner, tonight vs baseline rows.
- Schedule consistency card: bed/wake time with standard-deviation-based consistency bars.
- HealthKit permission banner: handles notRequested, healthDataUnavailable, noReadableSleepData, failed states.
- Empty state: moon-stars icon + permission banner when no session exists.
- Preview data: realistic session (7h 23m asleep, 97% efficiency, score 82, detailed stages, biometrics) anchored 3 days ago so it survives the 36-hour foreground sync window.
- AppEnvironment extended with SyncCoordinator and LocalDataRepositoryProtocol for both live and preview environments.
- All new files auto-discovered by Xcode's PBXFileSystemSynchronizedRootGroup — no pbxproj changes needed.

Verification performed:

- `xcodebuild build` passed (0 errors).
- All 8 SleepDataProcessor tests passed.
- All 3 LocalDataRepository/SyncCoordinator tests passed.
- `BetterTests.testSleepSessionCodableRoundTrip`, `testStoredSleepSessionRoundTrip`, `testPhaseOneContainerCanPersistModels` passed.
- `BetterUITests.testShellRendersFiveTabs` passed (UI test verifies five tabs render and Sleep tab shows "BETTER SLEEP" header).
- `BetterUITestsLaunchTests.testLaunch` passed on all parallel clones.

Blockers and follow-ups:

- `BetterTests.testAppEnvironmentPreviewBuilds` reports failure at 0.000 seconds due to `xcrun: simctl not found` — a simulator diagnostic infrastructure issue unrelated to code. The method under test (AppEnvironment.preview()) is exercised successfully by all LocalDataRepository tests which use the same preview container.
- Sleep tab renders from cached preview data; real HealthKit sync requires physical iPhone + Apple Watch.
- Trends, Protocol, Alerts, Settings tabs show "Coming in Phase 6" placeholder — deferred per plan.

## Phase 4

Status: completed and verified in the iOS simulator.

Files changed:

- `Better/Features/Sleep/SleepDashboardViewModel.swift` (new)
- `Better/Features/Trends/TrendsViewModel.swift` (new)
- `Better/Features/Protocol/ProtocolViewModel.swift` (new)
- `Better/Features/Alerts/AlertsViewModel.swift` (new)
- `Better/Features/Settings/SettingsViewModel.swift` (new)
- `current_completed_phase.md`

What changed:

- Added `SleepDashboardViewModel` (`@MainActor @Observable`) that exposes `todaySession`, `baseline`, `dataQuality`, `authorizationState`, `isLoading`, `errorMessage`, and `lastSyncedAt`; drives `onAppear`, `refresh`, `requestHealthKitAccess`, and `loadCachedData` through `SyncCoordinator` and `LocalDataRepositoryProtocol`.
- Added `TrendsViewModel` with `TrendWindow` (7/14/30 day) and `TrendMetric` (9 metrics) enums, `TrendChartPoint` and `StageCompositionPoint` value types, and derived `chartPoints`, `weekOverWeekChange`, and `stageCompositionPoints` computed from cached sessions. Deep/REM chart points are suppressed when `dataQuality != .detailedStages`.
- Added `ProtocolViewModel` with hardcoded seed `ProtocolItem` array (Magnesium Glycinate, Melatonin), `markTaken(_:)` that persists `ProtocolAdherence`, `isTakenToday(_:)` helper, and a consecutive-nights streak computation over a 90-day lookback.
- Added `AlertsViewModel` with `DailyReminderSettings` and `SmartAlertSettings` value types, full alerts list, `unreadCount`, `groupedAlerts` keyed by `SleepAlertKind`, and `markRead`/`markAllRead` operations.
- Added `SettingsViewModel` that loads the user profile and writes it back, reads `healthRepository.isHealthDataAvailable()`, fetches connected sources, reflects `syncCoordinator.lastSyncedAt`, and exports derived session data to a CSV file in `FileManager.temporaryDirectory`. No raw HealthKit identifiers are included in the CSV.
- All ViewModels take repository and coordinator dependencies through constructor injection for testability.

Verification:

- `swiftc -typecheck` passed for all 5 ViewModel files together with their upstream dependencies.
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project Better.xcodeproj -scheme Better -destination 'platform=iOS Simulator,name=iPhone 17'` passed (15 unit + UI tests, 0 failures).

Blockers and follow-ups:

- ViewModel unit tests with `MockLocalDataRepository` and a `MockSyncCoordinator` are deferred to Phase 10.
- `MockHealthKitRepository` does not yet exist; `SettingsViewModel` compiles against the protocol and will require the mock for Phase 5/10 previews.
- `protocols.json` seed data file is deferred to Phase 6; Phase 4 uses two hardcoded seed `ProtocolItem` values.
- Views that consume these ViewModels are deferred to Phase 5 (Sleep) and Phase 6 (Trends, Protocol, Alerts, Settings).

## Phase 6

Status: completed and verified with app build plus targeted UI verification.

Files changed:

- `Better/App/AppEnvironment.swift`
- `Better/App/RootTabView.swift`
- `Better/Core/Data/PreviewSleepData.swift`
- `Better/Core/Data/protocols.json`
- `Better/Core/Repositories/PreviewHealthKitRepository.swift`
- `Better/Features/Trends/TrendsTabView.swift`
- `Better/Features/Trends/TrendWindowPickerView.swift`
- `Better/Features/Trends/TrendMetricSelectorView.swift`
- `Better/Features/Trends/TrendLineChartView.swift`
- `Better/Features/Trends/StageStackedBarView.swift`
- `Better/Features/Trends/BaselineComparisonChartView.swift`
- `Better/Features/Trends/ProtocolImpactView.swift`
- `Better/Features/Protocol/ProtocolViewModel.swift`
- `Better/Features/Protocol/ProtocolTabView.swift`
- `Better/Features/Protocol/ProtocolItemRowView.swift`
- `Better/Features/Protocol/AdherenceHeatmapView.swift`
- `Better/Features/Protocol/ProtocolImpactChartView.swift`
- `Better/Features/Protocol/AdherenceStreakBannerView.swift`
- `Better/Features/Alerts/AlertsTabView.swift`
- `Better/Features/Alerts/AlertRowView.swift`
- `Better/Features/Alerts/AlertDetailSheet.swift`
- `Better/Features/Alerts/NotificationSettingsView.swift`
- `Better/Features/Alerts/AlertThresholdsView.swift`
- `Better/Features/Settings/SettingsViewModel.swift`
- `Better/Features/Settings/SettingsTabView.swift`
- `Better/Features/Settings/HealthStatusView.swift`
- `Better/Features/Settings/ConnectedDevicesView.swift`
- `Better/Features/Settings/ProfileSettingsView.swift`
- `Better/Features/Settings/ResearchExportView.swift`
- `BetterUITests/BetterUITests.swift`
- `current_completed_phase.md`

What was implemented:

- Replaced Phase 5 placeholders in the app shell with real SwiftUI tabs for Insights, Protocol, Alerts, and Settings.
- Added Trends UI for 7/14/30-day windows, metric selection, a lightweight line chart, stage stacked bars, baseline comparison, and protocol impact language that avoids causal claims.
- Added Protocol UI for active protocol status, mark-as-taken flow, streak banner, 21-day adherence heatmap, ingredient rows, and protocol impact comparison.
- Added `protocols.json` seed data and updated `ProtocolViewModel` to load bundled seed protocols with the hardcoded fallback preserved.
- Added Alerts UI for notification/reminder toggles, smart-alert toggles, fixed threshold display, recent alert rows, detail sheet, unread badge, and mark-read actions.
- Added Settings UI for Health availability, connected Health sources, profile goal/baseline/research-mode editing, app-settings handoff, and CSV export of derived cached sleep records.
- Extended preview/mock data with multiple cached sessions, alerts, adherence history, profile settings, and connected Health source summaries so all Phase 6 tabs render from local domain data.
- Extended `AppEnvironment` with `healthRepository` so Settings can use the existing repository contract without reaching into HealthKit directly.
- Updated the UI test to verify the Phase 6 tab headers instead of the old placeholder path.

Verification performed:

- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build -project Better.xcodeproj -scheme Better -destination 'platform=iOS Simulator,name=iPhone 17'` passed.
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project Better.xcodeproj -scheme Better -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:BetterUITests/BetterUITests/testShellRendersFiveTabs` passed.
- Full `xcodebuild test` compiled and ran the suite; all listed tests passed except the pre-existing `BetterTests.testAppEnvironmentPreviewBuilds` infrastructure failure described below.

Blockers and follow-ups:

- Full-suite `xcodebuild test` still reports `BetterTests.testAppEnvironmentPreviewBuilds` failed at 0.000 seconds while Xcode diagnostics report `xcrun: error: unable to find utility "simctl", not a developer tool or in PATH`. This is the same simulator diagnostic infrastructure issue noted in Phase 5; targeted app build and UI verification pass.
- Phase 6 intentionally does not request notification permission or schedule notifications; `UNUserNotificationCenter` integration remains deferred to Phase 7.
- Physical Apple Health source reads and Health permission behavior still require validation on a physical iPhone paired with Apple Watch.

## Phase 7

Status: completed and verified with targeted unit tests and app build.

Files changed:

- `Better/Core/Services/AlertGenerationService.swift` (new)
- `Better/Core/Services/SyncCoordinator.swift`
- `Better/Core/Models/ProtocolModels.swift`
- `Better/Features/Alerts/AlertRowView.swift`
- `Better/Features/Alerts/AlertThresholdsView.swift`
- `BetterTests/AlertGenerationServiceTests.swift` (new)
- `current_completed_phase.md`

What was implemented:

- Added `AlertGenerationService`, an actor that deterministically generates in-app sleep insights from the latest session, rolling baseline, user profile, recent sessions, and protocol adherence.
- Implemented Phase 7 alert rules for low score, short sleep, low deep sleep, low REM sleep, high WASO, low HRV, low SpO2, irregular schedule, 7-night improvement trend, and optional protocol-miss monitoring.
- Added deterministic alert IDs keyed by session date and rule so repeated generation does not create duplicate alerts for the same session/rule.
- Added local-notification scheduling policy without requesting notification permission: notifications only schedule when already authorized, explicitly enabled, and the alert category is enabled; multiple enabled smart alerts from one night are grouped into one "Sleep analysis ready" notification.
- Replaced the earlier coordinator-local alert helper with the new alert service while keeping sync storage through `LocalDataRepository.saveAlerts`.
- Extended alert kinds and alert UI icons/threshold display for the new Phase 7 rules.

Verification performed:

- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project Better.xcodeproj -scheme Better -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:BetterTests/AlertGenerationServiceTests` passed.
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project Better.xcodeproj -scheme Better -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:BetterTests/LocalDataRepositoryTests/testSyncCoordinatorInitialSyncCachesSessionsBaselineBiometricsAndAlerts` passed.
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build -project Better.xcodeproj -scheme Better -destination 'platform=iOS Simulator,name=iPhone 17'` passed.

Blockers and follow-ups:

- Notification permission request UX remains deferred to Phase 9 onboarding/settings context. Phase 7 intentionally does not request permission at first launch.
- Real notification delivery and HealthKit-derived alert behavior still require validation on a physical iPhone with user-granted permissions.

## Phase 8

Status: completed with app build verification; simulator test execution remains blocked by local `simctl` tooling.

Files changed:

- `Better/Core/Services/BackgroundTaskService.swift` (new)
- `Better/App/AppEnvironment.swift`
- `Better/App/BetterApp.swift`
- `BetterTests/BetterTests.swift`
- `current_completed_phase.md`

What was implemented:

- Added `BackgroundTaskService`, a main-actor lifecycle service for Phase 8 background refresh responsibilities.
- Registered `BGAppRefreshTask` early from `BetterApp` using task identifier `ai.better-health.Better.sleep-sync`.
- Added opportunistic refresh scheduling through `BGAppRefreshTaskRequest`, with a one-hour default earliest begin date and captured schedule errors for diagnostics.
- Added bounded background-task handling that schedules the next refresh before syncing, sets an expiration handler, runs the existing incremental anchored sync path, and calls `setTaskCompleted(success:)`.
- Started HealthKit sleep observers from app startup/active lifecycle by delegating to the existing `SyncCoordinator.startObservingHealthChanges()` path, which preserves observer acknowledgement after processing.
- Added background task infrastructure to `AppEnvironment`; live environments register/schedule background tasks, while preview/UI-testing environments keep the service disabled so tests and previews do not submit background work.
- Confirmed the existing plist and entitlements already contain `BGTaskSchedulerPermittedIdentifiers`, `UIBackgroundModes = fetch`, HealthKit, and HealthKit background-delivery configuration, so no Phase 8 config changes were needed.

Verification performed:

- `plutil -p Better/Info.plist` passed and confirmed the permitted task identifier and fetch background mode.
- `plutil -p Better/Better.entitlements` passed and confirmed HealthKit plus HealthKit background delivery entitlements.
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build -project Better.xcodeproj -scheme Better -destination 'platform=iOS Simulator,name=iPhone 17'` passed.

Blockers and follow-ups:

- `xcodebuild test -only-testing:BetterTests/BetterTests/testAppEnvironmentPreviewBuilds` compiled, but failed at 0.000 seconds because Xcode test diagnostics could not find `simctl` (`xcrun: error: unable to find utility "simctl"`). This is the same local simulator infrastructure issue recorded in earlier phases.
- HealthKit background delivery and actual `BGAppRefreshTask` launches still require validation on a physical iPhone with user-granted Health permissions; Simulator can only verify compilation and foreground/empty-data paths.

## Phase 9

Status: completed with app build verification; full unit execution has the existing local `simctl` diagnostic failure.

Files changed:

- `Better/App/RootTabView.swift`
- `Better/Core/Models/OnboardingModels.swift`
- `Better/Core/Models/ProtocolModels.swift`
- `Better/Core/Persistence/PersistenceModels.swift`
- `Better/Features/Onboarding/OnboardingViewModel.swift`
- `Better/Features/Onboarding/OnboardingFlowView.swift`
- `Better/Features/Onboarding/WelcomeStepView.swift`
- `Better/Features/Onboarding/HealthPermissionStepView.swift`
- `Better/Features/Onboarding/SleepGoalStepView.swift`
- `Better/Features/Onboarding/SleepQuestionnaireStepView.swift`
- `Better/Features/Onboarding/SleepAssessmentQuestion.swift`
- `Better/Features/Onboarding/NotificationPermissionStepView.swift`
- `Better/Features/Onboarding/ResearchModeStepView.swift`
- `current_completed_phase.md`

What was implemented:

- Added first-run root gating based on `UserProfile.hasCompletedOnboarding`; completed users go directly into the existing five-tab dashboard.
- Added a six-step native SwiftUI onboarding flow: welcome/value proposition, Apple Health permission context, sleep goal, personalised sleep assessment, optional notifications, and research mode opt-in.
- Apple Health remains skippable, and the onboarding copy makes clear that users can connect later from Settings.
- Notification permission is requested only after an explicit tap in the notifications step and remains optional.
- Added the full 12-question personalised sleep assessment grouped by Sleep Timing & Chronotype, Sleep Quality, Daytime Function, and Behavioral Drivers, with modern dark cards, progress feedback, and selectable option rows.
- Persisted assessment answers on `UserProfile` through SwiftData using an optional encoded payload for lightweight migration compatibility.
- Onboarding completion persists through the existing local repository profile save path.

Verification performed:

- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build -project Better.xcodeproj -scheme Better -destination 'platform=iOS Simulator,name=iPhone 17'` passed.
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project Better.xcodeproj -scheme Better -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:BetterTests` compiled and ran; all substantive unit tests passed.
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project Better.xcodeproj -scheme Better -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:BetterTests/LocalDataRepositoryTests/testLocalRepositoryPersistsProfileAlertsAdherenceAndAnchor` passed after adding assessment-answer persistence coverage.

Blockers and follow-ups:

- The same pre-existing `BetterTests.testAppEnvironmentPreviewBuilds` infrastructure failure remains: Xcode diagnostics cannot find `simctl` and fails the test at 0.000 seconds.
- Real Apple Health permission prompts, notification authorization UI, and HealthKit sync behavior still require validation on a physical iPhone.
