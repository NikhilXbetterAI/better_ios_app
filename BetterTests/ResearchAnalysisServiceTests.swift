import Foundation
import HealthKit
import XCTest
@testable import Better

@MainActor
final class ResearchAnalysisServiceTests: XCTestCase {
    func testBuildExportPackageJoinsNightlyProtocolActivityStatusAndBaselineData() async throws {
        let protocolItem = Self.protocolItem()
        let session = Self.session(
            key: "2026-05-04",
            start: Self.date("2026-05-03T22:00:00Z"),
            end: Self.date("2026-05-04T06:00:00Z"),
            totalSleepHours: 8,
            score: 84,
            biometrics: Self.biometrics(key: "2026-05-04")
        )
        let repository = MockLocalDataRepository(
            sessions: [session],
            dailyActivitySummaries: [
                DailyActivitySummary(dateKey: "2026-05-04", steps: 8_500, activeEnergy: 420, exerciseMinutes: 35, standHours: 11, distanceMeters: 6_000)
            ],
            baselines: [Self.baseline()],
            adherence: [
                ProtocolAdherence(
                    protocolID: protocolItem.id.uuidString,
                    dateKey: "2026-05-04",
                    taken: true,
                    takenAt: Self.date("2026-05-03T21:00:00Z")
                )
            ],
            activityStatusLogs: [
                ActivityStatusLog(dateKey: "2026-05-04", status: .jetLagged, note: "Flight")
            ],
            profile: UserProfile(baselineWindowDays: 30, isResearchMode: true)
        )
        let service = ResearchAnalysisService(
            localRepository: repository,
            healthRepository: ResearchFakeHealthKitRepository(),
            calendar: Self.utcCalendar
        )

        let package = try await service.buildExportPackage(
            from: Self.date("2026-05-04T00:00:00Z"),
            to: Self.date("2026-05-05T00:00:00Z"),
            protocolItems: [protocolItem],
            generatedAt: Self.date("2026-05-05T12:00:00Z")
        )

        let row = try XCTUnwrap(package.nightlyRows.first)
        XCTAssertEqual(row.sleepDateKey, "2026-05-04")
        XCTAssertTrue(row.isJetLagged)
        XCTAssertEqual(row.activityStatus, .jetLagged)
        XCTAssertEqual(row.activityNote, "Flight")
        XCTAssertEqual(row.steps, 8_500)
        XCTAssertEqual(row.protocolNamesTaken, ["Magnesium"])
        XCTAssertEqual(row.minutesFromProtocolToSleep.first ?? 0, 60, accuracy: 0.001)
        XCTAssertEqual(row.baselineTotalSleepDeltaHours ?? 0, 1, accuracy: 0.001)
        XCTAssertEqual(row.baselineEfficiencyDeltaPercent ?? 0, 10.117, accuracy: 0.001)
        XCTAssertEqual(row.baselineWASODeltaMinutes ?? 0, 10, accuracy: 0.001)
        XCTAssertEqual(row.baselineLatencyDeltaMinutes ?? 0, 5, accuracy: 0.001)
        XCTAssertEqual(row.baselineHRVDelta ?? 0, 10, accuracy: 0.001)
    }

