# Security & Vulnerability Analysis — Better iOS App

> Audit date: 2026-05-06  
> Scope: full static analysis of source, entitlements, Info.plist, and test targets  
> Methodology: manual code review of all Swift files, plist inspection, architecture cross-reference

---

## Quick Summary

| Severity | Count | Biggest risk |
|----------|-------|-------------|
| **App Store Blocker** | 3 | Encryption export declaration, HealthKit write description, missing background mode |
| **High** | 3 | Silent encryption fallback, background task race, HealthKit observer error swallowing |
| **Medium** | 3 | HealthKit permission breadth mismatch, migration silent failure, observer query leak |
| **Low** | 2 | Notification permission timing, Keychain error detail |

---

## Part 1 — App Store Blockers

These will get the app rejected or flagged during review.

---

### BLOCKER-1 · `ITSAppUsesNonExemptEncryption` is set to `false` — but you do use it

**File:** `Better/Info.plist:29`

```xml
<key>ITSAppUsesNonExemptEncryption</key>
<false/>
```

**What it means:** Setting this to `false` is a declaration to Apple that your app does not use non-exempt encryption. The app uses **AES-256-GCM implemented via CryptoKit** (`EncryptionService.swift`) to encrypt all health data written to SwiftData. That is non-exempt encryption by definition — you wrote the algorithm calls yourself, regardless of the underlying framework.

**Why it will block you:** Apple's App Store Connect submission process cross-checks this flag. If it's `false` and the app clearly uses AES, the binary analysis during review will catch it. Submitting a false declaration also carries export compliance liability under US EAR regulations.

**Fix:** Set `ITSAppUsesNonExemptEncryption` to `true`. This triggers the encryption documentation questions in App Store Connect. Answer them as follows:
- Does the app use encryption? **Yes**
- Is the encryption solely for data protection at rest? **Yes**
- Do you use only standard encryption algorithms (AES, RSA, etc.)? **Yes**
- Does the app transmit encrypted data outside the device? **No**

This path typically qualifies for self-classification under EAR, requires no ERN, and does not delay review.

---

### BLOCKER-2 · `NSHealthUpdateUsageDescription` claims HealthKit writes — none are implemented

**File:** `Better/Info.plist:33–34`

```xml
<key>NSHealthUpdateUsageDescription</key>
<string>Better asks before saving any sleep or wellness entries you choose to add to Apple Health.</string>
```

**File:** `Better/Core/Repositories/HealthKitRepository.swift:41`

```swift
healthStore.requestAuthorization(toShare: [], read: readTypes)
```

The write authorization request passes an **empty set** for `toShare`. The app never requests HealthKit write permissions, yet the usage description promises users it will. Apple's review team checks that usage descriptions accurately describe actual system usage. A mismatch here is grounds for rejection under the Privacy guideline (5.1.1).

**Fix (choose one):**
- **Option A (recommended):** Remove `NSHealthUpdateUsageDescription` entirely from Info.plist if no writes are planned for launch.
- **Option B:** If manual health entry writing to HealthKit is planned, add the write types to `toShare:` in `requestAuthorization()` and update the string to list the exact types that will be written.

---

### BLOCKER-3 · HealthKit background delivery needs `healthkit` in `UIBackgroundModes`

**File:** `Better/Info.plist:44–47`

```xml
<key>UIBackgroundModes</key>
<array>
    <string>fetch</string>
</array>
```

**File:** `Better/Core/Repositories/HealthKitRepository.swift:177`

```swift
healthStore.enableBackgroundDelivery(for: sleepType, frequency: .immediate) { _, _ in }
```

The app calls `enableBackgroundDelivery` with `.immediate` frequency. Apple's HealthKit documentation requires that apps using background delivery declare the `healthkit` background mode in `UIBackgroundModes`. The `com.apple.developer.healthkit.background-delivery` entitlement (which you have) controls the capability, but `UIBackgroundModes` controls whether the OS will wake the process for that delivery. Without `healthkit` in the array, background delivery wakeups may silently fail on-device even though they appear to work in the simulator.

**Fix:** Add `healthkit` to `UIBackgroundModes`:

```xml
<key>UIBackgroundModes</key>
<array>
    <string>fetch</string>
    <string>healthkit</string>
</array>
```

---

## Part 2 — High Severity

These don't block submission but represent meaningful security risks or instability.

---

### HIGH-1 · Encryption silently falls back to plain JSON on failure

**File:** `Better/Core/Persistence/PersistenceModels.swift:59–63`

```swift
nonisolated static func encode<T: Encodable>(_ value: T) throws -> Data {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let jsonData = try encoder.encode(value)
    return (try? EncryptionService.shared.encrypt(jsonData)) ?? jsonData  // ← plain-text written if encryption fails
}
```

