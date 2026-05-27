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
            displayName: "Maya",
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

    func testLocalRepositoryPersistsAndFetchesContextEntries() async throws {
        let repository = try await makeRepository()
        let entry = SleepContextEntry(
            sleepDateKey: "2026-06-01",
            caffeineLate: true,
            alcohol: false,
            workout: nil,
            perceivedSleepQuality: .good,
            notes: "Encrypted note"
        )

        try await repository.saveContextEntry(entry)

        let fetched = try await repository.fetchContextEntry(forSleepDateKey: "2026-06-01")
        let inventory = try await repository.fetchDataInventory()

        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.caffeineLate, true)
        XCTAssertEqual(fetched?.alcohol, false)
        XCTAssertNil(fetched?.workout)
        XCTAssertEqual(fetched?.perceivedSleepQuality, .good)
        XCTAssertEqual(fetched?.notes, "Encrypted note")
        let contextEntryCount = inventory.contextEntryCount
        XCTAssertEqual(contextEntryCount, 1)

        // Test replacement
        var updated = entry
        updated.caffeineLate = false
        try await repository.saveContextEntry(updated)

        let refetched = try await repository.fetchContextEntry(forSleepDateKey: "2026-06-01")
        XCTAssertEqual(refetched?.caffeineLate, false)

        // Test deletion
        try await repository.deleteAllContextEntries()
        let emptyInventory = try await repository.fetchDataInventory()
        let emptyContextEntryCount = emptyInventory.contextEntryCount
        XCTAssertEqual(emptyContextEntryCount, 0)
    }

    func testLocalRepositoryPersistsProtocolBaselineSnapshotExtendedMetrics() async throws {
        let repository = try await makeRepository()
        let snapshot = Self.protocolBaselineSnapshot()

        try await repository.saveBaselineSnapshot(snapshot)

        let fetched = try await repository.fetchBaselineSnapshot()
        XCTAssertEqual(fetched?.id, snapshot.id)
        XCTAssertEqual(fetched?.meanRestorativeMin, 80.0)
        XCTAssertEqual(fetched?.stdRestorativePctOfInBed, 5.0)
        XCTAssertEqual(fetched?.meanDeepMin, 64.0)
        XCTAssertEqual(fetched?.stdDeepMin, 7.0)
        XCTAssertEqual(fetched?.meanRemMin, 82.0)
        XCTAssertEqual(fetched?.stdRemMin, 9.0)
        XCTAssertEqual(fetched?.meanAwakeMin, 18.0)
        XCTAssertEqual(fetched?.stdAwakeMin, 4.0)
        XCTAssertEqual(fetched?.meanTotalSleepMin, 421.0)
        XCTAssertEqual(fetched?.stdTotalSleepMin, 31.0)
        XCTAssertEqual(fetched?.meanLatencyMin, 16.0)
        XCTAssertEqual(fetched?.stdLatencyMin, 6.0)
        XCTAssertEqual(fetched?.meanSleepScore, 77.0)
        XCTAssertEqual(fetched?.stdSleepScore, 8.0)
    }

    @MainActor
    func testLocalRepositoryDecodesLegacyProtocolBaselineSnapshotBody() async throws {
        let container = try BetterPersistenceContainerFactory.makePreviewContainer()
        let context = ModelContext(container)
        let legacyBody = LegacyProtocolBaselineSnapshotBody(
            meanRestorativeMin: 80.0,
            stdRestorativeMin: 10.0,
            meanRestorativePctOfInBed: 62.0,
            stdRestorativePctOfInBed: 5.0,
            meanLongestRestorativeBlockMin: 60.0,
            stdLongestRestorativeBlockMin: 8.0,
            continuityCategoryDistribution: [.good: 1.0]
        )
        context.insert(StoredProtocolBaselineSnapshot(
            id: UUID(),
            frozenAt: Self.date("2026-04-01T00:00:00Z"),
            windowStart: Self.date("2026-01-01T00:00:00Z"),
            windowEnd: Self.date("2026-04-01T00:00:00Z"),
            validNightCount: 14,
            isInsufficient: false,
            bodyData: try PersistenceJSON.encode(legacyBody)
        ))
        try context.save()
        let repository = LocalDataRepository(modelContainer: container)

        let fetched = try await repository.fetchBaselineSnapshot()

        XCTAssertEqual(fetched?.meanRestorativeMin, 80.0)
        XCTAssertEqual(fetched?.stdLongestRestorativeBlockMin, 8.0)
        XCTAssertEqual(fetched?.continuityCategoryDistribution[.good], 1.0)
        XCTAssertNil(fetched?.meanDeepMin)
        XCTAssertNil(fetched?.stdDeepMin)
        XCTAssertNil(fetched?.meanRemMin)
        XCTAssertNil(fetched?.stdRemMin)
        XCTAssertNil(fetched?.meanAwakeMin)
        XCTAssertNil(fetched?.stdAwakeMin)
        XCTAssertNil(fetched?.meanTotalSleepMin)
        XCTAssertNil(fetched?.stdTotalSleepMin)
        XCTAssertNil(fetched?.meanLatencyMin)
        XCTAssertNil(fetched?.stdLatencyMin)
        XCTAssertNil(fetched?.meanSleepScore)
        XCTAssertNil(fetched?.stdSleepScore)
    }

    func testLocalRepositoryPersistsSleepModeSettingsScheduleAndSessions() async throws {
        let repository = try await makeRepository()
        let settings = SleepModeSettings(
            breathingRounds: 5,
            blackoutAfterBreathing: true,
            dimScreenDuringBlackout: false,
            playAudioDuringBlackout: true,
            createdAt: Self.date("2026-05-04T10:00:00Z"),
            updatedAt: Self.date("2026-05-04T10:00:00Z")
        )
        let schedule = SleepModeSchedule(
            isEnabled: true,
            startHour: 22,
            startMinute: 15,
            endHour: 6,
            endMinute: 30,
            activeWeekdays: [2, 3, 4, 5, 6],
            reminderLeadMinutes: 20,
            autoEnterWhenForeground: true,
            useFocusChecklist: true,
            useScreenTimeShields: false,
            createdAt: Self.date("2026-05-04T10:00:00Z"),
            updatedAt: Self.date("2026-05-04T10:00:00Z")
        )
        let session = SleepModeSession(
            startedAt: Self.date("2026-05-04T22:15:00Z"),
            endedAt: Self.date("2026-05-05T06:30:00Z"),
            startReason: .scheduledForeground,
            breathingRoundsCompleted: 5,
            blackoutStartedAt: Self.date("2026-05-04T22:20:00Z"),
            blackoutEndedAt: Self.date("2026-05-05T06:25:00Z"),
            screenTimeShieldsEnabled: false,
            createdAt: Self.date("2026-05-04T22:15:00Z"),
            updatedAt: Self.date("2026-05-05T06:30:00Z"),
            calendar: Self.utcCalendar
        )

        try await repository.saveSleepModeSettings(settings)
        try await repository.saveSleepModeSchedule(schedule)
        try await repository.saveSleepModeSession(session)

        let fetchedSettings = try await repository.fetchSleepModeSettings()
        let fetchedSchedule = try await repository.fetchSleepModeSchedule()
        let fetchedSessions = try await repository.fetchSleepModeSessions(
            from: Self.date("2026-05-04T00:00:00Z"),
            to: Self.date("2026-05-06T00:00:00Z")
        )
        let inventory = try await repository.fetchDataInventory()

        XCTAssertEqual(fetchedSettings, settings)
        XCTAssertEqual(fetchedSchedule, schedule)
        XCTAssertEqual(fetchedSessions, [session])
        XCTAssertEqual(inventory.sleepModeSettingsCount, 1)
        XCTAssertEqual(inventory.sleepModeScheduleCount, 1)
        XCTAssertEqual(inventory.sleepModeSessionCount, 1)
        XCTAssertEqual(inventory.lastSleepModeSessionDate, session.startedAt)
    }

    func testLocalRepositoryDeletesSleepModeData() async throws {
        let repository = try await makeRepository()
        try await repository.saveSleepModeSettings(SleepModeSettings())
        try await repository.saveSleepModeSchedule(SleepModeSchedule(isEnabled: true))
        try await repository.saveSleepModeSession(
            SleepModeSession(startedAt: Self.date("2026-05-04T22:00:00Z"), calendar: Self.utcCalendar)
        )

        try await repository.deleteAllSleepModeData()

        let inventory = try await repository.fetchDataInventory()
        let fetchedSettings = try await repository.fetchSleepModeSettings()
        let fetchedSchedule = try await repository.fetchSleepModeSchedule()
        XCTAssertNil(fetchedSettings)
        XCTAssertNil(fetchedSchedule)
        XCTAssertEqual(inventory.sleepModeSessionCount, 0)
    }

    func testLocalRepositoryPrunesOldData() async throws {
        let repository = try await makeRepository()
        let now = Date()
        let sixtyOneDaysAgo = now.addingTimeInterval(-61 * 86_400)
        let thirtyDaysAgo = now.addingTimeInterval(-30 * 86_400)
        
        let oldSession = Self.session(
            key: SleepDateKey.calendarDateKey(for: sixtyOneDaysAgo, calendar: Self.utcCalendar),
            start: sixtyOneDaysAgo.addingTimeInterval(-8 * 3_600),
            end: sixtyOneDaysAgo
        )
        let recentSession = Self.session(
            key: SleepDateKey.calendarDateKey(for: thirtyDaysAgo, calendar: Self.utcCalendar),
            start: thirtyDaysAgo.addingTimeInterval(-8 * 3_600),
            end: thirtyDaysAgo
        )
        
        try await repository.saveSessions([oldSession, recentSession])
        
        var inventory = try await repository.fetchDataInventory()
        let initialSleepSessionCount = inventory.sleepSessionCount
        XCTAssertEqual(initialSleepSessionCount, 2)
        
        try await repository.pruneDataOlderThan(days: 60)
        
        inventory = try await repository.fetchDataInventory()
        let prunedSleepSessionCount = inventory.sleepSessionCount
        XCTAssertEqual(prunedSleepSessionCount, 1)
        
        let sessions = try await repository.fetchCachedSessions(
            from: sixtyOneDaysAgo.addingTimeInterval(-100 * 86_400),
            to: now
        )
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first?.sleepDateKey, recentSession.sleepDateKey)
    }

    @MainActor
    func testSyncCoordinatorInitialSyncCachesSessionsBaselineBiometricsAndSuppressesOlderAlerts() async throws {
        let localRepository = try await makeRepository()
        try await localRepository.saveProfile(
            UserProfile(
                sleepGoalHours: 8,
                baselineWindowDays: 30,
                createdAt: Self.date("2026-05-05T00:00:00Z")
            )
        )
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
        XCTAssertEqual(alerts.map(\.kind), [])
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
    func testSleepDashboardLoadsRecentSessionsEndingAtSelectedDate() async throws {
        let sessions = (1...35).map { day in
            let end = Self.utcCalendar.date(
                byAdding: .day,
                value: day - 1,
                to: Self.date("2026-04-01T06:00:00Z")
            )!
            let start = end.addingTimeInterval(-8 * 3_600)
            return Self.session(
                key: SleepDateKey.calendarDateKey(for: end, calendar: Self.utcCalendar),
                start: start,
                end: end,
                score: Double(60 + day)
            )
        }
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

        await viewModel.selectDate("2026-05-05")

        // SleepDashboardViewModel.loadRecentSessions now uses a 60-day window
        // (limit: 59 plus the selected session, .suffix(60)). With 35 fabricated
        // sessions ending 2026-05-05, all 35 are returned.
        XCTAssertEqual(viewModel.recentSessions.count, 35)
        XCTAssertEqual(viewModel.recentSessions.first?.sleepDateKey, "2026-04-01")
        XCTAssertEqual(viewModel.recentSessions.last?.sleepDateKey, "2026-05-05")
    }

    func testScheduleChartMetricsAverageSleepTimesAcrossMidnight() {
        let sessions = [
            Self.session(
                key: "2026-05-01",
                start: Self.date("2026-04-30T23:50:00Z"),
                end: Self.date("2026-05-01T07:00:00Z")
            ),
            Self.session(
                key: "2026-05-02",
                start: Self.date("2026-05-02T00:10:00Z"),
                end: Self.date("2026-05-02T07:00:00Z")
            )
        ]

        let metrics = SleepScheduleChartMetrics(sessions: sessions, calendar: Self.utcCalendar)
        let midnightDistance = min(
            abs(metrics.bedtimeAverageMinute),
            abs(metrics.bedtimeAverageMinute - 1_440)
        )

        XCTAssertLessThan(midnightDistance, 1)
        XCTAssertEqual(metrics.bedtimeVariationMinutes, 10, accuracy: 0.1)
        XCTAssertEqual(metrics.wakeAverageMinute, 7 * 60, accuracy: 0.1)
        XCTAssertEqual(ScheduleConsistencyView.formatMinuteOfDay(metrics.bedtimeAverageMinute), "12:00 AM")
    }

    func testBiometricHistoryOmitsMissingValues() {
        let sessions = [
            Self.session(
                key: "2026-05-01",
                start: Self.date("2026-04-30T22:00:00Z"),
                end: Self.date("2026-05-01T06:00:00Z")
            ),
            Self.session(
                key: "2026-05-02",
                start: Self.date("2026-05-01T22:00:00Z"),
                end: Self.date("2026-05-02T06:00:00Z"),
                biometrics: NightlyBiometricSummary(
                    sleepSessionID: UUID(),
                    sleepDateKey: "2026-05-02",
                    respiratoryRateAverage: 14.4
                )
            )
        ]

        XCTAssertEqual(sessions.biometricTrendPoints { $0.heartRateAverage }, [])
        XCTAssertEqual(sessions.biometricTrendPoints { $0.respiratoryRateAverage }.map(\.value), [14.4])
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

    @MainActor
    func testTrendsLoadsChronotypeFromWearableSessions() async throws {
        let sessions = Self.chronotypeSessions()
        let repository = MockLocalDataRepository(sessions: sessions)
        let viewModel = TrendsViewModel(localRepository: repository, calendar: Self.utcCalendar)

        await viewModel.loadData(now: Self.date("2026-05-01T00:00:00Z"))

        XCTAssertEqual(viewModel.chronotypeResult?.status, .estimated)
        XCTAssertEqual(viewModel.chronotypeResult?.validNightCount, 14)
        XCTAssertEqual(viewModel.chronotypeResult?.workdayNightCount, 10)
        XCTAssertEqual(viewModel.chronotypeResult?.freeDayNightCount, 4)
        XCTAssertEqual(viewModel.chronotypeResult?.estimate?.bucket, .intermediate)
    }

    @MainActor
    func testTrendsChronotypeShowsInsufficientDataWhenRequirementsAreMissing() async throws {
        let sessions = [
            Self.session(key: "2026-04-06", start: Self.date("2026-04-06T00:30:00Z"), end: Self.date("2026-04-06T07:30:00Z")),
            Self.session(key: "2026-04-07", start: Self.date("2026-04-07T00:30:00Z"), end: Self.date("2026-04-07T07:30:00Z"))
        ]
        let repository = MockLocalDataRepository(sessions: sessions)
        let viewModel = TrendsViewModel(localRepository: repository, calendar: Self.utcCalendar)

        await viewModel.loadData(now: Self.date("2026-05-01T00:00:00Z"))

        XCTAssertEqual(viewModel.chronotypeResult?.status, .insufficientData)
        XCTAssertTrue(viewModel.chronotypeResult?.missingRequirements.contains(.totalNights) == true)
        XCTAssertTrue(viewModel.chronotypeResult?.missingRequirements.contains(.freeDayNights) == true)
    }

    @MainActor
    func testSleepDashboardLoadsBodyClockForSelectedDate() async throws {
        let sessions = Self.chronotypeSessions()
        let repository = MockLocalDataRepository(
            sessions: sessions,
            profile: UserProfile(sleepGoalHours: 8, baselineWindowDays: 30)
        )
        let coordinator = SyncCoordinator(
            healthRepository: FakeHealthKitRepository(),
            localRepository: repository,
            processor: SleepDataProcessor(calendar: Self.utcCalendar)
        )
        let viewModel = SleepDashboardViewModel(
            syncCoordinator: coordinator,
            localRepository: repository,
            processor: SleepDataProcessor(calendar: Self.utcCalendar),
            calendar: Self.utcCalendar
        )

        await viewModel.selectDate("2026-04-18")

        XCTAssertEqual(viewModel.bodyClockResult?.status, .estimated)
        XCTAssertEqual(viewModel.bodyClockResult?.estimate?.bucket, .intermediate)
        XCTAssertEqual(viewModel.selectedSleepBodyClockAlignment?.category, .aligned)
        XCTAssertEqual(viewModel.selectedSleepBodyClockAlignment?.signedDeltaMinutes, 21)
    }

    @MainActor
    func testSleepDashboardHidesBodyClockAlignmentWhenDataIsInsufficient() async throws {
        let sessions = [
            Self.session(key: "2026-04-06", start: Self.date("2026-04-06T00:30:00Z"), end: Self.date("2026-04-06T07:30:00Z")),
            Self.session(key: "2026-04-07", start: Self.date("2026-04-07T00:30:00Z"), end: Self.date("2026-04-07T07:30:00Z"))
        ]
        let repository = MockLocalDataRepository(
            sessions: sessions,
            profile: UserProfile(sleepGoalHours: 8, baselineWindowDays: 30)
        )
        let coordinator = SyncCoordinator(
            healthRepository: FakeHealthKitRepository(),
            localRepository: repository,
            processor: SleepDataProcessor(calendar: Self.utcCalendar)
        )
        let viewModel = SleepDashboardViewModel(
            syncCoordinator: coordinator,
            localRepository: repository,
            processor: SleepDataProcessor(calendar: Self.utcCalendar),
            calendar: Self.utcCalendar
        )

        await viewModel.selectDate("2026-04-07")

        XCTAssertEqual(viewModel.bodyClockResult?.status, .insufficientData)
        XCTAssertNil(viewModel.selectedSleepBodyClockAlignment)
    }

    @MainActor
    func testSleepDashboardRecalculatesBodyClockAlignmentForHistoricalSelection() async throws {
        let sessions = Self.chronotypeSessions()
        let repository = MockLocalDataRepository(
            sessions: sessions,
            profile: UserProfile(sleepGoalHours: 8, baselineWindowDays: 30)
        )
        let coordinator = SyncCoordinator(
            healthRepository: FakeHealthKitRepository(),
            localRepository: repository,
            processor: SleepDataProcessor(calendar: Self.utcCalendar)
        )
        let viewModel = SleepDashboardViewModel(
            syncCoordinator: coordinator,
            localRepository: repository,
            processor: SleepDataProcessor(calendar: Self.utcCalendar),
            calendar: Self.utcCalendar
        )

        await viewModel.selectDate("2026-04-18")
        XCTAssertNotNil(viewModel.selectedSleepBodyClockAlignment)

        await viewModel.selectDate("2026-04-06")

        XCTAssertEqual(viewModel.selectedSession?.sleepDateKey, "2026-04-06")
        XCTAssertEqual(viewModel.bodyClockResult?.status, .insufficientData)
        XCTAssertNil(viewModel.selectedSleepBodyClockAlignment)
    }

    func testActivityStatusLogPersistsAndOverwritesSameDate() async throws {
        let repository = try await makeRepository()
        let first = ActivityStatusLog(
            dateKey: "2026-05-04",
            status: .traveling,
            note: "Flight day",
            createdAt: Self.date("2026-05-04T08:00:00Z"),
            updatedAt: Self.date("2026-05-04T08:00:00Z")
        )
        let replacement = ActivityStatusLog(
            dateKey: "2026-05-04",
            status: .jetLagged,
            note: "Adjusting",
            createdAt: first.createdAt,
            updatedAt: Self.date("2026-05-04T20:00:00Z")
        )
        let nextDay = ActivityStatusLog(dateKey: "2026-05-05", status: .active)

        try await repository.saveActivityStatusLog(first)
        try await repository.saveActivityStatusLog(replacement)
        try await repository.saveActivityStatusLog(nextDay)

        let selected = try await repository.fetchActivityStatusLog(forDateKey: "2026-05-04")
        let range = try await repository.fetchActivityStatusLogs(from: "2026-05-04", to: "2026-05-05")

        XCTAssertEqual(selected?.status, .jetLagged)
        XCTAssertEqual(selected?.note, "Adjusting")
        XCTAssertEqual(range.map(\.dateKey), ["2026-05-04", "2026-05-05"])
        XCTAssertEqual(range.first?.status, .jetLagged)
    }

    func testDailyActivitySummaryPersistsOverwritesAndFetchesRange() async throws {
        let repository = try await makeRepository()
        let first = DailyActivitySummary(
            dateKey: "2026-05-04",
            steps: 8_000,
            activeEnergy: 300,
            exerciseMinutes: 20,
            standHours: 9,
            flights: 4,
            distanceMeters: 5_000,
            generatedAt: Self.date("2026-05-04T12:00:00Z")
        )
        let replacement = DailyActivitySummary(
            dateKey: "2026-05-04",
            steps: 9_000,
            activeEnergy: 350,
            exerciseMinutes: 30,
            standHours: 10,
            flights: 5,
            distanceMeters: 6_000,
            generatedAt: Self.date("2026-05-04T13:00:00Z")
        )
        let nextDay = DailyActivitySummary(dateKey: "2026-05-05", steps: 7_500)

        try await repository.saveDailyActivitySummary(first)
        try await repository.saveDailyActivitySummary(replacement)
        try await repository.saveDailyActivitySummary(nextDay)

        let range = try await repository.fetchDailyActivitySummaries(from: "2026-05-04", to: "2026-05-05")

        XCTAssertEqual(range.map(\.dateKey), ["2026-05-04", "2026-05-05"])
        XCTAssertEqual(range.first?.steps, 9_000)
        XCTAssertEqual(range.first?.exerciseMinutes, 30)
    }

    func testHealthKitQuantityMappingIncludesBiologyAndActivityTypes() {
        let mappedTypes: [BiometricType] = [
            .vo2Max,
            .bodyMass,
            .leanBodyMass,
            .bodyFatPercentage,
            .bodyTemperature,
            .stepCount,
            .activeEnergyBurned,
            .appleExerciseTime,
            .appleStandTime,
            .flightsClimbed,
            .distanceWalkingRunning
        ]

        for type in mappedTypes {
            XCTAssertNotNil(HealthKitRepository.quantityType(for: type), "\(type) should map to a HealthKit quantity type")
        }
    }

    @MainActor
    func testActivityViewModelSavesManualStatusAndReloadsSelectedDay() async throws {
        let repository = MockLocalDataRepository(
            sessions: [
                Self.session(
                    key: "2026-05-04",
                    start: Self.date("2026-05-03T22:00:00Z"),
                    end: Self.date("2026-05-04T06:00:00Z"),
                    score: 81
                )
            ]
        )
        let viewModel = ActivityViewModel(
            localRepository: repository,
            healthRepository: FakeHealthKitRepository(),
            calendar: Self.utcCalendar,
            now: Self.date("2026-05-04T12:00:00Z")
        )

        await viewModel.load()
        await viewModel.saveStatus(.sick, note: "Cold symptoms")

        XCTAssertEqual(viewModel.selectedStatusLog?.status, .sick)
        XCTAssertEqual(viewModel.selectedStatusLog?.note, "Cold symptoms")
        XCTAssertEqual(viewModel.weekSummaries.map(\.sleepDateKey), ["2026-05-04"])
    }

    @MainActor
    func testBiologyViewModelBuildsPartialDataState() async throws {
        let session = Self.session(
            key: "2026-05-04",
            start: Self.date("2026-05-03T22:00:00Z"),
            end: Self.date("2026-05-04T06:00:00Z")
        )
        let repository = MockLocalDataRepository(sessions: [session], baselines: [PreviewSleepData.sampleBaseline])
        let healthRepository = FakeHealthKitRepository(
            biometricSamples: [
                .vo2Max: [
                    BiometricSample(
                        type: .vo2Max,
                        value: 47,
                        unit: BiometricType.vo2Max.unitSymbol,
                        startDate: Self.date("2026-05-04T08:00:00Z"),
                        endDate: Self.date("2026-05-04T08:01:00Z")
                    )
                ]
            ]
        )
        let viewModel = BiologyViewModel(
            localRepository: repository,
            healthRepository: healthRepository,
            calendar: Self.utcCalendar
        )

        await viewModel.load(now: Self.date("2026-05-04T12:00:00Z"))

        XCTAssertEqual(viewModel.metrics.first { $0.kind == .vo2Max }?.value, 47)
        XCTAssertEqual(viewModel.metrics.first { $0.kind == .hrvBaseline }?.value, PreviewSleepData.sampleBaseline.hrvAverage)
        XCTAssertEqual(viewModel.metrics.first { $0.kind == .bodyTemperature }?.rating, "Not available")
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
        dataQuality: SleepDataQuality = .detailedStages,
        biometrics: NightlyBiometricSummary? = nil
    ) -> SleepSession {
        let totalSleep = totalSleep ?? end.timeIntervalSince(start)
        return SleepSession(
            sleepDateKey: key,
            startDate: start,
            endDate: end,
            inBedStartDate: start,
            inBedEndDate: end,
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
            ),
            biometrics: biometrics
        )
    }

    static func protocolBaselineSnapshot() -> ProtocolBaselineSnapshot {
        ProtocolBaselineSnapshot(
            id: UUID(),
            frozenAt: date("2026-04-01T00:00:00Z"),
            windowStart: date("2026-01-01T00:00:00Z"),
            windowEnd: date("2026-04-01T00:00:00Z"),
            validNightCount: 14,
            meanRestorativeMin: 80.0,
            stdRestorativeMin: 10.0,
            meanRestorativePctOfInBed: 62.0,
            stdRestorativePctOfInBed: 5.0,
            meanLongestRestorativeBlockMin: 60.0,
            stdLongestRestorativeBlockMin: 8.0,
            continuityCategoryDistribution: [.good: 0.7, .moderatelyFragmented: 0.3],
            isInsufficient: false,
            meanDeepMin: 64.0,
            stdDeepMin: 7.0,
            meanRemMin: 82.0,
            stdRemMin: 9.0,
            meanAwakeMin: 18.0,
            stdAwakeMin: 4.0,
            meanTotalSleepMin: 421.0,
            stdTotalSleepMin: 31.0,
            meanLatencyMin: 16.0,
            stdLatencyMin: 6.0,
            meanSleepScore: 77.0,
            stdSleepScore: 8.0
        )
    }

    static func chronotypeSessions() -> [SleepSession] {
        [
            session(key: "2026-04-05", start: date("2026-04-05T00:30:00Z"), end: date("2026-04-05T07:30:00Z")),
            session(key: "2026-04-06", start: date("2026-04-06T00:30:00Z"), end: date("2026-04-06T07:30:00Z")),
            session(key: "2026-04-07", start: date("2026-04-07T00:30:00Z"), end: date("2026-04-07T07:30:00Z")),
            session(key: "2026-04-08", start: date("2026-04-08T00:30:00Z"), end: date("2026-04-08T07:30:00Z")),
            session(key: "2026-04-09", start: date("2026-04-09T00:30:00Z"), end: date("2026-04-09T07:30:00Z")),
            session(key: "2026-04-12", start: date("2026-04-12T00:30:00Z"), end: date("2026-04-12T07:30:00Z")),
            session(key: "2026-04-13", start: date("2026-04-13T00:30:00Z"), end: date("2026-04-13T07:30:00Z")),
            session(key: "2026-04-14", start: date("2026-04-14T00:30:00Z"), end: date("2026-04-14T07:30:00Z")),
            session(key: "2026-04-15", start: date("2026-04-15T00:30:00Z"), end: date("2026-04-15T07:30:00Z")),
            session(key: "2026-04-16", start: date("2026-04-16T00:30:00Z"), end: date("2026-04-16T07:30:00Z")),
            session(key: "2026-04-10", start: date("2026-04-10T01:00:00Z"), end: date("2026-04-10T09:00:00Z")),
            session(key: "2026-04-11", start: date("2026-04-11T01:00:00Z"), end: date("2026-04-11T09:00:00Z")),
            session(key: "2026-04-17", start: date("2026-04-17T01:00:00Z"), end: date("2026-04-17T09:00:00Z")),
            session(key: "2026-04-18", start: date("2026-04-18T01:00:00Z"), end: date("2026-04-18T09:00:00Z"))
        ]
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

private struct LegacyProtocolBaselineSnapshotBody: Codable {
    var meanRestorativeMin: Double?
    var stdRestorativeMin: Double?
    var meanRestorativePctOfInBed: Double?
    var stdRestorativePctOfInBed: Double?
    var meanLongestRestorativeBlockMin: Double?
    var stdLongestRestorativeBlockMin: Double?
    var continuityCategoryDistribution: [SleepContinuityCategory: Double]
}

final class FakeHealthKitRepository: HealthKitRepositoryProtocol, @unchecked Sendable {
    var sleepSamples: [HKCategorySample]
    var biometricSamples: [BiometricType: [BiometricSample]]
    var anchoredResult: HealthKitAnchoredResult?
    var requestAuthorizationCallCount = 0

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
        requestAuthorizationCallCount += 1
        return HealthAuthorizationResult(
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
