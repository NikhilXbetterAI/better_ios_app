# Better Sleep Mode - Architecture Implementation Plan

Last updated: 2026-05-17

## Goal

Add a sleep-support feature without making the existing Better UI feel crowded.

The feature should let a user:

- Set an automatic nightly schedule.
- Start Sleep Mode manually from the Sleep tab.
- Run a 3-4-7 breathing light sequence.
- Enter a blacked-out, low-stimulation screen.
- Optionally play sleep sound / white noise later.
- Optionally shield distracting apps and websites during sleep time, if the app gets Apple's Screen Time / Family Controls entitlement.
- Keep all sleep behavior data private, local, and App Store acceptable.

## Current Architecture Fit

Better currently has clean seams for this feature:

| Existing area | Current role | Sleep Mode addition |
|---|---|---|
| `Better/App/RootTabView.swift` | Owns the five root tabs and secondary settings/alerts sheets | Do not add a new tab. Keep Sleep Mode inside Sleep and Settings. |
| `Better/Features/Sleep/SleepTabView.swift` | Main nightly sleep dashboard | Add a compact `Sleep Mode` action near the top hero. |
| `Better/Features/Settings/SettingsTabView.swift` | Health, profile, privacy, export | Add a `Sleep Mode Schedule` settings section. |
| `Better/Core/Repositories/LocalDataRepository.swift` | SwiftData persistence behind repository protocol | Persist schedule, settings, and session usage. |
| `Better/Core/Persistence/PersistenceModels.swift` | SwiftData schema and encrypted JSON blob helpers | Add stored sleep mode settings/schedule/session models. |
| `Better/Core/Services/BackgroundTaskService.swift` | BGTask-based sleep sync | Do not use this for exact Sleep Mode start time. BGTasks are not exact timers. |
| `Better/Core/Services/AlertGenerationService.swift` | In-app alerts and local notifications | Reuse notification patterns for scheduled Sleep Mode reminders. |
| `Better/Core/Services/PrivacyDataService.swift` | Inventory, delete, resync | Add Sleep Mode data to inventory/delete flows. |
| `Better/Core/Services/ResearchAnalysisService.swift` | Joins sleep + behavior data | Join Sleep Mode usage as a nightly context factor. |

Recommended placement:

```text
Better/
├── Core/
│   ├── Models/
│   │   └── SleepModeModels.swift
│   ├── Services/
│   │   ├── SleepModeSessionService.swift
│   │   ├── SleepModeScheduleService.swift
│   │   ├── SleepModeNotificationService.swift
│   │   ├── BreathingSequenceEngine.swift
│   │   ├── SleepAudioService.swift                  # Phase 3
│   │   └── ScreenTimeShieldService.swift             # Optional entitlement path
│   └── Persistence/
│       └── PersistenceModels.swift
└── Features/
    └── SleepMode/
        ├── SleepModeEntryCard.swift
        ├── SleepModeView.swift
        ├── SleepModeViewModel.swift
        ├── SleepModeScheduleView.swift
        ├── BreathingLightView.swift
        ├── SleepBlackoutView.swift
        ├── FocusSetupCardView.swift
        └── ScreenTimeShieldSetupView.swift           # Optional entitlement path
```

## iOS / App Store Reality Check

### What can be automatic?

| Desired behavior | App-Store-safe answer |
|---|---|
| Start Better Sleep Mode exactly at 10:30 PM | Not reliably possible if the app is not already foregrounded. iOS does not let normal apps launch an interactive screen exactly at a scheduled time. |
| Notify user at sleep time | Yes. Use `UNCalendarNotificationTrigger` with repeating time components. |
| Start a black screen automatically while app is already open | Yes. If Better is foregrounded, the app can transition into Sleep Mode at the scheduled time. |
| Run background code exactly at bedtime | No. `BGTaskScheduler` is system-controlled and may be delayed by hours. Use it for maintenance/sync, not exact bedtime activation. |
| Automatically silence all notifications except calls | No. Use iOS Focus instructions. Focus settings are user-controlled. |
| Actually block selected distracting apps/sites | Possible only with Screen Time APIs: `FamilyControls`, `DeviceActivity`, `ManagedSettings`, app extensions, and Apple's Family Controls entitlement approval. |

Sources:

- Local notifications can use `UNCalendarNotificationTrigger` for repeating date/time delivery: https://developer.apple.com/documentation/usernotifications/uncalendarnotificationtrigger
- Apple says BGTaskScheduler is for background work and the system schedules launch timing; it is not an exact user-facing timer: https://developer.apple.com/documentation/backgroundtasks/bgtaskscheduler
- Apple's BGTask development docs explicitly warn launch delay can be many hours: https://developer.apple.com/documentation/backgroundtasks/starting-and-terminating-tasks-during-development
- Screen Time app/site shielding requires Family Controls / Device Activity / Managed Settings: https://developer.apple.com/documentation/familycontrols
- Family Controls distribution requires Apple entitlement approval: https://developer.apple.com/documentation/familycontrols/requesting-the-family-controls-entitlement

## Recommended Product Strategy

Ship two levels.

### Level 1 - Core Sleep Mode, No Special Entitlement

This is the most App-Store-safe first version.

Capabilities:

- Manual Sleep Mode from Sleep tab.
- Schedule-based reminder notification.
- If the app is open at the scheduled time, auto-enter Sleep Mode.
- iOS Focus setup guidance for call-only interruptions.
- Blackout screen and breathing sequence.
- Optional brightness dimming with restore safeguards.
- Local session logging.

Limitations:

- Cannot force-open Better at bedtime.
- Cannot globally block other apps.
- Cannot silence other apps' notifications.

### Level 2 - Optional Screen Time Shielding

This is the stronger "block mobile behavior" version, but it has more App Store and entitlement risk.

Capabilities:

- User selects distracting apps/categories/websites through Apple's `FamilyActivityPicker`.
- Better stores opaque tokens, not readable app names.
- `DeviceActivityCenter` schedules a sleep interval.
- `DeviceActivityMonitor` extension applies shields at interval start.
- `ManagedSettingsStore` shields selected apps/websites.
- Shield is removed at interval end.

Requirements:

- `FamilyControls` capability on app and extensions.
- Apple approval for the Family Controls distribution entitlement.
- App extension targets:
  - `DeviceActivityMonitorExtension`
  - Optional `ShieldConfigurationExtension`
  - Optional `ShieldActionExtension`
- Clear product framing: this is a user-controlled digital wellbeing feature, not surveillance.

Sources:

- `AuthorizationCenter.requestAuthorization(for: .individual)` supports individual authorization with biometric approval: https://developer.apple.com/documentation/familycontrols/authorizationcenter
- `FamilyActivityPicker` lets users select apps/websites/categories without revealing choices to the app: https://developer.apple.com/documentation/familycontrols/familyactivitypicker
- `FamilyActivitySelection` stores opaque values for privacy: https://developer.apple.com/documentation/familycontrols/familyactivityselection
- `DeviceActivityMonitor.intervalDidStart` can shield selected apps when scheduled activity starts: https://developer.apple.com/documentation/deviceactivity/deviceactivitymonitor
- `ManagedSettingsStore` / `ShieldSettings` apply app and website shields: https://developer.apple.com/documentation/managedsettings/managedsettingsstore

## UI Placement Without Messing The App

### Sleep Tab

Add one compact entry point, not a new root tab.

Where:

- In `SleepTabView.heroSection`, below `quickStatsStrip` or as a small trailing action near the existing top bar.

Recommended component:

```text
SleepModeEntryCard
```

Visual behavior:

- Small horizontal card.
- Icon: `moon.zzz.fill`.
- Primary text: `Sleep Mode`.
- Secondary text:
  - If schedule off: `Wind down now`
  - If schedule on: `Tonight at 10:30 PM`
  - If active: `Active - hold to exit`
- Primary action: push `SleepModeView`.
- Secondary action: small schedule icon opens `SleepModeScheduleView`.

Why this works:

- Sleep Mode belongs to the nightly Sleep experience.
- It does not compete with Insights, Protocol, Biology, or Activity.
- It keeps the root tab count stable.

### Settings

Add a dedicated section in `SettingsTabView` after `ProfileSettingsView` and before `PrivacyControlsView`:

```text
SleepModeSettingsCard
```

Fields:

- Schedule enabled.
- Bedtime start.
- End time / wake time.
- Days of week.
- Remind before start: 0, 10, 20, 30 minutes.
- Auto-enter if app is open.
- Blackout after breathing.
- Optional brightness dimming.
- Focus setup checklist.
- Optional app/site shielding setup if entitlement is available.

