# Red Light Filter Toggle — Feasibility Research

**Goal:** Add a single toggle in the Better app that turns the entire iOS screen red (like Accessibility → Display & Text Size → Color Filters → Color Tint set to red) to help the user fall asleep by removing blue light.

**TL;DR:** iOS does **not** allow third-party apps to programmatically change system Accessibility settings, system color filters, Night Shift, or True Tone. Apple's sandbox blocks this for security/privacy reasons. There is **no public API** that does what the user is describing system-wide. However, several **legitimate workarounds** exist, ranging from "works only inside our app" to "one-tap via Apple Shortcuts after one-time setup."

---

## 1. What iOS Does and Does Not Allow

### ❌ Not possible from a third-party app
| Capability | Why blocked |
|---|---|
| Toggle **Accessibility → Color Filters** programmatically | No public API. `UIAccessibility` only exposes *read* properties (e.g. `UIAccessibility.isInvertColorsEnabled`), never *write*. |
| Toggle **Night Shift** / change its color temperature | Private framework (`CoreBrightness`). Using it = App Store rejection. |
| Toggle **True Tone**, **Reduce White Point**, **Smart Invert** | Same — read-only via `UIAccessibility`. |
| Deep-link directly to a specific Settings subpage (e.g. `prefs:root=ACCESSIBILITY&path=…`) | The `prefs:` URL scheme is private. Apps that ship with it get rejected. `UIApplication.openSettingsURLString` only opens the app's own settings page. |
| Apply a screen tint that persists after the user leaves the app | iOS sandbox: no app can draw outside its own window. |

