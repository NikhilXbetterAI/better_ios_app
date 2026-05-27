# CLAUDE.md

Guidance for Claude Code working in this repo. For deep architecture details, see [`APP_ARCHITECTURE.md`](APP_ARCHITECTURE.md).

## Project

**Better** — iOS health app. Tracks sleep via HealthKit and measures how daily behaviors (supplements, activity, illness, travel) affect sleep quality. Provides research-grade taken-vs-not-taken analysis with explicit confidence levels.

**Stack:** SwiftUI · SwiftData · HealthKit · iOS 18+ · Xcode 16+

## Build & Test

```bash
xcodebuild -scheme Better -configuration Debug              # build
xcodebuild -scheme Better -configuration Debug test         # unit tests
xcodebuild -scheme Better -configuration Debug test -only BetterTests/SleepDataProcessorTests
xcodebuild -scheme BetterUITests test                       # UI tests
```

UI tests use the `--uitesting` launch arg to inject test doubles.

## Architecture (3 layers)

**Data** → **Services** → **UI**. See [`APP_ARCHITECTURE.md`](APP_ARCHITECTURE.md) for diagrams and the metric calculation reference.

- **Repositories** (`Core/Repositories/`) — `HealthKitRepository` (read-only HK), `LocalDataRepository` (SwiftData CRUD). Contracts in `RepositoryProtocols.swift`.
- **Processors** (`Core/Processors/`) — `SleepDataProcessor` builds sessions from HK samples, scores them, computes baselines with circular statistics for times.
- **Services** (`Core/Services/`) — `SyncCoordinator`, `BaselineEngine`, `ProtocolComparisonService`, `ResearchAnalysisService`, `ResearchCSVExporter`, `AlertGenerationService`, `PrivacyDataService`, `BackgroundTaskService`.
- **Security** (`Core/Security/`) — `EncryptionService` (AES-256-GCM), `KeychainService`, `DataMigrationService`.
- **Features** (`Features/`) — Sleep, Trends, Protocol, Alerts, Settings, Activity, Biology, Onboarding. Each has `@Observable` view models that take repositories via constructor injection (DI container is `App/AppEnvironment.swift`).

## Critical Invariants — Don't Break These

1. **HealthKit is read-only.** Auth requested with `toShare: []`. Don't add `healthkit` to `UIBackgroundModes` (iOS rejects it); background delivery is granted via the entitlement.
2. **Unknown ≠ not-taken.** A missing `ProtocolAdherence` row is `.unknown` and must be excluded from taken-vs-not-taken comparisons and CSV deltas. Same rule for `SleepContextEntry` tristate fields — `nil` is never coerced to `false`.
3. **Baseline selection (Trends / Protocol / Research / CSV / SyncCoordinator):** prefer 14-day primary, fall back to 7-day. 30-day is *stable context only*, never the active comparator. **Sleep dashboard only** uses a separate 30-day primary / 60-day fallback selector via `BaselineEngine.selectDashboardBaseline(...)`; copy in that view refers to "your usual sleep" rather than the window length.
4. **Sleep quality score formula** (`HealthSleepScoreEstimator` in `Core/Models/SleepModels.swift`): **50 pts duration** (actual ÷ sleep-goal seconds), **30 pts bedtime consistency** (circular deviation from baseline bedtime, unlocks after 5 valid nights), **20 pts continuity** (WASO penalty: 0 pts at ≥60 min WASO, 20 pts at ≤5 min WASO). Total is always 0–100. Unspecified-stage nights score on duration + WASO only (bedtime component still applies if baseline is ready); these set `isPartial` on the session.
5. **Session split:** >30 min awake gap = new session.
6. **Sensitive data is encrypted** (sessions, baselines, adherence, onboarding answers). Settings (theme, notif flags) stay unencrypted. SQLite uses `FileProtectionType.complete`. `PersistenceJSON.decode()` transparently falls back to plain JSON for legacy rows.
7. **SwiftData schema changes require migration.** Models live in `Core/Persistence/PersistenceModels.swift`.
8. **Background sync = every 6h** via `BGTaskScheduler`. Frequency changes need `BGTaskSchedulerPermittedIdentifiers` in `Info.plist`.
9. **CSV export:** preserve existing column order when adding fields (`ResearchCSVExporter`).
10. **App Review:** the HealthKit pre-permission CTA stays neutral ("Continue", not promotional).
11. **Protocol Formula Tracking.** Restorative sleep / longest restorative block / continuity reuse `SleepSession.restorativeSleepDuration` and `SleepSession.continuitySummary` — no duplicate calculation. `restorativePctOfInBed` is `nil` (rendered "—") unless `dataQuality ∈ {.detailedStages, .mixedSources}`. `ProtocolFormulaVersion.formulaText` is immutable once a `ProtocolNightLog` references it (exception: imported placeholders allow one backfill). `ProtocolBaselineSnapshot` is frozen at creation and never recomputed on HealthKit resync. The container fallback no longer silently wipes the store — migration failures throw and surface a recovery state.

## Design System

Tokens in `Core/DesignSystem/`: `BetterColors`, `BetterTypography`, `BetterSpacing`, `BetterHealthComponents`. Modernized in 2026 with glassmorphism — gradient card surfaces, `glassStroke` borders, `.ultraThinMaterial` tab bars, per-step accent colors on onboarding. Use `BetterHealthCard`, `MetricGaugeView`, `SparklineView`, `FloatingActionButton` rather than rolling new containers.

Common animations: spring `response: 0.4, damping: 0.75` for metric changes; `0.45, 0.82` for card swaps; `easeInOut 0.5` for background fades.

## Conventions

- `@Observable` view models, `@MainActor` methods that call services in `Task` blocks. Don't hold strong references to services beyond what DI provides.
- Use `circularMeanHour()` / `circularStdDeviation()` from `SleepDataProcessor` for any time-of-day stat (handles midnight wraparound).
- Tests: mock via `MockLocalDataRepository` / `PreviewHealthKitRepository`. `EncryptionServiceTests` may need `-parallel-testing-enabled NO` to avoid simulator-clone Keychain collisions.

## Tooling

- **XcodeBuildMCP** for builds/tests/project introspection.
- **axiom-*** skills for domain-specific review (axiom-health, axiom-swiftui, axiom-data, axiom-concurrency, axiom-security, axiom-testing, axiom-build, axiom-performance). Skip them for trivial edits — use Read/Edit/Write directly.

## References

- [`APP_ARCHITECTURE.md`](APP_ARCHITECTURE.md) — full diagrams, data flow, §11 metric calculation reference (formulas + file:line for every UI number)
- `core_product.md` — feature spec + research methodology
- `BASELINE_AND_HISTORY_IMPLEMENTATION.md` — history sync strategy
- `Better/Info.plist` — HK purpose strings
- `Better/Better.entitlements` — HK + background delivery
