import Foundation
import OSLog

nonisolated struct ResearchAnalysisService: Sendable {
    private let localRepository: LocalDataRepositoryProtocol
    private let healthRepository: HealthKitRepositoryProtocol
    private let calendar: Calendar
    private let logger = Logger(subsystem: "Better", category: "ResearchAnalysis")

    init(
        localRepository: LocalDataRepositoryProtocol,
        healthRepository: HealthKitRepositoryProtocol,
        calendar: Calendar = .current
    ) {
        self.localRepository = localRepository
        self.healthRepository = healthRepository
        self.calendar = calendar
    }

    func buildExportPackage(
        from startDate: Date,
        to endDate: Date,
        protocolItems: [ProtocolItem] = ProtocolCatalog.load(),
        generatedAt: Date = Date()
    ) async throws -> ResearchExportPackage {
        let cappedStart = max(startDate, endDate.addingTimeInterval(-60 * 86_400))
        let sessions = try await localRepository.fetchCachedSessions(from: cappedStart, to: endDate)
        let profile = try await localRepository.fetchProfile()
        let storedBaseline = try await localRepository.fetchLatestBaseline(windowDays: profile.baselineWindowDays)
        let baselineSelection = BaselineEngine(
            processor: SleepDataProcessor(calendar: calendar, sleepGoalHours: profile.sleepGoalHours),
            calendar: calendar
        ).selectBaseline(from: sessions, generatedAt: generatedAt)
        let baseline = baselineSelection.activeBaseline ?? storedBaseline
        let adherence = try await localRepository.fetchAdherence(from: startDate, to: endDate)
        let protocolComparison = ProtocolComparisonService(calendar: calendar).compare(
            sessions: sessions,
            adherence: adherence,
            window: .last30Days,
            endingAt: endDate
        )

        let startKey = SleepDateKey.calendarDateKey(for: startDate, calendar: calendar)
        let endKey = SleepDateKey.calendarDateKey(for: endDate, calendar: calendar)
        let statusLogs = try await localRepository.fetchActivityStatusLogs(from: startKey, to: endKey)
        let nightLogs = try await localRepository.fetchNightLogs(from: startKey, to: endKey)
        let formulaVersions = try await localRepository.fetchAllFormulaVersions()
        let activitySummaries = try await loadActivitySummaries(from: startDate, to: endDate)
        let contextEntries = try await localRepository.fetchContextEntries(from: startKey, to: endKey)
        let contextService = ContextComparisonService(calendar: calendar)
        let contextResults30d = contextService.compareAll(
            sessions: sessions,
            contextEntries: contextEntries,
            adherence: adherence,
            window: .last30Days,
            endingAt: endDate
        )
        let contextResultsAll = contextService.compareAll(
            sessions: sessions,
            contextEntries: contextEntries,
            adherence: adherence,
            window: .all,
            endingAt: endDate
        )
        let contextComparisonResults = contextResults30d + contextResultsAll

        let rows = buildNightlyRows(
            sessions: sessions,
            adherence: adherence,
            statusLogs: statusLogs,
            activitySummaries: activitySummaries,
            contextEntries: contextEntries,
            baseline: baseline,
            protocolItems: protocolItems,
            comparisonConfidence: protocolComparison.confidence,
            nightLogs: nightLogs,
            formulaVersions: formulaVersions
        )
        logger.debug(
            "Research export rows=\(rows.count, privacy: .public) baselineWindow=\(baseline?.windowDays ?? 0, privacy: .public) protocolTaken=\(protocolComparison.takenNightCount, privacy: .public) protocolNotTaken=\(protocolComparison.notTakenNightCount, privacy: .public) protocolUnknown=\(protocolComparison.unknownNightCount, privacy: .public)"
        )
        let summaries = buildProtocolSummaries(rows: rows, protocolItems: protocolItems)
        let insight = buildInsightSummary(rows: rows, summaries: summaries, generatedAt: generatedAt)
        let chronotypeResult = ChronotypeCalculationService().estimate(
            sessions: sessions,
            contextEntries: contextEntries,
            activityLogs: statusLogs,
            windowDays: 90,
            endingAt: endDate,
            calendar: calendar
        )

        return ResearchExportPackage(
            generatedAt: generatedAt,
            rangeStart: startDate,
            rangeEnd: endDate,
            baselineWindowDays: profile.baselineWindowDays,
            baselineValidNights: baseline?.validNights ?? 0,
            isResearchMode: profile.isResearchMode,
            nightlyRows: rows,
            protocolSummaries: summaries,
            insightSummary: insight,
            chronotypeResult: chronotypeResult,
            baselineSelection: baselineSelection,
            contextComparisonResults: contextComparisonResults
        )
    }
}

