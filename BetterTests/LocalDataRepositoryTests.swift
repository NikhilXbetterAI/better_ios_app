import HealthKit
import SwiftData
import XCTest
@testable import Better

final class LocalDataRepositoryTests: XCTestCase {
    func testLocalRepositoryPersistsAndReplacesSessionsByRange() async throws {
        let repository = try await makeRepository()
        let firstSession = Self.session(
            key: "2026-05-04",
            start: Self.date("2026-05-03T22:00:00Z"),
            end: Self.date("2026-05-04T06:00:00Z")
        )
        let replacement = Self.session(
            key: "2026-05-05",
            start: Self.date("2026-05-04T22:00:00Z"),
            end: Self.date("2026-05-05T06:00:00Z")
        )

        try await repository.saveSessions([firstSession])
        let latestSession = try await repository.fetchLatestSession()
        XCTAssertEqual(latestSession?.sleepDateKey, "2026-05-04")

        try await repository.replaceSessions(
            [replacement],
            from: Self.date("2026-05-03T00:00:00Z"),
            to: Self.date("2026-05-06T00:00:00Z")
        )

        let sessions = try await repository.fetchCachedSessions(
            from: Self.date("2026-05-03T00:00:00Z"),
            to: Self.date("2026-05-06T00:00:00Z")
        )

        let sleepDateKeys = sessions.map { $0.sleepDateKey }
        XCTAssertEqual(sleepDateKeys, ["2026-05-05"])
    }

    func testLocalRepositoryFetchesSessionPreviousSessionsAndDateSummaries() async throws {
        let repository = try await makeRepository()
        let sessions = [
            Self.session(
                key: "2026-05-01",
                start: Self.date("2026-04-30T22:00:00Z"),
                end: Self.date("2026-05-01T06:00:00Z"),
                score: 80
            ),
            Self.session(
                key: "2026-05-03",
                start: Self.date("2026-05-02T22:00:00Z"),
                end: Self.date("2026-05-03T06:00:00Z"),
                score: 72,
                dataQuality: .unspecifiedSleepOnly
            ),
            Self.session(
                key: "2026-05-04",
                start: Self.date("2026-05-03T22:00:00Z"),
                end: Self.date("2026-05-04T06:00:00Z"),
                score: 90
            )
        ]

        try await repository.saveSessions(sessions)

        let selected = try await repository.fetchSession(forSleepDateKey: "2026-05-03")
        let previous = try await repository.fetchSessions(beforeSleepDateKey: "2026-05-04", limit: 2)
        let summaries = try await repository.fetchAvailableSleepDates(from: "2026-05-01", to: "2026-05-04")

        XCTAssertEqual(selected?.sleepDateKey, "2026-05-03")
        XCTAssertEqual(previous.map(\.sleepDateKey), ["2026-05-03", "2026-05-01"])
        XCTAssertEqual(summaries.map(\.sleepDateKey), ["2026-05-01", "2026-05-03", "2026-05-04"])
        XCTAssertEqual(summaries[1].dataQuality, .unspecifiedSleepOnly)
        XCTAssertEqual(summaries[1].score, 72)
    }

    func testLocalRepositoryPersistsProfileAlertsAdherenceAndAnchor() async throws {
        let repository = try await makeRepository()
        let profile = UserProfile(
            sleepGoalHours: 7.5,
            baselineWindowDays: 15,
            sleepAssessmentAnswers: [
                SleepAssessmentAnswer(
                    questionID: "sleep_latency",
                    question: "How long does it usually take you to fall asleep?",
                    section: "Sleep Quality",
                    selectedOption: "10-20 minutes",
                    selectedOptionIndex: 1
                )
            ]
        )
        let alert = SleepAlert(kind: .analysisReady, title: "Ready", body: "Updated")
        let adherence = ProtocolAdherence(protocolID: "magnesium", dateKey: "2026-05-04", taken: true)
        let anchor = Data([1, 2, 3])

        try await repository.saveProfile(profile)
        try await repository.saveAlerts([alert])
        try await repository.saveAdherence(adherence)
        try await repository.saveSyncAnchor(anchor, for: "sleep")
        try await repository.markAlertRead(id: alert.id)

        let fetchedProfile = try await repository.fetchProfile()
        let unreadAlerts = try await repository.fetchAlerts(unreadOnly: true)
        let allAlerts = try await repository.fetchAlerts(unreadOnly: false)
        let fetchedAdherence = try await repository.fetchAdherence(
            from: Self.date("2026-05-04T00:00:00Z"),
            to: Self.date("2026-05-05T00:00:00Z")
        )
        let fetchedAnchor = try await repository.fetchSyncAnchor(for: "sleep")

        XCTAssertEqual(fetchedProfile, profile)
        XCTAssertEqual(unreadAlerts, [])
        XCTAssertEqual(allAlerts.first?.isRead, true)
        XCTAssertEqual(fetchedAdherence, [adherence])
        XCTAssertEqual(fetchedAnchor, anchor)
    }