The comment says "the store's own file protection still applies." That is true but incomplete. File protection (`FileProtectionType.complete`) only blocks access while the device is **locked**. An attacker with a jailbroken device or physical access immediately after unlock can read the SQLite file. The app promises users AES-256 encryption of health data in both its UI and its `PrivacyControlsView`. If the Keychain is momentarily unavailable (low-battery auto-lock race, Keychain reset), this promise breaks silently — no error, no log, the user never knows their data went in as plain text.

**Scenarios where this triggers:**
1. First launch on a new device where Keychain hasn't been set up yet and an iOS upgrade is in progress
2. `resetKey()` is called (e.g. in tests or a future privacy "delete all" flow) and a write happens before the new key is generated
3. MDM profile revokes Keychain access while the app is backgrounded

**Fix:** Throw instead of falling back. Let callers handle the error with a UI prompt:

```swift
nonisolated static func encode<T: Encodable>(_ value: T) throws -> Data {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let jsonData = try encoder.encode(value)
    return try EncryptionService.shared.encrypt(jsonData)  // let it throw
}
```

If you want write resilience during migration, handle the fallback explicitly in `DataMigrationService` with a logged warning, not in the generic encode path.

---

### HIGH-2 · Background task double-completion race condition

**File:** `Better/Core/Services/BackgroundTaskService.swift:101–124`

```swift
var didCompleteTask = false
let refreshTask = Task { @MainActor in
    await syncCoordinator.performIncrementalRefresh()
}

task.expirationHandler = {
    refreshTask.cancel()
    Task { @MainActor in
        guard !didCompleteTask else { return }
        didCompleteTask = true
        task.setTaskCompleted(success: false)  // path A
    }
}

await refreshTask.value

guard !didCompleteTask else { return }
didCompleteTask = true

// path B
task.setTaskCompleted(success: !refreshTask.isCancelled)
```

`didCompleteTask` is a local `var` accessed from two concurrent `Task { @MainActor in }` closures. Both path A and path B can proceed to call `setTaskCompleted()` if the expiration fires at the exact moment `await refreshTask.value` returns. `BGTask.setTaskCompleted()` called twice is documented as undefined behaviour and has crashed apps in production.

**Fix:** Use `Task.isCancelled` and a single completion point:

```swift
func handleSleepRefresh(task: BGAppRefreshTask) async {
    scheduleNextSleepRefresh()
    let refreshTask = Task { @MainActor in
        await syncCoordinator.performIncrementalRefresh()
    }
    task.expirationHandler = { refreshTask.cancel() }
    await refreshTask.value
    task.setTaskCompleted(success: !refreshTask.isCancelled)
}
```

---

### HIGH-3 · HealthKit observer errors silently swallowed — permission revocation goes undetected

**File:** `Better/Core/Repositories/HealthKitRepository.swift:162–166`

```swift
let query = HKObserverQuery(sampleType: sleepType, predicate: nil) { _, completionHandler, error in
    if error != nil {
        completionHandler()
        return
    }
    // …
}
```

**File:** `Better/Core/Repositories/HealthKitRepository.swift:177`

```swift
healthStore.enableBackgroundDelivery(for: sleepType, frequency: .immediate) { _, _ in }
```

When the user revokes HealthKit permission in Settings, the next observer callback fires with an error. The current code acknowledges the callback and silently continues. The app will keep running in a state where it thinks it has HealthKit access but doesn't, until the next foreground refresh (which will fail and set the fallback state). Background delivery errors are completely discarded.

**Fix:** On observer error, log it and push an event upstream so `SyncCoordinator` can update `authorizationState`:

```swift
if let error {
    logger.error("HealthKit observer error: \(error.localizedDescription, privacy: .public)")
    completionHandler()
    return
}
```

For background delivery:

```swift
healthStore.enableBackgroundDelivery(for: sleepType, frequency: .immediate) { success, error in
    if let error {
        logger.error("Background delivery failed: \(error.localizedDescription, privacy: .public)")
    }
}
```

---

## Part 3 — Medium Severity

Real issues that degrade security guarantees or user experience, but don't cause immediate data loss.

---

### MEDIUM-1 · HealthKit permission description doesn't cover all requested types

**File:** `Better/Info.plist:31–32`

```xml
<key>NSHealthShareUsageDescription</key>
<string>Better reads your sleep, heart, HRV, oxygen saturation, and respiratory data from Apple Health to show sleep trends and protocol insights.</string>
```

**File:** `Better/Core/Repositories/HealthKitRepository.swift:230–249`

