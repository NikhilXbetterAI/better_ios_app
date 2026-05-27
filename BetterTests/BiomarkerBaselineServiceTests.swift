import Foundation
import Testing
@testable import Better

@MainActor
struct BiomarkerBaselineServiceTests {
    let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    @Test
    func recompute_picksPrimaryWindow_whenEnoughNights() async throws {
        let now = date("2026-05-25")
        let sessions = (0..<20).map { i in
            makeSession(
                date: dateByAdding(-i, to: now),
                rhr: 50 + Double(i % 4),
                hrv: 70 + Double(i % 6),
                spo2: 0.97,
                breath: 14.5
            )
        }
        let repo = MockLocalDataRepository(sessions: sessions)
        let service = BiomarkerBaselineService(repository: repo, calendar: calendar)

        let baseline = await service.recompute(now: now)
        #expect(baseline?.windowDays == BiomarkerBaselineService.primaryWindowDays)
        #expect((baseline?.sampleCounts[.rhr] ?? 0) == 20)
        #expect((baseline?.sampleCounts[.hrv] ?? 0) == 20)
        #expect((baseline?.means[.spo2] ?? 0) > 96 && (baseline?.means[.spo2] ?? 0) < 98)
    }

    @Test
    func recompute_fallsBackToSixtyDays_whenPrimarySparse() async throws {
        let now = date("2026-05-25")
        // Only 3 nights inside 30 days, but 8 nights inside 60 days.
        let recent = (0..<3).map { i in makeSession(date: dateByAdding(-i, to: now), hrv: 60) }
        let older  = (35..<40).map { i in makeSession(date: dateByAdding(-i, to: now), hrv: 60) }
        let repo = MockLocalDataRepository(sessions: recent + older)
        let service = BiomarkerBaselineService(repository: repo, calendar: calendar)

        let baseline = await service.recompute(now: now)
        #expect(baseline?.windowDays == BiomarkerBaselineService.fallbackWindowDays)
        #expect((baseline?.sampleCounts[.hrv] ?? 0) == 8)
    }

    @Test
    func cacheIsReusedWhenFresh_andRefreshedWhenStale() async throws {
        let now = date("2026-05-25")
        let sessions = (0..<10).map { i in
            makeSession(date: dateByAdding(-i, to: now), hrv: 60 + Double(i))
        }
        let repo = MockLocalDataRepository(sessions: sessions)
        let service = BiomarkerBaselineService(repository: repo, calendar: calendar)

        let first = await service.currentBaseline(now: now)
        #expect(first != nil)

        // Asking again 6 days later should hit cache (no recompute).
        let cached = await service.currentBaseline(now: dateByAdding(6, to: now))
        #expect(cached?.computedAt == first?.computedAt)

        // 8 days later — TTL expired, expect a fresh computedAt.
        let later = dateByAdding(8, to: now)
        let refreshed = await service.currentBaseline(now: later)
        #expect(refreshed?.computedAt != first?.computedAt)
    }

    @Test
    func reaction_directionRulesPerBiomarker() {
        let baseline = BiomarkerBaseline(
            computedAt: Date(),
            windowDays: 30,
            sampleCounts: [.rhr: 20, .hrv: 20, .spo2: 20, .breath: 20],
            means:        [.rhr: 55,  .hrv: 70,  .spo2: 97,  .breath: 15],
            stdDevs:      [.rhr: 4,   .hrv: 8,   .spo2: 1,   .breath: 1]
        )

        // Lower RHR is improved.
        let rhrLow = SleepBiomarkerReaction.make(key: .rhr, tonight: 48, baseline: baseline)
        #expect(rhrLow?.direction == .improved)

        // Higher HRV is improved.
        let hrvHigh = SleepBiomarkerReaction.make(key: .hrv, tonight: 88, baseline: baseline)
        #expect(hrvHigh?.direction == .improved)

        // Small drift below |z|=0.75 should be neutral.
        let neutral = SleepBiomarkerReaction.make(key: .rhr, tonight: 56, baseline: baseline)
        #expect(neutral?.direction == .neutral)
    }

    @Test
    func breath_requiresBothZScoreAndAbsDeltaForWorse() {
        // stdDev = 0.5 br/min, mean = 15.
        // tonight = 15.5 → delta = +0.5, z = +1.0 (exceeds 0.75 threshold) BUT
        // abs(delta) < 1.0 → Fix 4 should suppress .worse and return .neutral.
        let baseline = BiomarkerBaseline(
            computedAt: Date(),
            windowDays: 30,
            sampleCounts: [.breath: 10],
            means:        [.breath: 15.0],
            stdDevs:      [.breath: 0.5]
        )

        // Sub-1 delta even though |z| > 0.75 — must be .neutral.
        let subDelta = SleepBiomarkerReaction.make(key: .breath, tonight: 15.5, baseline: baseline)
        #expect(subDelta?.direction == .neutral,
                "breath reaction with |z|=1.0 but |delta|=0.5 should be .neutral (Fix 4)")

