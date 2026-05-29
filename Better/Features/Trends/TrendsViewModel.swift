import Foundation
import Observation
import SwiftUI

enum TrendWindow: Int, CaseIterable, Identifiable, Sendable {
    case week = 7
    case month = 30
    case threeMonths = 90

    var id: Int { rawValue }
    var days: Int { rawValue }

    var displayName: String {
        switch self {
        case .week: "7D"
        case .month: "30D"
        case .threeMonths: "90D"
        }
    }
}

enum TrendMetric: String, CaseIterable, Identifiable, Sendable {
    case totalSleep
    case longestRestorativeBlock
    case score
    case deepSleep
    case remSleep
    case hrv
    case waso
    case latency
    case respiratoryRate
    case oxygenSaturation

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .totalSleep: "Total Sleep"
        case .longestRestorativeBlock: "Longest Stretch"
        case .score: "Sleep Score"
        case .deepSleep: "Deep Sleep"
        case .remSleep: "REM Sleep"
        case .hrv: "HRV"
        case .waso: "Wake Time"
        case .latency: "Latency"
        case .respiratoryRate: "Breath Rate"
        case .oxygenSaturation: "Blood Oxygen"
        }
    }

    var unitLabel: String {
        switch self {
        case .totalSleep, .longestRestorativeBlock, .deepSleep, .remSleep: "hrs"
        case .score: "pts"
        case .hrv: "ms"
        case .waso, .latency: "min"
        case .respiratoryRate: "br/min"
        case .oxygenSaturation: "%"
        }
    }
}

struct TrendChartPoint: Identifiable, Sendable, Equatable {
    let id: String
    let date: Date
    let dateKey: String
    let value: Double
    let details: TrendPointDetails

    init(date: Date, dateKey: String, value: Double, details: TrendPointDetails, metric: String = "") {
        self.id = metric.isEmpty ? dateKey : "\(dateKey)_\(metric)"
        self.date = date
        self.dateKey = dateKey
        self.value = value
        self.details = details
    }

    /// Semantic equality: id is a stable content-derived key, not a random UUID.
    /// Two points with the same dateKey, value, and details are the same data point.
    static func == (lhs: TrendChartPoint, rhs: TrendChartPoint) -> Bool {
        lhs.dateKey == rhs.dateKey && lhs.value == rhs.value && lhs.details == rhs.details
    }
}

struct TrendPointDetails: Sendable, Hashable {
    let totalSleep: TimeInterval
    let timeInBed: TimeInterval
    let efficiency: Double
    let score: SleepQualityScore
}

struct StageCompositionPoint: Identifiable, Sendable, Equatable {
    let id: String
    let date: Date
    let dateKey: String
    let deepPercent: Double
    let corePercent: Double
    let remPercent: Double
    let awakePercent: Double
    let deepDuration: TimeInterval
    let coreDuration: TimeInterval
    let remDuration: TimeInterval
    let awakeDuration: TimeInterval

    var sleepDuration: TimeInterval {
        deepDuration + coreDuration + remDuration
    }

    var totalStageDuration: TimeInterval {
        sleepDuration + awakeDuration
    }

    init(
        date: Date,
        dateKey: String,
        deepPercent: Double,
        corePercent: Double,
        remPercent: Double,
        awakePercent: Double,
        deepDuration: TimeInterval,
        coreDuration: TimeInterval,
        remDuration: TimeInterval,
        awakeDuration: TimeInterval
    ) {
        self.id = dateKey
        self.date = date
        self.dateKey = dateKey
        self.deepPercent = deepPercent
        self.corePercent = corePercent
        self.remPercent = remPercent
        self.awakePercent = awakePercent
        self.deepDuration = deepDuration
        self.coreDuration = coreDuration
        self.remDuration = remDuration
        self.awakeDuration = awakeDuration
    }

