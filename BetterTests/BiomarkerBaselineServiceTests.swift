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
    func bodySignalPresentation_formatsPercentDeltaAndStatusForAllBiomarkers() {
        let baseline = BiomarkerBaseline(
            computedAt: Date(),
            windowDays: 30,
            sampleCounts: [.rhr: 20, .hrv: 20, .spo2: 20, .breath: 20],
            means:        [.rhr: 50,  .hrv: 80,  .spo2: 96,  .breath: 16],
            stdDevs:      [.rhr: 4,   .hrv: 8,   .spo2: 1,   .breath: 1]
        )

        let rhr = presentation(key: .rhr, tonight: 60, baseline: baseline)
        let hrv = presentation(key: .hrv, tonight: 100, baseline: baseline)
        let spo2 = presentation(key: .spo2, tonight: 94.08, baseline: baseline)
        let breath = presentation(key: .breath, tonight: 17.6, baseline: baseline)

        #expect(rhr.statusText == "above baseline")
        #expect(rhr.percentText == "+20%")
        #expect(hrv.statusText == "Much better than baseline")
        #expect(hrv.percentText == "+25%")
        #expect(spo2.statusText == "below baseline")
        #expect(spo2.percentText == "-2%")
        #expect(breath.statusText == "Slightly off rhythm")
        #expect(breath.percentText == "+10%")
    }

    @Test
    func bodySignalPresentation_mapsRhrAndHrvToUserFacingMeaning() {
        let baseline = BiomarkerBaseline(
            computedAt: Date(),
            windowDays: 30,
            sampleCounts: [.rhr: 20, .hrv: 20],
            means:        [.rhr: 50,  .hrv: 80],
            stdDevs:      [.rhr: 4,   .hrv: 8]
        )

        let rhr = presentation(key: .rhr, tonight: 60, baseline: baseline)
        let hrv = presentation(key: .hrv, tonight: 100, baseline: baseline)

        #expect(rhr.signal == .harder)
        #expect(rhr.meaningText == "Higher heart rate can mean more strain.")
        #expect(hrv.signal == .recovered)
        #expect(hrv.meaningText == "Higher HRV typically means better recovery.")
    }

    @Test
    func bodySignalPresentation_neutralDeltaSaysSameAsUsual() {
        let baseline = BiomarkerBaseline(
            computedAt: Date(),
            windowDays: 30,
            sampleCounts: [.rhr: 20, .breath: 20, .spo2: 20],
            means: [.rhr: 50, .breath: 16, .spo2: 97],
            stdDevs: [.rhr: 4, .breath: 1, .spo2: 1]
        )

        let tinyRHR = presentation(key: .rhr, tonight: 50.2, baseline: baseline)
        let breathFourPercentHigher = presentation(key: .breath, tonight: 16.64, baseline: baseline)
        let stableOxygen = presentation(key: .spo2, tonight: 97, baseline: baseline)

        #expect(tinyRHR.signal == .steady)
        #expect(tinyRHR.comparisonText == "same as baseline")
        #expect(breathFourPercentHigher.signal == .steady)
        #expect(breathFourPercentHigher.statusText == "Normal")
        #expect(breathFourPercentHigher.percentText == "4%")
        #expect(stableOxygen.statusText == "Normal")
        #expect(stableOxygen.percentText == "0%")
    }

    @Test
    func bodySignalPresentation_handlesMissingBaselineAndMissingValue() {
        let building = BiomarkerBodySignalPresentation.make(
            key: .hrv,
            tonight: 72,
            baseline: nil,
            reaction: nil,
            readiness: .building(sampleCount: 2, minimumCount: 5),
            provenance: nil
        )
        let missing = BiomarkerBodySignalPresentation.make(
            key: .hrv,
            tonight: nil,
            baseline: nil,
            reaction: nil,
            readiness: .unavailable(minimumCount: 5),
            provenance: nil
        )

        #expect(building.signal == .building)
        #expect(building.comparisonText == "Needs 3 more nights for a personal comparison.")
        #expect(missing.signal == .missing)
        #expect(missing.meaningText == "No reading captured tonight.")
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

    /// Regression fixture for the stddev convention in BiomarkerBaselineService.
    ///
    /// BiomarkerBaselineService uses Bessel-corrected sample stddev (÷n-1) because it
    /// estimates population parameters from a small nightly window.
    /// SleepDataProcessor uses population stddev (÷n) for its descriptive baseline stats.
    ///
    /// This test pins the CURRENT (n-1) behavior so any accidental convention change is caught.
    /// Values: [55, 65, 60] → mean = 60, Σ(xi−μ)² = 50 → sample stddev = √(50/2) ≈ 5.0
    @Test
    func stdDevConvention_isSampleStdDev_notPopulation() {
        // Three sessions, HRV values [55, 65, 60].
        let sessions: [SleepSession] = [
            makeSession(date: Date(timeIntervalSince1970: 0),  hrv: 55),
            makeSession(date: Date(timeIntervalSince1970: 86400), hrv: 65),
            makeSession(date: Date(timeIntervalSince1970: 172800), hrv: 60)
        ]
        let baseline = BiomarkerBaselineService.computeBaseline(
            from: sessions,
            windowDays: 30,
            computedAt: Date(timeIntervalSince1970: 0)
        )
        let sd = baseline.stdDevs[.hrv] ?? 0
        // Sample stddev (n-1): √((25+25+0)/2) = √25 = 5.0
        // Population stddev (n): √((25+25+0)/3) ≈ 4.082
        // Assert sample stddev (within floating-point tolerance).
        #expect(abs(sd - 5.0) < 0.001,
                "BiomarkerBaselineService must use sample stddev (÷n-1); got \(sd), expected 5.0")
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

    private func presentation(
        key: BiomarkerKey,
        tonight: Double?,
        baseline: BiomarkerBaseline
    ) -> BiomarkerBodySignalPresentation {
        BiomarkerBodySignalPresentation.make(
            key: key,
            tonight: tonight,
            baseline: baseline,
            reaction: SleepBiomarkerReaction.make(key: key, tonight: tonight, baseline: baseline),
            readiness: baseline.readiness(for: key),
            provenance: nil
        )
    }
}
