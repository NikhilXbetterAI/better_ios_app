import Foundation

// MARK: - Preview data based on the Figma prototype's sleepData.ts

enum PreviewSleepData {
    // Session anchored 3 days ago so it's outside the 36-hour foreground refresh window.
    static var sampleSession: SleepSession {
        let calendar = Calendar.current
        let base = calendar.date(byAdding: .day, value: -3, to: calendar.startOfDay(for: Date()))!
        // Bed: 11:32 PM, wake: 7:18 AM → 7h 46m in bed, 7h 23m asleep
        let bedTime = base.addingTimeInterval(-0.5 * 3600 + 32 * 60)   // 11:32 PM two nights ago
        let wakeTime = bedTime.addingTimeInterval(7 * 3600 + 46 * 60)  // 7:18 AM

        // Stage blocks matching todayBlocks in sleepData.ts (minutes from bedTime)
        let blocks: [(Int, Int, SleepStageType)] = [
            (0,   13,  .core),
            (13,  75,  .deep),
            (88,  45,  .core),
            (133, 45,  .rem),
            (178, 15,  .awake),
            (193, 30,  .core),
            (223, 60,  .deep),
            (283, 45,  .core),
            (328, 75,  .rem),
            (403, 30,  .core),
            (433, 25,  .rem),
            (458, 8,   .awake),
        ]

        let stages = blocks.map { startMin, durationMin, type in
            SleepStage(
                type: type,
                startDate: bedTime.addingTimeInterval(Double(startMin) * 60),
                endDate: bedTime.addingTimeInterval(Double(startMin + durationMin) * 60)
            )
        }

        let deepMin  = 135.0; let coreMin = 233.0; let remMin = 145.0; let awakeMin = 23.0
        let totalSleep = (deepMin + coreMin + remMin) * 60
        let totalInBed = 7 * 3600.0 + 46 * 60
        let waso = awakeMin * 60

        let score = SleepQualityScore(
            overall: 82,
            durationScore: 88,
            efficiencyScore: 94,
            remScore: 78,
            deepScore: 84,
            isPartial: false
        )

        return SleepSession(
            sleepDateKey: sleepDateKey(for: bedTime),
            startDate: bedTime,
            endDate: wakeTime,
            inBedStartDate: bedTime,
            inBedEndDate: wakeTime,
            stages: stages,
            sources: [SleepSource(name: "Apple Watch", bundleIdentifier: "com.apple.health", productType: "Watch6,2")],
            dataQuality: .detailedStages,
            totalInBedTime: totalInBed,
            totalSleepTime: totalSleep,
            awakeDuration: waso,
            coreDuration: coreMin * 60,
            deepDuration: deepMin * 60,
            remDuration: remMin * 60,
            unspecifiedSleepDuration: 0,
            sleepLatency: 11 * 60,
            waso: waso,
            efficiency: 0.97,
            qualityScore: score,
            biometrics: sampleBiometrics(sessionID: UUID(), dateKey: sleepDateKey(for: bedTime))
        )
    }

    static func sampleBiometrics(sessionID: UUID, dateKey: String) -> NightlyBiometricSummary {
        NightlyBiometricSummary(
            sleepSessionID: sessionID,
            sleepDateKey: dateKey,
            heartRateAverage: 58,
            heartRateMinimum: 46,
            heartRateMaximum: 72,
            hrvAverage: 52,
            hrvMedian: 50,
            oxygenSaturationAverage: 0.97,
            oxygenSaturationMinimum: 0.95,
            respiratoryRateAverage: 14.2
        )
    }

