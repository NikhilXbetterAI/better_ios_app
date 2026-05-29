import Foundation

nonisolated struct ChronotypeInsightSummaryService: Sendable {
    static let sleepStartToleranceMinutes = 60
    static let avoidSleepOffsetMinutes = 60
    static let minimumComparisonGroupCount = 3

    func dashboardState(
        result: ChronotypeCalculationResult,
        sessions: [SleepSession],
        baseline: SleepBaseline?,
        sleepGoalHours: Double,
        calendar: Calendar = .current
    ) -> ChronotypeDashboardState {
        let validSessions = sessionsForIncludedNights(result.includedNights, sessions: sessions)
        let actualAverageBedtimeMinute = circularMedian(validSessions.map { minuteOfDay(for: sleepOnset(for: $0), calendar: calendar) })
        let actualAverageWakeMinute = circularMedian(validSessions.map { minuteOfDay(for: sleepWake(for: $0), calendar: calendar) })
        let actualAverageDuration = median(validSessions.map(\.totalSleepTime))

        guard let estimate = result.estimate else {
            return ChronotypeDashboardState(
                chronotypeResult: result,
                actualAverageBedtimeMinute: actualAverageBedtimeMinute,
                actualAverageWakeMinute: actualAverageWakeMinute,
                actualAverageDuration: actualAverageDuration,
                recommendedFormulaMinute: nil,
                avoidSleepBeforeMinute: nil,
                avoidSleepAfterMinute: nil,
                bestNight: nil,
                worstNight: nil,
                sleepWindowImpact: nil
            )
        }

        return ChronotypeDashboardState(
            chronotypeResult: result,
            actualAverageBedtimeMinute: actualAverageBedtimeMinute,
            actualAverageWakeMinute: actualAverageWakeMinute,
            actualAverageDuration: actualAverageDuration,
            recommendedFormulaMinute: normalizeMinute(estimate.optimalSleepWindow.startMinute - 60),
            avoidSleepBeforeMinute: normalizeMinute(estimate.optimalSleepWindow.startMinute - Self.avoidSleepOffsetMinutes),
            avoidSleepAfterMinute: normalizeMinute(estimate.optimalSleepWindow.startMinute + Self.avoidSleepOffsetMinutes),
            bestNight: bestNight(
                sessions: validSessions,
                baseline: baseline,
                sleepGoalHours: sleepGoalHours,
                calendar: calendar
            ),
            worstNight: worstNight(
                sessions: validSessions,
                estimate: estimate,
                baseline: baseline,
                sleepGoalHours: sleepGoalHours,
                calendar: calendar
            ),
            sleepWindowImpact: impactSummary(
                sessions: validSessions,
                estimate: estimate,
                baseline: baseline,
                sleepGoalHours: sleepGoalHours,
                calendar: calendar
            )
        )
    }

    func impactSummary(
        sessions: [SleepSession],
        estimate: ChronotypeEstimate,
        baseline: SleepBaseline?,
        sleepGoalHours: Double,
        calendar: Calendar = .current
    ) -> SleepWindowImpactSummary {
        let groups = Dictionary(grouping: sessions) { session in
            isSleepStartInBestWindow(
                minuteOfDay(for: sleepOnset(for: session), calendar: calendar),
                targetStartMinute: estimate.optimalSleepWindow.startMinute
            )
        }
        let inWindow = groups[true, default: []]
        let outsideWindow = groups[false, default: []]

        guard inWindow.count >= Self.minimumComparisonGroupCount,
              outsideWindow.count >= Self.minimumComparisonGroupCount else {
            return SleepWindowImpactSummary(
                inWindowNightCount: inWindow.count,
                outsideWindowNightCount: outsideWindow.count,
                scoreDelta: nil,
                restorativeDelta: nil,
                deepDelta: nil,
                remDelta: nil,
                awakeDelta: nil,
                durationDelta: nil
            )
        }

        return SleepWindowImpactSummary(
            inWindowNightCount: inWindow.count,
            outsideWindowNightCount: outsideWindow.count,
            scoreDelta: averageScore(inWindow, baseline: baseline, sleepGoalHours: sleepGoalHours, calendar: calendar)
                - averageScore(outsideWindow, baseline: baseline, sleepGoalHours: sleepGoalHours, calendar: calendar),
            restorativeDelta: average(inWindow.map(\.restorativeSleepDuration)) - average(outsideWindow.map(\.restorativeSleepDuration)),
            deepDelta: average(inWindow.map(\.deepDuration)) - average(outsideWindow.map(\.deepDuration)),
            remDelta: average(inWindow.map(\.remDuration)) - average(outsideWindow.map(\.remDuration)),
            awakeDelta: average(inWindow.map(\.waso)) - average(outsideWindow.map(\.waso)),
            durationDelta: average(inWindow.map(\.totalSleepTime)) - average(outsideWindow.map(\.totalSleepTime))
        )
    }

    func bestNight(
        sessions: [SleepSession],
        baseline: SleepBaseline?,
        sleepGoalHours: Double,
        calendar: Calendar = .current
    ) -> ChronotypeNightSummary? {
        sessions
            .max { lhs, rhs in
                score(for: lhs, baseline: baseline, sleepGoalHours: sleepGoalHours, calendar: calendar)
                    < score(for: rhs, baseline: baseline, sleepGoalHours: sleepGoalHours, calendar: calendar)
            }
            .map {
                nightSummary(
                    session: $0,
                    score: score(for: $0, baseline: baseline, sleepGoalHours: sleepGoalHours, calendar: calendar),
                    reason: bestReason(for: $0),
                    calendar: calendar
                )
            }
    }

    func worstNight(
        sessions: [SleepSession],
        estimate: ChronotypeEstimate,
        baseline: SleepBaseline?,
        sleepGoalHours: Double,
        calendar: Calendar = .current
    ) -> ChronotypeNightSummary? {
        sessions
            .min { lhs, rhs in
                score(for: lhs, baseline: baseline, sleepGoalHours: sleepGoalHours, calendar: calendar)
                    < score(for: rhs, baseline: baseline, sleepGoalHours: sleepGoalHours, calendar: calendar)
            }
            .map {
                nightSummary(
                    session: $0,
                    score: score(for: $0, baseline: baseline, sleepGoalHours: sleepGoalHours, calendar: calendar),
                    reason: worstReason(for: $0, estimate: estimate, calendar: calendar),
                    calendar: calendar
                )
            }
    }

    func isSleepStartInBestWindow(_ minute: Int, targetStartMinute: Int) -> Bool {
        abs(signedCircularDelta(from: targetStartMinute, to: minute)) <= Self.sleepStartToleranceMinutes
    }

    func normalizeMinute(_ minute: Int) -> Int {
        ((minute % 1_440) + 1_440) % 1_440
    }
}

