# Red Light Filter Implementation Plan

**Date:** May 19, 2026  
**Scope:** iOS app implementation plan for Better's red light filter / red sleep mode feature.

## Verdict

The research in [RED_LIGHT_FILTER_RESEARCH.md](RED_LIGHT_FILTER_RESEARCH.md) is correct on the core platform constraint:

> Better cannot directly toggle iOS-wide Color Filters, Night Shift, True Tone, Reduce White Point, or draw over other apps using public App Store-safe APIs.

So this is not the only possible user-facing feature, but it is the only legitimate path that gets close to the requested product behavior:

1. **System-wide red tint:** Use Apple's **Shortcuts** app to run the built-in **Set Color Filters** action after the user configures Color Filters as red in Settings.
2. **Inside Better only:** Add a SwiftUI red overlay for Better's own Sleep Mode screens.
3. **Manual system fallback:** Guide the user to enable **Accessibility Shortcut** so triple-click toggles the preconfigured Color Filter.

Anything closer, such as directly changing the Color Filter hue/intensity from Better or toggling Night Shift via private frameworks, should be rejected because it relies on private APIs or unsupported Settings URL schemes.

## Corrections To The Research

The high-level recommendation is right, but the implementation plan should avoid these assumptions:

| Research assumption | Correction |
| --- | --- |
| `UIApplication.openSettingsURLString` can help open Accessibility settings | It only opens Better's own app settings page. It cannot deep-link to Accessibility > Display & Text Size. |
| `canOpenURL(shortcuts://run-shortcut?name=...)` can detect whether a named shortcut exists | It can only tell whether the Shortcuts URL scheme can be opened. It does not reliably prove the specific shortcut is installed. |
| Better can ship a pre-installed Shortcut | Better can link to an iCloud Shortcut or show setup instructions. The user still has to add it. |
| App Intent can directly call `UIApplication.shared.open(shortcuts://...)` with `openAppWhenRun = false` | Do not use this as v1 architecture. App Intents should either open Better into the setup/toggle screen or be deferred until device testing proves a compliant handoff. |
| Shortcut execution will always bounce back to Better | Treat this as a device-test item, not a guaranteed contract. The product must tolerate a visible Shortcuts app hop. |

## Source Check

Apple's current iPhone User Guide confirms Color Filters are user-configured from **Settings > Accessibility > Display & Text Size**, where the user can choose filters and adjust intensity or hue.

Apple's iPhone Accessibility Shortcut guide confirms triple-click side/Home button can turn selected accessibility features on or off.

Apple's Shortcuts User Guide confirms apps can run an installed shortcut with `shortcuts://run-shortcut?name=[name]`.

Apple's `UIApplication.openSettingsURLString` documentation confirms that public Settings linking is for the app's own settings page, not arbitrary system Settings pages.

## Product Shape

### V1 Experience

After one-time setup:

- User taps **Red Sleep Mode** inside Better.
- Better opens `shortcuts://run-shortcut?name=Better%20Red%20Sleep%20Mode`.
- Shortcuts runs the user's installed shortcut.
- iOS toggles the already-configured red Color Filter system-wide.
- Better keeps an optimistic local state label, but never claims it can read the true system Color Filter state.

### Required One-Time Setup

Better cannot remove this setup. The app should make it short and non-technical:

1. User configures iOS Color Filters as red manually.
2. User adds the Better shortcut from an iCloud Shortcut URL.
3. Optional but recommended: user adds Color Filters to Accessibility Shortcut for triple-click access.

### In-App Fallback

If setup is incomplete or the Shortcuts handoff fails, Better should still apply a red overlay inside Sleep Mode. This does not solve system-wide tinting, but it prevents the toggle from feeling broken while staying honest in copy.

## Phase 0 - Device Validation Spike

**Goal:** Prove the exact iOS behavior on a real device before building product UI.

**Tasks:**

- Create a manual Shortcut named `Better Red Sleep Mode`.
- Add the Shortcuts action **Set Color Filters** with mode **Toggle**.
- Configure iOS Color Filters manually as red tint at high intensity.
- Run `shortcuts://run-shortcut?name=Better%20Red%20Sleep%20Mode` from a small local test button.
- Test the visible app transition and whether Shortcuts returns to Better.
- Test behavior when the Shortcut is missing.
- Test whether the action exists and works on the app's minimum supported iOS version.
- Test triple-click side button with Color Filters selected in Accessibility Shortcut.