    func testProtocolSummariesComparePerProtocolAnyProtocolAndJetLagAdjustedRows() async throws {
        let protocolItem = Self.protocolItem()
        var sessions: [SleepSession] = []
        var adherence: [ProtocolAdherence] = []
        var statuses: [ActivityStatusLog] = []

        for day in 1...10 {
            let key = String(format: "2026-05-%02d", day)
            let taken = day <= 5
            sessions.append(
                Self.session(
                    key: key,
                    start: Self.date(String(format: "2026-05-%02dT22:00:00Z", day)),
                    end: Self.date(String(format: "2026-05-%02dT06:00:00Z", day + 1)),
                    totalSleepHours: taken ? 8 : 6,
                    score: taken ? 86 : 70
                )
            )
            if taken {
                adherence.append(ProtocolAdherence(protocolID: protocolItem.id.uuidString, dateKey: key, taken: true, takenAt: Self.date(String(format: "2026-05-%02dT21:00:00Z", day))))
            } else {
                adherence.append(ProtocolAdherence(protocolID: protocolItem.id.uuidString, dateKey: key, taken: false))
            }
        }
        statuses.append(ActivityStatusLog(dateKey: "2026-05-01", status: .jetLagged))
        statuses.append(ActivityStatusLog(dateKey: "2026-05-06", status: .traveling))

        let repository = MockLocalDataRepository(
            sessions: sessions,
            baselines: [Self.baseline()],
            adherence: adherence,
            activityStatusLogs: statuses,
            profile: UserProfile(baselineWindowDays: 30, isResearchMode: true)
        )
        let service = ResearchAnalysisService(
            localRepository: repository,
            healthRepository: ResearchFakeHealthKitRepository(),
            calendar: Self.utcCalendar
        )

        let package = try await service.buildExportPackage(
            from: Self.date("2026-05-01T00:00:00Z"),
            to: Self.date("2026-05-12T00:00:00Z"),
            protocolItems: [protocolItem],
            generatedAt: Self.date("2026-05-12T12:00:00Z")
        )

        let any = try XCTUnwrap(package.protocolSummaries.first { $0.protocolID == "any_protocol" })
        let perProtocol = try XCTUnwrap(package.protocolSummaries.first { $0.protocolID == protocolItem.id.uuidString })
        XCTAssertEqual(any.takenNightCount, 5)
        XCTAssertEqual(any.missedNightCount, 5)
        XCTAssertEqual(any.sleepDifferenceHours ?? 0, 2, accuracy: 0.001)
        XCTAssertEqual(perProtocol.scoreDifference ?? 0, 16, accuracy: 0.001)
        XCTAssertEqual(perProtocol.jetLagAdjustedSleepDifferenceHours ?? 0, 2, accuracy: 0.001)
        XCTAssertEqual(perProtocol.confidence, .low)
        XCTAssertTrue(perProtocol.caveats.contains("Travel or jet-lag nights present"))
    }

    func testInsufficientConfidenceAndCaveatsForSmallOrIncompleteSamples() async throws {
        let protocolItem = Self.protocolItem()
        let sessions = [
            Self.session(key: "2026-05-01", start: Self.date("2026-05-01T22:00:00Z"), end: Self.date("2026-05-02T05:00:00Z"), dataQuality: .unspecifiedSleepOnly),
            Self.session(key: "2026-05-02", start: Self.date("2026-05-02T22:00:00Z"), end: Self.date("2026-05-03T05:00:00Z"))
        ]
        let repository = MockLocalDataRepository(
            sessions: sessions,
            adherence: [ProtocolAdherence(protocolID: protocolItem.id.uuidString, dateKey: "2026-05-01", taken: true)],
            profile: UserProfile(baselineWindowDays: 30, isResearchMode: true)
        )
        let service = ResearchAnalysisService(
            localRepository: repository,
            healthRepository: ResearchFakeHealthKitRepository(),
            calendar: Self.utcCalendar
        )

        let package = try await service.buildExportPackage(
            from: Self.date("2026-05-01T00:00:00Z"),
            to: Self.date("2026-05-04T00:00:00Z"),
            protocolItems: [protocolItem]
        )

        let summary = try XCTUnwrap(package.protocolSummaries.first { $0.protocolID == protocolItem.id.uuidString })
        XCTAssertEqual(summary.confidence, .insufficient)
        XCTAssertTrue(summary.caveats.contains("Low sample size"))
        XCTAssertTrue(summary.caveats.contains("Some protocol timing is missing"))
        XCTAssertTrue(summary.caveats.contains("Some biometrics are missing"))
        XCTAssertTrue(summary.caveats.contains("Some nights do not have detailed sleep stages"))
    }

    func testMissingProtocolDataExportsUnknownAndDoesNotCountAsMissed() async throws {
        let protocolItem = Self.protocolItem()
        let sessions = [
            Self.session(key: "2026-05-01", start: Self.date("2026-05-01T22:00:00Z"), end: Self.date("2026-05-02T06:00:00Z"), totalSleepHours: 8),
            Self.session(key: "2026-05-02", start: Self.date("2026-05-02T22:00:00Z"), end: Self.date("2026-05-03T06:00:00Z"), totalSleepHours: 6)
        ]
        let repository = MockLocalDataRepository(
            sessions: sessions,
            adherence: [
                ProtocolAdherence(protocolID: protocolItem.id.uuidString, dateKey: "2026-05-01", taken: true)
            ],
            profile: UserProfile(baselineWindowDays: 30, isResearchMode: true)
        )
        let service = ResearchAnalysisService(
            localRepository: repository,
            healthRepository: ResearchFakeHealthKitRepository(),
            calendar: Self.utcCalendar
        )

        let package = try await service.buildExportPackage(
            from: Self.date("2026-05-01T00:00:00Z"),
            to: Self.date("2026-05-04T00:00:00Z"),
            protocolItems: [protocolItem]
        )

        let unknownRow = try XCTUnwrap(package.nightlyRows.first { $0.sleepDateKey == "2026-05-02" })
        XCTAssertEqual(unknownRow.protocolUsageStatus, .unknown)
        XCTAssertNil(unknownRow.protocolTaken)

        let summary = try XCTUnwrap(package.protocolSummaries.first { $0.protocolID == "any_protocol" })
        XCTAssertEqual(summary.takenNightCount, 1)
        XCTAssertEqual(summary.missedNightCount, 0)
        XCTAssertNil(summary.sleepDifferenceHours)
    }