private extension ChronotypeInsightSummaryService {
    nonisolated func sessionsForIncludedNights(_ nights: [ChronotypeNight], sessions: [SleepSession]) -> [SleepSession] {
        let includedKeys = Set(nights.map(\.sleepDateKey))
        return sessions
            .filter { includedKeys.contains($0.sleepDateKey) }
            .sorted { $0.startDate < $1.startDate }
    }

    nonisolated func sleepOnset(for session: SleepSession) -> Date {
        session.stages
            .filter { $0.type.isSleep }
            .map(\.startDate)
            .min() ?? session.startDate
    }

    nonisolated func sleepWake(for session: SleepSession) -> Date {
        session.stages
            .filter { $0.type.isSleep }
            .map(\.endDate)
            .max() ?? session.endDate
    }

    nonisolated func score(
        for session: SleepSession,
        baseline: SleepBaseline?,
        sleepGoalHours: Double,
        calendar: Calendar
    ) -> Double {
        Double(HealthSleepScoreEstimator.estimate(
            session: session,
            baseline: baseline,
            sleepGoalHours: sleepGoalHours,
            calendar: calendar
        ).overall)
    }

    nonisolated func averageScore(
        _ sessions: [SleepSession],
        baseline: SleepBaseline?,
        sleepGoalHours: Double,
        calendar: Calendar
    ) -> Double {
        average(sessions.map { score(for: $0, baseline: baseline, sleepGoalHours: sleepGoalHours, calendar: calendar) })
    }

