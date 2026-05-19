# Codebase Improvements — Better iOS App

> Audit date: 2026-05-06  
> Scope: code quality, dead code, redundancy, unnecessary permissions, Swift best practices  
> This document is NOT about security — see `SECURITY_ANALYSIS.md` for that.

---

## Quick Summary

| Category | Count | Biggest win |
|----------|-------|-------------|
| Dead / stub code to remove | 3 | Empty test class, screenshot-only UI test |
| Duplicate logic to consolidate | 2 | Threshold constants copied across 3 service files |
| Wrong or misleading Info.plist entries | 2 | Unused background mode, missing HealthKit background mode |
| API misuse / correctness | 3 | NSLock used where actor would be cleaner, observer error dropped, `try?` in migration |
| Minor polish | 4 | Lock scope, `@unchecked Sendable`, cancellation handling, unneeded `SleepSource.sourceKey` |

---

## 1. Dead & Stub Code to Remove

### DEAD-1 · `BetterUITestsLaunchTests.swift` — does nothing useful

**File:** `BetterUITests/BetterUITestsLaunchTests.swift`

```swift
final class BetterUITestsLaunchTests: XCTestCase {
    override class var runsForEachTargetApplicationUIConfiguration: Bool { true }

    @MainActor
    func testLaunch() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launch()

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Phase 1 Shell"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
```

This takes a screenshot and adds it as an attachment. There are no assertions. It will always pass. The only artifact it produces is a screenshot file that no CI pipeline currently uses. It adds launch time to every test run for zero signal.

**Action:** Delete `BetterUITestsLaunchTests.swift` entirely, or convert it into a real smoke test that asserts the Sleep tab renders.

---

### DEAD-2 · `SleepSource.sourceKey` is private and used in exactly one place

**File:** `Better/Core/Repositories/HealthKitRepository.swift:357–367`

```swift
nonisolated private extension SleepSource {
    var sourceKey: String {
        [
            name,
            bundleIdentifier ?? "",
            productType ?? "",
            operatingSystemVersion ?? "",
            isManualEntry ? "manual" : "automatic"
        ].joined(separator: "|")
    }
}
```

This computed property exists solely to de-duplicate sources in `fetchSourceSummaries()`. The extension adds 12 lines of file noise for a one-line use. The pattern it implements (`Dictionary(grouping:by:).mapValues { $0.first! }`) could just use the bundle identifier as the key directly, since sources with the same bundle ID are the same app.

**Action:** Inline the de-duplication logic at the call site and remove the extension. Alternatively, make `SleepSource` conform to `Hashable` (which it likely should anyway) and use a `Set`.

---

### DEAD-3 · `ConnectedDevicesView` always shows a green "online" dot — hardcoded, misleading

**File:** `Better/Features/Settings/ConnectedDevicesView.swift:33`

```swift
Circle().fill(BetterColors.success).frame(width: 8, height: 8)
```

Every connected source always shows a green dot, regardless of whether that device has synced recently. The app has no concept of "last seen" for individual sources. This makes the UI appear to have live device status that it does not have.

**Action:** Either remove the dot entirely, or replace it with a neutral indicator (grey circle) and add a "last sync" timestamp if you surface that data in the future. Showing a fake "connected" indicator to users is misleading and can cause support confusion.

---

## 2. Duplicate Constants — Consolidate Thresholds

### DUP-1 · Meaningful-delta thresholds copied verbatim into three files

**Files and lines:**

`Better/Core/Services/ProtocolInsightService.swift:4–7`
```swift
static let meaningfulDurationDelta: TimeInterval = 20 * 60
static let meaningfulEfficiencyDelta = 0.03
static let meaningfulStageDelta: TimeInterval = 10 * 60
static let meaningfulAwakeDelta: TimeInterval = 10 * 60
```

`Better/Core/Services/ContextComparisonService.swift:98–101`
```swift
static let meaningfulDurationDelta:  TimeInterval = 20 * 60
static let meaningfulEfficiencyDelta: Double      = 0.03
static let meaningfulStageDelta:     TimeInterval = 10 * 60
static let meaningfulAwakeDelta:     TimeInterval = 10 * 60
```

