# Better Sleep Mode - Implementation Plan

Last updated: 2026-05-17

## Purpose

Add a sleep-support mode to Better that helps users wind down, reduce phone stimulation, and fall asleep. This is separate from the existing sleep analytics stack, but it should feed useful context back into the app's local sleep research model.

The feature should include:

- A low-stimulation Sleep Mode screen.
- Call-only interruption guidance through iOS Focus setup.
- Blackout screen while the sleep session is active.
- A deliberate unlock/exit gesture or button combination to prevent accidental checking.
- White noise / sleep sound playback.
- A breathing light sequence, starting with a 3-4-7 inhale-hold-exhale pattern.
- Local session logging so Better can later compare "Sleep Mode used" vs. sleep outcomes.

## Important iOS Constraints

These constraints should be explicit in product copy and implementation.

| Desired behavior | What Better can do | Constraint |
|---|---|---|
| Turn off every notification except calls | Guide the user to create/use an iOS Sleep Focus that allows calls from chosen people; optionally expose App Intents / Shortcuts to start a Better wind-down session | Third-party apps should not promise to programmatically suppress all system notifications. Notification filtering is controlled by iOS Focus settings. |
| Black out the screen | Render an in-app black screen with ultra-low brightness styling, hidden controls, optional temporary brightness dimming, and an intentional exit gesture | The app cannot control the whole device UI if the user leaves Better or locks the phone. Any brightness change must be restored on exit/background. |
| Require a special combination to unlock Better's sleep screen | Implement an in-app "hold both corners", long press sequence, or typed phrase to exit | This is not device-level lockout. It only protects the Better Sleep Mode screen. |
| White noise during sleep | Use `AVAudioSession` with background audio capability and local bundled/generative loop files | Requires app capability/configuration and careful handling of interruptions, route changes, and battery. |
| Breathing light sequence | Build a SwiftUI full-screen animation with configurable inhale/hold/exhale durations | Should respect Reduce Motion, avoid bright flashes, and avoid medical claims. |

References checked while writing this plan:

- Apple Focus user guide: https://support.apple.com/guide/iphone/set-up-a-focus-iphd6288a67f/ios
- Apple Focus Filters / App Intents documentation: https://developer.apple.com/documentation/appintents/focus
- Apple background audio guidance: https://developer.apple.com/documentation/avfaudio/avaudiosession
- Apple screen brightness API: https://developer.apple.com/documentation/uikit/uiscreen/brightness

## Product Shape

### New Surface

Add a new first-class `Sleep Mode` surface. Recommended navigation:

- Add a moon/bed secondary action on the existing Sleep tab hero.
- Add a full `Sleep Mode` screen as a pushed view from `SleepTabView`.
- Do not add a sixth root tab for MVP. The app already has five primary tabs and Sleep Mode is an action inside the Sleep domain, not an analytics section.

### Core User Flow

1. User opens Sleep tab.
2. User taps the Sleep Mode action.
3. Better shows a setup screen:
   - Start now.
   - Choose soundscape once audio ships.
   - Choose breathing pattern.
   - Enable blackout after breathing.
   - Reminder to turn on Sleep Focus / call-only Focus.
4. User starts a wind-down session.
5. Better shows breathing light sequence.
6. Better transitions to blackout screen with optional sound still playing.
7. User exits only through an intentional interaction.
8. Better logs the session locally.
9. Next morning, Better can show "Sleep Mode used" as a context factor alongside sleep score, latency, HRV, WASO, and sleep duration.

## MVP Scope

### Must Have

- `SleepModeView` entry point from Sleep tab.
- Full-screen breathing light with 3-4-7 sequence.
- Blackout screen after breathing.
- Intentional exit control.
- Sleep Mode settings persisted locally.
- Sleep Mode session record persisted locally.
- A context flag in research analysis: `sleep_mode_used`.
- Basic tests for the breathing phase timer and session logging.

### Should Have

- Multiple sound presets:
  - White noise
  - Brown noise
  - Pink noise
  - Rain
  - Ocean
  - Fan
- Audio fade in/out.
- Timer options: 20, 30, 45, 60, 90 minutes, all night.
- Haptics disabled by default, optional gentle start/stop haptic only.
- Shortcut/App Intent: "Start Better Sleep Mode".
- Focus setup education card with manual iOS Focus setup steps. Deep-link only to Better's own app settings/notification settings where supported.

### Not MVP