    nonisolated func nightSummary(
        session: SleepSession,
        score: Double,
        reason: String,
        calendar: Calendar
    ) -> ChronotypeNightSummary {
        ChronotypeNightSummary(
            sleepDateKey: session.sleepDateKey,
            bedtimeMinute: minuteOfDay(for: sleepOnset(for: session), calendar: calendar),
            wakeMinute: minuteOfDay(for: sleepWake(for: session), calendar: calendar),
            duration: session.totalSleepTime,
            score: score,
            reason: reason
        )
    }

    nonisolated func bestReason(for session: SleepSession) -> String {
        if session.efficiency >= 0.88 && session.totalSleepTime >= 7 * 3_600 {
            return "You slept long and stayed asleep."
        }

        if session.restorativeSleepDuration >= 2 * 3_600 {
            return "You got strong deep and REM sleep."
        }

        if session.waso <= 30 * 60 {
            return "You had little wake time."
        }

        return "Your sleep score was your best in this set."
    }

    nonisolated func worstReason(for session: SleepSession, estimate: ChronotypeEstimate, calendar: Calendar) -> String {
        if session.totalSleepTime < 6 * 3_600 {
            return "You did not sleep long enough."
        }

        if session.efficiency < 0.78 || session.waso > 60 * 60 {
            return "You spent too much time awake."
        }

        let onsetMinute = minuteOfDay(for: sleepOnset(for: session), calendar: calendar)
        if !isSleepStartInBestWindow(onsetMinute, targetStartMinute: estimate.optimalSleepWindow.startMinute) {
            return "You slept outside your best window."
        }

        if session.restorativeSleepDuration < 90 * 60 {
            return "You got less deep and REM sleep."
        }

        return "This night had the lowest score in this set."
    }

    nonisolated func minuteOfDay(for date: Date, calendar: Calendar) -> Int {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return normalizeMinute(((components.hour ?? 0) * 60) + (components.minute ?? 0))
    }

    nonisolated func circularMedian(_ minutes: [Int]) -> Int? {
        guard !minutes.isEmpty else { return nil }
        let anchor = circularMean(minutes)
        let unwrapped = minutes.map { minute -> Double in
            var value = Double(minute)
            while value - anchor > 720 { value -= 1_440 }
            while anchor - value > 720 { value += 1_440 }
            return value
        }
        guard let median = median(unwrapped) else { return nil }
        return normalizeMinute(Int(median.rounded()))
    }

    nonisolated func circularMean(_ minutes: [Int]) -> Double {
        guard !minutes.isEmpty else { return 0 }
        let angles = minutes.map { Double($0) / 1_440 * 2 * Double.pi }
        let sine = angles.map(sin).reduce(0, +) / Double(angles.count)
        let cosine = angles.map(cos).reduce(0, +) / Double(angles.count)
        var angle = atan2(sine, cosine)
        if angle < 0 { angle += 2 * Double.pi }
        return angle / (2 * Double.pi) * 1_440
    }

    nonisolated func median(_ values: [TimeInterval]) -> TimeInterval? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }

    nonisolated func average(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }

    nonisolated func signedCircularDelta(from targetMinute: Int, to actualMinute: Int) -> Int {
        var delta = actualMinute - targetMinute
        while delta > 720 { delta -= 1_440 }
        while delta < -720 { delta += 1_440 }
        return delta
    }
}
