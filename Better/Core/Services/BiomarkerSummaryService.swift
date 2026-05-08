import Foundation

nonisolated struct BiomarkerSummaryService: Sendable {
    private let localRepository: LocalDataRepositoryProtocol
    private let healthRepository: HealthKitRepositoryProtocol
    private let calendar: Calendar

    init(
        localRepository: LocalDataRepositoryProtocol,
        healthRepository: HealthKitRepositoryProtocol,
        calendar: Calendar = .current
    ) {
        self.localRepository = localRepository
        self.healthRepository = healthRepository
        self.calendar = calendar
    }

    func summaries(now: Date = Date()) async throws -> [BiomarkerKind: [BiomarkerTimeline: BiomarkerSummary]] {
        let longest = BiomarkerTimeline.sixtyDays
        let endDate = calendar.startOfDay(for: now)
        let startDate = startDate(for: longest, endingAt: endDate)
        let paddedStart = calendar.date(byAdding: .day, value: -2, to: startDate) ?? startDate
        let paddedEnd = calendar.date(byAdding: .day, value: 1, to: endDate) ?? now

        async let sessions = localRepository.fetchCachedSessions(from: paddedStart, to: paddedEnd)
        async let rhrSamples = healthRepository.fetchBiometrics(for: .restingHeartRate, from: startDate, to: paddedEnd)

        let fetchedSessions = try await sessions
        let validSessions = fetchedSessions
            .filter { BaselineEngine.isValidNight($0, calendar: calendar) }
            .sorted { $0.sleepDateKey < $1.sleepDateKey }
        let rhr = try await rhrSamples

        var result: [BiomarkerKind: [BiomarkerTimeline: BiomarkerSummary]] = [:]
        for kind in BiomarkerKind.allCases {
            var byTimeline: [BiomarkerTimeline: BiomarkerSummary] = [:]
            for timeline in BiomarkerTimeline.allCases {
                byTimeline[timeline] = summary(
                    kind: kind,
                    timeline: timeline,
                    sessions: validSessions,
                    restingHeartRateSamples: rhr,
                    endingAt: endDate
                )
            }
            result[kind] = byTimeline
        }
        return result
    }
}

private extension BiomarkerSummaryService {
    nonisolated func summary(
        kind: BiomarkerKind,
        timeline: BiomarkerTimeline,
        sessions: [SleepSession],
        restingHeartRateSamples: [BiometricSample],
        endingAt endDate: Date
    ) -> BiomarkerSummary {
        let startDate = startDate(for: timeline, endingAt: endDate)
        let points = points(
            kind: kind,
            timeline: timeline,
            startDate: startDate,
            endDate: endDate,
            sessions: sessions,
            restingHeartRateSamples: restingHeartRateSamples
        )
        let values = points.map(\.value)

        return BiomarkerSummary(
            kind: kind,
            timeline: timeline,
            currentValue: points.last?.value,
            average: average(values),
            bestValue: bestValue(for: kind, values: values),
            minValue: values.min(),
            maxValue: values.max(),
            validSampleCount: values.count,
            expectedDayCount: timeline.rawValue,
            points: points,
            education: education(for: kind),
            calculationNote: calculationNote(for: kind, timeline: timeline)
        )
    }

    nonisolated func points(
        kind: BiomarkerKind,
        timeline: BiomarkerTimeline,
        startDate: Date,
        endDate: Date,
        sessions: [SleepSession],
        restingHeartRateSamples: [BiometricSample]
    ) -> [BiomarkerDailyPoint] {
        switch kind {
        case .restingHeartRate:
            return restingHeartRatePoints(
                samples: restingHeartRateSamples,
                startDate: startDate,
                endDate: endDate,
                timeline: timeline
            )
        case .hrv, .spo2, .respiratoryRate:
            return sessionPoints(
                kind: kind,
                sessions: sessions,
                startDate: startDate,
                endDate: endDate
            )
        }
    }

    nonisolated func sessionPoints(
        kind: BiomarkerKind,
        sessions: [SleepSession],
        startDate: Date,
        endDate: Date
    ) -> [BiomarkerDailyPoint] {
        sessions.compactMap { session in
            guard let date = SleepDateKey.date(from: session.sleepDateKey, calendar: calendar) else { return nil }
            guard date >= startDate && date <= endDate else { return nil }
            guard let value = value(for: kind, from: session) else { return nil }
            return BiomarkerDailyPoint(
                kind: kind,
                dateKey: session.sleepDateKey,
                date: date,
                value: value,
                unit: kind.unit,
                status: status(for: kind, value: value),
                source: "Sleep biometrics",
                isSelectedEligible: true
            )
        }
        .sorted { $0.date < $1.date }
    }