    func testExplicitFalseProtocolDataExportsNotTaken() async throws {
        let protocolItem = Self.protocolItem()
        let session = Self.session(
            key: "2026-05-01",
            start: Self.date("2026-05-01T22:00:00Z"),
            end: Self.date("2026-05-02T06:00:00Z")
        )
        let repository = MockLocalDataRepository(
            sessions: [session],
            adherence: [
                ProtocolAdherence(protocolID: protocolItem.id.uuidString, dateKey: "2026-05-01", taken: false)
            ],
            profile: UserProfile(baselineWindowDays: 30, isResearchMode: true)
        )
        let service = ResearchAnalysisService(
            localRepository: repository,
            healthRepository: ResearchFakeHealthKitRepository(),
            calendar: Self.utcCalendar
        )

        let package = try await service.buildExportPackage(
            from: Self.date("2026-05-01T00:00:00Z"),
            to: Self.date("2026-05-02T12:00:00Z"),
            protocolItems: [protocolItem]
        )

        let row = try XCTUnwrap(package.nightlyRows.first)
        XCTAssertEqual(row.protocolUsageStatus, .notTaken)
        XCTAssertEqual(row.protocolTaken, false)
        XCTAssertEqual(row.protocolName, "Magnesium")
    }

    func testSickNightsAreExcludedFromAdjustedSleepDifference() async throws {
        let protocolItem = Self.protocolItem()
        var sessions: [SleepSession] = []
        var adherence: [ProtocolAdherence] = []
        var statuses: [ActivityStatusLog] = []

        for day in 1...10 {
            let key = String(format: "2026-05-%02d", day)
            let taken = day <= 5
            let isSick = day == 3 || day == 8
            sessions.append(Self.session(
                key: key,
                start: Self.date(String(format: "2026-05-%02dT22:00:00Z", day)),
                end: Self.date(String(format: "2026-05-%02dT06:00:00Z", day + 1)),
                totalSleepHours: isSick ? 3 : (taken ? 8 : 6),
                score: isSick ? 50 : (taken ? 86 : 70)
            ))
            if taken {
                adherence.append(ProtocolAdherence(
                    protocolID: protocolItem.id.uuidString,
                    dateKey: key,
                    taken: true,
                    takenAt: Self.date(String(format: "2026-05-%02dT21:00:00Z", day))
                ))
            } else {
                adherence.append(ProtocolAdherence(
                    protocolID: protocolItem.id.uuidString,
                    dateKey: key,
                    taken: false
                ))
            }
            if isSick {
                statuses.append(ActivityStatusLog(dateKey: key, status: .sick))
            }
        }

        let repository = MockLocalDataRepository(
            sessions: sessions,
            baselines: [Self.baseline()],
            adherence: adherence,
            activityStatusLogs: statuses,
            profile: UserProfile(baselineWindowDays: 30, isResearchMode: true)
        )
        let service = ResearchAnalysisService(
            localRepository: repository,
            healthRepository: ResearchFakeHealthKitRepository(),
            calendar: Self.utcCalendar
        )

        let package = try await service.buildExportPackage(
            from: Self.date("2026-05-01T00:00:00Z"),
            to: Self.date("2026-05-12T00:00:00Z"),
            protocolItems: [protocolItem],
            generatedAt: Self.date("2026-05-12T12:00:00Z")
        )

        let perProtocol = try XCTUnwrap(
            package.protocolSummaries.first { $0.protocolID == protocolItem.id.uuidString }
        )
        // adjustedTaken excludes day 3 (sick): mean(8,8,8,8) = 8h
        // adjustedMissed excludes day 8 (sick): mean(6,6,6,6) = 6h
        // diff = 2.0h
        XCTAssertEqual(perProtocol.jetLagAdjustedSleepDifferenceHours ?? 0, 2, accuracy: 0.001)
    }