    static func == (lhs: StageCompositionPoint, rhs: StageCompositionPoint) -> Bool {
        lhs.dateKey == rhs.dateKey
            && lhs.deepDuration == rhs.deepDuration
            && lhs.coreDuration == rhs.coreDuration
            && lhs.remDuration == rhs.remDuration
            && lhs.awakeDuration == rhs.awakeDuration
    }
}

struct TrendComparisonSummary: Sendable, Hashable, Equatable {
    var currentAverage: Double
    var previousAverage: Double
    var percentChange: Double
    var currentValidNights: Int
    var previousValidNights: Int
}

@MainActor
@Observable
final class TrendsViewModel {
    private let localRepository: LocalDataRepositoryProtocol
    private let chronotypeService: ChronotypeCalculationService
    private let insightService = SleepInsightService()
    private let calendar: Calendar
    private var comparisonSessions: [SleepSession] = []
    private enum UserDefaultsKeys {
        static let protocolStartDate = "better.protocol.startDate"
    }

    var sessions: [SleepSession] = []
    var selectedWindow: TrendWindow = .month
    var selectedMetric: TrendMetric = .totalSleep
    var baseline: SleepBaseline?
    var chartPoints: [TrendChartPoint] = []
    var comparisonSummary: TrendComparisonSummary?
    var stageCompositionPoints: [StageCompositionPoint] = []
    var adherenceByDateKey: [String: Bool] = [:]
    var protocolStartDate: Date? = nil
    var isLoading = false
    var errorMessage: String?
    var latestSessionInsights: [SleepInsight] = []
    var chronotypeResult: ChronotypeCalculationResult?
    var sleepGoalHours: Double = 8.0

    // Explorer state
    var secondaryMetric: TrendMetric? = nil
    var secondaryChartPoints: [TrendChartPoint] = []
    var tertiaryMetric: TrendMetric? = nil
    var tertiaryChartPoints: [TrendChartPoint] = []
    var periodAverages: [TrendWindow: [TrendMetric: Double]] = [:]

    /// Stable color for each metric comparison slot (0=primary, 1=compare1, 2=compare2).
    static func explorerColor(slot: Int) -> Color {
        switch slot {
        case 0: return BetterColors.brand
        case 1: return BetterColors.success
        default: return BetterColors.warning
        }
    }

    // Per-session metric value cache. Two parallel structures to distinguish
    // "not yet computed" from "computed but nil".
    // Key: "\(session.id):\(metric.rawValue)"
    private var metricValueCacheComputed: Set<String> = []
    private var metricValueCacheValues: [String: Double] = [:]

    // Cached derived properties to avoid main-thread scroll lag
    var bestSleepSession: SleepSession? = nil
    var avgScoreInPeriod: Double? = nil
    var avgDurationHours: Double? = nil
    var scoreSparklineValues: [Double] = []
    var weekendAvgHours: Double? = nil
    var weekdayAvgHours: Double? = nil
    var weekendSessionCount: Int = 0
    var weekdaySessionCount: Int = 0


    var weekOverWeekChange: Double? {
        comparisonSummary?.percentChange
    }

    // MARK: - Derived Insight Properties

    /// The single source of truth for a session's score — matches the Sleep Dashboard.
    func healthScore(for session: SleepSession) -> Double {
        Double(HealthSleepScoreEstimator.estimate(
            session: session,
            baseline: baseline,
            sleepGoalHours: sleepGoalHours,
            calendar: calendar
        ).overall)
    }


    init(
        localRepository: LocalDataRepositoryProtocol,
        chronotypeService: ChronotypeCalculationService = ChronotypeCalculationService(),
        calendar: Calendar = .current
    ) {
        self.localRepository = localRepository
        self.chronotypeService = chronotypeService
        self.calendar = calendar
    }

    func onAppear() async {
        await loadData()
    }

    func selectWindow(_ window: TrendWindow) async {
        selectedWindow = window
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        await loadData()
    }