    @MainActor
    func testSyncCoordinatorInitialSyncCachesSessionsBaselineBiometricsAndAlerts() async throws {
        let localRepository = try await makeRepository()
        let healthRepository = FakeHealthKitRepository(
            sleepSamples: [
                sample(.inBed, start: "2026-05-03T22:00:00Z", end: "2026-05-04T06:00:00Z"),
                sample(.asleepCore, start: "2026-05-03T22:30:00Z", end: "2026-05-04T02:30:00Z"),
                sample(.asleepDeep, start: "2026-05-04T02:30:00Z", end: "2026-05-04T04:00:00Z"),
                sample(.asleepREM, start: "2026-05-04T04:00:00Z", end: "2026-05-04T05:45:00Z")
            ],
            biometricSamples: [
                .heartRate: [
                    BiometricSample(
                        type: .heartRate,
                        value: 58,
                        unit: BiometricType.heartRate.unitSymbol,
                        startDate: date("2026-05-04T02:00:00Z"),
                        endDate: date("2026-05-04T02:01:00Z")
                    )
                ]
            ]
        )
        let coordinator = SyncCoordinator(
            healthRepository: healthRepository,
            localRepository: localRepository,
            processor: SleepDataProcessor(calendar: Self.utcCalendar)
        )

        await coordinator.performInitialSync(now: Self.date("2026-05-04T12:00:00Z"))

        let cached = try await localRepository.fetchCachedSessions(
            from: Self.date("2026-05-03T00:00:00Z"),
            to: Self.date("2026-05-05T00:00:00Z")
        )
        let baseline = try await localRepository.fetchLatestBaseline(windowDays: 30)
        let alerts = try await localRepository.fetchAlerts(unreadOnly: false)

        XCTAssertEqual(cached.count, 1)
        XCTAssertEqual(cached[0].sleepDateKey, "2026-05-04")
        XCTAssertEqual(cached[0].biometrics?.heartRateAverage, 58)
        XCTAssertEqual(baseline?.validNights, 1)
        XCTAssertEqual(alerts.map(\.kind), [.analysisReady])
        XCTAssertEqual(coordinator.phase, .idle)
        XCTAssertEqual(coordinator.lastSyncedAt, Self.date("2026-05-04T14:00:00Z"))
    }

    @MainActor
    func testSleepDashboardBaselineExcludesSelectedDate() async throws {
        let selectedKey = "2026-05-10"
        let sessions = (1...6).map { day in
            let previousDate = day == 1 ? "2026-04-30" : String(format: "2026-05-%02d", day - 1)
            return Self.session(
                key: String(format: "2026-05-%02d", day),
                start: Self.date("\(previousDate)T22:00:00Z"),
                end: Self.date(String(format: "2026-05-%02dT06:00:00Z", day)),
                totalSleep: 7 * 3_600,
                score: 75
            )
        } + [
            Self.session(
                key: selectedKey,
                start: Self.date("2026-05-09T22:00:00Z"),
                end: Self.date("2026-05-10T06:00:00Z"),
                totalSleep: 10 * 3_600,
                score: 95
            )
        ]
        let localRepository = MockLocalDataRepository(
            sessions: sessions,
            profile: UserProfile(sleepGoalHours: 8, baselineWindowDays: 30)
        )
        let coordinator = SyncCoordinator(
            healthRepository: FakeHealthKitRepository(),
            localRepository: localRepository,
            processor: SleepDataProcessor(calendar: Self.utcCalendar)
        )
        let viewModel = SleepDashboardViewModel(
            syncCoordinator: coordinator,
            localRepository: localRepository,
            processor: SleepDataProcessor(calendar: Self.utcCalendar),
            calendar: Self.utcCalendar
        )

        await viewModel.selectDate(selectedKey)

        XCTAssertEqual(viewModel.selectedSession?.sleepDateKey, selectedKey)
        XCTAssertEqual(viewModel.selectedBaseline?.validNights, 6)
        XCTAssertEqual(viewModel.selectedBaseline?.totalSleepAverage, 7 * 3_600)
        XCTAssertEqual(viewModel.baselineConfidenceLabel, "warming up")
    }