- Device-level notification blocking.
- Device-level lockout.
- Focus-mode automation or direct Focus switching.
- White noise playback. Build it in Phase 3 after the core session UI is stable.
- Remote/cloud sound downloads.
- Adaptive audio based on live biometrics.
- Medical claims about insomnia treatment.
- Alarm clock replacement.

## Architecture Fit

The current app uses:

- SwiftUI feature modules under `Better/Features`.
- Domain models under `Better/Core/Models`.
- SwiftData persistence through `LocalDataRepository`.
- Services under `Better/Core/Services`.
- Local-first encrypted storage for sensitive health and behavior data.

Sleep Mode should follow that structure:

```text
Better/
├── Core/
│   ├── Models/
│   │   └── SleepModeModels.swift
│   ├── Services/
│   │   ├── SleepModeSessionService.swift
│   │   ├── SleepAudioService.swift
│   │   └── BreathingSequenceEngine.swift
│   └── Persistence/
│       └── PersistenceModels.swift        # add StoredSleepModeSession/settings
└── Features/
    └── SleepMode/
        ├── SleepModeView.swift
        ├── SleepModeViewModel.swift
        ├── BreathingLightView.swift
        ├── SleepBlackoutView.swift
        ├── SoundscapePickerView.swift      # Phase 3
        └── FocusSetupCardView.swift
```

## Data Model

### `SleepModeSettings`

Store as a user preference, but treat it as privacy-relevant because it reveals bedtime behavior.

Suggested fields:

```swift
struct SleepModeSettings: Codable, Hashable, Sendable {
    var isEnabled: Bool
    var defaultSoundscape: SleepSoundscape
    var soundVolume: Double
    var audioTimerMinutes: Int?
    var breathingPattern: BreathingPattern
    var breathingRounds: Int
    var blackoutAfterBreathing: Bool
    var requireIntentionalExit: Bool
    var dimWhileBreathing: Bool
    var updatedAt: Date
}
```

### `SleepModeSession`

Persist one row per usage session:

```swift
struct SleepModeSession: Codable, Hashable, Sendable, Identifiable {
    var id: UUID
    var sleepDateKey: String
    var startedAt: Date
    var endedAt: Date?
    var breathingPattern: BreathingPattern
    var breathingRoundsCompleted: Int
    var soundscape: SleepSoundscape?
    var plannedAudioTimerMinutes: Int?
    var audioDurationSeconds: TimeInterval
    var blackoutDurationSeconds: TimeInterval
    var endedReason: SleepModeEndReason
    var createdAt: Date
    var updatedAt: Date
}
```

Recovery rule:

- If the app launches and finds an active session whose `endedAt` is nil, close it with `.interrupted` or `.abandoned` based on the last foreground timestamp. This prevents stale active sessions from corrupting research rows.

### `BreathingPattern`

Start with the device-inspired 3-4-7 pattern:

```swift
struct BreathingPattern: Codable, Hashable, Sendable, Identifiable {
    var id: String
    var name: String
    var inhaleSeconds: Double
    var holdSeconds: Double
    var exhaleSeconds: Double

    static let threeFourSeven = BreathingPattern(
        id: "3-4-7",
        name: "3-4-7",
        inhaleSeconds: 3,
        holdSeconds: 4,
        exhaleSeconds: 7
    )
}
```

## Services

### `BreathingSequenceEngine`

Pure logic, easy to test.

Responsibilities:

- Given a pattern, round count, and elapsed time, return current phase.
- Expose phase progress from `0...1`.
- Return total duration.
- Support pause/resume.
- Respect Reduce Motion by letting UI render as opacity changes instead of scale-heavy animation.

Test cases:

- Phase at 0s is inhale.
- Phase at 3.1s is hold for 3-4-7.
- Phase at 7.1s is exhale for 3-4-7.
- Phase wraps to next round at 14s.
- Completed state after configured rounds.

### `SleepAudioService`

Actor or `@MainActor` observable service wrapping `AVAudioPlayer` / `AVQueuePlayer`.

Responsibilities:

- Load bundled loop files.
- Start, pause, resume, stop.
- Fade volume up/down.
- Track playback duration.
- Handle route/interruption notifications.
- Keep audio playing in background when the user locks the phone, if the app has background audio capability.

Implementation notes:

