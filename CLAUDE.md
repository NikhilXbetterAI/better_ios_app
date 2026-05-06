# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Better** is an iOS health optimization app that tracks sleep using Apple HealthKit and measures how daily behaviors (supplements, activity, illness, travel) affect sleep quality. The app provides research-grade statistical analysis comparing sleep metrics on protocol taken vs. not taken nights, with explicit confidence levels. Unknown protocol nights must stay distinct from not taken nights.

**Core tech**: SwiftUI, SwiftData, HealthKit, iOS 18+

## Development Environment & Build Commands

### Setup

- Open `Better.xcodeproj` in Xcode 16+
- No package manager required (native Xcode project)
- Entitlements: `Better/Better.entitlements` grants HealthKit read/write permissions

### Build & Run

```bash
# Build the app
xcodebuild -scheme Better -configuration Debug

# Run unit tests
xcodebuild -scheme Better -configuration Debug test

# Run a single test file
xcodebuild -scheme Better -configuration Debug test -only BetterTests/SleepDataProcessorTests

# Run UI tests
xcodebuild -scheme BetterUITests test

# Build for Release
xcodebuild -scheme Better -configuration Release
```

### Running in Simulator

- Open `Better.xcodeproj` and press Cmd+R in Xcode
- Tests run with `Cmd+U` or via `xcodebuild` commands above
- Onboarding flow shows on first app launch; use `--uitesting` argument flag for test environments

## Codebase Architecture

The app uses a **3-layer architecture**: Data (repositories + processors) → Business Logic (services) → UI (SwiftUI views + view models).

### Data Layer

- **`HealthKitRepository`** (`Better/Core/Repositories/`) — Reads HealthKit data and fetches sleep samples, biometrics, and observer queries
- **`LocalDataRepository`** — Persists derived data (sleep sessions, baselines, alerts, adherence) in SwiftData
- **`RepositoryProtocols.swift`** — Defines contracts for both repositories; use these in tests
- **`PersistenceModels.swift`** — SwiftData model definitions (maps domain structs to persistent entities)

### Processing Layer

- **`SleepDataProcessor`** (`Better/Core/Processors/`) — Core sleep logic engine:
  - Resolves overlapping HealthKit samples (source priority)
  - Splits fragments into separate sessions (>30 min wake = new session)
  - Calculates sleep quality score (0–100): 30% duration, 20% efficiency, 25% REM, 25% deep
  - Computes rolling baselines with circular statistics for times (handles midnight wraparound)
  - Summarizes biometrics per session
  - Baseline selection should prefer 14 valid nights, fall back to 7 valid nights, and keep 30-day stable context separate from the active baseline

- **`ResearchAnalysisService`** (`Better/Core/Services/`) — Statistical analysis:
  - Joins nightly sleep + protocol adherence + activity status into per-night rows
  - Computes effect sizes (protocol taken nights vs. not taken nights)
  - Keeps unknown protocol nights out of taken-vs-not-taken comparisons
  - Assigns confidence levels (Low/Moderate/Strong based on sample size + confounders)
  - Detects caveats (small sample, high confounding, mixed sources)

### Services Layer

- **`SyncCoordinator`** — Orchestrates the full sync pipeline: HealthKit → processor → repository → alerts
- **`BackgroundTaskService`** — Schedules background syncs (uses `BGTaskScheduler`)
- **`AlertGenerationService`** — Turns session/baseline/profile data into in-app alerts and local notifications
- **`PrivacyDataService`** — Exposes privacy operations to the UI: inventory fetch, data deletion, re-sync

### Security Layer

- **`KeychainService`** — Stores and retrieves the per-install AES-256 encryption key from iOS Keychain with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` protection
- **`EncryptionService`** — AES-256-GCM encryption for sensitive data; key is cached in-memory with `NSLock`; `isEnabled` flag for test bypass
- **`DataMigrationService`** — One-shot idempotent migration from unencrypted to encrypted storage, tracked via `UserDefaults` version flag

### Frontend Layer

- **`BetterApp.swift`** — Entry point; initializes `AppEnvironment` and registers background handlers
- **`RootTabView.swift`** — Root navigation: decides onboarding vs. main tabs
- **`AppEnvironment.swift`** — Dependency injection container; injects repositories and services
- **`Features/`** — 8 feature modules, each with its own view hierarchy and view model:
  - Sleep, Trends, Protocol, Alerts, Settings, Activity, Biology, Onboarding

### Design System

- **`Core/DesignSystem/`** — Colors, typography, spacing, and reusable UI components
  - `BetterColors.swift` — Color tokens
  - `BetterTypography.swift` — Font/size definitions
  - `BetterSpacing.swift` — Padding/margin standards

## Key Patterns & Conventions

### Repository Pattern with Dependency Injection

All services receive repositories via constructor injection. Mock/preview repositories are provided for tests and previews. When wiring up new code, define protocol-based contracts in `RepositoryProtocols.swift`.

### @Observable ViewModels

The app uses SwiftUI's `@Observable` macro for reactive state. ViewModels:
- Are ObservableObject (via `@Observable`)
- Call repositories/services in task blocks or `@MainActor` methods
- Avoid holding strong references to services to prevent memory leaks

Example:
```swift
@Observable
final class SleepViewModel {
    var sessions: [SleepSession] = []
    private let repository: LocalDataRepository
    
    init(repository: LocalDataRepository) {
        self.repository = repository
    }
    
