import Foundation
import Observation

@MainActor
@Observable
final class ChronotypeViewModel {
    private let localRepository: LocalDataRepositoryProtocol
    private let chronotypeService: ChronotypeCalculationService
    private let summaryService: ChronotypeInsightSummaryService
    private let calendar: Calendar

    var state: ChronotypeDashboardState?
    var activeFormula: ProtocolFormulaVersion?
    var validSessionCount = 0
    var isLoading = false
    var errorMessage: String?

    init(
        localRepository: LocalDataRepositoryProtocol,
        chronotypeService: ChronotypeCalculationService = ChronotypeCalculationService(),
        summaryService: ChronotypeInsightSummaryService = ChronotypeInsightSummaryService(),
        calendar: Calendar = .current
    ) {
        self.localRepository = localRepository
        self.chronotypeService = chronotypeService
        self.summaryService = summaryService
        self.calendar = calendar
    }

    func onAppear() async {
        guard state == nil else { return }
        await loadData()
    }

    func loadData(now: Date = Date()) async {
        isLoading = true
        errorMessage = nil

        do {
            let startDate = calendar.date(byAdding: .day, value: -91, to: now)
                ?? now.addingTimeInterval(-91 * 86_400)
            let endKey = SleepDateKey.calendarDateKey(for: now, calendar: calendar)

            async let profileTask = localRepository.fetchProfile()
            async let baselineTask = localRepository.fetchLatestBaseline(windowDays: 30)
            async let formulaTask = localRepository.fetchActiveFormulaVersion()
            let profile = try await profileTask
            let baseline = try await baselineTask
            activeFormula = try await formulaTask

            // Cache-first: if the snapshot for today's window is fresh, skip the
            // expensive 90-day session/context/activity fetch entirely.
            if var cached = await chronotypeService.cachedEstimate(
                windowEndSleepDateKey: endKey,
                localRepository: localRepository
            ) {
                validSessionCount = cached.validNightCount
                // Chronotype tab still needs sessions for per-night detail, but only
                // if the estimate is available (insufficient-data doesn't render nights).
                let sessions: [SleepSession]
                if cached.estimate != nil {
                    sessions = (try? await localRepository.fetchCachedSessions(from: startDate, to: now)) ?? []
                    
                    // Reconstruct includedNights to resolve empty sleep statistics on cache hit
                    let calendar = calendar
                    cached.includedNights = sessions
                        .filter { session in
                            session.totalSleepTime >= 3 * 3_600 &&
                            session.totalSleepTime <= 12 * 3_600 &&
                            session.dataQuality != .inBedOnly &&
                            session.dataQuality != .noData
                        }
                        .compactMap { session -> ChronotypeNight? in
                            let sleepStages = session.stages
                                .filter { $0.type.isSleep }
                                .sorted { $0.startDate < $1.startDate }
                            let onset = sleepStages.first?.startDate ?? session.startDate
                            let wake = sleepStages.map(\.endDate).max() ?? session.endDate
                            guard onset < wake else { return nil }
                            
                            let midpoint = onset.addingTimeInterval(session.totalSleepTime / 2)
                            let components = calendar.dateComponents([.hour, .minute], from: midpoint)
                            let midpointMinute = ((components.hour ?? 0) * 60 + (components.minute ?? 0)) % 1_440
                            
                            let dayType: ChronotypeDayType = {
                                switch calendar.component(.weekday, from: onset) {
                                case 1...5: return .workday
                                default: return .freeDay
                                }
                            }()
                            
                            return ChronotypeNight(
                                sleepDateKey: session.sleepDateKey,
                                dayType: dayType,
                                onset: onset,
                                wake: wake,
                                duration: session.totalSleepTime,
                                midpointMinute: midpointMinute
                            )
                        }
                        .sorted { $0.onset < $1.onset }
                } else {
                    sessions = []
                }
                state = summaryService.dashboardState(
                    result: cached,
                    sessions: sessions,
                    baseline: baseline,
                    sleepGoalHours: profile.sleepGoalHours,
                    calendar: calendar
                )
            } else {
                let startKey = SleepDateKey.calendarDateKey(for: startDate, calendar: calendar)

                async let sessionsTask = localRepository.fetchCachedSessions(from: startDate, to: now)
                async let contextTask = localRepository.fetchContextEntries(from: startKey, to: endKey)
                async let activityTask = localRepository.fetchActivityStatusLogs(from: startKey, to: endKey)
                let sessions = try await sessionsTask
                let contextEntries = try await contextTask
                let activityLogs = try await activityTask

                let result = await calculateChronotype(
                    sessions: sessions,
                    contextEntries: contextEntries,
                    activityLogs: activityLogs,
                    endingAt: now
                )
                await chronotypeService.saveSnapshot(
                    result: result,
                    windowEndSleepDateKey: endKey,
                    localRepository: localRepository
                )
                validSessionCount = result.validNightCount
                state = summaryService.dashboardState(
                    result: result,
                    sessions: sessions,
                    baseline: baseline,
                    sleepGoalHours: profile.sleepGoalHours,
                    calendar: calendar
                )
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    /// Supplement timing rows derived from the active formula, or a CTA if none.
    func supplementTimingRows(optimalSleepStartMinute: Int) -> [ChronotypeSupplementTimingRow] {
        guard let formula = activeFormula, !formula.components.isEmpty else {
            return [ChronotypeSupplementTimingRow(
                supplementName: "Add a sleep formula",
                recommendedMinute: optimalSleepStartMinute,
                offsetMinutes: 0,
                isCTA: true
            )]
        }

        return formula.components.map { component in
            let offset = component.sleepTimingOffsetMinutes ?? knownOffset(for: component.name) ?? 60
            let minute = normalizeMinute(optimalSleepStartMinute - offset)
            return ChronotypeSupplementTimingRow(
                supplementName: component.name,
                recommendedMinute: minute,
                offsetMinutes: offset,
                isCTA: false
            )
        }
    }

    private func knownOffset(for name: String) -> Int? {
        let lower = name.lowercased()
        if lower.contains("melatonin") { return 30 }
        if lower.contains("magnesium") { return 60 }
        if lower.contains("theanine") { return 45 }
        if lower.contains("ashwagandha") { return 60 }
        if lower.contains("gaba") { return 30 }
        return nil
    }

    private func normalizeMinute(_ minute: Int) -> Int {
        ((minute % 1_440) + 1_440) % 1_440
    }

    private func calculateChronotype(
        sessions: [SleepSession],
        contextEntries: [SleepContextEntry],
        activityLogs: [ActivityStatusLog],
        endingAt: Date
    ) async -> ChronotypeCalculationResult {
        let service = chronotypeService
        let calendar = calendar

        return await Task.detached {
            service.estimate(
                sessions: sessions,
                contextEntries: contextEntries,
                activityLogs: activityLogs,
                windowDays: 90,
                endingAt: endingAt,
                calendar: calendar
            )
        }.value
    }
}