    nonisolated func restingHeartRatePoints(
        samples: [BiometricSample],
        startDate: Date,
        endDate: Date,
        timeline: BiomarkerTimeline
    ) -> [BiomarkerDailyPoint] {
        let grouped = Dictionary(grouping: samples) { sample in
            SleepDateKey.calendarDateKey(for: sample.endDate, calendar: calendar)
        }

        return grouped.compactMap { dateKey, daySamples in
            guard let date = SleepDateKey.date(from: dateKey, calendar: calendar) else { return nil }
            guard date >= startDate && date <= endDate else { return nil }
            guard let value = average(daySamples.map(\.value)) else { return nil }
            return BiomarkerDailyPoint(
                kind: .restingHeartRate,
                dateKey: dateKey,
                date: date,
                value: value,
                unit: BiomarkerKind.restingHeartRate.unit,
                status: status(for: .restingHeartRate, value: value),
                source: "Apple Health RHR",
                isSelectedEligible: true
            )
        }
        .sorted { $0.date < $1.date }
    }

    nonisolated func value(for kind: BiomarkerKind, from session: SleepSession) -> Double? {
        switch kind {
        case .hrv:
            session.biometrics?.hrvAverage
        case .spo2:
            session.biometrics?.oxygenSaturationAverage.map(percentValue)
        case .respiratoryRate:
            session.biometrics?.respiratoryRateAverage
        case .restingHeartRate:
            nil
        }
    }

    nonisolated func startDate(for timeline: BiomarkerTimeline, endingAt endDate: Date) -> Date {
        calendar.date(byAdding: .day, value: -(timeline.rawValue - 1), to: endDate) ?? endDate
    }

    nonisolated func average(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    nonisolated func bestValue(for kind: BiomarkerKind, values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        switch kind {
        case .hrv, .spo2:
            return values.max()
        case .restingHeartRate:
            return values.min()
        case .respiratoryRate:
            return values.min { abs($0 - 15) < abs($1 - 15) }
        }
    }

    nonisolated func percentValue(_ value: Double) -> Double {
        value <= 1 ? value * 100 : value
    }

    nonisolated func status(for kind: BiomarkerKind, value: Double) -> String {
        switch kind {
        case .restingHeartRate:
            if value <= 58 { return "Optimal" }
            if value <= 68 { return "Normal" }
            if value <= 80 { return "Fair" }
            return "Needs Attention"
        case .hrv:
            if value >= 60 { return "Optimal" }
            if value >= 40 { return "Normal" }
            if value >= 20 { return "Fair" }
            return "Needs Attention"
        case .spo2:
            if value >= 98 { return "Optimal" }
            if value >= 95 { return "Normal" }
            if value >= 93 { return "Fair" }
            return "Needs Attention"
        case .respiratoryRate:
            if value >= 14 && value <= 16 { return "Optimal" }
            if value >= 12 && value <= 18 { return "Normal" }
            if value >= 10 && value <= 20 { return "Fair" }
            return "Needs Attention"
        }
    }

    nonisolated func education(for kind: BiomarkerKind) -> String {
        switch kind {
        case .hrv:
            return "HRV reflects how well your body adapts and recovers. Higher values often align with stronger recovery readiness and lower strain."
        case .restingHeartRate:
            return "Resting heart rate reflects baseline cardiovascular load. Higher values can show strain, poor recovery, illness, or stress."
        case .spo2:
            return "SpO2 reflects overnight oxygen saturation. Stable oxygen levels support clearer sleep-breathing and recovery interpretation."
        case .respiratoryRate:
            return "Breathing rate reflects overnight respiratory rhythm. Shifts can add context for stress, illness, training load, or recovery."
        }
    }

    nonisolated func calculationNote(for kind: BiomarkerKind, timeline: BiomarkerTimeline) -> String {
        switch kind {
        case .restingHeartRate:
            return "Average, best, and range use Apple Health resting heart rate samples from the last \(timeline.rawValue) days."
        case .hrv:
            return "Average, best, and range use valid sleep nights with overnight HRV values from the last \(timeline.rawValue) days."
        case .spo2:
            return "Average, best, and range use valid sleep nights with overnight SpO2 values from the last \(timeline.rawValue) days."
        case .respiratoryRate:
            return "Average, best, and range use valid sleep nights with breathing-rate values from the last \(timeline.rawValue) days."
        }
    }
}