**Exit criteria:**

- A foreground app button can trigger the Shortcut.
- Missing Shortcut behavior is understood.
- Triple-click reliably toggles the same preconfigured red tint.
- Product copy is updated to match observed behavior.

## Phase 1 - Core Service And State

**Goal:** Add a small, testable integration layer without overpromising system state visibility.

**New file:**

```text
Better/Core/Services/RedLightFilterService.swift
```

**Responsibilities:**

- Build the `shortcuts://run-shortcut` URL.
- Open the Better iCloud Shortcut install URL.
- Open app settings only where useful, but do not pretend it opens Accessibility settings.
- Persist setup progress:
  - `notStarted`
  - `colorTintConfiguredByUser`
  - `shortcutAddedByUser`
  - `accessibilityShortcutExplained`
  - `complete`
- Store an optimistic `lastRequestedState`, clearly named as local state.
- Expose `toggleSystemRedFilter()` returning a result enum:
  - `.openedShortcut`
  - `.shortcutsUnavailable`
  - `.setupIncomplete`
  - `.invalidURL`

**Important design rule:**

Do not model this as true system state. iOS does not expose whether Color Filters are currently enabled or whether their tint is red.

**Modified files:**

```text
Better/App/AppEnvironment.swift
Better/Info.plist
```

**Info.plist addition:**

```xml
<key>LSApplicationQueriesSchemes</key>
<array>
    <string>shortcuts</string>
</array>
```

Only add this if the implementation uses `canOpenURL` for the Shortcuts scheme. Do not use it as named-shortcut detection.

## Phase 2 - Setup Wizard

**Goal:** Convert unavoidable manual setup into a short guided flow.

**New files:**

```text
Better/Features/Settings/RedLightFilterSetupView.swift
Better/Features/Settings/RedLightFilterSetupViewModel.swift
```

**Wizard steps:**

1. **Make iPhone tint red**
   - Explain the path: Settings > Accessibility > Display & Text Size > Color Filters.
   - Show compact visual instructions.
   - User taps `I configured red tint`.
   - Optional button: `Open Settings`, using only public `UIApplication.openSettingsURLString` and copy that tells the user to navigate manually.

2. **Add Better shortcut**
   - Button opens the iCloud Shortcut share URL.
   - User returns and taps `I added the shortcut`.
   - Do not attempt false automatic detection of the named shortcut.

3. **Enable triple-click access**
   - Explain Settings > Accessibility > Accessibility Shortcut > Color Filters.
   - Mark as recommended, not required.
   - User can skip.

4. **Test toggle**
   - Button calls the service.
   - If successful, mark setup complete.
   - If not, show a plain-language recovery path.

**UX copy constraints:**

- Say "Red Sleep Mode" in user-facing primary UI.
- Keep "Shortcuts" and "Color Filters" inside setup/help screens only.
- Be honest: "Better uses your iPhone's Accessibility Color Filter through a Shortcut."

## Phase 3 - In-App Red Overlay Fallback

**Goal:** Provide immediate value in Better even without system-wide tinting.

**Implementation options:**

- Add overlay support to `SleepModeView`.
- Optionally add an app-wide overlay at the root only while Better is foregrounded.

**Preferred V1 scope:**

Start with Sleep Mode only:

```text
Better/Features/SleepMode/SleepModeView.swift
Better/Features/SleepMode/SleepModeViewModel.swift
```

**Behavior:**

- When Red Sleep Mode is locally enabled, overlay Sleep Mode screens with a non-interactive red blend.
- Do not apply the overlay to Settings or setup screens, where color accuracy and instructions matter.
- Make the overlay intensity configurable later only if users complain.

**Suggested SwiftUI approach:**

```swift
Color.red
    .opacity(0.48)
    .blendMode(.multiply)
    .ignoresSafeArea()
    .allowsHitTesting(false)
```

Device-test blend modes on OLED and LCD devices before finalizing opacity.

## Phase 4 - Settings And Sleep Dashboard Integration

**Goal:** Surface the feature where users expect it without cluttering the core sleep dashboard.

**Modified files:**

```text
Better/Features/Settings/SettingsTabView.swift
Better/Features/Sleep/SleepTabView.swift
Better/Features/SleepMode/SleepModeView.swift
```

**New components:**

```text
Better/Features/Settings/RedLightFilterSettingsCard.swift
Better/Features/SleepMode/RedLightFilterToggleRow.swift
```