### ✅ Possible
| Capability | Scope |
|---|---|
| Draw a red overlay over **our own app's UI** | Only while Better is in the foreground. |
| Install / run an **Apple Shortcut** that flips Color Filters | System-wide. Requires one-time user setup. |
| Trigger Color Filters via the **Accessibility Shortcut** (triple-click side button) | System-wide. User must enable it once in Settings. |
| Open Settings (the app's own settings page) | `UIApplication.openSettingsURLString` is the only sanctioned deep link. |
| Suggest / donate a Siri Shortcut intent | User can then say "Hey Siri, sleep red light." |

---

## 2. Approach Options, Ranked

### Option A — In-App Red Overlay (works today, ships immediately)
A `Color.red.opacity(0.55)` view layered above the root with `.allowsHitTesting(false)` and `.blendMode(.multiply)` or `.blendMode(.plusDarker)`.

- **Pros:** Pure SwiftUI, zero entitlements, instant.
- **Cons:** Only red while Better is foregrounded. The moment the user locks the phone or switches apps, it's gone — which defeats the bedtime use case (they're going to put the phone down or check Messages).
- **Verdict:** Good as a **bonus** ("red mode" inside Better's own night dashboard) but does not satisfy the user's actual goal.

```swift
// Sketch
ZStack {
    rootContent
    if redFilterOn {
        Color.red
            .opacity(0.55)
            .blendMode(.multiply)
            .ignoresSafeArea()
            .allowsHitTesting(false)
    }
}
```

### Option B — Pre-built Apple Shortcut + One-Tap Trigger (recommended)
Apple's **Shortcuts** app exposes a built-in action called **"Set Color Filters"** (and a sibling "Set Color Tint"). A Shortcut that calls this action *can* flip the system Color Filter on/off — Shortcuts has the entitlement that third-party apps lack.

Flow:
1. Better ships a **pre-configured Shortcut** ("Better — Red Sleep Mode") that the user installs from a `shortcuts://` link or iCloud share URL.
2. The Shortcut toggles Color Filters → Color Tint → Red (hue 0°, intensity max).
3. Better's toggle button calls `UIApplication.shared.open(URL(string: "shortcuts://run-shortcut?name=Better%20Red%20Sleep%20Mode")!)` to run it.
4. Optional: donate an `INIntent` so Siri / Spotlight / Lock Screen widget can run it too.

- **Pros:** True system-wide red tint. Legitimate, App-Store-safe.
- **Cons:** One-time user setup (install the Shortcut). Running it briefly switches to the Shortcuts app and back — there's a visible jump unless we use a Personal Automation that runs silently.
- **Silent variant:** A **Personal Automation** triggered by an "Open App: Better" event, or by a NFC tag / time-of-day, can run the Color Filters action with "Run Immediately" + "Notify When Run = off." From iOS 16.4+ Personal Automations can run without confirmation.
- **Verdict:** This is the best legitimate path. Reframe the in-app toggle as "Sleep Mode → enables red tint via your Shortcut."

### Option C — Accessibility Shortcut (triple-click)
Settings → Accessibility → Accessibility Shortcut → check **Color Filters**. Then triple-clicking the side/Home button toggles the system filter (which the user has pre-configured as red).

- **Pros:** Zero app-side work; fastest physical action.
- **Cons:** Not "a toggle in the app." Better can only *teach* the user to set this up.
- **Verdict:** Document it as a fallback for users who don't want Shortcuts.

### Option D — Focus Filter (iOS 16+)
Apps can vend a **Focus Filter** (`SetFocusFilterIntent`) that activates when the user enables a specific Focus (e.g., Sleep Focus). The filter can change in-app state — but **it cannot change system Color Filters**. Same sandbox limit.

- **Verdict:** Useful for syncing Better's *in-app* night mode with Sleep Focus, but does not solve the system-wide red-tint goal.

### Option E — HomeKit "Adaptive Lighting" / Smart Bulbs
If the user has HomeKit-compatible bulbs (Hue, Nanoleaf, etc.), the app could toggle the room lights to red via the HomeKit SDK. Doesn't change the phone screen but addresses the *real* goal ("remove blue light at bedtime") more completely.

- **Verdict:** Adjacent feature, not a replacement.

### Option F — Private APIs (`CoreBrightness`, `prefs:` URLs, MobileGestalt)
Some jailbreak tweaks and internal Apple tooling can toggle Night Shift / Color Filters directly. **Do not use.** Guaranteed App Store rejection, possible developer-account flags.

---

## 3. Production-Grade Plan (Verified Reality Check)

> **Important caveat I want to be honest about up front.** I had `WebSearch` unavailable in this session, so the facts below are stated from Apple's published behavior over iOS 16–18 and the public Shortcuts documentation linked at the bottom. Before shipping, the implementing engineer should verify each step on the latest iOS version on a real device — Apple sometimes tightens or relaxes Shortcuts/Automation behavior in point releases.

### 3.1 The actual capability stack

| Layer | What it does | Where the work lives |
|---|---|---|
| **System Color Filter** (the thing that turns the screen red) | Settings → Accessibility → Display & Text Size → Color Filters → Color Tint → hue/intensity | iOS — **must be pre-configured by the user**. The Shortcut action toggles this filter on/off but cannot set hue or intensity. |
| **Accessibility Shortcut** | Triple-click side/Home button toggles the pre-configured Color Filter | iOS Settings → Accessibility → Accessibility Shortcut → check "Color Filters" |
| **Shortcuts app, "Set Color Filters" action** | A built-in Shortcut action with Turn On / Turn Off / Toggle | Shortcuts app — invokable via `shortcuts://run-shortcut?name=…` from Better |
| **Personal Automation** (optional) | Runs a Shortcut on a trigger (open app, time, NFC). Can run without confirmation on most triggers since iOS 16.4. | Shortcuts app → Automation tab. **Not strictly needed** for the user's goals; lives in v2. |

Three crucial constraints:

1. The "Set Color Filters" Shortcut action **does not pick the color** — it just flips on whatever the user pre-configured in Settings. So configuring Color Tint = red is a mandatory one-time setup step.
2. Better cannot run the Shortcut completely silently from inside the app. `shortcuts://run-shortcut?name=…` opens the Shortcuts app, runs the action, and bounces back. There is a visible ~0.5–1s flicker. The only way to avoid this is a Personal Automation triggered by something other than our app's button — which doesn't fit a "toggle button" UX.
3. The **triple-click side button** is the *only* mechanism that toggles the filter when Better isn't running. There is no third-party API to do this from a locked screen or background. The user's "works even if app is not open" goal is satisfied entirely by the Accessibility Shortcut, not by anything Better ships.

### 3.2 What the user actually experiences

**Better's setup wizard (one-time, ~45 seconds, the only time the user sees the "details"):**

```
Step 1/3 — Configure your red tint
  [Open Settings] → Better opens Settings app.
  We show a card overlay illustration of the path:
    Accessibility → Display & Text Size → Color Filters
      → Color Filters: ON
      → Color Tint
      → Hue: full red (slider all the way right)
      → Intensity: full
  User flips back to Better (or we detect via app-active notification).

Step 2/3 — Install the one-tap toggle
  [Install Shortcut] → opens iCloud Shortcut share URL → Shortcuts app
    → user taps "Add Shortcut"
  We detect install by attempting `shortcuts://run-shortcut?name=Better Red Mode`
  with a sentinel mode and listening for openURL callback.

Step 3/3 — Enable triple-click toggle (optional but recommended)
  [Open Settings] → user navigates to Accessibility → Accessibility Shortcut
    → check "Color Filters"
  We mark this step "skippable" — works without it; just no triple-click.
```

After setup the user only ever sees:

- **One toggle in Better** — Settings → Sleep Mode → "Red Light Filter" (and a duplicate quick-access tile on the Sleep dashboard).
- **Triple-click side button** — works system-wide, even when phone is locked. ✓ matches the user's "even if app is not open" goal.
- **(Bonus) "Hey Siri, red mode"** — donated via App Intents.

### 3.3 Implementation, file by file

**New files**
```
Better/Core/Services/RedFilterService.swift
Better/Features/Settings/RedFilterSetupView.swift          // 3-step wizard
Better/Features/Settings/RedFilterSetupViewModel.swift
Better/Features/Sleep/Components/RedFilterToggleTile.swift // dashboard tile
Better/AppIntents/ToggleRedFilterIntent.swift              // Siri + Shortcuts donation
```

**Modified files**
```
Better/App/AppEnvironment.swift        // inject RedFilterService
Better/Features/Settings/SettingsView.swift  // new "Sleep Mode" section
Better/Features/Sleep/SleepDashboardView.swift  // add the tile
Better/Info.plist                      // LSApplicationQueriesSchemes += "shortcuts"
Better/Better.entitlements             // no new entitlements required
```

**`RedFilterService.swift` — the single source of truth**

```swift
import UIKit
import Combine
import AppIntents

@Observable
final class RedFilterService {

    enum SetupState: Codable {
        case notStarted
        case tintConfigured        // user did step 1
        case shortcutInstalled     // user did step 2 (we mark optimistically)
        case triClickEnabled       // user did step 3 (we cannot detect; user asserts)
        case complete
    }

    // Persisted via @AppStorage in the view layer; service exposes plain reads.
    private(set) var setupState: SetupState
    private(set) var lastToggledOn: Bool   // optimistic UI mirror — iOS won't tell us

    private let shortcutName = "Better Red Mode"
    private let iCloudShortcutURL = URL(string: "https://www.icloud.com/shortcuts/REPLACE_WITH_REAL_ID")!

    // MARK: - User actions

    func openColorTintSettings() {
        // Only public deep link. Shows app's own Settings page on iOS 18,
        // but the wizard's instructional card guides the user from there.
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    func installShortcut() {
        UIApplication.shared.open(iCloudShortcutURL)
    }

    @discardableResult
    func toggle() -> Bool {
        guard let url = runShortcutURL() else { return false }
        UIApplication.shared.open(url)
        lastToggledOn.toggle()
        return true
    }

    func openAccessibilityShortcutSettings() {
        openColorTintSettings()  // same public hook; wizard shows the path
    }

    // MARK: - Detection

    var isShortcutInstalled: Bool {
        guard let url = runShortcutURL() else { return false }
        return UIApplication.shared.canOpenURL(url)
    }

    private func runShortcutURL() -> URL? {
        let encoded = shortcutName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? shortcutName
        return URL(string: "shortcuts://run-shortcut?name=\(encoded)")
    }
}
```

**`ToggleRedFilterIntent.swift` — Siri + Spotlight + Lock-Screen widget**

```swift
import AppIntents

struct ToggleRedFilterIntent: AppIntent {
    static let title: LocalizedStringResource = "Toggle Red Sleep Mode"
    static let openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult {
        // Forward to the system Shortcut by name.
        let name = "Better Red Mode".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let url = URL(string: "shortcuts://run-shortcut?name=\(name)")!
        await UIApplication.shared.open(url)
        return .result()
    }
}
```

**`Info.plist` addition**
```xml
<key>LSApplicationQueriesSchemes</key>
<array>
    <string>shortcuts</string>
</array>
```

### 3.4 Hiding the details — UX rules

- The wizard runs **once**, full-screen, with our existing onboarding gradient/glass tokens (per [CLAUDE.md](CLAUDE.md) Modern UI Design Patterns).
- After completion the user **never** sees the words "Shortcut" or "Color Filter" again — they just see the toggle labeled **Red Sleep Mode**.
- If `isShortcutInstalled` becomes false later (user deleted it), the toggle quietly returns to the wizard at step 2 — no errors, no jargon.
- If the user toggles before completing setup, we silently fall back to the **in-app overlay** so the toggle never feels broken.

### 3.5 Why we are NOT using Personal Automations in v1

Personal Automations triggered by "Open app: Better" can run silently and would eliminate the visible Shortcuts flicker. But:

- They only fire when the app *opens*, not on an in-app button press.
- Setting one up requires the user to navigate Shortcuts → Automation → "Create Personal Automation" — three more setup screens.
- The marginal UX win (≤1s flicker removed) does not justify the setup cost.

Reserve this for a v2 "Hands-free" mode where opening Better at night auto-tints the screen.

### 3.6 QA checklist before shipping

- [ ] Verify "Set Color Filters" action exists in current iOS Shortcuts version and supports **Toggle**.
- [ ] Verify `shortcuts://run-shortcut?name=…` bounces back to Better automatically (it should — Shortcuts apps closes when the action completes if the Shortcut has no "Show Result" step).
- [ ] Verify `canOpenURL("shortcuts://…")` correctly returns false when the Shortcut is uninstalled.
- [ ] Test the 3-step wizard on a brand-new iCloud account where the Shortcut isn't pre-installed.
- [ ] Test triple-click toggle while the phone is locked.
- [ ] Test Siri intent ("Hey Siri, red sleep mode").
- [ ] Test the fallback in-app overlay path for users who skip Shortcut setup.

### 3.7 Files this would touch in Better
- `Features/Settings/` — new "Sleep Mode" section + `RedFilterSetupView`.
- `Features/Sleep/` — `RedFilterToggleTile` on the dashboard.
- New `Core/Services/RedFilterService.swift`.
- New `AppIntents/ToggleRedFilterIntent.swift`.
- `App/AppEnvironment.swift` — inject the service.
- `Info.plist` — `LSApplicationQueriesSchemes` += `shortcuts`.

---

## 4. Apple Documentation to Read Before Implementing

| Topic | Reference |
|---|---|
| `UIAccessibility` properties (read-only) | developer.apple.com/documentation/uikit/uiaccessibility |
| Running Shortcuts via URL | support.apple.com/guide/shortcuts/run-shortcuts-from-the-url-scheme-apdf22b0444c |
| `AppIntents` framework (iOS 16+) | developer.apple.com/documentation/appintents |
| Focus Filters | developer.apple.com/documentation/appintents/focus-filters |
| `openSettingsURLString` (only public deep link to Settings) | developer.apple.com/documentation/uikit/uiapplication/1623042-opensettingsurlstring |
| App Review Guidelines §2.5.1 (no private API) | developer.apple.com/app-store/review/guidelines/#software-requirements |

---

## 5. Honest Summary for the Product Decision

The user's mental model — "an app should be able to flip the same switch I flip manually in Accessibility" — is reasonable but doesn't match how iOS is built. The closest legitimate experience is:

> **One-time setup:** install a Better-provided Shortcut.
> **From then on:** one tap in Better → screen turns red system-wide.

This is genuinely close to "a toggle in the app" and is shippable. Anything closer requires private APIs and Apple will reject it.

If we want a zero-setup version, we are limited to tinting *Better's own screens* — useful as a "night reading mode" but not the same product.