    func selectMetric(_ metric: TrendMetric) {
        selectedMetric = metric
        // If the new primary clashes with secondary or tertiary, clear those
        if secondaryMetric == metric { secondaryMetric = nil; tertiaryMetric = nil }
        if tertiaryMetric == metric { tertiaryMetric = nil }
        updateChartPoints()
        updateSecondaryChartPoints()
        updateTertiaryChartPoints()
        updateComparisonSummary(from: comparisonSessions, endingAt: Date())
        recomputeDerivedMetrics()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    func selectSecondaryMetric(_ metric: TrendMetric?) {
        secondaryMetric = metric
        // If secondary clears out, clear tertiary too (tertiary requires secondary)
        if metric == nil { tertiaryMetric = nil }
        updateSecondaryChartPoints()
        updateTertiaryChartPoints()
        recomputeDerivedMetrics()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    func selectTertiaryMetric(_ metric: TrendMetric?) {
        tertiaryMetric = metric
        updateTertiaryChartPoints()
        recomputeDerivedMetrics()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    func loadData(now: Date = Date()) async {
        isLoading = true
        errorMessage = nil
        // Invalidate cache — sessions and baselines may have changed.
        metricValueCacheComputed.removeAll(keepingCapacity: true)
        metricValueCacheValues.removeAll(keepingCapacity: true)
        protocolStartDate = UserDefaults.standard.object(forKey: UserDefaultsKeys.protocolStartDate) as? Date
        do {
            let startDate = calendar.date(byAdding: .day, value: -selectedWindow.days, to: now)
                ?? now.addingTimeInterval(Double(-selectedWindow.days) * 86_400)
            let comparisonStart = comparisonWindows(endingAt: now).previous.start
            let chronotypeStart = calendar.date(byAdding: .day, value: -91, to: now)
                ?? now.addingTimeInterval(-91 * 86_400)
            let fetchStart = min(comparisonStart, chronotypeStart)
            let fetchedSessions = try await localRepository.fetchCachedSessions(from: fetchStart, to: now)
            comparisonSessions = fetchedSessions
            sessions = fetchedSessions.filter { $0.endDate > startDate && $0.startDate < now }
            let profile = try await localRepository.fetchProfile()
            sleepGoalHours = profile.sleepGoalHours
            baseline = try await localRepository.fetchLatestBaseline(windowDays: profile.baselineWindowDays)
            let adherence = try await localRepository.fetchAdherence(from: startDate, to: now)
            let chronotypeEndKey = SleepDateKey.calendarDateKey(for: now, calendar: calendar)
            // Cache-first: skip 90-day session/context/activity fetch when snapshot is fresh.
            if let cached = await chronotypeService.cachedEstimate(
                windowEndSleepDateKey: chronotypeEndKey,
                localRepository: localRepository
            ) {
                chronotypeResult = cached
            } else {
                let chronotypeStartKey = SleepDateKey.calendarDateKey(for: chronotypeStart, calendar: calendar)
                let contextEntries = try await localRepository.fetchContextEntries(from: chronotypeStartKey, to: chronotypeEndKey)
                let activityLogs = try await localRepository.fetchActivityStatusLogs(from: chronotypeStartKey, to: chronotypeEndKey)
                let computed = await calculateChronotype(
                    sessions: fetchedSessions,
                    contextEntries: contextEntries,
                    activityLogs: activityLogs,
                    endingAt: now
                )
                chronotypeResult = computed
                await chronotypeService.saveSnapshot(
                    result: computed,
                    windowEndSleepDateKey: chronotypeEndKey,
                    localRepository: localRepository
                )
            }
            var byKey: [String: Bool] = [:]
            for record in adherence {
                byKey[record.dateKey] = byKey[record.dateKey] == true || record.taken
            }
            adherenceByDateKey = byKey
            updateComparisonSummary(from: fetchedSessions, endingAt: now)
            updateChartPoints()
            updateSecondaryChartPoints()
            updateTertiaryChartPoints()
            updateStageCompositionPoints()
            updateLatestInsights()
            recomputeDerivedMetrics()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

private extension TrendsViewModel {
    func recomputeDerivedMetrics() {
        periodAverages = computePeriodAverages()
        guard !sessions.isEmpty else {
            bestSleepSession = nil
            avgScoreInPeriod = nil
            avgDurationHours = nil
            scoreSparklineValues = []
            weekendSessionCount = 0
            weekdaySessionCount = 0
            weekendAvgHours = nil
            weekdayAvgHours = nil
            return
        }

        let sortedSessions = sessions.sorted { $0.startDate < $1.startDate }

        var maxScore: Double = 0
        var maxScoreSession: SleepSession? = nil
        var scoreSum: Double = 0
        var durationSum: TimeInterval = 0
        var weekendDurationSum: TimeInterval = 0
        var weekdayDurationSum: TimeInterval = 0
        var weekendCount = 0
        var weekdayCount = 0
        var sparklineScores: [Double] = []

        for session in sortedSessions {
            let score = healthScore(for: session)
            sparklineScores.append(score)
            scoreSum += score
            durationSum += session.totalSleepTime

            if score > maxScore {
                maxScore = score
                maxScoreSession = session
            }

            if calendar.isDateInWeekend(session.startDate) {
                weekendDurationSum += session.totalSleepTime
                weekendCount += 1
            } else {
                weekdayDurationSum += session.totalSleepTime
                weekdayCount += 1
            }
        }

        let count = sessions.count
        bestSleepSession = maxScoreSession
        avgScoreInPeriod = scoreSum / Double(count)
        avgDurationHours = durationSum / Double(count) / 3_600
        scoreSparklineValues = sparklineScores
        weekendSessionCount = weekendCount
        weekdaySessionCount = weekdayCount
        weekendAvgHours = weekendCount > 0 ? weekendDurationSum / Double(weekendCount) / 3_600 : nil
        weekdayAvgHours = weekdayCount > 0 ? weekdayDurationSum / Double(weekdayCount) / 3_600 : nil
    }

    func calculateChronotype(
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

    func updateChartPoints() {
        let metricRaw = selectedMetric.rawValue
        chartPoints = sessions.compactMap { session in
            guard let value = metricValue(for: session) else { return nil }
            return TrendChartPoint(
                date: session.startDate,
                dateKey: session.sleepDateKey,
                value: value,
                details: TrendPointDetails(
                    totalSleep: session.totalSleepTime,
                    timeInBed: session.totalInBedTime,
                    efficiency: session.efficiency,
                    score: session.qualityScore
                ),
                metric: metricRaw
            )
        }
    }

    func updateSecondaryChartPoints() {
        guard let metric = secondaryMetric else {
            secondaryChartPoints = []
            return
        }
        let metricRaw = metric.rawValue
        secondaryChartPoints = sessions.compactMap { session -> TrendChartPoint? in
            guard let value = metricValue(for: session, metric: metric) else { return nil }
            return TrendChartPoint(
                date: session.startDate,
                dateKey: session.sleepDateKey,
                value: value,
                details: TrendPointDetails(
                    totalSleep: session.totalSleepTime,
                    timeInBed: session.totalInBedTime,
                    efficiency: session.efficiency,
                    score: session.qualityScore
                ),
                metric: metricRaw
            )
        }
    }

    func updateTertiaryChartPoints() {
        guard let metric = tertiaryMetric else {
            tertiaryChartPoints = []
            return
        }
        let metricRaw = metric.rawValue
        tertiaryChartPoints = sessions.compactMap { session -> TrendChartPoint? in
            guard let value = metricValue(for: session, metric: metric) else { return nil }
            return TrendChartPoint(
                date: session.startDate,
                dateKey: session.sleepDateKey,
                value: value,
                details: TrendPointDetails(
                    totalSleep: session.totalSleepTime,
                    timeInBed: session.totalInBedTime,
                    efficiency: session.efficiency,
                    score: session.qualityScore
                ),
                metric: metricRaw
            )
        }
    }

    func computePeriodAverages() -> [TrendWindow: [TrendMetric: Double]] {
        let metrics = [selectedMetric, secondaryMetric, tertiaryMetric].compactMap { $0 }
        guard !metrics.isEmpty, !comparisonSessions.isEmpty else { return [:] }
        let now = Date()
        var result: [TrendWindow: [TrendMetric: Double]] = [:]
        for window in TrendWindow.allCases {
            let cutoff = Calendar.current.date(byAdding: .day, value: -window.days, to: now)
                ?? now.addingTimeInterval(Double(-window.days) * 86_400)
            let windowSessions = comparisonSessions.filter { $0.endDate > cutoff && $0.startDate < now }
            guard !windowSessions.isEmpty else { continue }
            var metricMap: [TrendMetric: Double] = [:]
            for metric in metrics {
                let values = windowSessions.compactMap { metricValue(for: $0, metric: metric) }
                if !values.isEmpty {
                    metricMap[metric] = values.reduce(0, +) / Double(values.count)
                }
            }
            if !metricMap.isEmpty {
                result[window] = metricMap
            }
        }
        return result
    }

    func updateLatestInsights() {
        let sorted = sessions.sorted { $0.startDate < $1.startDate }
        if let latestSession = sorted.last {
            latestSessionInsights = insightService.insights(
                session: latestSession,
                baseline: baseline,
                recentSessions: sorted
            )
        } else {
            latestSessionInsights = []
        }
    }

    func updateStageCompositionPoints() {
        stageCompositionPoints = sessions.compactMap { session -> StageCompositionPoint? in
            guard session.dataQuality == .detailedStages, session.totalSleepTime > 0 else { return nil }
            let total = session.deepDuration + session.coreDuration + session.remDuration + session.awakeDuration
            guard total > 0 else { return nil }
            return StageCompositionPoint(
                date: session.startDate,
                dateKey: session.sleepDateKey,
                deepPercent: session.deepDuration / total,
                corePercent: session.coreDuration / total,
                remPercent: session.remDuration / total,
                awakePercent: session.awakeDuration / total,
                deepDuration: session.deepDuration,
                coreDuration: session.coreDuration,
                remDuration: session.remDuration,
                awakeDuration: session.awakeDuration
            )
        }
    }

    func updateComparisonSummary(from availableSessions: [SleepSession], endingAt endDate: Date) {
        let windows = comparisonWindows(endingAt: endDate)
        let currentValues = availableSessions
            .filter { $0.endDate > windows.current.start && $0.startDate < windows.current.end }
            .compactMap { metricValue(for: $0) }
        let previousValues = availableSessions
            .filter { $0.endDate > windows.previous.start && $0.startDate < windows.previous.end }
            .compactMap { metricValue(for: $0) }

        guard !currentValues.isEmpty, !previousValues.isEmpty else {
            comparisonSummary = nil
            return
        }

        let currentAverage = currentValues.reduce(0, +) / Double(currentValues.count)
        let previousAverage = previousValues.reduce(0, +) / Double(previousValues.count)
        guard previousAverage != 0 else {
            comparisonSummary = nil
            return
        }

        comparisonSummary = TrendComparisonSummary(
            currentAverage: currentAverage,
            previousAverage: previousAverage,
            percentChange: (currentAverage - previousAverage) / previousAverage,
            currentValidNights: currentValues.count,
            previousValidNights: previousValues.count
        )
    }

    func comparisonWindows(endingAt endDate: Date) -> (current: DateInterval, previous: DateInterval) {
        switch selectedWindow {
        case .week:
            return weekComparisonWindows(endingAt: endDate)
        case .month:
            return monthComparisonWindows(endingAt: endDate)
        case .threeMonths:
            return rollingComparisonWindows(days: 90, endingAt: endDate)
        }
    }

    func rollingComparisonWindows(days: Int, endingAt endDate: Date) -> (current: DateInterval, previous: DateInterval) {
        let currentStart = calendar.date(byAdding: .day, value: -days, to: endDate)
            ?? endDate.addingTimeInterval(Double(-days) * 86_400)
        let previousStart = calendar.date(byAdding: .day, value: -days, to: currentStart)
            ?? currentStart.addingTimeInterval(Double(-days) * 86_400)
        return (
            DateInterval(start: currentStart, end: endDate),
            DateInterval(start: previousStart, end: currentStart)
        )
    }

    func weekComparisonWindows(endingAt endDate: Date) -> (current: DateInterval, previous: DateInterval) {
        guard let week = calendar.dateInterval(of: .weekOfYear, for: endDate) else {
            return rollingComparisonWindows(days: 7, endingAt: endDate)
        }

        let elapsed = endDate.timeIntervalSince(week.start)
        let previousStart = calendar.date(byAdding: .weekOfYear, value: -1, to: week.start)
            ?? week.start.addingTimeInterval(-7 * 86_400)
        let previousEnd = min(previousStart.addingTimeInterval(elapsed), week.start)
        return (
            DateInterval(start: week.start, end: endDate),
            DateInterval(start: previousStart, end: previousEnd)
        )
    }

    func monthComparisonWindows(endingAt endDate: Date) -> (current: DateInterval, previous: DateInterval) {
        guard let month = calendar.dateInterval(of: .month, for: endDate) else {
            return rollingComparisonWindows(days: 30, endingAt: endDate)
        }

        let elapsed = endDate.timeIntervalSince(month.start)
        let previousStart = calendar.date(byAdding: .month, value: -1, to: month.start)
            ?? month.start.addingTimeInterval(-30 * 86_400)
        let previousEnd = min(previousStart.addingTimeInterval(elapsed), month.start)
        return (
            DateInterval(start: month.start, end: endDate),
            DateInterval(start: previousStart, end: previousEnd)
        )
    }

    /// Memoized explicit-metric overload. Used by `updateSecondaryChartPoints`,
    /// `computePeriodAverages`, `updateComparisonSummary`, and `updateChartPoints`.
    /// Cache key: "\(session.id):\(metric.rawValue)". Cleared in `loadData()`.
    /// Nil results are stored via the absence of an entry in `metricValueCacheValues`
    /// combined with presence in `metricValueCacheComputed`.
    func metricValue(for session: SleepSession, metric: TrendMetric) -> Double? {
        let key = "\(session.id):\(metric.rawValue)"
        if metricValueCacheComputed.contains(key) {
            return metricValueCacheValues[key]
        }
        let result = computeMetricValue(for: session, metric: metric)
        metricValueCacheComputed.insert(key)
        if let result {
            metricValueCacheValues[key] = result
        }
        return result
    }

    /// Convenience overload that evaluates `selectedMetric`.
    func metricValue(for session: SleepSession) -> Double? {
        metricValue(for: session, metric: selectedMetric)
    }

    /// Pure computation — no caching. Called only from `metricValue(for:metric:)`.
    private func computeMetricValue(for session: SleepSession, metric: TrendMetric) -> Double? {
        switch metric {
        case .totalSleep:
            return session.totalSleepTime / 3_600
        case .longestRestorativeBlock:
            let summary = session.continuitySummary
            guard !summary.blocks.isEmpty else { return nil }
            return summary.longestBlockDuration / 3_600
        case .score:
            return Double(session.appleScorePartial)
        case .deepSleep:
            guard session.dataQuality == .detailedStages else { return nil }
            return session.deepDuration / 3_600
        case .remSleep:
            guard session.dataQuality == .detailedStages else { return nil }
            return session.remDuration / 3_600
        case .hrv:
            return session.biometrics?.hrvAverage
        case .waso:
            return session.waso / 60
        case .latency:
            return session.sleepLatency / 60
        case .respiratoryRate:
            return session.biometrics?.respiratoryRateAverage
        case .oxygenSaturation:
            return session.biometrics?.oxygenSaturationAverage.map { $0 * 100 }
        }
    }
}
