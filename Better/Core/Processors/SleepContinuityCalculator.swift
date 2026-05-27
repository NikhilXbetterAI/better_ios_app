import Foundation

nonisolated enum SleepContinuityCalculator {
    static let ignoredAwakeThreshold: TimeInterval = 180
    static let meaningfulAwakeThreshold: TimeInterval = 300

    static func summary(for stages: [SleepStage]) -> SleepContinuitySummary {
        var blocks: [SleepContinuityBlock] = []
        var meaningfulAwakeningCount = 0

        var currentStart: Date?
        var currentEnd: Date?
        var currentSleepDuration: TimeInterval = 0
        var currentShortAwakeDuration: TimeInterval = 0
        var currentShortAwakeningCount = 0

        func closeCurrentBlock(at endDate: Date? = nil) {
            guard
                let start = currentStart,
                let lastEnd = currentEnd,
                currentSleepDuration > 0
            else {
                currentStart = nil
                currentEnd = nil
                currentSleepDuration = 0
                currentShortAwakeDuration = 0
                currentShortAwakeningCount = 0
                return
            }

            blocks.append(
                SleepContinuityBlock(
                    index: blocks.count + 1,
                    startDate: start,
                    endDate: max(start, endDate ?? lastEnd),
                    sleepDuration: currentSleepDuration,
                    includedShortAwakeDuration: currentShortAwakeDuration,
                    shortAwakeningCount: currentShortAwakeningCount
                )
            )

            currentStart = nil
            currentEnd = nil
            currentSleepDuration = 0
            currentShortAwakeDuration = 0
            currentShortAwakeningCount = 0
        }

        let stagesForAnalysis = normalizedStages(stages)
        for (stageIndex, stage) in stagesForAnalysis.enumerated() {
            switch stage.type {
            case .inBed:
                continue
            case .awake:
                guard currentStart != nil else { continue }
                let awakeDuration = stage.endDate.timeIntervalSince(stage.startDate)
                if awakeDuration >= meaningfulAwakeThreshold {
                    if hasFutureSleepStage(after: stageIndex, in: stagesForAnalysis) {
                        closeCurrentBlock(at: stage.startDate)
                        meaningfulAwakeningCount += 1
                    } else {
                        currentEnd = max(currentEnd ?? stage.startDate, stage.startDate)
                    }
                } else {
                    if awakeDuration >= ignoredAwakeThreshold {
                        currentShortAwakeningCount += 1
                        currentShortAwakeDuration += awakeDuration
                    }
                    currentEnd = max(currentEnd ?? stage.endDate, stage.endDate)
                }
            case .unspecified, .core, .deep, .rem:
                if let end = currentEnd, stage.startDate > end {
                    let gapDuration = stage.startDate.timeIntervalSince(end)
                    if gapDuration >= meaningfulAwakeThreshold {
                        closeCurrentBlock()
                        meaningfulAwakeningCount += 1
                    } else if gapDuration >= ignoredAwakeThreshold {
                        currentShortAwakeningCount += 1
                        currentShortAwakeDuration += gapDuration
                    }
                }

                if currentStart == nil {
                    currentStart = stage.startDate
                    currentEnd = stage.startDate
                }

                let contributionStart = max(stage.startDate, currentEnd ?? stage.startDate)
                let contribution = max(0, stage.endDate.timeIntervalSince(contributionStart))
                currentSleepDuration += contribution
                currentEnd = max(currentEnd ?? stage.endDate, stage.endDate)
            }
        }

        closeCurrentBlock()

        guard let longest = blocks.max(by: { $0.sleepDuration < $1.sleepDuration }) else {
            return .unavailable
        }

        return SleepContinuitySummary(
            blocks: blocks,
            longestBlockDuration: longest.sleepDuration,
            longestBlockIndex: longest.index,
            meaningfulAwakeningCount: meaningfulAwakeningCount,
            continuityCategory: category(for: longest.sleepDuration),
            longestBlock: longest
        )
    }

    static func category(for duration: TimeInterval) -> SleepContinuityCategory {
        guard duration > 0 else { return .unavailable }
        switch duration {
        case let value where value > 5 * 3_600:
            return .exceptional
        case 4 * 3_600...5 * 3_600:
            return .strong
        case 3 * 3_600..<4 * 3_600:
            return .good
        case 2 * 3_600..<3 * 3_600:
            return .moderatelyFragmented
        default:
            return .highlyFragmented
        }
    }
}

nonisolated private extension SleepContinuityCalculator {
    static func normalizedStages(_ stages: [SleepStage]) -> [SleepStage] {
        let sorted = stages
            .filter { $0.endDate > $0.startDate }
            .sorted {
                if $0.startDate == $1.startDate {
                    return $0.endDate < $1.endDate
                }
                return $0.startDate < $1.startDate
            }

        var normalized: [SleepStage] = []
        for stage in sorted {
            guard var previous = normalized.popLast() else {
                normalized.append(stage)
                continue
            }

            if previous.type == stage.type, stage.startDate <= previous.endDate {
                previous.endDate = max(previous.endDate, stage.endDate)
                normalized.append(previous)
            } else {
                normalized.append(previous)
                normalized.append(stage)
            }
        }

        return normalized
    }

    static func hasFutureSleepStage(after index: Int, in stages: [SleepStage]) -> Bool {
        stages.dropFirst(index + 1).contains { stage in
            switch stage.type {
            case .unspecified, .core, .deep, .rem:
                true
            case .inBed, .awake:
                false
            }
        }
    }
}
