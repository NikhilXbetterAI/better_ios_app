import Foundation

nonisolated struct ManualBiologyEntry: Codable, Hashable, Sendable, Identifiable {
    var id: UUID
    var kind: BiologyMetricKind
    var value: Double
    var enteredAt: Date

    init(
        id: UUID = UUID(),
        kind: BiologyMetricKind,
        value: Double,
        enteredAt: Date = .now
    ) {
        self.id = id
        self.kind = kind
        self.value = value
        self.enteredAt = enteredAt
    }
}