Why Settings:

- Scheduling is a preference, not a nightly dashboard metric.
- Privacy and blocking permissions need deliberate setup, not a casual tap.

### Onboarding

Do not add to initial onboarding MVP.

Reason:

- Existing onboarding already covers HealthKit, sleep goal, research, notifications.
- Adding Screen Time / Focus setup during onboarding risks overwhelming the user.
- Add a contextual prompt after the user has seen the Sleep tab.

## Scheduling Design

### Data Model

```swift
struct SleepModeSchedule: Codable, Hashable, Sendable, Identifiable {
    var id: UUID
    var isEnabled: Bool
    var startHour: Int
    var startMinute: Int
    var endHour: Int
    var endMinute: Int
    var activeWeekdays: Set<Int> // Calendar weekday: 1...7
    var reminderLeadMinutes: Int
    var autoEnterWhenForeground: Bool
    var useFocusChecklist: Bool
    var useScreenTimeShields: Bool
    var createdAt: Date
    var updatedAt: Date
}
```

Important date rule:

- If `end` is earlier than `start`, treat the interval as overnight.
- Use the start time to calculate `sleepDateKey` with `SleepDateKey.sleepDateKey(forSessionStart:)`.
- Persist the user's calendar/time zone behavior. Use local calendar for UI and schedule display.

### Core Scheduling Service

```swift
@MainActor
@Observable
final class SleepModeScheduleService {
    func loadSchedule() async
    func saveSchedule(_ schedule: SleepModeSchedule) async throws
    func nextStartDate(now: Date) -> Date?
    func currentInterval(now: Date) -> DateInterval?
    func shouldAutoEnterForeground(now: Date) -> Bool
}
```

Responsibilities:

- Compute next schedule.
- Tell UI whether Sleep Mode should be active.
- Reschedule local notifications when settings change.
- Never rely on BGTaskScheduler for exact start.

### Reminder Notifications

Use `UNUserNotificationCenter` with `UNCalendarNotificationTrigger`.

Implementation:

- One repeating notification per active weekday.
- Identifier prefix: `sleep-mode-start-`.
- Content:
  - Title: `Sleep Mode`
  - Body: `Wind down is scheduled now. Open Better to start blackout mode.`
- Category/action:
  - `Start Sleep Mode`
  - This opens the app; the app routes into `SleepModeView`.

Privacy:

- Notification body should not mention health data, sleep scores, HRV, protocol data, or selected blocked apps.

### Foreground Auto-Enter

In `BetterApp`, the app already observes `scenePhase`.

Add a service check when scene becomes active:

```swift
.onChange(of: scenePhase) { _, newPhase in
    if newPhase == .active {
        sleepModeScheduleService.evaluateForegroundActivation()
    }
}
```

Root routing:

- Add an app-level optional route/sheet state in `RootTabView`, or inject a small `SleepModeCoordinator`.
- If the schedule is active and `autoEnterWhenForeground == true`, present `SleepModeView` full-screen.
- Avoid pushing into a nested NavigationStack unexpectedly.

Recommended presentation:

```swift
.fullScreenCover(item: $sleepModeCoordinator.activePresentation) {
    SleepModeView(...)
}
```

This keeps the black screen from fighting tab/navigation bars.

## Blocking / Mobile Behavior Control

### Path A - App-Store-Safe MVP Blocking

This is not true device blocking. It is intentional friction.

Features:

- Full-screen blackout.
- Hide tab/navigation bars.
- Long-press to exit.
- Optional brightness dimming.
- Optional idle timer disabled only during breathing, not all-night blackout by default.
- Focus setup checklist for notifications/calls.

What to say in the app:

- "Better can keep this screen dark and low stimulation. Use iOS Focus to silence notifications and allow calls."

What not to say:

- "Better blocks your phone."
- "Better turns off notifications."
- "Better prevents all distractions."

### Path B - Real App/Site Shielding With Screen Time APIs

Use this only after product validation.

Required components:

```text
Better app
├── FamilyControls authorization
├── FamilyActivityPicker setup UI
├── App Group storage for opaque tokens/schedule
├── DeviceActivityCenter schedule
├── DeviceActivityMonitor extension
├── ManagedSettingsStore shield application
├── ShieldConfiguration extension               # optional custom shield UI
└── ShieldAction extension                      # optional unlock/override action
```

User setup flow:

1. User opens Sleep Mode settings.
2. User taps `Block distracting apps during Sleep Mode`.
3. Better explains what it will do and that selections stay private/opaque.
4. Better calls `AuthorizationCenter.shared.requestAuthorization(for: .individual)`.
5. User approves with biometric auth.
6. Better presents `FamilyActivityPicker`.
7. User selects apps/categories/websites.
8. Better saves opaque `FamilyActivitySelection`.
9. Better schedules `DeviceActivitySchedule`.
10. Monitor extension applies shield at interval start and clears it at interval end.

Privacy benefit:

- Apple's picker uses opaque tokens. Better does not need to know exact app names or websites.

App Store risk:

- Family Controls is a managed capability. Apple must approve it for distribution.
- The feature must be clearly user-benefiting and user-controlled.
- Do not use VPN, MDM profiles, private APIs, or deceptive lockout behavior.

Implementation detail:

- Keep this behind a compile-time capability flag:

```swift
#if canImport(FamilyControls)
// Screen Time setup
#endif
```

- Also keep runtime feature availability:

```swift
enum SleepModeBlockingCapability {
    case inAppOnly
    case screenTimeAvailable
    case screenTimeAuthorized
    case screenTimeDenied
}
```

## Privacy Plan

### Data to Store

Store only what Better needs:

- Schedule time and enabled days.
- Breathing pattern and rounds.
- Sleep Mode session start/end.
- Whether blackout was used.
- Whether audio was used.
- Whether shielding was enabled.
- Opaque Family Controls tokens, only if Screen Time feature ships.

Do not store:

- Raw app usage history.
- Names of blocked apps/websites if avoidable.
- Notification contents from other apps.
- Microphone data.
- Location.
- Any cloud copy of Sleep Mode sessions.

### Persistence

Add SwiftData models:

- `StoredSleepModeSettings`
- `StoredSleepModeSchedule`
- `StoredSleepModeSession`
- Optional `StoredSleepModeShieldSelection`

Use `PersistenceJSON.encode` for:

- Full schedule/settings blobs.
- Session detail blobs.
- FamilyActivitySelection opaque token payloads.

Add to:

- `BetterPersistenceContainerFactory.schema`
- `LocalDataRepositoryProtocol`
- `LocalDataRepository`
- `MockLocalDataRepository`
- `LocalDataInventory`
- `PrivacyDataService.deleteAllLocalData`
- `DataMigrationService.migrateToEncryptedStorage`

### Export / Research

Add only derived fields:

- `sleep_mode_used`
- `sleep_mode_scheduled`
- `sleep_mode_started_at`
- `sleep_mode_ended_at`
- `sleep_mode_intent`
- `sleep_mode_breathing_rounds`
- `sleep_mode_blackout_minutes`
- `sleep_mode_audio_minutes`
- `sleep_mode_shielding_enabled`

Do not export:

- Selected app/site tokens.
- Blocked app names.
- Raw interaction events.

### App Privacy / Review

App Store Review Guidelines treat health, fitness, and medical data as sensitive. The app must not use health/fitness data for advertising or unrelated data mining, must disclose collected health data, and must not store personal health information in iCloud.

Source:

- App Store Review Guidelines, health data/privacy section: https://developer.apple.com/app-store/review/guidelines/

Better already fits the right model:

- Local-first storage.
- Explicit HealthKit copy.
- User-triggered export.
- No server dependency.

Sleep Mode should preserve that model.

## App Store Acceptance Plan

### Safe for First Submission

Use:

- SwiftUI UI.
- UserNotifications for reminders.
- App Intents for Better-specific shortcuts.
- AVAudioSession for local audio later.
- HealthKit read-only behavior unchanged.
- Local encrypted SwiftData storage.

Avoid:

- Private APIs.
- MDM profiles.
- VPN-based blocking.
- Claiming notification control that the app does not have.
- Medical treatment claims.
- Writing anything to HealthKit.
- Uploading sleep behavior data.

### If Adding Screen Time Shielding

Before implementation:

1. Request Family Controls entitlement in Apple Developer account.
2. Define the feature as user-controlled digital wellbeing / sleep routine support.
3. Add a privacy explanation for opaque app/category/domain selections.
4. Add extension targets and App Group storage.
5. Test on physical devices and TestFlight.
6. Keep the app usable without Screen Time approval.

Review copy:

- "Block selected distracting apps during your scheduled Sleep Mode."
- "Your selections are handled by Apple's Screen Time picker and stored as private tokens."
- "You can turn this off anytime."

Do not frame it as:

- Surveillance.
- Employee monitoring.
- Hidden parental control.
- Device lockdown.

## Detailed Phase Plan

### Phase 1 - Core Models And Schedule

Goal: add schedule/settings/session persistence with no visible UI risk.

Files:

- `Better/Core/Models/SleepModeModels.swift`
- `Better/Core/Repositories/RepositoryProtocols.swift`
- `Better/Core/Repositories/LocalDataRepository.swift`
- `Better/Core/Repositories/MockLocalDataRepository.swift`
- `Better/Core/Persistence/PersistenceModels.swift`
- `Better/Core/Services/SleepModeScheduleService.swift`
- `BetterTests/SleepModeScheduleServiceTests.swift`
- `BetterTests/LocalDataRepositoryTests.swift`

Tasks:

1. Add `SleepModeSettings`, `SleepModeSchedule`, `SleepModeSession`.
2. Add repository methods:
   - `saveSleepModeSettings`
   - `fetchSleepModeSettings`
   - `saveSleepModeSchedule`
   - `fetchSleepModeSchedule`
   - `saveSleepModeSession`
   - `fetchSleepModeSessions`
3. Add SwiftData models and schema entries.
4. Add mock repository storage.
5. Add inventory/delete/migration support.
6. Add schedule calculation tests for:
   - same-day interval
   - overnight interval
   - weekdays
   - disabled schedule
   - DST/time-zone sanity

Exit criteria:

- App builds.
- Existing tests still pass.
- New schedule tests pass.

### Phase 2 - Minimal UI Integration

Goal: expose Sleep Mode without changing root app structure.

Files:

- `Better/Features/Sleep/SleepTabView.swift`
- `Better/Features/SleepMode/SleepModeEntryCard.swift`
- `Better/Features/SleepMode/SleepModeView.swift`
- `Better/Features/SleepMode/SleepModeViewModel.swift`
- `Better/Features/SleepMode/SleepModeScheduleView.swift`
- `Better/Features/Settings/SettingsTabView.swift`

Tasks:

1. Add `SleepModeEntryCard` to the Sleep tab.
2. Add `SleepModeScheduleView` in Settings.
3. Use `.sheet(item:)` or `.fullScreenCover(item:)` for Sleep Mode presentation.
4. Keep setup UI compact and settings-like.
5. Do not add a sixth root tab.

Exit criteria:

- Sleep dashboard still feels like the primary screen.
- Sleep Mode can be opened manually.
- Schedule can be edited.

### Phase 3 - Notifications And Foreground Auto-Enter

Goal: make schedule useful within iOS limits.

Files:

- `Better/Core/Services/SleepModeNotificationService.swift`
- `Better/App/AppEnvironment.swift`
- `Better/App/BetterApp.swift`
- `Better/App/RootTabView.swift`

Tasks:

1. Add notification scheduling using `UNCalendarNotificationTrigger`.
2. Request notification permission only when user enables schedule/reminders.
3. Add action category for `Start Sleep Mode`.
4. Route notification tap/action into `SleepModeView`.
5. Add foreground auto-enter when the app is active at scheduled start.
6. Do not use BGTaskScheduler for exact activation.

Exit criteria:

- User receives bedtime reminder.
- Tapping reminder opens Better into Sleep Mode.
- If Better is already open, schedule can auto-present Sleep Mode.

### Phase 4 - Breathing And Blackout

Goal: ship the core sleep-support experience.

Files:

- `Better/Core/Services/BreathingSequenceEngine.swift`
- `Better/Features/SleepMode/BreathingLightView.swift`
- `Better/Features/SleepMode/SleepBlackoutView.swift`
- `Better/Core/Services/SleepModeSessionService.swift`

Tasks:

1. Add 3-4-7 breathing pattern engine.
2. Add test-only short duration pattern for UI tests.
3. Add full-screen breathing light.
4. Add blackout screen.
5. Add long-press exit progress.
6. Restore brightness and idle timer on:
   - exit
   - app background
   - interruption
   - next launch stale-session recovery
7. Persist session start/end and end reason.

Exit criteria:

- User can start, breathe, blackout, and exit.
- No stuck brightness / idle timer state.
- Session is saved locally.

