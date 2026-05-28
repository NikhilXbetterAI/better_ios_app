import Foundation

enum SleepVerdict: Sendable, Hashable {
    case better
    case usual
    case harder

    var headline: String {
        switch self {
        case .better: return "Last night was better than your usual sleep."
        case .usual:  return "Last night was about usual."
        case .harder: return "Last night was harder than usual."
        }
    }
}

enum SleepRowStatus: Sendable, Hashable {
    case moreThanUsual
    case aboutUsual
    case lessThanUsual
    case fewerWakeUps

    var label: String {
        switch self {
        case .moreThanUsual: return "More than usual"
        case .aboutUsual:    return "About usual"
        case .lessThanUsual: return "Less than usual"
        case .fewerWakeUps:  return "Fewer wake-ups"
        }
    }
}

enum SleepUsualComparison {
    /// A row is "about usual" when |value - average| is less than half a SD.
    /// Falls back to a 10 % band if SD is 0 (small samples).
    static func rowStatus(
        value: Double,
        baselineAverage: Double,
        baselineStdDev: Double,
        lowerIsBetter: Bool,
        isAwakeMetric: Bool = false
    ) -> SleepRowStatus {
        let band = baselineStdDev > 0 ? baselineStdDev * 0.5 : max(abs(baselineAverage) * 0.10, 1)
        let diff = value - baselineAverage
        if abs(diff) < band { return .aboutUsual }
        if diff > 0 {
            return isAwakeMetric ? .moreThanUsual : .moreThanUsual
        } else {
            return isAwakeMetric ? .fewerWakeUps : .lessThanUsual
        }
    }

    /// Status color rule: for higher-is-better metrics, "more" = good and
    /// "less" = bad. For lower-is-better metrics it inverts. Returned as a
    /// semantic tag so the view can pick the design-system color.
    static func isFavorable(
        status: SleepRowStatus,
        lowerIsBetter: Bool
    ) -> Bool? {
        switch status {
        case .aboutUsual: return nil
        case .moreThanUsual: return !lowerIsBetter
        case .lessThanUsual, .fewerWakeUps: return lowerIsBetter
        }
    }

    /// Classify the night vs the baseline. Combines total-sleep, deep, REM,
    /// awake, and latency deltas — each normalized by its baseline SD.
    static func classify(session: SleepSession, baseline: SleepBaseline) -> SleepVerdict {
        func norm(_ value: Double, mean: Double, sd: Double) -> Double {
            let band = sd > 0 ? sd : max(abs(mean) * 0.10, 1)
            return (value - mean) / band
        }

        let total = norm(session.totalSleepTime, mean: baseline.totalSleepAverage, sd: baseline.totalSleepStandardDeviation)
        let deep  = norm(session.deepDuration,   mean: baseline.deepAverage,       sd: baseline.deepStandardDeviation)
        let rem   = norm(session.remDuration,    mean: baseline.remAverage,        sd: baseline.remStandardDeviation)
        let awake = norm(session.awakeDuration,  mean: baseline.wasoAverage,       sd: baseline.wasoStandardDeviation)
        let latency = norm(session.sleepLatency, mean: baseline.latencyAverage,    sd: baseline.latencyStandardDeviation)

        // Weighted score: total carries most weight; awake & latency subtract.
        let score = (total * 0.4) + (deep * 0.25) + (rem * 0.25) - (awake * 0.2) - (latency * 0.1)

        if score > 0.5 { return .better }
        if score < -0.5 { return .harder }
        return .usual
    }
}