    @MainActor
    func testSleepDashboardTodaySelectionDoesNotFallbackToLatestHistoricalSession() async throws {
        let todayKey = SleepDateKey.today(calendar: Self.utcCalendar, now: Self.date("2026-05-10T12:00:00Z"))
        let oldSession = Self.session(
            key: "2026-05-01",
            start: Self.date("2026-04-30T22:00:00Z"),
            end: Self.date("2026-05-01T06:00:00Z")
        )
        let localRepository = MockLocalDataRepository(
            sessions: [oldSession],
            profile: UserProfile(sleepGoalHours: 8, baselineWindowDays: 30)
        )
        let coordinator = SyncCoordinator(
            healthRepository: FakeHealthKitRepository(),
            localRepository: localRepository,
            processor: SleepDataProcessor(calendar: Self.utcCalendar)
        )
        let viewModel = SleepDashboardViewModel(
            syncCoordinator: coordinator,
            localRepository: localRepository,
            processor: SleepDataProcessor(calendar: Self.utcCalendar),
            calendar: Self.utcCalendar
        )

        await viewModel.selectDate(todayKey)

        XCTAssertEqual(viewModel.selectedSleepDateKey, todayKey)
        XCTAssertNil(viewModel.selectedSession)
    }

    @MainActor
    func testTrendsWeekComparisonUsesEqualElapsedCalendarDays() async throws {
        let sessions = [
            Self.session(key: "2026-04-27", start: Self.date("2026-04-26T22:00:00Z"), end: Self.date("2026-04-27T06:00:00Z"), score: 60),
            Self.session(key: "2026-04-28", start: Self.date("2026-04-27T22:00:00Z"), end: Self.date("2026-04-28T06:00:00Z"), score: 60),
            Self.session(key: "2026-04-29", start: Self.date("2026-04-28T22:00:00Z"), end: Self.date("2026-04-29T06:00:00Z"), score: 60),
            Self.session(key: "2026-05-04", start: Self.date("2026-05-03T22:00:00Z"), end: Self.date("2026-05-04T06:00:00Z"), score: 90),
            Self.session(key: "2026-05-05", start: Self.date("2026-05-04T22:00:00Z"), end: Self.date("2026-05-05T06:00:00Z"), score: 90),
            Self.session(key: "2026-05-06", start: Self.date("2026-05-05T22:00:00Z"), end: Self.date("2026-05-06T06:00:00Z"), score: 90)
        ]
        let repository = MockLocalDataRepository(sessions: sessions)
        let viewModel = TrendsViewModel(localRepository: repository, calendar: Self.utcCalendar)
        viewModel.selectedWindow = .week
        viewModel.selectedMetric = .score

        await viewModel.loadData(now: Self.date("2026-05-06T12:00:00Z"))

        XCTAssertEqual(viewModel.comparisonSummary?.currentValidNights, 3)
        XCTAssertEqual(viewModel.comparisonSummary?.previousValidNights, 3)
        XCTAssertEqual(viewModel.comparisonSummary?.percentChange ?? 0, 0.5, accuracy: 0.0001)
    }

    @MainActor
    func testTrendsMonthComparisonUsesEqualElapsedCalendarDays() async throws {
        let sessions = [
            Self.session(key: "2026-04-02", start: Self.date("2026-04-01T22:00:00Z"), end: Self.date("2026-04-02T06:00:00Z"), score: 50),
            Self.session(key: "2026-04-03", start: Self.date("2026-04-02T22:00:00Z"), end: Self.date("2026-04-03T06:00:00Z"), score: 50),
            Self.session(key: "2026-05-02", start: Self.date("2026-05-01T22:00:00Z"), end: Self.date("2026-05-02T06:00:00Z"), score: 100),
            Self.session(key: "2026-05-03", start: Self.date("2026-05-02T22:00:00Z"), end: Self.date("2026-05-03T06:00:00Z"), score: 100)
        ]
        let repository = MockLocalDataRepository(sessions: sessions)
        let viewModel = TrendsViewModel(localRepository: repository, calendar: Self.utcCalendar)
        viewModel.selectedWindow = .month
        viewModel.selectedMetric = .score

        await viewModel.loadData(now: Self.date("2026-05-10T12:00:00Z"))

        XCTAssertEqual(viewModel.comparisonSummary?.currentValidNights, 2)
        XCTAssertEqual(viewModel.comparisonSummary?.previousValidNights, 2)
        XCTAssertEqual(viewModel.comparisonSummary?.percentChange ?? 0, 1.0, accuracy: 0.0001)
    }
}