**Settings card:**

- Shows setup status.
- Opens setup wizard when incomplete.
- Has a `Test Red Sleep Mode` action when complete.

**Sleep Mode entry:**

- Add a compact red-mode toggle row to the Sleep Mode intro screen.
- If setup complete, call the Shortcut.
- If setup incomplete, present setup wizard.
- Always enable the in-app red overlay for the current Sleep Mode session when requested.

**Avoid in V1:**

- Do not add a prominent tile to the main sleep dashboard until the setup/test path proves stable. A broken-looking system integration on the primary dashboard will reduce trust.

## Phase 5 - Shortcut Packaging

**Goal:** Make the external dependency maintainable.

**Tasks:**

- Create the official `Better Red Sleep Mode` Shortcut manually.
- Shortcut action:
  - `Set Color Filters` = `Toggle`
- Avoid extra actions that show alerts, notifications, or results.
- Publish through an iCloud Shortcut URL.
- Store the URL in a single constant in `RedLightFilterService`.
- Add a short internal note explaining how to regenerate the Shortcut if the iCloud link changes.

**Do not store:**

- Private URL schemes.
- Settings deep links using `prefs:`.
- Any private framework calls.

## Phase 6 - App Intents And Siri

**Goal:** Add system discoverability only after the foreground button path is stable.

**Recommendation: defer to V1.1.**

App Intents are still useful, but they should not be the v1 mechanism for flipping the Color Filter. A safer first intent is:

```text
Better/AppIntents/OpenRedSleepModeIntent.swift
```

**Behavior:**

- Opens Better directly into the Red Sleep Mode setup/toggle screen.
- Does not try to call `UIApplication.shared.open(shortcuts://...)` from a background intent.

**Possible V1.1 behavior after device validation:**

- Add an App Shortcut phrase like "Open Red Sleep Mode in Better".
- If foreground handoff is reliable, route to the same service action after opening the app.

## Phase 7 - QA Matrix

**Device coverage:**

- Latest iOS 26 device.
- One iOS 18 or iOS 17 device if Better supports it.
- Fresh install with no Shortcut.
- Existing install with Shortcut added.
- Shortcut deleted after setup complete.
- Color Filter configured as red.
- Color Filter configured incorrectly.
- Accessibility Shortcut enabled and disabled.

**Behavior checks:**

- Setup state survives app relaunch.
- Toggle opens Shortcuts URL.
- Missing Shortcuts app / unavailable scheme shows recovery.
- User can skip triple-click setup.
- In-app overlay does not block gestures.
- Sleep Mode blackout exit remains visible and usable.
- VoiceOver labels explain the setup controls.
- No private API usage appears in code review.

**Build checks:**

- Run app build with the normal Better scheme.
- Add unit tests for URL construction and setup state transitions.
- Add view model tests for incomplete setup, complete setup, and failure states.

## Phase 8 - Release Copy

**Settings label:**

```text
Red Sleep Mode
```

**Short description:**

```text
Tint your iPhone red at bedtime using your iPhone's Color Filters and a Better Shortcut.
```

**Setup disclaimer:**

```text
iOS does not let apps change display color filters directly. Better uses a Shortcut after you configure the red tint once.
```

**Fallback copy:**

```text
Better can still tint Sleep Mode inside the app. To tint your whole iPhone, finish Shortcut setup.
```

## Phase Order Summary

| Phase | Outcome | Ship Gate |
| --- | --- | --- |
| 0 | Real-device proof | Required before code merge |
| 1 | Service and persistent setup state | Unit-tested |
| 2 | Setup wizard | Usable without engineering explanation |
| 3 | In-app red overlay | Works inside Sleep Mode |
| 4 | Settings/Sleep Mode integration | Primary user path complete |
| 5 | Official Shortcut link | Stable iCloud Shortcut URL |
| 6 | App Intents/Siri | Defer unless validated |
| 7 | QA | No private API, no false state claims |
| 8 | Release copy | Honest App Review-safe messaging |

## Final Recommendation

Ship V1 as:

1. Guided setup for red Color Filters.
2. Better-provided Shortcut link.
3. Foreground Better button that runs the Shortcut.
4. Optional triple-click instructions.
5. In-app Sleep Mode red overlay fallback.

Do not spend engineering time trying to bypass iOS restrictions. The product win is making Apple's allowed path feel simple and trustworthy, not pretending Better has system privileges it cannot have.