The app requests **17 distinct HealthKit types**, including:
- `bodyMass`, `leanBodyMass`, `bodyFatPercentage`, `bodyTemperature` (body composition)
- `vo2Max` (fitness)
- `stepCount`, `activeEnergyBurned`, `appleExerciseTime`, `appleStandTime`, `flightsClimbed`, `distanceWalkingRunning` (activity)

None of these are mentioned in the usage description. Apple's review guideline 5.1.1 requires that the description "clearly and completely describes your app's use of the data." Requesting undisclosed types is flagged during review.

**Fix:** Update `NSHealthShareUsageDescription` to list all categories:

```
Better reads sleep, heart rate, HRV, blood oxygen, respiratory rate, body composition (weight, body fat, temperature), fitness (VO2 Max), and daily activity (steps, calories, exercise, stand hours) from Apple Health to power sleep insights and research tracking.
```

---

### MEDIUM-2 · Data migration silently leaves records unencrypted on error

**File:** `Better/Core/Repositories/LocalDataRepository.swift` (migration methods)

```swift
session.qualityScoreData = (try? PersistenceJSON.encode(domain.qualityScore)) ?? session.qualityScoreData
```

The `try?` pattern means if `PersistenceJSON.encode` throws (e.g., Keychain unavailable during migration), the original unencrypted data is kept in place without any log entry, warning, or retry. After migration completes, `UserDefaults` records migration as done. On the next launch, migration is skipped. The record stays unencrypted forever.

**Fix:** Either propagate the error out of the migration function so it retries on next launch, or log a specific warning that a record remained unencrypted.

---

### MEDIUM-3 · Observer query array is append-only — potential memory leak on repeated observation starts

**File:** `Better/Core/Repositories/HealthKitRepository.swift:343–347`

```swift
func retainObserverQuery(_ query: HKObserverQuery) {
    observerLock.lock()
    observerQueries.append(query)
    observerLock.unlock()
}
```

`stopObserverQuery` does remove entries, but if `startObservingSleepChanges()` is called more than once without a corresponding stop (e.g., due to a reconnect loop or a bug in the caller), queries accumulate indefinitely. Each retained query holds a reference to the `HKHealthStore`.

**Fix:** Add a guard at the start of `startObservingSleepChanges()` that stops and removes all existing observer queries before registering a new one.

---

## Part 4 — Low Severity

Minor issues worth addressing before launch.

---

### LOW-1 · Notification permission requested at app launch, before the user enables notifications

**File:** `Better/Core/Services/AlertGenerationService.swift:19–41`

`localNotificationsEnabled` defaults to `false`. However, depending on how `AlertGenerationService` is wired in `AppEnvironment`, authorization may be requested during onboarding regardless of whether the user will ever enable notifications. iOS gives each app **one** system permission prompt for notifications. Wasting it before the user has expressed intent is a known conversion killer.

**Fix:** Only call `UNUserNotificationCenter.requestAuthorization()` at the moment the user toggles notifications ON in Settings, not during general onboarding unless there is a dedicated notification onboarding step that explains the value first.

---

### LOW-2 · Keychain error messages don't include human-readable OSStatus descriptions

**File:** `Better/Core/Security/KeychainService.swift:74–80`

```swift
case .storeFailed(let status): "Keychain store failed: \(status)"
```

OSStatus codes like `-25300` (errSecItemNotFound) or `-34018` (errSecMissingEntitlement) are opaque to developers reading crash reports. When these errors surface in production logs or TestFlight feedback, they require a lookup to decode.

**Fix:** Add a helper that maps common OSStatus codes to readable strings, or use `SecCopyErrorMessageString(status, nil)` which returns Apple's own description.

---

## Part 5 — Encryption Architecture Assessment

The overall encryption design is **sound**:

| Property | Assessment |
|----------|-----------|
| Algorithm | AES-256-GCM via CryptoKit — correct and modern |
| Key storage | iOS Keychain with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` — correct binding |
| Key scope | Per-install, generated locally, never transmitted — correct |
| File protection | SQLite files set to `.complete` — correct |
| Migration path | `PersistenceJSON.decode` falls back to plain JSON for old records — intentional, acceptable |
| Test isolation | Unique Keychain accounts per test — correct |

The main weakness is the **silent fallback on encode failure** (HIGH-1 above), which is the only path that can undermine the encryption guarantee at runtime.

---

## Part 6 — Data Transmission Assessment

No outbound network calls were found in the codebase. All data stays on device unless the user explicitly exports via the Share Sheet. This is a strong privacy posture and should be highlighted in the App Store privacy nutrition label.

**Recommended App Store privacy label settings:**

| Data type | Collected | Linked to user | Used for tracking |
|-----------|-----------|----------------|-------------------|
| Health & Fitness | Yes — processed locally only | No | No |
| Usage Data | No | — | — |
| Diagnostics | No | — | — |

---

*End of Security Analysis — Better iOS App*