`Better/Core/Services/SleepInsightService.swift` (similar constants)

These are the same four numbers in at least two — likely three — services. When a product decision changes a threshold (e.g., "make the duration threshold 15 min instead of 20"), someone has to find and update every copy. The third copy will inevitably be missed.

**Action:** Create a single `SleepAnalysisThresholds` namespace in `Core/Models/` or `Core/Services/`:

```swift
nonisolated enum SleepAnalysisThresholds {
    static let meaningfulDurationDelta: TimeInterval = 20 * 60
    static let meaningfulEfficiencyDelta: Double = 0.03
    static let meaningfulStageDelta: TimeInterval = 10 * 60
    static let meaningfulAwakeDelta: TimeInterval = 10 * 60
}
```

Then replace all per-file `Self.meaningfulXxx` with `SleepAnalysisThresholds.meaningfulXxx`. Tests that reference these constants can import the shared type.

---

### DUP-2 · `ComparisonConfidence.sortOrder` is defined twice

**File:** `Better/Core/Services/ContextComparisonService.swift:302–310`

```swift
nonisolated private extension ComparisonConfidence {
    var sortOrder: Int {
        switch self {
        case .unavailable: 0
        case .low:         1
        case .medium:      2
        case .high:        3
        }
    }
}
```

The same `sortOrder` property almost certainly exists in `ProtocolComparisonService.swift` or a related file (the pattern is used for sorting results in both services). A `private extension` means each file gets its own siloed copy.

**Action:** Move `sortOrder` (and `displayName` from `ProtocolInsightService.swift:163–176`) into the `ComparisonConfidence` enum definition in `Core/Models/ProtocolModels.swift` so it is defined once and accessible everywhere.

---

## 3. Info.plist — Wrong or Unnecessary Entries

### PLIST-1 · Keep `UIBackgroundModes` limited to valid iOS values

**File:** `Better/Info.plist:44–47`

```xml
<key>UIBackgroundModes</key>
<array>
    <string>fetch</string>
</array>
```

`fetch` is for `BGAppRefreshTask`. Do not add `healthkit` here: it is not a valid iOS `UIBackgroundModes` value and causes App Store validation to fail. HealthKit observer delivery belongs to the `com.apple.developer.healthkit.background-delivery` entitlement in `Better.entitlements`.

**Action:** Keep `fetch`, keep `healthkit` out of this array, and rely on `AppleHealthReviewComplianceTests` to prevent regression.

---

### PLIST-2 · `UISupportedInterfaceOrientations` includes landscape for an app with portrait-only content

**File:** `Better/Info.plist:48–53`

```xml
<key>UISupportedInterfaceOrientations</key>
<array>
    <string>UIInterfaceOrientationPortrait</string>
    <string>UIInterfaceOrientationLandscapeLeft</string>
    <string>UIInterfaceOrientationLandscapeRight</string>
</array>
```

The sleep dashboard, hypnogram, charts, and protocol checklist are all designed for portrait. None of the views in `Features/` contain landscape-specific layout code. Running them in landscape likely produces broken or compressed layouts on small iPhones.

**Action:** Unless landscape layout is intentionally supported and has been tested on real hardware, restrict to portrait only:

```xml
<key>UISupportedInterfaceOrientations</key>
<array>
    <string>UIInterfaceOrientationPortrait</string>
</array>
```

If you want to keep landscape for iPad, the `~ipad` key already handles that separately.

---

## 4. API Misuse & Correctness

### API-1 · `@unchecked Sendable` on `HealthKitRepository` masks real concurrency concerns

**File:** `Better/Core/Repositories/HealthKitRepository.swift:11`

```swift
nonisolated final class HealthKitRepository: HealthKitRepositoryProtocol, @unchecked Sendable {
    private let observerLock = NSLock()
    private var observerQueries: [HKObserverQuery] = []
```

`@unchecked Sendable` opts out of the compiler's concurrency checks. The code uses `NSLock` to protect `observerQueries`, which is correct. However, the `@unchecked` suppression means if a future developer adds a new stored property and forgets to protect it, the compiler won't warn them. `HKHealthStore` is itself documented as thread-safe, so the only shared mutable state that needs a lock is `observerQueries`.