    @MainActor func refreshSessions() async {
        sessions = await repository.fetchSessionsForLastN(days: 30)
    }
}
```

### Circular Statistics for Time-Based Metrics

Bedtime and wake time use circular statistics (not standard mean/std) to handle midnight wraparound correctly. Use `circularMeanHour()` and `circularStdDeviation()` from `SleepDataProcessor` when computing baseline times.

### Testing Strategy

- **Unit tests** in `BetterTests/` use mock repositories (`MockLocalDataRepository`, `PreviewHealthKitRepository`)
- **Integration tests** test repository + processor pipelines with real SwiftData containers
- **UI tests** in `BetterUITests/` use `--uitesting` environment flag to inject test doubles
- Core processors and services are fully tested; views are tested by manual QA

Key test files:
- `SleepDataProcessorTests.swift` — Tests overlap resolution, quality scoring, baselines
- `BaselineEngineTests.swift` — Tests baseline selection, confidence, and outlier filtering
- `LocalDataRepositoryTests.swift` — Tests SwiftData CRUD and queries
- `ResearchAnalysisServiceTests.swift` — Tests effect summaries and confidence scoring
- `ProtocolComparisonServiceTests.swift` — Tests protocol usage mapping and taken/not-taken comparison
- `AlertGenerationServiceTests.swift` — Tests alert creation logic
- `EncryptionServiceTests.swift` — Tests encryption round-trip, Keychain persistence, key reset, legacy data fallback
- `PrivacyDataServiceTests.swift` — Tests data deletion, inventory counts, migration idempotency, fallback states

**Encryption test parallelization note:** The `EncryptionServiceTests` suite uses unique Keychain accounts per test instance to prevent simulator clone collisions. Run with `-parallel-testing-enabled NO` if you encounter flakiness. To make this permanent, edit the **Better** scheme in Xcode (Product → Scheme → Edit Scheme → Test → Arguments) and add `-parallel-testing-enabled NO`.

## Important Implementation Notes

1. **HealthKit is read-only** — The app reads sleep + biometrics but does not write back to HealthKit (except manual entries via Settings)

2. **SwiftData model version** — Domain models are mapped to SwiftData models in `PersistenceModels.swift`. Changes to persistence models require schema migration support.

3. **Baseline computation** — Baselines use a rolling N-day window and exclude low-quality sessions (quality gate). Update `SleepDataProcessor.calculateBaseline()` if changing baseline logic.

4. **Protocol usage state** — A missing adherence row is `unknown`, not `not taken`. Preserve that distinction in analysis and CSV export.

5. **Confounding detection** — The Research Analysis Service auto-detects travel, jet-lag, and illness status from the user's logged activity status. These nights are flagged but not excluded from analysis (unless explicitly adjusted in effect calculation).

6. **Background sync** — `BackgroundTaskService` schedules sleep refreshes every 6 hours. Changes to sync frequency require updating the `BGTaskSchedulerPermittedIdentifiers` entry in `Info.plist`.

7. **HealthKit permissions** — Both read and write permissions are declared in `Info.plist`. Permissions are requested during onboarding via `HealthKitRepository.requestAuthorization()`.

8. **Encryption & storage protection** — All sensitive data (sleep sessions, baselines, onboarding answers, protocol adherence) is encrypted via `EncryptionService` (AES-256-GCM). The encryption key is stored in iOS Keychain with device-level protection. SQLite files get `FileProtectionType.complete`. Non-sensitive settings (theme, notification flags) remain unencrypted for faster access.

9. **Data migration** — `DataMigrationService` runs once on app launch (tracked via `UserDefaults` version flag). `PersistenceJSON.decode()` automatically falls back to plain JSON for pre-encryption records, enabling transparent migration without schema changes.

10. **Privacy controls** — `PrivacyDataService` exposes three operations: (a) fetch data inventory (count of sessions, baselines, alerts, adherence), (b) delete all health data (clears sensitive records and resets app to onboarding state), (c) re-sync from Apple Health. These are wired to `PrivacyControlsView` in Settings.

11. **HealthKit fallback states** — When HealthKit permission is denied, or data is insufficient, or only "in bed" data is available, the sleep dashboard displays contextual fallback banners via `HealthKitFallbackState` enum. See `SleepDashboardViewModel.healthKitFallbackState` for the computed logic.

12. **Research export** — `ResearchCSVExporter` appends protocol and baseline context fields to the nightly CSV. Preserve existing columns when adding new export fields.

## File Organization

```
Better/
├── App/                          # App entry point + navigation
│   ├── BetterApp.swift
│   ├── RootTabView.swift
│   ├── AppEnvironment.swift      # DI container
│   └── AppTab.swift
├── Core/
│   ├── Data/                     # Queries and helper structures
│   ├── DesignSystem/             # Colors, typography, components
│   ├── Models/                   # Domain models
│   ├── Persistence/              # SwiftData models, encryption/decryption
│   ├── Processors/               # SleepDataProcessor
│   ├── Repositories/             # HealthKit + Local storage
│   ├── Security/                 # Encryption, Keychain, data migration
│   └── Services/                 # SyncCoordinator, Background tasks, Alerts, Privacy
└── Features/                     # Feature modules
    ├── Sleep/                    # Sleep dashboard + fallback states
    ├── Trends/                   # Trends charts
    ├── Protocol/                 # Protocol adherence tracker
    ├── Alerts/                   # Alert history
    ├── Settings/                 # User settings + privacy controls
    ├── Activity/                 # Activity + status logging
    ├── Biology/                  # Biometric trends
    └── Onboarding/               # Initial setup flow
```

## References

- See `PROJECT_ARCHITECTURE.md` for detailed backend/frontend flow diagrams
- See `core_product.md` for feature descriptions and the research analysis methodology
- See `BASELINE_AND_HISTORY_IMPLEMENTATION.md` for historical data sync strategy
- HealthKit permissions declared in `Better/Info.plist`
- Entitlements in `Better/Better.entitlements`
