import XCTest
import SwiftData
@testable import Better

final class BetterTests: XCTestCase {
    func testSleepSessionCodableRoundTrip() throws {
        let session = Self.sampleSession()
        let data = try JSONEncoder().encode(session)
        let decoded = try JSONDecoder().decode(SleepSession.self, from: data)

        XCTAssertEqual(decoded, session)
    }

    func testStoredSleepSessionRoundTrip() throws {
        let session = Self.sampleSession()
        let stored = try StoredSleepSession(domain: session)
        let decoded = try stored.toDomain()

        XCTAssertEqual(decoded, session)
    }

    func testPhaseOneContainerCanPersistModels() throws {
        let container = try BetterPersistenceContainerFactory.makePreviewContainer()
        let context = ModelContext(container)
        let profile = UserProfile(
            id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
            sleepGoalHours: 8.5,
            baselineWindowDays: 30,
            isResearchMode: true,
            hasCompletedOnboarding: true,
            createdAt: Date(timeIntervalSince1970: 1_717_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_717_000_600)
        )
        let storedProfile = StoredUserProfile(domain: profile)
        context.insert(storedProfile)

        try context.save()

        let fetched = try context.fetch(FetchDescriptor<StoredUserProfile>())
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.toDomain(), profile)
    }

    @MainActor
    func testAppEnvironmentPreviewBuilds() {
        let environment = AppEnvironment.preview()
        // Verify the primary shell tabs are defined
        XCTAssertEqual(AppTab.allCases.map(\.title), ["Sleep", "Insights", "Chronotype", "Formula", "Settings"])
        // Verify the preview environment exposes the sync coordinator
        XCTAssertNotNil(environment.syncCoordinator)
        // Verify the preview environment exposes disabled background infrastructure.
        XCTAssertNotNil(environment.backgroundTaskService)
    }
}

private extension BetterTests {
    static func sampleSession() -> SleepSession {
        let sharedSource = SleepSource(
            id: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
            name: "Apple Watch",
            bundleIdentifier: "com.apple.Health",
            productType: "Watch6,1",
            operatingSystemVersion: "11.0",
            isManualEntry: false
        )

        let stages = [
            SleepStage(
                id: UUID(uuidString: "66666666-7777-8888-9999-AAAAAAAAAAAA")!,
                type: .core,
                startDate: Date(timeIntervalSince1970: 1_717_009_200),
                endDate: Date(timeIntervalSince1970: 1_717_010_000),
                source: sharedSource
            ),
            SleepStage(
                id: UUID(uuidString: "BBBBBBBB-CCCC-DDDD-EEEE-FFFFFFFFFFFF")!,
                type: .deep,
                startDate: Date(timeIntervalSince1970: 1_717_010_000),
                endDate: Date(timeIntervalSince1970: 1_717_010_900),
                source: sharedSource
            ),
            SleepStage(
                id: UUID(uuidString: "12345678-1234-1234-1234-1234567890AB")!,
                type: .rem,
                startDate: Date(timeIntervalSince1970: 1_717_010_900),
                endDate: Date(timeIntervalSince1970: 1_717_011_700),
                source: sharedSource
            )
        ]

        let biometrics = NightlyBiometricSummary(
            id: UUID(uuidString: "CCCCCCCC-DDDD-EEEE-FFFF-000000000000")!,
            sleepSessionID: UUID(uuidString: "D1D1D1D1-D2D2-D3D3-D4D4-D5D5D5D5D5D5")!,
            sleepDateKey: "2026-05-04",
            samples: [
                BiometricSample(
                    id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
                    type: .heartRate,
                    value: 58,
                    unit: "count/min",
                    startDate: Date(timeIntervalSince1970: 1_717_009_500),
                    endDate: Date(timeIntervalSince1970: 1_717_009_530),
                    source: sharedSource
                )
            ],
            heartRateAverage: 58,
            heartRateMinimum: 52,
            heartRateMaximum: 66,
            hrvAverage: 44,
            hrvMedian: 43,
            oxygenSaturationAverage: 0.97,
            oxygenSaturationMinimum: 0.95,
            respiratoryRateAverage: 13.9
        )

        return SleepSession(
            id: UUID(uuidString: "D1D1D1D1-D2D2-D3D3-D4D4-D5D5D5D5D5D5")!,
            sleepDateKey: "2026-05-04",
            startDate: Date(timeIntervalSince1970: 1_717_008_600),
            endDate: Date(timeIntervalSince1970: 1_717_012_200),
            inBedStartDate: Date(timeIntervalSince1970: 1_717_008_400),
            inBedEndDate: Date(timeIntervalSince1970: 1_717_012_300),
            stages: stages,
            sources: [sharedSource],
            dataQuality: .detailedStages,
            totalInBedTime: 3_900,
            totalSleepTime: 3_100,
            awakeDuration: 120,
            coreDuration: 800,
            deepDuration: 900,
            remDuration: 800,
            unspecifiedSleepDuration: 600,
            sleepLatency: 300,
            waso: 120,
            efficiency: 0.82,
            qualityScore: SleepQualityScore(
                overall: 84,
                durationScore: 86,
                efficiencyScore: 82,
                remScore: 81,
                deepScore: 87,
                isPartial: false
            ),
            biometrics: biometrics
        )
    }
}
