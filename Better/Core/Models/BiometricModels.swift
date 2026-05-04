import Foundation

enum BiometricType: String, Codable, CaseIterable, Hashable, Sendable, Identifiable {
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

struct BiometricSample: Codable, Hashable, Sendable, Identifiable {
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

enum BiologyMetricKind: String, Codable, CaseIterable, Hashable, Sendable, Identifiable {
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

struct BiologyMetric: Codable, Hashable, Sendable, Identifiable {
    var id: BiologyMetricKind { kind }
    var kind: BiologyMetricKind
    var title: String
    var value: Double?
    var unit: String
    var rating: String
    var trend: String
    var history: [Double]

    init(
        kind: BiologyMetricKind,
        title: String,
        value: Double?,
        unit: String,
        rating: String,
        trend: String = "Stable",
        history: [Double] = []
    ) {
        self.kind = kind
        self.title = title
        self.value = value
        self.unit = unit
        self.rating = rating
        self.trend = trend
        self.history = history
    }
}

struct ActivityMetricSummary: Codable, Hashable, Sendable {
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

struct NightlyBiometricSummary: Codable, Hashable, Sendable, Identifiable {
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