nonisolated private extension ResearchAnalysisService {
    func buildNightlyRows(
        sessions: [SleepSession],
        adherence: [ProtocolAdherence],
        statusLogs: [ActivityStatusLog],
        activitySummaries: [DailyActivitySummary],
        contextEntries: [SleepContextEntry],
        baseline: SleepBaseline?,
        protocolItems: [ProtocolItem],
        comparisonConfidence: ComparisonConfidence,
        nightLogs: [ProtocolNightLog] = [],
        formulaVersions: [ProtocolFormulaVersion] = []
    ) -> [NightlyResearchRow] {
        let adherenceByDate = Dictionary(grouping: adherence, by: \.dateKey)
        let statusByDate = Dictionary(uniqueKeysWithValues: statusLogs.map { ($0.dateKey, $0) })
        let activityByDate = Dictionary(uniqueKeysWithValues: activitySummaries.map { ($0.dateKey, $0) })
        let contextByDate = Dictionary(uniqueKeysWithValues: contextEntries.map { ($0.sleepDateKey, $0) })
        let nightLogByDate = Dictionary(uniqueKeysWithValues: nightLogs.map { ($0.sleepDateKey, $0) })
        let formulaVersionByID = Dictionary(uniqueKeysWithValues: formulaVersions.map { ($0.id, $0) })
        let protocolNameByID = Dictionary(uniqueKeysWithValues: protocolItems.map { ($0.id.uuidString, $0.name) })

        return sessions.sorted { $0.sleepDateKey < $1.sleepDateKey }.map { session in
            let nightlyAdherence = adherenceByDate[session.sleepDateKey, default: []].sorted { lhs, rhs in
                (lhs.takenAt ?? lhs.updatedAt) < (rhs.takenAt ?? rhs.updatedAt)
            }
            let taken = nightlyAdherence.filter(\.taken)
            let notTaken = nightlyAdherence.filter { !$0.taken }
            let protocolUsageStatus = ProtocolComparisonService.status(for: nightlyAdherence)
            let status = statusByDate[session.sleepDateKey]
            let activity = activityByDate[session.sleepDateKey]
            let context = contextByDate[session.sleepDateKey]
            let biometrics = session.biometrics
            let hasDetailedStages = session.dataQuality == .detailedStages || session.dataQuality == .mixedSources
            let baselineTotalSleepMinutes = baseline.map { $0.totalSleepAverage / 60 }
            let durationVsBaselineMinutes = baseline.map { (session.totalSleepTime - $0.totalSleepAverage) / 60 }
            let continuity = session.continuitySummary
            let hasContinuity = !continuity.blocks.isEmpty
            let nightLog = nightLogByDate[session.sleepDateKey]
            let formulaVersion = nightLog.flatMap { formulaVersionByID[$0.versionID] }
            let restorativePctOfInBed: Double? = (hasDetailedStages && session.totalInBedTime > 0)
                ? min(session.restorativeSleepDuration / session.totalInBedTime * 100.0, 100.0)
                : nil
            let timings = taken.compactMap { adherence in
                adherence.takenAt.map { session.startDate.timeIntervalSince($0) / 60 }
            }
            let protocolNames = nightlyAdherence.map { protocolNameByID[$0.protocolID] ?? $0.protocolID }

            return NightlyResearchRow(
                sleepDateKey: session.sleepDateKey,
                sleepStart: session.startDate,
                sleepEnd: session.endDate,
                dataQuality: session.dataQuality,
                totalSleepHours: session.totalSleepTime / 3_600,
                inBedHours: session.totalInBedTime / 3_600,
                efficiencyPercent: session.efficiency * 100,
                deepHours: hasDetailedStages ? session.deepDuration / 3_600 : nil,
                remHours: hasDetailedStages ? session.remDuration / 3_600 : nil,
                coreHours: hasDetailedStages ? session.coreDuration / 3_600 : nil,
                awakeHours: session.awakeDuration / 3_600,
                wasoMinutes: session.waso / 60,
                latencyMinutes: session.sleepLatency / 60,
                sleepScore: session.qualityScore.overall,
                durationScore: session.qualityScore.durationScore,
                efficiencyScore: session.qualityScore.efficiencyScore,
                remScore: session.qualityScore.remScore,
                deepScore: session.qualityScore.deepScore,
                hrvAverage: biometrics?.hrvAverage,
                hrvMedian: biometrics?.hrvMedian,
                heartRateAverage: biometrics?.heartRateAverage,
                heartRateMinimum: biometrics?.heartRateMinimum,
                heartRateMaximum: biometrics?.heartRateMaximum,
                respiratoryRateAverage: biometrics?.respiratoryRateAverage,
                oxygenSaturationAveragePercent: biometrics?.oxygenSaturationAverage.map { $0 * 100 },
                oxygenSaturationMinimumPercent: biometrics?.oxygenSaturationMinimum.map { $0 * 100 },
                steps: activity?.steps,
                activeEnergyKcal: activity?.activeEnergy,
                exerciseMinutes: activity?.exerciseMinutes,
                standHours: activity?.standHours,
                distanceMeters: activity?.distanceMeters,
                activityStatus: status?.status,
                isJetLagged: status?.status == .jetLagged,
                activityNote: status?.note,
                protocolTakenAny: protocolUsageStatus == .taken,
                protocolIDsTaken: taken.map(\.protocolID),
                protocolIDsNotTaken: notTaken.map(\.protocolID),
                protocolNamesTaken: taken.map { protocolNameByID[$0.protocolID] ?? $0.protocolID },
                protocolTakenAt: taken.compactMap(\.takenAt),
                minutesFromProtocolToSleep: timings,
                baselineTotalSleepDeltaHours: baseline.map { (session.totalSleepTime - $0.totalSleepAverage) / 3_600 },
                baselineEfficiencyDeltaPercent: baseline.map { (session.efficiency - $0.efficiencyAverage) * 100 },
                baselineWASODeltaMinutes: baseline.map { (session.waso - $0.wasoAverage) / 60 },
                baselineLatencyDeltaMinutes: baseline.map { (session.sleepLatency - $0.latencyAverage) / 60 },
                baselineHRVDelta: baseline.flatMap { baseline in
                    biometrics?.hrvAverage.map { $0 - baseline.hrvAverage }
                },
                sourceNames: session.sources.map(\.name),
                baselineWindowUsed: baseline?.windowDays,
                baselineTotalSleepMinutes: baselineTotalSleepMinutes,
                durationVsBaselineMinutes: durationVsBaselineMinutes,
                protocolUsageStatus: protocolUsageStatus,
                protocolTaken: protocolUsageStatus.protocolTaken,
                protocolName: protocolNames.joinedOrNil(separator: "|"),
                protocolTiming: timings.map { Self.formatMinutes($0) }.joinedOrNil(separator: "|"),
                dataQualityStatus: session.dataQuality.rawValue,
                comparisonConfidence: comparisonConfidence,
                caffeineLate:   context?.caffeineLate,
                alcohol:        context?.alcohol,
                workout:        context?.workout,
                lateMeal:       context?.lateMeal,
                highStress:     context?.highStress,
                screenTimeLate: context?.screenTimeLate,
                nap:            context?.nap,
                travel:         context?.travel,
                perceivedSleepQuality:   context?.perceivedSleepQuality?.displayName,
                morningEnergy:           context?.morningEnergy?.displayName,
                contextNotesPresent:     context.map { $0.hasNotes },
                contextCompletionStatus: context?.completionStatus.rawValue,
                restorativeSleepHours: hasDetailedStages ? session.restorativeSleepDuration / 3_600 : nil,
                longestRestorativeBlockHours: hasContinuity ? continuity.longestBlockDuration / 3_600 : nil,
                longestRestorativeBlockMinutes: hasContinuity ? continuity.longestBlockDuration / 60 : nil,
                sleepContinuityCategory: hasContinuity ? continuity.continuityCategory.rawValue : SleepContinuityCategory.unavailable.rawValue,
                sleepBlockCount: continuity.blocks.count,
                meaningfulAwakeCount: continuity.meaningfulAwakeningCount,
                sleepBlockDurationsMinutes: continuity.blocks.map { $0.sleepDuration / 60 },
                sleepBlockStartDates: continuity.blocks.map(\.startDate),
                sleepBlockEndDates: continuity.blocks.map(\.endDate),
                formulaVersionLabel: formulaVersion?.resolvedLabel,
                formulaVersionID: formulaVersion?.id.uuidString,
                formulaNightStatus: nightLog?.status.rawValue,
                restorativePctOfInBed: restorativePctOfInBed
            )
        }
    }

    func buildInsightSummary(
        rows: [NightlyResearchRow],
        summaries: [ProtocolEffectSummary],
        generatedAt: Date
    ) -> ResearchInsightSummary {
        let best = summaries
            .filter { $0.protocolID != "any_protocol" }
            .filter { $0.confidence != .insufficient }
            .compactMap { summary -> ProtocolEffectSummary? in
                guard let delta = summary.sleepDifferenceHours, delta > 0 else { return nil }
                return summary
            }
            .sorted { ($0.sleepDifferenceHours ?? 0) > ($1.sleepDifferenceHours ?? 0) }
            .first
        let baselineAverage = average(rows.compactMap(\.baselineTotalSleepDeltaHours))
        let confoundedCount = rows.filter(\.isTravelConfounded).count
        let confounderNote = confoundedCount > 0
            ? "\(confoundedCount) night\(confoundedCount == 1 ? "" : "s") included travel or jet-lag context."
            : nil

        let summary: String
        if let best, let delta = best.sleepDifferenceHours {
            summary = "\(best.protocolName) is associated with \(Self.formatHours(delta)) more sleep on observed nights. Treat this as observational, not causal."
        } else if rows.count >= 5 {
            summary = "Per-formula impact analysis lives in the Protocol tab. Treat all deltas as observational, not causal."
        } else {
            summary = "More logged nights are needed before per-formula effects can be interpreted."
        }

        return ResearchInsightSummary(
            generatedAt: generatedAt,
            validNightCount: rows.count,
            bestProtocolName: best?.protocolName,
            bestProtocolSleepDifferenceHours: best?.sleepDifferenceHours,
            confidence: best?.confidence ?? .insufficient,
            baselineSleepDifferenceHours: baselineAverage,
            confounderNote: confounderNote,
            summary: summary
        )
    }

    func buildProtocolSummaries(rows: [NightlyResearchRow], protocolItems: [ProtocolItem]) -> [ProtocolEffectSummary] {
        let any = effectSummary(
            protocolID: "any_protocol",
            protocolName: "Any Protocol",
            rows: rows,
            isTaken: { $0.protocolUsageStatus == .taken },
            isNotTaken: { $0.protocolUsageStatus == .notTaken }
        )
        let perProtocol = protocolItems.map { item in
            effectSummary(
                protocolID: item.id.uuidString,
                protocolName: item.name,
                rows: rows,
                isTaken: { $0.protocolIDsTaken.contains(item.id.uuidString) },
                isNotTaken: { $0.protocolIDsNotTaken.contains(item.id.uuidString) }
            )
        }
        return ([any] + perProtocol).sorted { lhs, rhs in
            if lhs.protocolID == "any_protocol" { return true }
            if rhs.protocolID == "any_protocol" { return false }
            return lhs.protocolName < rhs.protocolName
        }
    }

    func effectSummary(
        protocolID: String,
        protocolName: String,
        rows: [NightlyResearchRow],
        isTaken: (NightlyResearchRow) -> Bool,
        isNotTaken: (NightlyResearchRow) -> Bool
    ) -> ProtocolEffectSummary {
        let takenRows = rows.filter(isTaken)
        let missedRows = rows.filter(isNotTaken)
        let confidence = confidence(takenRows: takenRows, missedRows: missedRows)
        return ProtocolEffectSummary(
            protocolID: protocolID,
            protocolName: protocolName,
            takenNightCount: takenRows.count,
            missedNightCount: missedRows.count,
            sleepDifferenceHours: difference(takenRows.map(\.totalSleepHours), missedRows.map(\.totalSleepHours)),
            scoreDifference: difference(takenRows.map(\.sleepScore), missedRows.map(\.sleepScore)),
            efficiencyDifferencePercent: difference(takenRows.map(\.efficiencyPercent), missedRows.map(\.efficiencyPercent)),
            wasoDifferenceMinutes: difference(takenRows.map(\.wasoMinutes), missedRows.map(\.wasoMinutes)),
            latencyDifferenceMinutes: difference(takenRows.map(\.latencyMinutes), missedRows.map(\.latencyMinutes)),
            hrvDifference: difference(takenRows.compactMap(\.hrvAverage), missedRows.compactMap(\.hrvAverage)),
            jetLagAdjustedSleepDifferenceHours: difference(
                takenRows.filter { !$0.isConfounded }.map(\.totalSleepHours),
                missedRows.filter { !$0.isConfounded }.map(\.totalSleepHours)
            ),
            earlyTimingSleepDelta: nil,
            optimalTimingSleepDelta: nil,
            lateTimingSleepDelta: nil,
            confidence: confidence,
            caveats: caveats(takenRows: takenRows, missedRows: missedRows, allRows: rows)
        )
    }

    func confidence(takenRows: [NightlyResearchRow], missedRows: [NightlyResearchRow]) -> AnalysisConfidence {
        let minCount = min(takenRows.count, missedRows.count)
        switch minCount {
        case 7...: return .strong
        case 4...6: return .moderate
        case 2...3: return .low
        default: return .insufficient
        }
    }

    func caveats(takenRows: [NightlyResearchRow], missedRows: [NightlyResearchRow], allRows: [NightlyResearchRow]) -> [String] {
        var caveats: [String] = ["Observed association only; not causal."]
        if min(takenRows.count, missedRows.count) < 4 {
            caveats.append("Low sample size.")
        }
        if allRows.contains(where: \.isConfounded) {
            caveats.append("Some nights include travel or jet lag context.")
        }
        return caveats
    }

    func loadActivitySummaries(from startDate: Date, to endDate: Date) async throws -> [DailyActivitySummary] {
        let startKey = SleepDateKey.calendarDateKey(for: startDate, calendar: calendar)
        let endKey = SleepDateKey.calendarDateKey(for: endDate, calendar: calendar)
        var summariesByKey = Dictionary(
            uniqueKeysWithValues: try await localRepository
                .fetchDailyActivitySummaries(from: startKey, to: endKey)
                .map { ($0.dateKey, $0) }
        )

        for date in calendarDates(from: startDate, to: endDate) {
            let key = SleepDateKey.calendarDateKey(for: date, calendar: calendar)
            guard summariesByKey[key] == nil else { continue }
            let summary = await fetchActivitySummary(for: date, dateKey: key)
            try? await localRepository.saveDailyActivitySummary(summary)
            summariesByKey[key] = summary
        }

        return summariesByKey.values.sorted { $0.dateKey < $1.dateKey }
    }

    func fetchActivitySummary(for date: Date, dateKey: String) async -> DailyActivitySummary {
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)

        async let steps = trySum(.stepCount, from: start, to: end)
        async let energy = trySum(.activeEnergyBurned, from: start, to: end)
        async let exercise = trySum(.appleExerciseTime, from: start, to: end)
        async let stand = trySum(.appleStandTime, from: start, to: end)
        async let flights = trySum(.flightsClimbed, from: start, to: end)
        async let distance = trySum(.distanceWalkingRunning, from: start, to: end)

        return await DailyActivitySummary(
            dateKey: dateKey,
            steps: steps,
            activeEnergy: energy,
            exerciseMinutes: exercise,
            standHours: stand.map { $0 / 60 },
            flights: flights,
            distanceMeters: distance
        )
    }

    func trySum(_ type: BiometricType, from start: Date, to end: Date) async -> Double? {
        try? await sum(type, from: start, to: end)
    }

    func sum(_ type: BiometricType, from start: Date, to end: Date) async throws -> Double? {
        let samples = try await healthRepository.fetchBiometrics(for: type, from: start, to: end)
        guard !samples.isEmpty else { return nil }
        return samples.map(\.value).reduce(0, +)
    }

    func calendarDates(from startDate: Date, to endDate: Date) -> [Date] {
        var dates: [Date] = []
        var current = calendar.startOfDay(for: startDate)
        let end = calendar.startOfDay(for: endDate)
        while current <= end {
            dates.append(current)
            current = calendar.date(byAdding: .day, value: 1, to: current) ?? current.addingTimeInterval(86_400)
        }
        return dates
    }

    func average(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    func difference(_ takenValues: [Double], _ missedValues: [Double]) -> Double? {
        guard let taken = average(takenValues), let missed = average(missedValues) else {
            return nil
        }
        return taken - missed
    }

    static func formatMinutes(_ minutes: Double) -> String {
        String(format: "%.0f", minutes)
    }

    static func formatHours(_ hours: Double) -> String {
        String(format: "%.1f hours", hours)
    }
}

nonisolated private extension NightlyResearchRow {
    var isTravelConfounded: Bool {
        activityStatus == .jetLagged || activityStatus == .traveling
    }

    var isConfounded: Bool {
        isTravelConfounded || travel == true
    }
}

nonisolated private extension Array where Element == String {
    func joinedOrNil(separator: String) -> String? {
        isEmpty ? nil : joined(separator: separator)
    }
}
