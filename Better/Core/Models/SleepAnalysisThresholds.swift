import Foundation

nonisolated enum SleepAnalysisThresholds {
    static let meaningfulDurationDelta: TimeInterval = 20 * 60
    static let meaningfulEfficiencyDelta: Double = 0.03
    static let meaningfulStageDelta: TimeInterval = 10 * 60
    static let meaningfulAwakeDelta: TimeInterval = 10 * 60
}