private extension LocalDataRepositoryTests {
    static let utcCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    func makeRepository() async throws -> LocalDataRepository {
        let container = try BetterPersistenceContainerFactory.makePreviewContainer()
        return LocalDataRepository(modelContainer: container)
    }

    static func session(
        key: String,
        start: Date,
        end: Date,
        totalSleep: TimeInterval? = nil,
        score: Double = 82,
        dataQuality: SleepDataQuality = .detailedStages
    ) -> SleepSession {
        let totalSleep = totalSleep ?? end.timeIntervalSince(start)
        return SleepSession(
            sleepDateKey: key,
            startDate: start,
            endDate: end,
            dataQuality: dataQuality,
            totalInBedTime: end.timeIntervalSince(start),
            totalSleepTime: totalSleep,
            efficiency: min(1, totalSleep / end.timeIntervalSince(start)),
            qualityScore: SleepQualityScore(
                overall: score,
                durationScore: score,
                efficiencyScore: score,
                remScore: score,
                deepScore: score,
                isPartial: dataQuality == .unspecifiedSleepOnly
            )
        )
    }

    static func sample(_ value: HKCategoryValueSleepAnalysis, start: String, end: String) -> HKCategorySample {
        HKCategorySample(
            type: HKCategoryType(.sleepAnalysis),
            value: value.rawValue,
            start: date(start),
            end: date(end)
        )
    }

    static func date(_ string: String) -> Date {
        ISO8601DateFormatter().date(from: string)!
    }

    func sample(_ value: HKCategoryValueSleepAnalysis, start: String, end: String) -> HKCategorySample {
        Self.sample(value, start: start, end: end)
    }

    func date(_ string: String) -> Date {
        Self.date(string)
    }
}

final class FakeHealthKitRepository: HealthKitRepositoryProtocol, @unchecked Sendable {
    var sleepSamples: [HKCategorySample]
    var biometricSamples: [BiometricType: [BiometricSample]]
    var anchoredResult: HealthKitAnchoredResult?

    init(
        sleepSamples: [HKCategorySample] = [],
        biometricSamples: [BiometricType: [BiometricSample]] = [:],
        anchoredResult: HealthKitAnchoredResult? = nil
    ) {
        self.sleepSamples = sleepSamples
        self.biometricSamples = biometricSamples
        self.anchoredResult = anchoredResult
    }

    func isHealthDataAvailable() -> Bool {
        true
    }

    func requestAuthorization() async throws -> HealthAuthorizationResult {
        HealthAuthorizationResult(
            requestCompleted: true,
            healthDataAvailable: true,
            canQuerySleep: true,
            lastQueryReturnedSamples: !sleepSamples.isEmpty
        )
    }

    func fetchSleepSamples(from: Date, to: Date) async throws -> [HKCategorySample] {
        sleepSamples.filter { $0.endDate > from && $0.startDate < to }
    }

    func fetchSleepSessions(from: Date, to: Date) async throws -> [SleepSession] {
        SleepDataProcessor(calendar: LocalDataRepositoryTests.utcCalendar)
            .process(samples: try await fetchSleepSamples(from: from, to: to))
    }

    func fetchBiometrics(for type: BiometricType, from: Date, to: Date) async throws -> [BiometricSample] {
        biometricSamples[type, default: []].filter { $0.endDate > from && $0.startDate < to }
    }

    func fetchSourceSummaries(from: Date, to: Date) async throws -> [SleepSource] {
        []
    }

    func startObservingSleepChanges() async throws -> AsyncStream<HealthKitChangeEvent> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }

    func fetchIncrementalSleepChanges(anchor: Data?) async throws -> HealthKitAnchoredResult {
        anchoredResult ?? HealthKitAnchoredResult(samples: [], deletedObjects: [], newAnchor: anchor)
    }
}
