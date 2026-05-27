import Foundation
import OSLog

nonisolated struct BaselineSelection: Codable, Hashable, Sendable {
    var activeBaseline: SleepBaseline?
    var recentBaseline: SleepBaseline?
    var primaryBaseline: SleepBaseline?
    var stableBaseline: SleepBaseline?
    var confidence: ComparisonConfidence
    var validNightCount: Int
    var excludedNightCount: Int
    var windowUsed: Int?
    var isBuilding: Bool { activeBaseline == nil }

    var allBaselines: [SleepBaseline] {
        [stableBaseline, primaryBaseline, recentBaseline].compactMap { $0 }
    }
}

nonisolated struct BaselineEngine: Sendable {
    static let minimumValidSleepDuration: TimeInterval = 2 * 3_600
    static let maximumValidSleepDuration: TimeInterval = 14 * 3_600

    // Sleep dashboard uses a separate 30/60 window selector. See CLAUDE.md
    // invariant #3 — Trends / Protocol / Research / CSV still use the 14/7 path.
    static let dashboardPrimaryWindow = 30
    static let dashboardFallbackWindow = 60
    static let dashboardMinimumValidNights = 5

    private let processor: SleepDataProcessor
    private let calendar: Calendar
    private let logger = Logger(subsystem: "Better", category: "BaselineEngine")

    init(
        processor: SleepDataProcessor,
        calendar: Calendar = .current
    ) {
        self.processor = processor
        self.calendar = calendar
    }

    func selectBaseline(
        from sessions: [SleepSession],
        generatedAt: Date = Date()
    ) -> BaselineSelection {
        let evaluated = sessions.map { ($0, Self.isValidNight($0, calendar: calendar)) }
        let validSessions = evaluated
            .filter(\.1)
            .map(\.0)
            .sorted { $0.sleepDateKey < $1.sleepDateKey }
        let excludedCount = evaluated.count - validSessions.count

        let stableSessions = Array(validSessions.suffix(30))
        let primarySessions = Array(validSessions.suffix(14))
        let recentSessions = Array(validSessions.suffix(7))

        let stable = stableSessions.isEmpty ? nil : processor.computeBaseline(
            from: stableSessions,
            windowDays: 30,
            generatedAt: generatedAt
        )
        let primary = primarySessions.count >= 14 ? processor.computeBaseline(
            from: primarySessions,
            windowDays: 14,
            generatedAt: generatedAt
        ) : nil
        let recent = recentSessions.count >= 7 ? processor.computeBaseline(
            from: recentSessions,
            windowDays: 7,
            generatedAt: generatedAt
        ) : nil
        let active = primary ?? recent
        let confidence = Self.confidence(validNightCount: validSessions.count)

        logger.debug(
            "Baseline selected window=\(active?.windowDays ?? 0, privacy: .public) valid=\(validSessions.count, privacy: .public) excluded=\(excludedCount, privacy: .public)"
        )

        return BaselineSelection(
            activeBaseline: active,
            recentBaseline: recent,
            primaryBaseline: primary,
            stableBaseline: stable,
            confidence: confidence,
            validNightCount: validSessions.count,
            excludedNightCount: excludedCount,
            windowUsed: active?.windowDays
        )
    }

    /// Sleep-dashboard-only baseline selector: 30-day primary, 60-day fallback,
    /// requires ≥ 5 valid nights in either window. Caller is expected to pass
    /// sessions covering at least the last 60 days before `generatedAt`.
    func selectDashboardBaseline(
        from sessions: [SleepSession],
        generatedAt: Date = Date()
    ) -> BaselineSelection {
        let evaluated = sessions.map { ($0, Self.isValidNight($0, calendar: calendar)) }
        let validSessions = evaluated
            .filter(\.1)
            .map(\.0)
            .sorted { $0.sleepDateKey < $1.sleepDateKey }
        let excludedCount = evaluated.count - validSessions.count

        let cutoff30 = calendar.date(byAdding: .day, value: -Self.dashboardPrimaryWindow, to: generatedAt) ?? generatedAt
        let cutoff60 = calendar.date(byAdding: .day, value: -Self.dashboardFallbackWindow, to: generatedAt) ?? generatedAt

        func inWindow(_ session: SleepSession, since cutoff: Date) -> Bool {
            guard let date = SleepDateKey.date(from: session.sleepDateKey, calendar: calendar) else { return false }
            return date >= cutoff
        }

        let in30 = validSessions.filter { inWindow($0, since: cutoff30) }
        let in60 = validSessions.filter { inWindow($0, since: cutoff60) }

        let primary: SleepBaseline? = in30.count >= Self.dashboardMinimumValidNights
            ? processor.computeBaseline(from: in30, windowDays: Self.dashboardPrimaryWindow, generatedAt: generatedAt)
            : nil
        let fallback: SleepBaseline? = (primary == nil && in60.count >= Self.dashboardMinimumValidNights)
            ? processor.computeBaseline(from: in60, windowDays: Self.dashboardFallbackWindow, generatedAt: generatedAt)
            : nil

        let active = primary ?? fallback
        let confidence = Self.confidence(validNightCount: validSessions.count)

        logger.debug(
            "Dashboard baseline selected window=\(active?.windowDays ?? 0, privacy: .public) in30=\(in30.count, privacy: .public) in60=\(in60.count, privacy: .public)"
        )

        return BaselineSelection(
            activeBaseline: active,
            recentBaseline: nil,
            primaryBaseline: primary,
            stableBaseline: fallback,
            confidence: confidence,
            validNightCount: validSessions.count,
            excludedNightCount: excludedCount,
            windowUsed: active?.windowDays
        )
    }

    static func isValidNight(_ session: SleepSession, calendar: Calendar = .current) -> Bool {
        guard SleepDateKey.date(from: session.sleepDateKey, calendar: calendar) != nil else { return false }
        guard session.totalSleepTime > minimumValidSleepDuration else { return false }
        guard session.totalSleepTime <= maximumValidSleepDuration else { return false }
        guard session.totalInBedTime >= session.totalSleepTime else { return false }
        guard session.dataQuality != .inBedOnly && session.dataQuality != .noData else { return false }
        guard session.startDate < session.endDate else { return false }

        let durations = [
            session.totalInBedTime,
            session.totalSleepTime,
            session.awakeDuration,
            session.coreDuration,
            session.deepDuration,
            session.remDuration,
            session.unspecifiedSleepDuration,
            session.sleepLatency,
            session.waso
        ]
        guard durations.allSatisfy({ $0 >= 0 }) else { return false }
        guard session.efficiency >= 0 && session.efficiency <= 1 else { return false }

        return true
    }

    static func confidence(validNightCount: Int) -> ComparisonConfidence {
        switch validNightCount {
        case 14...:
            return .high
        case 7...13:
            return .medium
        case 3...6:
            return .low
        default:
            return .unavailable
        }
    }
}