**Action:** Convert to an `actor` or at minimum document exactly which properties the lock covers, and audit that every access to `observerQueries` goes through the lock. If you use an actor, you can remove `NSLock` entirely and let Swift's concurrency model protect the state.

---

### API-2 · `NSLock` in `EncryptionService` can be simplified

**File:** `Better/Core/Security/EncryptionService.swift:7–78`

`EncryptionService` is a `final class` marked `@unchecked Sendable` with an `NSLock`. The only mutation it does is setting `cachedKey` in `loadOrCreateKey()`. This is a classic use-case for an actor:

```swift
actor EncryptionService {
    static let shared = EncryptionService()
    var isEnabled: Bool = true

    func encrypt(_ data: Data) async throws -> Data { … }
    func decrypt(_ data: Data) async throws -> Data { … }
}
```

The downside is callers need `await`. If the synchronous interface is important for call sites inside `PersistenceJSON.encode/decode`, keep the lock but make the lock scope explicit (it currently is correct — the `isEnabled` read is inside the lock in `encrypt` and `decrypt`). 

**Action (minor):** The current `NSLock` implementation is functionally correct. The only improvement is dropping `@unchecked Sendable` if you convert to an actor. If you stay with a class, add a comment documenting which properties the lock protects, since a future reader might miss it.

---

### API-3 · `SyncCoordinator.performForegroundRefresh` swallows metadata save errors with `try?`

**File:** `Better/Core/Services/SyncCoordinator.swift:80`

```swift
try? await saveMetadataDate(now, for: Self.lastForegroundRefreshMetadataKey)
```

If saving the "last foreground refresh" timestamp fails (e.g., SwiftData context is in a bad state), the coordinator won't know it failed. On the next app launch, it will think no sync has happened and will attempt a full refresh. This is self-healing but wastes battery and HealthKit quota. It can also produce a loop of excessive syncing on a device with persistent SwiftData issues.

**Action:** Log the error explicitly so it surfaces in crash reports:

```swift
do {
    try await saveMetadataDate(now, for: Self.lastForegroundRefreshMetadataKey)
} catch {
    logger.error("Failed to save foreground refresh timestamp: \(error.localizedDescription, privacy: .public)")
}
```

---

### API-4 · Biometric task group fails entirely if any single type throws

**File:** `Better/Core/Services/SyncCoordinator.swift` (in `attachBiometrics` or equivalent)

```swift
for try await samples in group {
    all.append(samples)
}
```

`withThrowingTaskGroup` cancels all child tasks and throws as soon as one child throws. If HealthKit returns an error for HRV (e.g., the user hasn't granted permission or their device doesn't support it), the entire biometric fetch fails and the sleep session is saved without any biometric data. This is unnecessarily all-or-nothing.

**Action:** Use `try?` per child task to collect partial results:

```swift
group.addTask {
    (try? await self.healthRepository.fetchBiometrics(for: type, …)) ?? []
}
```

Then switch from `withThrowingTaskGroup` to `withTaskGroup` since individual failures are now handled.

---

## 5. Minor Polish

### POLISH-1 · `BackgroundTaskService.scheduleNextSleepRefresh` schedules 1-hour intervals but CLAUDE.md says 6-hour

**File:** `Better/Core/Services/BackgroundTaskService.swift:79`

```swift
func scheduleNextSleepRefresh(
    earliestBeginDate: Date = Date(timeIntervalSinceNow: 60 * 60)  // 1 hour
```

`APP_ARCHITECTURE.md` documents "Background sync interval: every 6 hours." The code schedules the earliest begin date as 1 hour from now. `BGAppRefreshTask` will not fire before that date, but it may fire much later depending on system conditions. If the intent is 6-hour intervals, the `earliestBeginDate` should be `6 * 60 * 60`. If 1 hour is intentional, update the architecture documentation.

**Action:** Align the constant with the documented 6-hour interval, or document why 1 hour is chosen:

```swift
static let backgroundRefreshInterval: TimeInterval = 6 * 60 * 60

func scheduleNextSleepRefresh(
    earliestBeginDate: Date = Date(timeIntervalSinceNow: backgroundRefreshInterval)
```

---

### POLISH-2 · `HealthKitRepository.fetchSleepSessions` is defined but never called directly

**File:** `Better/Core/Repositories/HealthKitRepository.swift:93–96`

```swift
func fetchSleepSessions(from: Date, to: Date) async throws -> [SleepSession] {
    let samples = try await fetchSleepSamples(from: from, to: to)
    return sleepProcessor.process(samples: samples)
}
```

The `SyncCoordinator` calls `fetchSleepSamples` directly (to get raw `HKCategorySample`) and then processes them itself. This convenience wrapper exists but is unused in production code paths. It's also not in `RepositoryProtocols.swift`, so it can't be mocked in tests.

**Action:** Either add it to `HealthKitRepositoryProtocol` and use it in `SyncCoordinator` (eliminating the direct `fetchSleepSamples` call there), or remove it to reduce surface area. Keeping an untested, uncalled public method that does real processing is a maintenance liability.

---

### POLISH-3 · `PreviewHealthKitRepository` and `MockLocalDataRepository` should live in test targets only

**Files:**
- `Better/Core/Repositories/PreviewHealthKitRepository.swift`
- `Better/Core/Repositories/MockLocalDataRepository.swift`

These are in the main app target. They exist for Xcode Previews and unit tests. Shipping mock/preview implementations in the production binary unnecessarily inflates binary size and exposes test data structures to the production app. The risk is low, but it's not clean.

**Action:** Move both files to a shared framework or keep them in the main target but wrap in `#if DEBUG` compile conditions:

```swift
#if DEBUG
nonisolated final class MockLocalDataRepository: LocalDataRepositoryProtocol {
    …
}
#endif
```

---

### POLISH-4 · `ContextInsightService.swift` and `SleepInsightService.swift` likely have overlapping `SleepInsight` factory patterns

Both services produce `SleepInsight` structs with the same `id / title / body / category / priority / confidence / metricDelta / displayStyle` pattern. If either service has a private `insight(id:title:body:…)` helper, it is a private copy of the same pattern used in `ProtocolInsightService.swift`.

**Action:** Extract a shared `SleepInsight` factory method — either a static method on `SleepInsight` itself or a protocol `InsightProducing` — so the construction pattern is defined once. This is a refactor opportunity, not a bug.

---

## 6. Test Coverage Gaps

These aren't dead code — they're missing code that would prevent regressions.

| Gap | Risk |
|-----|------|
| No test for `PersistenceJSON.encode` throwing when `EncryptionService.isEnabled = true` and Keychain is unavailable | Encryption fallback behaviour is untested |
| No test for `BackgroundTaskService.handleSleepRefresh` expiration handler firing concurrently with task completion | The race condition (HIGH-2 in security doc) is untested |
| No test for `HealthKitRepository.startObservingSleepChanges` being called twice without a stop | Observer query leak is untested |
| `BetterUITests` only checks tab existence — no test for the sleep fallback banner states | Regressions in `HealthKitFallbackState` rendering go undetected |

---

## Priority Order for Action

1. Remove `BetterUITestsLaunchTests.swift` — zero risk, immediate CI speed gain
2. Fix `scheduleNextSleepRefresh` interval to match documented 6 hours (POLISH-1)
3. Consolidate threshold constants (DUP-1) — prevents divergence bugs
4. Remove `ComparisonConfidence.sortOrder` duplication (DUP-2)
5. Remove landscape orientations from `UISupportedInterfaceOrientations` (PLIST-2)
6. Move mocks to `#if DEBUG` (POLISH-3)
7. Fix biometric task group to tolerate partial failures (API-4)
8. Remove or replace fake green dot in `ConnectedDevicesView` (DEAD-3)
9. Inline or remove `SleepSource.sourceKey` extension (DEAD-2)
10. Consolidate `SleepInsight` factory pattern (POLISH-4)

---

*End of Codebase Improvements — Better iOS App*