### Phase 5 - Research Integration

Goal: make Sleep Mode visible in Better's analytics without claiming causality.

Files:

- `Better/Core/Services/ResearchAnalysisService.swift`
- `Better/Core/Models/ResearchAnalysisModels.swift`
- `Better/Core/Services/ResearchCSVExporter.swift`
- `Better/Features/Trends/...`

Tasks:

1. Join Sleep Mode sessions by `sleepDateKey`.
2. Add export fields.
3. Add insight only after enough sample size:
   - at least 5 Sleep Mode nights
   - at least 5 non-Sleep Mode nights
4. Phrase insights as association:
   - "On observed nights..."
   - "Associated with..."
   - "Not enough nights yet..."

Exit criteria:

- CSV export includes Sleep Mode context.
- Trends/Insights can summarize usage without medical claims.

### Phase 6 - Audio

Goal: add white/brown/pink noise safely.

Files:

- `Better/Core/Services/SleepAudioService.swift`
- `Better/Features/SleepMode/SoundscapePickerView.swift`
- `Better/Info.plist`

Tasks:

1. Start with generated white/brown/pink noise via `AVAudioEngine`, or local licensed loop assets.
2. Use `AVAudioSession` category `.playback` only during active playback.
3. Add `UIBackgroundModes` audio only if playback must continue when locked/backgrounded.
4. Handle calls, alarms, route changes, AirPods disconnects.
5. Add timer/fade-out.

Exit criteria:

- Audio works on physical device.
- Audio stops/fades predictably.
- No unnecessary background audio entitlement if not needed.

### Phase 7 - Optional Screen Time Shielding

Goal: add real selected app/site blocking if Apple entitlement is approved.

Files / targets:

- Main app:
  - `ScreenTimeShieldService.swift`
  - `ScreenTimeShieldSetupView.swift`
- New extension:
  - `BetterDeviceActivityMonitorExtension`
- Optional extensions:
  - `BetterShieldConfigurationExtension`
  - `BetterShieldActionExtension`
- Shared:
  - App Group storage for schedule and opaque selection tokens.

Tasks:

1. Request Family Controls entitlement.
2. Add `FamilyControls`, `DeviceActivity`, `ManagedSettings`.
3. Request `.individual` authorization.
4. Present `FamilyActivityPicker`.
5. Store opaque selection only.
6. Create `DeviceActivitySchedule`.
7. In monitor extension:
   - apply shields in `intervalDidStart`
   - clear shields in `intervalDidEnd`
8. Add user-visible disable control.
9. Add fallback UI if authorization denied or entitlement unavailable.

Exit criteria:

- Selected apps/sites shield during Sleep Mode interval.
- User can disable shields.
- App remains useful without entitlement.

## First Build Recommendation

Build in this order:

1. Phase 1: models/schedule persistence.
2. Phase 2: Sleep tab entry + Settings schedule.
3. Phase 3: notification reminder + foreground auto-enter.
4. Phase 4: breathing + blackout.

Do not start with Screen Time shielding.

Reason:

- It adds entitlement/review risk.
- It requires app extensions and App Group storage.
- It can delay the core feature.
- The core Sleep Mode experience is useful without device-level blocking.

After the core feature is validated, add Screen Time shielding as an optional advanced mode.

## Open Product Decisions

1. Should the default schedule be inferred from the user's average bedtime, or set manually?
2. Should Better ask for notification permission during onboarding, or only when enabling Sleep Mode schedule?
3. Should blackout let the phone auto-lock by default?
4. Should brightness dimming be opt-in or omitted?
5. Should app/site shielding be part of the main product, or a later "strict mode" toggle?
6. Should Sleep Mode usage be shown on the next-morning Sleep dashboard?
7. Should audio be generated noise, bundled loops, or both?

## Recommended UX Copy

For schedule:

> Sleep Mode can remind you at bedtime and open automatically when Better is already active.

For Focus:

> Use iOS Sleep Focus to silence notifications and allow calls from selected people.

For in-app blackout:

> Better can keep this screen dark and low stimulation. Hold to exit when you need to use the app.

For optional shielding:

> Block selected distracting apps during Sleep Mode. Your choices are handled by Apple's Screen Time picker and stored privately as opaque tokens.

Avoid:

> Better blocks your phone automatically.

> Better turns off all notifications except calls.

> Better treats insomnia.
