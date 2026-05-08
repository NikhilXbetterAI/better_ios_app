import Foundation

nonisolated enum BiometricType: String, Codable, CaseIterable, Hashable, Sendable, Identifiable {
    case heartRate
    case heartRateVariabilitySDNN
    case oxygenSaturation
    case respiratoryRate
    case restingHeartRate
    case vo2Max
    case bodyMass
    case leanBodyMass
    case bodyFatPercentage
    case bodyTemperature
    case stepCount
    case activeEnergyBurned
    case appleExerciseTime
    case appleStandTime
    case flightsClimbed
    case distanceWalkingRunning

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .heartRate:
            "Heart Rate"
        case .heartRateVariabilitySDNN:
            "HRV"
        case .oxygenSaturation:
            "Oxygen Saturation"
        case .respiratoryRate:
            "Respiratory Rate"
        case .restingHeartRate:
            "Resting Heart Rate"
        case .vo2Max:
            "VO2 Max"
        case .bodyMass:
            "Weight"
        case .leanBodyMass:
            "Lean Body Mass"
        case .bodyFatPercentage:
            "Body Fat"
        case .bodyTemperature:
            "Body Temperature"
        case .stepCount:
            "Steps"
        case .activeEnergyBurned:
            "Active Energy"
        case .appleExerciseTime:
            "Exercise"
        case .appleStandTime:
            "Stand"
        case .flightsClimbed:
            "Flights"
        case .distanceWalkingRunning:
            "Walking + Running"
        }
    }

    var unitSymbol: String {
        switch self {
        case .heartRate, .respiratoryRate, .restingHeartRate:
            "count/min"
        case .heartRateVariabilitySDNN:
            "ms"
        case .oxygenSaturation:
            "%"
        case .vo2Max:
            "mL/kg/min"
        case .bodyMass, .leanBodyMass:
            "kg"
        case .bodyFatPercentage:
            "%"
        case .bodyTemperature:
            "degC"
        case .stepCount, .flightsClimbed:
            "count"
        case .activeEnergyBurned:
            "kcal"
        case .appleExerciseTime, .appleStandTime:
            "min"
        case .distanceWalkingRunning:
            "m"
        }
    }
}

nonisolated struct BiometricSample: Codable, Hashable, Sendable, Identifiable {
    var id: UUID
    var type: BiometricType
    var value: Double
    var unit: String
    var startDate: Date
    var endDate: Date
    var source: SleepSource?

    init(
        id: UUID = UUID(),
        type: BiometricType,
        value: Double,
        unit: String,
        startDate: Date,
        endDate: Date,
        source: SleepSource? = nil
    ) {
        self.id = id
        self.type = type
        self.value = value
        self.unit = unit
        self.startDate = startDate
        self.endDate = endDate
        self.source = source
    }
}

nonisolated enum BiologyMetricKind: String, Codable, CaseIterable, Hashable, Sendable, Identifiable {
    case vo2Max
    case hrvBaseline
    case restingHeartRateBaseline
    case weight
    case leanBodyMass
    case bodyFatPercentage
    case bloodOxygen
    case respiratoryRate
    case bodyTemperature

    var id: String { rawValue }
}

nonisolated struct BiologyMetric: Codable, Hashable, Sendable, Identifiable {
    var id: BiologyMetricKind { kind }
    var kind: BiologyMetricKind
    var title: String
    var value: Double?
    var unit: String
    var rating: String
    var trend: String
    var history: [Double]
    /// `true` when the value came from a user-entered manual entry rather than Apple Health.
    var isManualEntry: Bool

    init(
        kind: BiologyMetricKind,
        title: String,
        value: Double?,
        unit: String,
        rating: String,
        trend: String = "Stable",
        history: [Double] = [],
        isManualEntry: Bool = false
    ) {
        self.kind = kind
        self.title = title
        self.value = value
        self.unit = unit
        self.rating = rating
        self.trend = trend
        self.history = history
        self.isManualEntry = isManualEntry
    }
}

nonisolated enum BiomarkerKind: String, Codable, CaseIterable, Hashable, Sendable, Identifiable {
    case hrv
    case restingHeartRate
    case spo2
    case respiratoryRate

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .hrv:
            "HRV"
        case .restingHeartRate:
            "RHR"
        case .spo2:
            "SpO2"
        case .respiratoryRate:
            "Breath"
        }
    }

    var fullName: String {
        switch self {
        case .hrv:
            "Heart rate variability"
        case .restingHeartRate:
            "Resting heart rate"
        case .spo2:
            "Blood oxygen"
        case .respiratoryRate:
            "Respiratory rate"
        }
    }

    var unit: String {
        switch self {
        case .hrv:
            "ms"
        case .restingHeartRate:
            "bpm"
        case .spo2:
            "%"
        case .respiratoryRate:
            "br/min"
        }
    }

    var healthKitType: BiometricType? {
        switch self {
        case .restingHeartRate:
            .restingHeartRate
        case .hrv, .spo2, .respiratoryRate:
            nil
        }
    }
}