    func testCSVExporterEscapesRowsAndWritesExpectedZipEntries() throws {
        let exporter = ResearchCSVExporter()
        let generatedAt = Self.date("2026-05-04T12:00:00Z")
        let row = NightlyResearchRow(
            sleepDateKey: "2026-05-04",
            sleepStart: Self.date("2026-05-03T22:00:00Z"),
            sleepEnd: Self.date("2026-05-04T06:00:00Z"),
            dataQuality: .detailedStages,
            totalSleepHours: 8,
            inBedHours: 8.5,
            efficiencyPercent: 94,
            deepHours: 1.5,
            remHours: 2,
            coreHours: 4.5,
            awakeHours: 0.5,
            wasoMinutes: 20,
            latencyMinutes: 10,
            sleepScore: 88,
            durationScore: 90,
            efficiencyScore: 92,
            remScore: 80,
            deepScore: 85,
            hrvAverage: 55,
            hrvMedian: 54,
            heartRateAverage: 58,
            heartRateMinimum: 48,
            heartRateMaximum: 78,
            respiratoryRateAverage: 14,
            oxygenSaturationAveragePercent: 98,
            oxygenSaturationMinimumPercent: 95,
            steps: 9_000,
            activeEnergyKcal: 400,
            exerciseMinutes: 30,
            standHours: 10,
            distanceMeters: 5_000,
            activityStatus: .active,
            isJetLagged: false,
            activityNote: "Comma, quote \" test",
            protocolTakenAny: true,
            protocolIDsTaken: ["p1"],
            protocolNamesTaken: ["Magnesium"],
            protocolTakenAt: [Self.date("2026-05-03T21:00:00Z")],
            minutesFromProtocolToSleep: [60],
            baselineTotalSleepDeltaHours: 1,
            baselineEfficiencyDeltaPercent: 4,
            baselineWASODeltaMinutes: -5,
            baselineLatencyDeltaMinutes: -3,
            baselineHRVDelta: 8,
            sourceNames: ["Apple Watch"]
        )
        let insight = ResearchInsightSummary(
            generatedAt: generatedAt,
            validNightCount: 1,
            bestProtocolName: nil,
            bestProtocolSleepDifferenceHours: nil,
            confidence: .insufficient,
            baselineSleepDifferenceHours: 1,
            confounderNote: nil,
            summary: "More logged nights are needed."
        )
        let package = ResearchExportPackage(
            generatedAt: generatedAt,
            rangeStart: Self.date("2026-05-01T00:00:00Z"),
            rangeEnd: Self.date("2026-05-05T00:00:00Z"),
            baselineWindowDays: 30,
            baselineValidNights: 10,
            isResearchMode: true,
            nightlyRows: [row],
            protocolSummaries: [],
            insightSummary: insight
        )

        let csv = exporter.nightlyRowsCSV([row])
        XCTAssertTrue(csv.contains("\"Comma, quote \"\" test\""))
        XCTAssertTrue(csv.components(separatedBy: "\n")[0].contains("protocol_usage_status"))
        XCTAssertTrue(csv.components(separatedBy: "\n")[0].contains("comparison_confidence"))
        XCTAssertTrue(csv.components(separatedBy: "\n")[0].contains("source_names,baseline_window_used"))

        let zipURL = try exporter.writeZIP(package: package)
        let data = try Data(contentsOf: zipURL)
        XCTAssertTrue(data.starts(with: Data([0x50, 0x4B, 0x03, 0x04])))
        let zipText = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(zipText.contains("nightly_research_rows.csv"))
        XCTAssertTrue(zipText.contains("protocol_effect_summary.csv"))
        XCTAssertTrue(zipText.contains("export_metadata.csv"))
    }
}

private extension ResearchAnalysisServiceTests {
    static let utcCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    static func protocolItem() -> ProtocolItem {
        ProtocolItem(
            id: UUID(uuidString: "A1B2C3D4-0000-0000-0000-000000000001")!,
            name: "Magnesium",
            dose: "400 mg",
            benefit: "Test",
            instructions: "Test"
        )
    }