    static var sampleBaseline: SleepBaseline {
        SleepBaseline(
            windowDays: 30,
            validNights: 28,
            totalSleepAverage: 7 * 3600 + 45 * 60,
            totalSleepStandardDeviation: 22 * 60,
            remAverage: 158 * 60,
            remStandardDeviation: 18 * 60,
            deepAverage: 126 * 60,
            deepStandardDeviation: 15 * 60,
            efficiencyAverage: 0.90,
            efficiencyStandardDeviation: 0.05,
            wasoAverage: 31 * 60,
            wasoStandardDeviation: 12 * 60,
            latencyAverage: 16 * 60,
            latencyStandardDeviation: 8 * 60,
            hrvAverage: 46,
            hrvStandardDeviation: 8,
            respiratoryRateAverage: 13.8,
            respiratoryRateStandardDeviation: 0.8,
            oxygenSaturationAverage: 0.97,
            oxygenSaturationStandardDeviation: 0.01,
            bedtimeMinuteAverage: 23 * 60 + 38,  // 11:38 PM
            bedtimeMinuteStandardDeviation: 18,
            wakeMinuteAverage: 7 * 60 + 12,      // 7:12 AM
            wakeMinuteStandardDeviation: 14
        )
    }

    static var sampleSessions: [SleepSession] {
        let primary = sampleSession
        let variants: [Double] = [0.92, 1.04, 0.88, 1.08, 0.97, 0.82, 1.01, 0.94, 1.06, 0.90, 1.03, 0.86]
        let earlier = variants.enumerated().map { index, multiplier in
            shiftedSession(
                from: primary,
                byDays: -(index + 1),
                sleepMultiplier: multiplier,
                scoreDelta: Double([3, -2, 5, -6, 1, -9, 4, -3, 6, -5, 2, -7][index])
            )
        }
        return ([primary] + earlier).sorted { $0.startDate < $1.startDate }
    }

    static var sampleAlerts: [SleepAlert] {
        let now = Date()
        return [
            SleepAlert(
                kind: .analysisReady,
                title: "Sleep analysis is ready",
                body: "Score 82 with 7h 23m asleep. Deep sleep was above your recent average.",
                sleepDateKey: sampleSession.sleepDateKey,
                severity: 0,
                isRead: false,
                createdAt: now.addingTimeInterval(-2_400)
            ),
            SleepAlert(
                kind: .irregularSchedule,
                title: "Bedtime shifted later",
                body: "Your bedtime varied more than usual across the last week.",
                sleepDateKey: sampleSession.sleepDateKey,
                severity: 1,
                isRead: false,
                createdAt: now.addingTimeInterval(-86_400)
            ),
            SleepAlert(
                kind: .lowRemSleep,
                title: "REM dipped below baseline",
                body: "REM was lower than your 30-day average. Watch for repeated dips before changing your routine.",
                sleepDateKey: sampleSession.sleepDateKey,
                severity: 1,
                isRead: true,
                createdAt: now.addingTimeInterval(-172_800),
                readAt: now.addingTimeInterval(-150_000)
            )
        ]
    }

    static var sampleAdherence: [ProtocolAdherence] {
        let itemID = "A1B2C3D4-0000-0000-0000-000000000001"
        let calendar = Calendar.current
        let takenOffsets = Set([0, -1, -2, -3, -5, -6, -7, -9, -10, -12, -14, -15, -16, -18, -19])
        return (-20...0).compactMap { offset in
            let date = calendar.date(byAdding: .day, value: offset, to: Date()) ?? Date()
            let taken = takenOffsets.contains(offset)
            return ProtocolAdherence(
                protocolID: itemID,
                dateKey: sleepDateKey(for: date),
                taken: taken,
                takenAt: taken ? calendar.date(bySettingHour: 21, minute: 18, second: 0, of: date) : nil
            )
        }
    }

    static var noDataSession: SleepSession? { nil }

    // MARK: - Mock repository pre-populated for preview

    #if DEBUG
    static func makeMockRepository(hasCompletedOnboarding: Bool = true) -> MockLocalDataRepository {
        let sessions = sampleSessions
        let baseline = sampleBaseline
        return MockLocalDataRepository(
            sessions: sessions,
            summaries: sessions.map { $0.biometrics ?? sampleBiometrics(sessionID: $0.id, dateKey: $0.sleepDateKey) },
            baselines: [baseline],
            alerts: sampleAlerts,
            adherence: sampleAdherence,
            activityStatusLogs: sampleActivityStatusLogs,
            profile: UserProfile(
                sleepGoalHours: 8,
                baselineWindowDays: 30,
                isResearchMode: true,
                hasCompletedOnboarding: hasCompletedOnboarding
            )
        )
    }
    #endif