- Configure `AVAudioSession` with `.playback` when sleep sound is central to the active session and should continue under Silent Mode / lock screen.
- Consider `.mixWithOthers` as a user-facing option only if Better should play under existing music or podcasts.
- Use local assets for the first audio version so the feature works offline.
- Add `UIBackgroundModes` audio only if the product explicitly wants playback while locked/backgrounded.
- Keep files small and loopable.
- Do not stream remote sleep sounds in MVP.
- For simple colored noise, consider generated noise with `AVAudioEngine` instead of storing large audio assets. For rain/ocean/fan, use loopable licensed assets and document licenses.

### `SleepModeSessionService`

Responsibilities:

- Start a session.
- Update progress counters.
- End a session with reason.
- Persist session rows via `LocalDataRepository`.
- Generate a lightweight context signal for research analysis.

## UI Plan

### Sleep Tab Entry

Add a compact Sleep Mode action near the top of `SleepTabView`:

- Icon: `moon.zzz.fill` or `bed.double.fill`.
- Label: `Sleep Mode`.
- Secondary detail: selected sound / breathing pattern.
- Action: push `SleepModeView`.

Do not crowd the existing dashboard. This should feel like an active nightly tool, not another analytics card.

### Setup Screen

Use the existing Better dark design system:

- `BetterColors.background`
- `BetterHealthCard`
- `BetterTypography`
- restrained controls
- no large marketing hero

Sections:

- Start button.
- Focus setup reminder.
- Breathing pattern selector.
- Soundscape picker once audio ships.
- Audio timer picker once audio ships.
- Blackout toggle.
- Exit protection toggle.
- Session intent picker:
  - `Fall asleep`
  - `Calm down`
  - `Back to sleep`

This gives the next-morning insight layer useful context without asking the user to type at night.

### Breathing Light

Full-screen, minimal UI:

- Black or near-black background.
- Center light that expands on inhale, holds steady, softens/shrinks on exhale.
- Phase label: `Inhale`, `Hold`, `Exhale`.
- Small countdown number.
- Very low brightness colors using `BetterColors.stageDeep` or a warm amber option.
- No dense text.

3-4-7 sequencing:

```text
Inhale: 3 seconds
Hold:   4 seconds
Exhale: 7 seconds
Round: 14 seconds
```

Default MVP duration:

- 6 rounds = 84 seconds.
- Then transition to blackout.

Functional improvements:

- Add a silent visual-only mode by default.
- Add an optional very low-volume breath cue later, but keep it off by default.
- Add a "Back to sleep" preset with fewer rounds and no setup friction.
- Add a one-tap "skip to blackout" control before controls hide.

### Blackout Screen

Full-screen black view:

- Hide navigation/tab bars.
- Hide controls after 2 seconds.
- Optional single dim glyph or nothing at all.
- Continue audio if enabled.
- Temporarily lower `UIScreen.main.brightness` only if the user opts in, store the previous value, and restore it on exit, app background, interruption, and crash-recovery best effort.
- Use `UIApplication.shared.isIdleTimerDisabled` only while an active blackout session intentionally needs the display to stay on. Default should allow auto-lock when audio-only sleep sound is running, because an all-night black screen still burns battery.
- Exit by one intentional gesture:
  - Press and hold both bottom corners for 2 seconds, or
  - Long-press the center for 4 seconds, then confirm.

Recommended MVP: long-press center for 4 seconds. It is simpler, more accessible, and testable.

Recommended user experience:

- Show a tiny progress ring while the long press is held.
- Do not require a second confirmation after a 4-second hold; the hold itself is the confirmation.
- Support iOS accessibility escape as an alternate exit.
- Add a test-only shorter hold duration for UI tests.

### Focus Setup Card

The card should be honest:

- "Use iOS Sleep Focus to silence notifications and allow calls from chosen people."
- Provide steps to configure Settings > Focus > Sleep / Do Not Disturb > People > Allow Calls From.
- A button may open Better's app settings using `UIApplication.openSettingsURLString`, but do not imply the app can deep-link directly into the Focus configuration screen unless validated on the target iOS version.
- Offer Shortcuts/App Intent later for "Start Better Sleep Mode".

Avoid claiming Better itself blocks notifications.

UI improvements:

- Show a compact checklist:
  - Sleep Focus created.
  - Calls from Favorites/selected contacts allowed.
  - Better Sleep Mode shortcut optional.
- Let users dismiss the card once configured.
- Keep the warning copy short; avoid making the sleep flow feel like a settings tutorial every night.

## Persistence Changes

Add repository methods:

```swift
func saveSleepModeSettings(_ settings: SleepModeSettings) async throws
func fetchSleepModeSettings() async throws -> SleepModeSettings
func saveSleepModeSession(_ session: SleepModeSession) async throws
func fetchSleepModeSessions(from startKey: String, to endKey: String) async throws -> [SleepModeSession]
```

Add SwiftData models:

- `StoredSleepModeSettings`
- `StoredSleepModeSession`

Update all repository implementations:

- `LocalDataRepository`
- `MockLocalDataRepository`
- preview data helpers
- repository tests

Encryption:

- Use the existing `PersistenceJSON.encode` path for complex fields.
- Session records should be treated like context/protocol adherence because they describe health behavior.
- If stored as separate SwiftData scalar columns, avoid storing unnecessary granular interaction events.

## Research / Analytics Integration

Add Sleep Mode as a context factor rather than a sleep score input.

In `ResearchAnalysisService`, add fields to nightly rows:

- `sleep_mode_used`
- `sleep_mode_started_at`
- `sleep_mode_intent`
- `sleep_mode_audio_minutes`
- `sleep_mode_breathing_rounds`
- `sleep_mode_blackout_minutes`
- `sleep_mode_end_reason`

Insights to support later:

- Sleep latency on Sleep Mode nights vs. non-Sleep Mode nights.
- WASO on Sleep Mode nights vs. non-Sleep Mode nights.
- HRV and sleep score trends after repeated use.
- Caveat when sample size is below 5 nights in either group.

Do not claim causation. Match the app's existing protocol-analysis language: "associated with", "observed nights", and confidence caveats.

Important analytics rule:

- Join by `sleepDateKey`, but use the Sleep Mode session start time to resolve edge cases. A session started before noon should not accidentally attach to the previous night's sleep.

## App Intents / Shortcuts

Add after MVP if the in-app flow is stable.

Candidate intents:

- `StartSleepModeIntent`
- `StopSleepModeIntent`
- `StartBreathingIntent`
- `PlaySleepSoundIntent`

Use cases:

- User creates a personal automation: when Sleep Focus turns on, open/start Better Sleep Mode.
- User says a shortcut phrase to start the wind-down routine.

Do not depend on Shortcuts for the MVP because user setup friction is high.

Correctness notes:

- App Intents can start Better-specific actions, but they do not grant Better permission to globally toggle Sleep Focus or silence unrelated apps.
- Focus Filters are useful only if Better has app-specific behavior or notification filtering to adapt while a Focus is active. They are not a general "turn on Focus" API.
- If a Focus Filter is added, it likely belongs in an App Intents extension and may need App Groups for shared state.

## Capability / Project Changes

Potential `Info.plist` / entitlement changes:

- Add background audio mode only if sound must continue when locked/backgrounded:

```xml
<key>UIBackgroundModes</key>
<array>
    <string>audio</string>
</array>
```

- Add any audio asset licensing notes to project documentation.
- Keep HealthKit permissions unchanged; Sleep Mode itself does not require new HealthKit read permissions.

Audio session behavior:

- Set `AVAudioSession.sharedInstance().setCategory(.playback, options: ...)` before playback.
- Activate the audio session only when audio starts, then deactivate on stop to avoid interrupting other audio unnecessarily.
- Handle interruption notifications for calls and alarms.

## Accessibility

Requirements:

- Respect Reduce Motion:
  - Use opacity and gentle brightness shifts instead of large scale animation.
- Respect VoiceOver:
  - Breathing phase should be readable but not spam announcements every second.
- Avoid bright flashing.
- Keep exit gesture accessible:
  - Provide an alternate hidden but reachable accessibility escape action.
- Do not depend on a multi-touch corner gesture as the only exit path; it is harder for some users and harder to test reliably.
- Support Dynamic Type on setup screens.
- Keep blackout screen genuinely dark for OLED devices.

## Privacy

Principles:

- Sleep Mode sessions stay on-device.
- No audio analytics.
- No microphone usage.
- No cloud sound downloads in MVP.
- No raw interaction telemetry.
- Include Sleep Mode data in privacy inventory and full local data deletion.
- Make brightness control opt-in and explain it plainly; changing system brightness is noticeable outside the app if restoration fails.

Update:

- `PrivacyDataService` inventory counts.
- Settings export/data deletion copy if needed.
- Research ZIP schema if Sleep Mode fields are exported.

## Testing Plan

Unit tests:

- `BreathingSequenceEngineTests`
- `SleepModeSessionServiceTests`
- `SleepModeSettingsPersistenceTests`
- Research row joins with Sleep Mode sessions.

UI tests:

- Start Sleep Mode from Sleep tab.
- Complete one short breathing pattern using test-only durations.
- Enter blackout screen.
- Exit via long press.
- Verify session persisted.

Manual device tests:

- Audio continues when the phone locks, if background audio is enabled.
- Audio stops/fades correctly on phone call interruption.
- Route changes: AirPods disconnect, speaker route, silent switch.
- Brightness is restored after exit, app backgrounding, force close/reopen, and lock/unlock.
- Idle timer behavior is correct for breathing, blackout, audio-only, and no-audio sessions.
- Screen remains black and does not show tab bar controls.
- Focus setup copy is accurate on a real iPhone.

Simulator limits:

- Background audio and Focus behavior need physical-device validation.
- Notification silencing cannot be fully validated inside the app.

## Phase Plan

### Phase 1 - Product Foundation

Goal: add the models, settings, and pure breathing engine without changing root navigation.

Tasks:

1. Add `SleepModeModels.swift`.
2. Add `BreathingSequenceEngine.swift`.
3. Add unit tests for 3-4-7 sequencing.
4. Add local repository contracts for settings/session persistence.
5. Add SwiftData storage models and migration-safe defaults.
6. Update `MockLocalDataRepository`, preview data, and repository tests.

Exit criteria:

- Tests prove phase sequencing.
- App builds with no UI changes.

### Phase 2 - In-App Sleep Mode MVP

Goal: make the feature usable inside the app.

Tasks:

1. Add `Features/SleepMode`.
2. Add Sleep tab entry point.
3. Build setup screen.
4. Build full-screen breathing light.
5. Build blackout screen.
6. Persist started/completed sessions.
7. Add short test-only pattern support for UI tests.
8. Add lifecycle handling for stale sessions, brightness restoration, and idle timer reset.

Exit criteria:

- User can start, complete, blackout, and exit.
- Session appears in local persistence.

### Phase 3 - Audio

Goal: add reliable white noise playback.

Tasks:

1. Add local loop assets.
2. Add `SleepAudioService`.
3. Add soundscape picker.
4. Add timer and fade out.
5. Configure background audio if required.
6. Test interruptions and route changes on device.
7. Add explicit audio-session activation/deactivation rules.

Exit criteria:

- White noise plays looped.
- Timer stops cleanly.
- Audio interruption behavior is predictable.

### Phase 4 - Focus / Shortcuts Integration

Goal: reduce friction around call-only Sleep Focus without overpromising system control.

Tasks:

1. Add Focus setup card.
2. Add Settings deep link where appropriate.
3. Add `StartSleepModeIntent`.
4. Add Shortcuts setup instructions in-app.
5. Consider Focus Filter support only if there is a meaningful Better-specific filter state to apply.

Exit criteria:

- User has a clear path to call-only interruption settings.
- Shortcut can start Sleep Mode.

### Phase 5 - Research Integration

Goal: make Sleep Mode useful to Better's analytics.

Tasks:

1. Join `SleepModeSession` into `ResearchAnalysisService`.
2. Add export fields.
3. Add an Insights card once enough nights exist.
4. Add caveats for small samples and confounders.
5. Add privacy inventory support.

Exit criteria:

- Sleep Mode usage appears in research rows.
- The app can compare Sleep Mode vs. non-Sleep Mode nights without causal claims.

## Open Decisions

1. Should Sleep Mode become a root tab later, or stay inside Sleep?
2. Should audio continue all night by default, or stop after 30/60 minutes?
3. Which exact exit gesture should ship first?
4. Should breathing default to 6 rounds, or should the user choose duration before each session?
5. Do we want generated audio assets, licensed assets, or simple synthesized noise?
6. Should brightness dimming be offered, or should the MVP use a pure black UI and avoid changing system brightness?
7. Should the app keep the screen awake during blackout, or let iOS auto-lock after the breathing flow?

## Recommended First Build

Build Phase 1 and Phase 2 first, without audio and without Shortcuts.

Reason:

- The breathing light and blackout mode are the highest-signal product test.
- They do not require new app capabilities.
- They avoid iOS Focus limitations.
- They create local behavioral data that can later become part of Better's analytics.
- Audio and Shortcuts can be layered on after the session model and UI are stable.
