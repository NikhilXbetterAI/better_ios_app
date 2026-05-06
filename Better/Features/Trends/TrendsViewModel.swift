import Foundation
import Observation

enum TrendWindow: Int, CaseIterable, Identifiable, Sendable {
    case week = 7
    case biWeekly = 15
    case month = 30

    var id: Int { rawValue }
    var days: Int { rawValue }

    var displayName: String {
        switch self {
        case .week: "7 Days"
        case .biWeekly: "15 Days"
        case .month: "30 Days"
        }
    }
}

enum TrendMetric: String, CaseIterable, Identifiable, Sendable {
    case totalSleep
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
        case .score: "Sleep Score"
        case .deepSleep: "Deep Sleep"
        case .remSleep: "REM Sleep"
        case .hrv: "HRV"
        case .waso: "WASO"
        case .latency: "Latency"
        case .respiratoryRate: "Resp. Rate"
        case .oxygenSaturation: "SpO2"
        }
    }

    var unitLabel: String {
        switch self {
        case .totalSleep, .deepSleep, .remSleep: "hrs"
        case .score: "pts"
        case .hrv: "ms"
        case .waso, .latency: "min"
        case .respiratoryRate: "br/min"
        case .oxygenSaturation: "%"
        }
    }
}

struct TrendChartPoint: Identifiable, Sendable {
    let id: UUID
    let date: Date
    let dateKey: String
    let value: Double
    let details: TrendPointDetails

    init(date: Date, dateKey: String, value: Double, details: TrendPointDetails) {
        self.id = UUID()
        self.date = date
        self.dateKey = dateKey
        self.value = value
        self.details = details
    }
}

struct TrendPointDetails: Sendable, Hashable {
    let totalSleep: TimeInterval
    let timeInBed: TimeInterval
    let efficiency: Double
    let score: SleepQualityScore
}

struct StageCompositionPoint: Identifiable, Sendable {
    let id: UUID
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
        self.id = UUID()
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
}

struct TrendComparisonSummary: Sendable, Hashable {
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
    private let calendar: Calendar
    private var comparisonSessions: [SleepSession] = []

    var sessions: [SleepSession] = []
    var selectedWindow: TrendWindow = .week
    var selectedMetric: TrendMetric = .totalSleep
    var baseline: SleepBaseline?
    var chartPoints: [TrendChartPoint] = []
    var comparisonSummary: TrendComparisonSummary?
    var stageCompositionPoints: [StageCompositionPoint] = []
    var isLoading = false
    var errorMessage: String?

    var weekOverWeekChange: Double? {
        comparisonSummary?.percentChange
    }

    init(localRepository: LocalDataRepositoryProtocol, calendar: Calendar = .current) {
        self.localRepository = localRepository
        self.calendar = calendar
    }

    func onAppear() async {
        await loadData()
    }

    func selectWindow(_ window: TrendWindow) async {
        selectedWindow = window
        await loadData()
    }

    func selectMetric(_ metric: TrendMetric) {
        selectedMetric = metric
        updateChartPoints()
        updateComparisonSummary(from: comparisonSessions, endingAt: Date())
    }

    func loadData(now: Date = Date()) async {
        isLoading = true
        errorMessage = nil
        do {
            let startDate = calendar.date(byAdding: .day, value: -selectedWindow.days, to: now)
                ?? now.addingTimeInterval(Double(-selectedWindow.days) * 86_400)
            let comparisonStart = comparisonWindows(endingAt: now).previous.start
            let fetchedSessions = try await localRepository.fetchCachedSessions(from: comparisonStart, to: now)
            comparisonSessions = fetchedSessions
            sessions = fetchedSessions.filter { $0.endDate > startDate && $0.startDate < now }
            let profile = try await localRepository.fetchProfile()
            baseline = try await localRepository.fetchLatestBaseline(windowDays: profile.baselineWindowDays)
            updateComparisonSummary(from: fetchedSessions, endingAt: now)
            updateChartPoints()
            updateStageCompositionPoints()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

private extension TrendsViewModel {
    func updateChartPoints() {
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
                )
            )
        }
    }

    func updateStageCompositionPoints() {
        stageCompositionPoints = sessions.compactMap { session -> StageCompositionPoint? in
            guard session.dataQuality == .detailedStages, session.totalSleepTime > 0 else { return nil }
            let total = session.totalSleepTime
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
        case .biWeekly:
            return rollingComparisonWindows(days: selectedWindow.days, endingAt: endDate)
        case .month:
            return monthComparisonWindows(endingAt: endDate)
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

    func metricValue(for session: SleepSession) -> Double? {
        switch selectedMetric {
        case .totalSleep:
            return session.totalSleepTime / 3_600
        case .score:
            return session.qualityScore.overall
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