    static var sampleActivityStatusLogs: [ActivityStatusLog] {
        let calendar = Calendar.current
        let statuses: [(Int, UserActivityStatus, String?)] = [
            (-5, .traveling, "London trip"),
            (-2, .jetLagged, "Adjusting after travel"),
            (0, .active, "Normal training day")
        ]
        return statuses.compactMap { offset, status, note in
            let date = calendar.date(byAdding: .day, value: offset, to: Date()) ?? Date()
            return ActivityStatusLog(
                dateKey: SleepDateKey.calendarDateKey(for: date, calendar: calendar),
                status: status,
                note: note
            )
        }
    }

    // MARK: - Helpers

    private static func sleepDateKey(for date: Date) -> String {
        SleepDateKey.sleepDateKey(forSessionStart: date)
    }

    private static func shiftedSession(
        from session: SleepSession,
        byDays days: Int,
        sleepMultiplier: Double,
        scoreDelta: Double
    ) -> SleepSession {
        let offset = TimeInterval(days * 86_400)
        let totalSleep = max(5.8 * 3_600, session.totalSleepTime * sleepMultiplier)
        let ratio = totalSleep / session.totalSleepTime
        let score = min(96, max(58, session.qualityScore.overall + scoreDelta))
        let dateKey = sleepDateKey(for: session.startDate.addingTimeInterval(offset))
        let stages = session.stages.map {
            SleepStage(
                type: $0.type,
                startDate: $0.startDate.addingTimeInterval(offset),
                endDate: $0.endDate.addingTimeInterval(offset),
                source: $0.source
            )
        }

        let id = UUID()
        let biometrics = NightlyBiometricSummary(
            sleepSessionID: id,
            sleepDateKey: dateKey,
            heartRateAverage: max(52, 61 - scoreDelta / 2),
            heartRateMinimum: 45,
            heartRateMaximum: 74,
            hrvAverage: max(34, 50 + scoreDelta),
            hrvMedian: max(32, 48 + scoreDelta),
            oxygenSaturationAverage: 0.965,
            oxygenSaturationMinimum: 0.945,
            respiratoryRateAverage: 14.1 + (scoreDelta / 40)
        )

        return SleepSession(
            id: id,
            sleepDateKey: dateKey,
            startDate: session.startDate.addingTimeInterval(offset),
            endDate: session.endDate.addingTimeInterval(offset),
            inBedStartDate: session.inBedStartDate?.addingTimeInterval(offset),
            inBedEndDate: session.inBedEndDate?.addingTimeInterval(offset),
            stages: stages,
            sources: session.sources,
            dataQuality: .detailedStages,
            totalInBedTime: max(totalSleep + 24 * 60, session.totalInBedTime * ratio),
            totalSleepTime: totalSleep,
            awakeDuration: max(8 * 60, session.awakeDuration * (2 - min(1.2, sleepMultiplier))),
            coreDuration: session.coreDuration * ratio,
            deepDuration: session.deepDuration * ratio,
            remDuration: session.remDuration * ratio,
            unspecifiedSleepDuration: 0,
            sleepLatency: max(6 * 60, session.sleepLatency * (2 - min(1.2, sleepMultiplier))),
            waso: max(8 * 60, session.waso * (2 - min(1.2, sleepMultiplier))),
            efficiency: min(0.98, max(0.82, session.efficiency + scoreDelta / 500)),
            qualityScore: SleepQualityScore(
                overall: score,
                durationScore: min(100, max(45, session.qualityScore.durationScore + scoreDelta)),
                efficiencyScore: min(100, max(45, session.qualityScore.efficiencyScore + scoreDelta)),
                remScore: min(100, max(45, session.qualityScore.remScore + scoreDelta)),
                deepScore: min(100, max(45, session.qualityScore.deepScore + scoreDelta)),
                isPartial: false
            ),
            biometrics: biometrics
        )
    }
}
