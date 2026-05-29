import Foundation

nonisolated enum SleepSummaryPeriod: String, Codable, Hashable, Sendable {
    case day
    case week
    case month
}

nonisolated struct SleepAggregateSummary: Codable, Hashable, Sendable, Identifiable {
    var id: String { "\(period.rawValue)-\(startSleepDateKey)-\(endSleepDateKey)" }
    var period: SleepSummaryPeriod
    var startSleepDateKey: String
    var endSleepDateKey: String
    var validNightCount: Int
    var averageScore: Double?
    var averageTotalSleepTime: TimeInterval?
    var averageEfficiency: Double?
    var averageREMDuration: TimeInterval?
    var averageDeepDuration: TimeInterval?
    var averageWASO: TimeInterval?
}

nonisolated struct SleepDashboardCacheSnapshot: Codable, Hashable, Sendable {
    var sleepDateKey: String
    var generatedAt: Date
    var sessionID: UUID?
    var baseline: SleepBaseline
    var healthScore: HealthSleepScoreEstimate?
    var insights: [SleepInsight]
    var bodyClockResult: ChronotypeCalculationResult?
    var bodyClockAlignment: BodyClockSleepAlignment?
    var daySummary: SleepAggregateSummary
    var weekSummary: SleepAggregateSummary
    var monthSummary: SleepAggregateSummary

    func isStale(now: Date = Date(), ttlDays: Int = 7) -> Bool {
        now.timeIntervalSince(generatedAt) > Double(ttlDays) * 86_400
    }
}
