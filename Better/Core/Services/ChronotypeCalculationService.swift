import Foundation

nonisolated struct ChronotypeCalculationService: Sendable {
    static let minimumWindowDays = 30
    static let maximumWindowDays = 90
    static let minimumValidSleepDuration: TimeInterval = 3 * 3_600
    static let maximumValidSleepDuration: TimeInterval = 12 * 3_600
    static let minimumTotalNights = 14
    static let minimumWorkdayNights = 6
    static let minimumFreeDayNights = 3
    static let stableBodyClockNightCount = 30

    func estimate(
        sessions: [SleepSession],
        contextEntries: [SleepContextEntry],
        activityLogs: [ActivityStatusLog],
        windowDays: Int = 90,
        endingAt: Date = Date(),
        calendar: Calendar = .current
    ) -> ChronotypeCalculationResult {
        let clampedWindowDays = Self.clamp(windowDays, lower: Self.minimumWindowDays, upper: Self.maximumWindowDays)
        let windowStart = calendar.date(byAdding: .day, value: -clampedWindowDays, to: endingAt) ?? endingAt
        let contextByDateKey = Dictionary(grouping: contextEntries, by: \.sleepDateKey)
        let activityByDateKey = Dictionary(grouping: activityLogs, by: \.dateKey)

        var includedNights: [ChronotypeNight] = []
        var excludedCountsByReason: [ChronotypeExclusionReason: Int] = [:]
        var candidateCount = 0

        for session in sessions {
            let onsetCandidate = onsetCandidate(for: session)
            guard onsetCandidate >= windowStart && onsetCandidate <= endingAt else { continue }
            candidateCount += 1

            guard let timing = timing(for: session) else {
                excludedCountsByReason[.invalidTiming, default: 0] += 1
                continue
            }

            if let exclusionReason = exclusionReason(
                for: session,
                timing: timing,
                contextEntries: contextByDateKey[session.sleepDateKey] ?? [],
                activityLogs: activityByDateKey[session.sleepDateKey] ?? [],
                calendar: calendar
            ) {
                excludedCountsByReason[exclusionReason, default: 0] += 1
                continue
            }

            let midpoint = timing.onset.addingTimeInterval(session.totalSleepTime / 2)
            let midpointMinute = Self.minuteOfDay(for: midpoint, calendar: calendar)
            includedNights.append(
                ChronotypeNight(
                    sleepDateKey: session.sleepDateKey,
                    dayType: Self.dayType(forOnset: timing.onset, calendar: calendar),
                    onset: timing.onset,
                    wake: timing.wake,
                    duration: session.totalSleepTime,
                    midpointMinute: midpointMinute
                )
            )
        }

        includedNights.sort { $0.onset < $1.onset }

        let workdayNights = includedNights.filter { $0.dayType == .workday }
        let freeDayNights = includedNights.filter { $0.dayType == .freeDay }
        let missingRequirements = Self.missingRequirements(
            validNightCount: includedNights.count,
            workdayNightCount: workdayNights.count,
            freeDayNightCount: freeDayNights.count
        )

        guard missingRequirements.isEmpty,
              let workdayMidpointMinute = Self.circularMedianMinute(workdayNights.map(\.midpointMinute)),
              let freeDayMidpointMinute = Self.circularMedianMinute(freeDayNights.map(\.midpointMinute)),
              let workdayMedianDuration = Self.median(workdayNights.map(\.duration)),
              let freeDayMedianDuration = Self.median(freeDayNights.map(\.duration))
        else {
            return ChronotypeCalculationResult(
                status: .insufficientData,
                estimate: nil,
                includedNights: includedNights,
                excludedCountsByReason: excludedCountsByReason,
                totalCandidateNightCount: candidateCount,
                validNightCount: includedNights.count,
                workdayNightCount: workdayNights.count,
                freeDayNightCount: freeDayNights.count,
                missingRequirements: missingRequirements,
                windowDays: clampedWindowDays,
                windowStart: windowStart,
                windowEnd: endingAt
            )
        }

        let weeklyAverageDuration = ((5 * workdayMedianDuration) + (2 * freeDayMedianDuration)) / 7
        let correctedMidpointMinute: Int
        if freeDayMedianDuration > workdayMedianDuration {
            let correctionMinutes = ((freeDayMedianDuration - weeklyAverageDuration) / 2) / 60
            correctedMidpointMinute = Self.normalizeMinute(Double(freeDayMidpointMinute) - correctionMinutes)
        } else {
            correctedMidpointMinute = freeDayMidpointMinute
        }

        let confidence = Self.confidence(
            validNightCount: includedNights.count,
            freeDayNightCount: freeDayNights.count,
            excludedNightCount: excludedCountsByReason.values.reduce(0, +),
            candidateNightCount: candidateCount
        )
        let readiness = Self.bodyClockReadiness(validNightCount: includedNights.count, confidence: confidence)
        let caveats = Self.bodyClockCaveats(
            validNightCount: includedNights.count,
            freeDayNightCount: freeDayNights.count,
            excludedCountsByReason: excludedCountsByReason,
            candidateNightCount: candidateCount
        )
        let estimate = ChronotypeEstimate(
            bucket: Self.bucket(for: correctedMidpointMinute),
            correctedMidpointMinute: correctedMidpointMinute,
            workdayMidpointMinute: workdayMidpointMinute,
            freeDayMidpointMinute: freeDayMidpointMinute,
            workdayMedianDuration: workdayMedianDuration,
            freeDayMedianDuration: freeDayMedianDuration,
            weeklyAverageDuration: weeklyAverageDuration,
            validNightCount: includedNights.count,
            workdayNightCount: workdayNights.count,
            freeDayNightCount: freeDayNights.count,
            excludedNightCount: excludedCountsByReason.values.reduce(0, +),
            excludedCountsByReason: excludedCountsByReason,
            confidence: confidence,
            bodyClockReadiness: readiness,
            bodyClockCaveats: caveats,
            optimalSleepWindow: Self.sleepWindow(centerMinute: correctedMidpointMinute, duration: weeklyAverageDuration)
        )

        return ChronotypeCalculationResult(
            status: .estimated,
            estimate: estimate,
            includedNights: includedNights,
            excludedCountsByReason: excludedCountsByReason,
            totalCandidateNightCount: candidateCount,
            validNightCount: includedNights.count,
            workdayNightCount: workdayNights.count,
            freeDayNightCount: freeDayNights.count,
            missingRequirements: [],
            windowDays: clampedWindowDays,
            windowStart: windowStart,
            windowEnd: endingAt
        )
    }

    func alignment(
        for session: SleepSession,
        estimate: ChronotypeEstimate,
        calendar: Calendar = .current
    ) -> BodyClockSleepAlignment? {
        guard let timing = timing(for: session) else { return nil }
        let midpoint = timing.onset.addingTimeInterval(session.totalSleepTime / 2)
        let actualMidpointMinute = Self.minuteOfDay(for: midpoint, calendar: calendar)
        return alignment(actualMidpointMinute: actualMidpointMinute, estimate: estimate)
    }

    func alignment(
        for night: ChronotypeNight,
        estimate: ChronotypeEstimate
    ) -> BodyClockSleepAlignment {
        alignment(actualMidpointMinute: night.midpointMinute, estimate: estimate)
    }

    private func alignment(
        actualMidpointMinute: Int,
        estimate: ChronotypeEstimate
    ) -> BodyClockSleepAlignment {
        let signedDeltaMinutes = Self.signedCircularDelta(
            from: estimate.correctedMidpointMinute,
            to: actualMidpointMinute
        )

        return BodyClockSleepAlignment(
            actualMidpointMinute: actualMidpointMinute,
            targetMidpointMinute: estimate.correctedMidpointMinute,
            signedDeltaMinutes: signedDeltaMinutes,
            category: Self.alignmentCategory(for: signedDeltaMinutes)
        )
    }

    private func onsetCandidate(for session: SleepSession) -> Date {
        session.stages
            .filter { $0.type.isSleep }
            .map(\.startDate)
            .min() ?? session.startDate
    }

    private func timing(for session: SleepSession) -> (onset: Date, wake: Date)? {
        let sleepStages = session.stages
            .filter { $0.type.isSleep }
            .sorted { $0.startDate < $1.startDate }

        let onset = sleepStages.first?.startDate ?? session.startDate
        let wake = sleepStages.map(\.endDate).max() ?? session.endDate

        guard onset < wake else { return nil }
        guard session.startDate < session.endDate else { return nil }
        guard session.totalSleepTime > 0 else { return nil }

        return (onset, wake)
    }

    private func exclusionReason(
        for session: SleepSession,
        timing: (onset: Date, wake: Date),
        contextEntries: [SleepContextEntry],
        activityLogs: [ActivityStatusLog],
        calendar: Calendar
    ) -> ChronotypeExclusionReason? {
        guard session.totalSleepTime >= Self.minimumValidSleepDuration else { return .tooShort }
        guard session.totalSleepTime <= Self.maximumValidSleepDuration else { return .tooLong }
        guard session.dataQuality != .inBedOnly && session.dataQuality != .noData else { return .poorDataQuality }
        guard session.dataQuality != .unspecifiedSleepOnly || Self.hasWearableSource(session.sources) else {
            return .poorDataQuality
        }
        guard SleepDateKey.date(from: session.sleepDateKey, calendar: calendar) != nil else { return .invalidTiming }
        guard timing.onset < timing.wake && session.startDate < session.endDate else { return .invalidTiming }
        guard session.totalSleepTime > 0 else { return .invalidTiming }

        if contextEntries.contains(where: { $0.travel == true }) {
            return .travelOrJetLag
        }

        if activityLogs.contains(where: { $0.status == .traveling || $0.status == .jetLagged }) {
            return .travelOrJetLag
        }

        return nil
    }

    private static func hasWearableSource(_ sources: [SleepSource]) -> Bool {
        sources.contains { source in
            guard !source.isManualEntry else { return false }

            if source.productType?.isEmpty == false {
                return true
            }

            let bundleIdentifier = source.bundleIdentifier?.lowercased() ?? ""
            return bundleIdentifier.contains("watch")
                || bundleIdentifier.contains("fitbit")
                || bundleIdentifier.contains("oura")
                || bundleIdentifier.contains("garmin")
                || bundleIdentifier.contains("whoop")
        }
    }

    private static func missingRequirements(
        validNightCount: Int,
        workdayNightCount: Int,
        freeDayNightCount: Int
    ) -> [ChronotypeMinimumRequirement] {
        var requirements: [ChronotypeMinimumRequirement] = []
        if validNightCount < minimumTotalNights { requirements.append(.totalNights) }
        if workdayNightCount < minimumWorkdayNights { requirements.append(.workdayNights) }
        if freeDayNightCount < minimumFreeDayNights { requirements.append(.freeDayNights) }
        return requirements
    }

    private static func confidence(
        validNightCount: Int,
        freeDayNightCount: Int,
        excludedNightCount: Int,
        candidateNightCount: Int
    ) -> ComparisonConfidence {
        let excludedRatio = candidateNightCount > 0 ? Double(excludedNightCount) / Double(candidateNightCount) : 0

        if validNightCount >= 45 && freeDayNightCount >= 8 && excludedRatio < 0.2 {
            return .high
        }

        if validNightCount >= 21 && freeDayNightCount >= 5 {
            return .medium
        }

        return .low
    }

    private static func bodyClockReadiness(
        validNightCount: Int,
        confidence: ComparisonConfidence
    ) -> BodyClockReadiness {
        if confidence == .high && validNightCount >= stableBodyClockNightCount {
            return .highConfidence
        }

        if validNightCount >= stableBodyClockNightCount {
            return .stable
        }

        return .preview
    }

    private static func bodyClockCaveats(
        validNightCount: Int,
        freeDayNightCount: Int,
        excludedCountsByReason: [ChronotypeExclusionReason: Int],
        candidateNightCount: Int
    ) -> [BodyClockCaveat] {
        var caveats: [BodyClockCaveat] = []
        let excludedCount = excludedCountsByReason.values.reduce(0, +)
        let excludedRatio = candidateNightCount > 0 ? Double(excludedCount) / Double(candidateNightCount) : 0

        if freeDayNightCount < 5 { caveats.append(.fewFreeDays) }
        if excludedRatio >= 0.2 { caveats.append(.highExclusionRate) }
        if validNightCount < stableBodyClockNightCount { caveats.append(.previewOnly) }
        if (excludedCountsByReason[.travelOrJetLag] ?? 0) > 0 { caveats.append(.travelRecentlyExcluded) }

        return caveats
    }

    private static func alignmentCategory(for signedDeltaMinutes: Int) -> BodyClockAlignmentCategory {
        let absoluteDelta = abs(signedDeltaMinutes)

        if absoluteDelta <= 30 {
            return .aligned
        }

        if signedDeltaMinutes < 0 {
            return absoluteDelta <= 75 ? .slightlyEarly : .early
        }

        return absoluteDelta <= 75 ? .slightlyLate : .late
    }

    private static func dayType(forOnset onset: Date, calendar: Calendar) -> ChronotypeDayType {
        switch calendar.component(.weekday, from: onset) {
        case 1...5:
            return .workday
        default:
            return .freeDay
        }
    }

    private static func bucket(for correctedMidpointMinute: Int) -> ChronotypeBucket {
        switch correctedMidpointMinute {
        case ..<180:
            return .early
        case 180..<240:
            return .earlyIntermediate
        case 240..<300:
            return .intermediate
        case 300..<360:
            return .lateIntermediate
        default:
            return .late
        }
    }

    private static func sleepWindow(centerMinute: Int, duration: TimeInterval) -> SleepWindowRecommendation {
        let roundedDuration = (duration / 900).rounded() * 900
        let halfDurationMinutes = roundedDuration / 120
        return SleepWindowRecommendation(
            startMinute: normalizeMinute(Double(centerMinute) - halfDurationMinutes),
            endMinute: normalizeMinute(Double(centerMinute) + halfDurationMinutes),
            duration: roundedDuration
        )
    }

    private static func median(_ values: [TimeInterval]) -> TimeInterval? {
        guard !values.isEmpty else { return nil }
        let sortedValues = values.sorted()
        let middle = sortedValues.count / 2

        if sortedValues.count.isMultiple(of: 2) {
            return (sortedValues[middle - 1] + sortedValues[middle]) / 2
        }

        return sortedValues[middle]
    }

    private static func circularMedianMinute(_ minutes: [Int]) -> Int? {
        guard !minutes.isEmpty else { return nil }
        let anchor = circularMeanMinute(minutes)
        let unwrapped = minutes.map { minute -> Double in
            var value = Double(minute)
            while value - anchor > 720 { value -= 1_440 }
            while anchor - value > 720 { value += 1_440 }
            return value
        }

        guard let median = median(unwrapped) else { return nil }
        return normalizeMinute(median)
    }

    private static func circularMeanMinute(_ minutes: [Int]) -> Double {
        guard !minutes.isEmpty else { return 0 }

        let angles = minutes.map { Double($0) / 1_440 * 2 * Double.pi }
        let sine = angles.map(sin).reduce(0, +) / Double(angles.count)
        let cosine = angles.map(cos).reduce(0, +) / Double(angles.count)
        var angle = atan2(sine, cosine)
        if angle < 0 { angle += 2 * Double.pi }

        return angle / (2 * Double.pi) * 1_440
    }

    private static func minuteOfDay(for date: Date, calendar: Calendar) -> Int {
        let components = calendar.dateComponents([.hour, .minute, .second], from: date)
        let seconds = ((components.hour ?? 0) * 3_600) + ((components.minute ?? 0) * 60) + (components.second ?? 0)
        return normalizeMinute(Double(seconds) / 60)
    }

    private static func normalizeMinute(_ minute: Double) -> Int {
        let normalized = minute.truncatingRemainder(dividingBy: 1_440)
        let positive = normalized < 0 ? normalized + 1_440 : normalized
        return Int(positive.rounded()) % 1_440
    }

    private static func signedCircularDelta(from targetMinute: Int, to actualMinute: Int) -> Int {
        var delta = actualMinute - targetMinute
        while delta > 720 { delta -= 1_440 }
        while delta < -720 { delta += 1_440 }
        return delta
    }

    private static func clamp(_ value: Int, lower: Int, upper: Int) -> Int {
        min(max(value, lower), upper)
    }
}