        // Both conditions met: delta = +1.5 br/min, z = +3.0 — must be .worse.
        let bothMet = SleepBiomarkerReaction.make(key: .breath, tonight: 16.5, baseline: baseline)
        #expect(bothMet?.direction == .worse,
                "breath reaction with |z|=3.0 and |delta|=1.5 should be .worse (Fix 4)")
    }

    @Test
    func reaction_returnsNil_whenBaselineHasTooFewSamples() {
        let baseline = BiomarkerBaseline(
            computedAt: Date(),
            windowDays: 30,
            sampleCounts: [.rhr: 2],
            means: [.rhr: 50],
            stdDevs: [.rhr: 3]
        )
        let r = SleepBiomarkerReaction.make(key: .rhr, tonight: 48, baseline: baseline)
        #expect(r == nil)
    }

    @Test
    func baselineReadiness_isPerBiomarker() {
        let baseline = BiomarkerBaseline(
            computedAt: Date(),
            windowDays: 30,
            sampleCounts: [.rhr: 8, .hrv: 2],
            means: [.rhr: 52, .hrv: 60],
            stdDevs: [.rhr: 3, .hrv: 6]
        )

        #expect(baseline.readiness(for: .rhr).isReady)
        #expect(!baseline.readiness(for: .hrv).isReady)
        #expect(!baseline.readiness(for: .spo2).isReady)
    }

    @Test
    func provenance_marksMissingAndManualWithoutScaryCopy() {
        let source = SleepSource(name: "Manual", isManualEntry: true)
        let sample = BiometricSample(
            type: .heartRate,
            value: 48,
            unit: "count/min",
            startDate: Date(),
            endDate: Date(),
            source: source
        )

        let manual = BiomarkerProvenance.make(
            key: .rhr,
            samples: [sample],
            fallbackSources: [],
            hasValue: true
        )
        let missing = BiomarkerProvenance.make(
            key: .hrv,
            samples: [sample],
            fallbackSources: [],
            hasValue: false
        )

        #expect(manual.confidence == .low)
        #expect(manual.neutralTrustCopy == "Manual or limited source")
        #expect(missing.confidence == .missing)
        #expect(missing.neutralTrustCopy == "No reading captured")
    }

    @Test
    func emptyBiometrics_doNotPoisonMean() {
        let now = Date()
        // Sessions with mixed nil values.
        let sessions: [SleepSession] = [
            makeSession(date: now, rhr: 50, hrv: nil),
            makeSession(date: now, rhr: nil, hrv: 70),
            makeSession(date: now, rhr: 52, hrv: 72)
        ]
        let baseline = BiomarkerBaselineService.computeBaseline(
            from: sessions,
            windowDays: 30,
            computedAt: now
        )
        #expect(baseline.sampleCounts[.rhr] == 2)
        #expect(baseline.sampleCounts[.hrv] == 2)
        #expect(abs((baseline.means[.rhr] ?? 0) - 51) < 0.01)
    }

    // MARK: helpers

    private func date(_ key: String) -> Date {
        SleepDateKey.date(from: key, calendar: calendar) ?? Date(timeIntervalSince1970: 0)
    }

    private func dateByAdding(_ days: Int, to date: Date) -> Date {
        calendar.date(byAdding: .day, value: days, to: date) ?? date
    }

    private func makeSession(
        date: Date,
        rhr: Double? = 55,
        hrv: Double? = 70,
        spo2: Double? = 0.97,
        breath: Double? = 15
    ) -> SleepSession {
        let start = calendar.date(byAdding: .hour, value: -8, to: date) ?? date.addingTimeInterval(-28_800)
        let end   = calendar.date(byAdding: .hour, value: -1, to: date) ?? date.addingTimeInterval(-3_600)
        let dateKey = SleepDateKey.calendarDateKey(for: date, calendar: calendar)
        let id = UUID()
        return SleepSession(
            id: id,
            sleepDateKey: dateKey,
            startDate: start,
            endDate: end,
            dataQuality: .detailedStages,
            totalInBedTime: 8 * 3_600,
            totalSleepTime: 7 * 3_600,
            efficiency: 0.9,
            biometrics: NightlyBiometricSummary(
                sleepSessionID: id,
                sleepDateKey: dateKey,
                heartRateMinimum: rhr,
                hrvAverage: hrv,
                oxygenSaturationAverage: spo2,
                respiratoryRateAverage: breath
            )
        )
    }
}