    static func session(
        key: String,
        start: Date,
        end: Date,
        totalSleepHours: Double = 7,
        score: Double = 80,
        dataQuality: SleepDataQuality = .detailedStages,
        biometrics: NightlyBiometricSummary? = nil
    ) -> SleepSession {
        let totalSleep = totalSleepHours * 3_600
        let totalInBed = totalSleep + 30 * 60
        return SleepSession(
            sleepDateKey: key,
            startDate: start,
            endDate: end,
            stages: [],
            sources: [SleepSource(name: "Apple Watch", bundleIdentifier: "hidden.example")],
            dataQuality: dataQuality,
            totalInBedTime: totalInBed,
            totalSleepTime: totalSleep,
            awakeDuration: 30 * 60,
            coreDuration: 4 * 3_600,
            deepDuration: 90 * 60,
            remDuration: 90 * 60,
            sleepLatency: 15 * 60,
            waso: 30 * 60,
            efficiency: totalSleep / totalInBed,
            qualityScore: SleepQualityScore(
                overall: score,
                durationScore: score,
                efficiencyScore: score,
                remScore: dataQuality == .unspecifiedSleepOnly ? 0 : score,
                deepScore: dataQuality == .unspecifiedSleepOnly ? 0 : score,
                isPartial: dataQuality == .unspecifiedSleepOnly
            ),
            biometrics: biometrics
        )
    }

    static func biometrics(key: String) -> NightlyBiometricSummary {
        NightlyBiometricSummary(
            sleepSessionID: UUID(),
            sleepDateKey: key,
            heartRateAverage: 58,
            heartRateMinimum: 48,
            heartRateMaximum: 78,
            hrvAverage: 60,
            hrvMedian: 58,
            oxygenSaturationAverage: 0.98,
            oxygenSaturationMinimum: 0.95,
            respiratoryRateAverage: 14
        )
    }

    static func baseline() -> SleepBaseline {
        SleepBaseline(
            windowDays: 30,
            generatedAt: date("2026-05-01T00:00:00Z"),
            validNights: 20,
            totalSleepAverage: 7 * 3_600,
            totalSleepStandardDeviation: 0,
            remAverage: 90 * 60,
            remStandardDeviation: 0,
            deepAverage: 90 * 60,
            deepStandardDeviation: 0,
            efficiencyAverage: 0.84,
            efficiencyStandardDeviation: 0,
            wasoAverage: 20 * 60,
            wasoStandardDeviation: 0,
            latencyAverage: 10 * 60,
            latencyStandardDeviation: 0,
            hrvAverage: 50,
            hrvStandardDeviation: 0,
            respiratoryRateAverage: 14,
            respiratoryRateStandardDeviation: 0,
            oxygenSaturationAverage: 0.98,
            oxygenSaturationStandardDeviation: 0,
            bedtimeMinuteAverage: 22 * 60,
            bedtimeMinuteStandardDeviation: 0,
            wakeMinuteAverage: 6 * 60,
            wakeMinuteStandardDeviation: 0
        )
    }

    static func date(_ string: String) -> Date {
        ISO8601DateFormatter().date(from: string)!
    }
}

final class ResearchFakeHealthKitRepository: HealthKitRepositoryProtocol, @unchecked Sendable {
    var samples: [BiometricType: [BiometricSample]]

    init(samples: [BiometricType: [BiometricSample]] = [:]) {
        self.samples = samples
    }

    func isHealthDataAvailable() -> Bool { true }

    func requestAuthorization() async throws -> HealthAuthorizationResult {
        HealthAuthorizationResult(requestCompleted: true, healthDataAvailable: true, canQuerySleep: true)
    }

    func fetchSleepSamples(from: Date, to: Date) async throws -> [HKCategorySample] { [] }

    func fetchSleepSessions(from: Date, to: Date) async throws -> [SleepSession] { [] }

    func fetchBiometrics(for type: BiometricType, from: Date, to: Date) async throws -> [BiometricSample] {
        samples[type, default: []].filter { $0.endDate > from && $0.startDate < to }
    }

    func fetchSourceSummaries(from: Date, to: Date) async throws -> [SleepSource] { [] }

    func startObservingSleepChanges() async throws -> AsyncStream<HealthKitChangeEvent> {
        AsyncStream { continuation in continuation.finish() }
    }

    func fetchIncrementalSleepChanges(anchor: Data?) async throws -> HealthKitAnchoredResult {
        HealthKitAnchoredResult(samples: [], deletedObjects: [], newAnchor: anchor)
    }
}