nonisolated enum BiomarkerTimeline: Int, Codable, CaseIterable, Hashable, Sendable, Identifiable {
    case sevenDays = 7
    case thirtyDays = 30
    case sixtyDays = 60

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .sevenDays:
            "7D"
        case .thirtyDays:
            "30D"
        case .sixtyDays:
            "60D"
        }
    }

    var description: String {
        "\(rawValue)-day"
    }
}

nonisolated struct BiomarkerDailyPoint: Codable, Hashable, Sendable, Identifiable {
    var id: String { "\(kind.rawValue)-\(dateKey)" }
    var kind: BiomarkerKind
    var dateKey: String
    var date: Date
    var value: Double
    var unit: String
    var status: String
    var source: String
    var isSelectedEligible: Bool
}

nonisolated struct BiomarkerSummary: Codable, Hashable, Sendable, Identifiable {
    var id: String { "\(kind.rawValue)-\(timeline.rawValue)" }
    var kind: BiomarkerKind
    var timeline: BiomarkerTimeline
    var currentValue: Double?
    var average: Double?
    var bestValue: Double?
    var minValue: Double?
    var maxValue: Double?
    var validSampleCount: Int
    var expectedDayCount: Int
    var points: [BiomarkerDailyPoint]
    var education: String
    var calculationNote: String
}

nonisolated struct ActivityMetricSummary: Codable, Hashable, Sendable {
    var steps: Double?
    var activeEnergy: Double?
    var exerciseMinutes: Double?
    var standHours: Double?
    var flights: Double?
    var distanceMeters: Double?

    init(
        steps: Double? = nil,
        activeEnergy: Double? = nil,
        exerciseMinutes: Double? = nil,
        standHours: Double? = nil,
        flights: Double? = nil,
        distanceMeters: Double? = nil
    ) {
        self.steps = steps
        self.activeEnergy = activeEnergy
        self.exerciseMinutes = exerciseMinutes
        self.standHours = standHours
        self.flights = flights
        self.distanceMeters = distanceMeters
    }
}

nonisolated struct NightlyBiometricSummary: Codable, Hashable, Sendable, Identifiable {
    var id: UUID
    var sleepSessionID: UUID
    var sleepDateKey: String
    var samples: [BiometricSample]
    var heartRateAverage: Double?
    var heartRateMinimum: Double?
    var heartRateMaximum: Double?
    var hrvAverage: Double?
    var hrvMedian: Double?
    var oxygenSaturationAverage: Double?
    var oxygenSaturationMinimum: Double?
    var respiratoryRateAverage: Double?

    init(
        id: UUID = UUID(),
        sleepSessionID: UUID,
        sleepDateKey: String,
        samples: [BiometricSample] = [],
        heartRateAverage: Double? = nil,
        heartRateMinimum: Double? = nil,
        heartRateMaximum: Double? = nil,
        hrvAverage: Double? = nil,
        hrvMedian: Double? = nil,
        oxygenSaturationAverage: Double? = nil,
        oxygenSaturationMinimum: Double? = nil,
        respiratoryRateAverage: Double? = nil
    ) {
        self.id = id
        self.sleepSessionID = sleepSessionID
        self.sleepDateKey = sleepDateKey
        self.samples = samples
        self.heartRateAverage = heartRateAverage
        self.heartRateMinimum = heartRateMinimum
        self.heartRateMaximum = heartRateMaximum
        self.hrvAverage = hrvAverage
        self.hrvMedian = hrvMedian
        self.oxygenSaturationAverage = oxygenSaturationAverage
        self.oxygenSaturationMinimum = oxygenSaturationMinimum
        self.respiratoryRateAverage = respiratoryRateAverage
    }
}

nonisolated struct BiometricTrendPoint: Codable, Hashable, Sendable, Identifiable {
    var id: String { sleepDateKey }
    var sleepDateKey: String
    var date: Date
    var value: Double
}

nonisolated extension Array where Element == SleepSession {
    func biometricTrendPoints(_ value: (NightlyBiometricSummary) -> Double?) -> [BiometricTrendPoint] {
        compactMap { session in
            guard let biometrics = session.biometrics,
                  let trendValue = value(biometrics),
                  let date = SleepDateKey.date(from: session.sleepDateKey)
            else { return nil }
            return BiometricTrendPoint(
                sleepDateKey: session.sleepDateKey,
                date: date,
                value: trendValue
            )
        }
        .sorted { $0.date < $1.date }
    }
}
