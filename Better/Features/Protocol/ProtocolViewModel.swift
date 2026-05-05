import Foundation
import Observation

struct ProtocolImpactSummary: Sendable {
    let adherentNightCount: Int
    let missedNightCount: Int
    let adherentSleepAverage: Double?
    let missedSleepAverage: Double?
    let adherentScoreAverage: Double?
    let missedScoreAverage: Double?
}

@MainActor
@Observable
final class ProtocolViewModel {
    private let localRepository: LocalDataRepositoryProtocol

    var items: [ProtocolItem] = []
    var todayAdherence: [ProtocolAdherence] = []
    var adherenceHistory: [ProtocolAdherence] = []
    var adherenceStreak: Int = 0
    var impactSummary: ProtocolImpactSummary?
    var selectedProtocol: ProtocolItem?
    var isLoading = false
    var errorMessage: String?

    init(localRepository: LocalDataRepositoryProtocol) {
        self.localRepository = localRepository
        items = Self.loadSeedProtocols()
        selectedProtocol = items.first
    }

    func onAppear() async {
        await loadTodayAdherence()
    }

    func markTaken(_ item: ProtocolItem, takenAt: Date = Date()) async {
        let dateKey = Self.dateKey(for: Date())
        let adherence = ProtocolAdherence(
            protocolID: item.id.uuidString,
            dateKey: dateKey,
            taken: true,
            takenAt: takenAt
        )
        do {
            try await localRepository.saveAdherence(adherence)
            await loadTodayAdherence()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadTodayAdherence() async {
        isLoading = true
        errorMessage = nil
        do {
            let now = Date()
            let start = Calendar.current.startOfDay(for: now)
            let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? now
            todayAdherence = try await localRepository.fetchAdherence(from: start, to: end)
            await updateAdherenceStreak()
            await updateImpactSummary()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func isTakenToday(_ item: ProtocolItem) -> Bool {
        todayAdherence.contains { $0.protocolID == item.id.uuidString && $0.taken }
    }
}

private extension ProtocolViewModel {
    func updateAdherenceStreak() async {
        do {
            let now = Date()
            let lookbackStart = Calendar.current.date(byAdding: .day, value: -90, to: now)
                ?? now.addingTimeInterval(-90 * 86_400)
            let allAdherence = try await localRepository.fetchAdherence(from: lookbackStart, to: now)
            adherenceHistory = allAdherence
            adherenceStreak = Self.computeStreak(from: allAdherence)
        } catch {
            adherenceStreak = 0
        }
    }

    static func computeStreak(from adherence: [ProtocolAdherence]) -> Int {
        let takenKeys = Set(adherence.filter(\.taken).map(\.dateKey))
        var streak = 0
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        var current = Date()
        while true {
            let key = dateKey(for: current)
            guard takenKeys.contains(key) else { break }
            streak += 1
            current = calendar.date(byAdding: .day, value: -1, to: current)
                ?? current.addingTimeInterval(-86_400)
        }
        return streak
    }

    static func dateKey(for date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    static func loadSeedProtocols() -> [ProtocolItem] {
        ProtocolCatalog.load()
    }

    func updateImpactSummary() async {
        do {
            let now = Date()
            let start = Calendar.current.date(byAdding: .day, value: -30, to: now)
                ?? now.addingTimeInterval(-30 * 86_400)
            let sessions = try await localRepository.fetchCachedSessions(from: start, to: now)
            let adherence = try await localRepository.fetchAdherence(from: start, to: now)
            let followedKeys = Set(adherence.filter(\.taken).map(\.dateKey))
            let adherentSessions = sessions.filter { followedKeys.contains($0.sleepDateKey) }
            let missedSessions = sessions.filter { !followedKeys.contains($0.sleepDateKey) }

            impactSummary = ProtocolImpactSummary(
                adherentNightCount: adherentSessions.count,
                missedNightCount: missedSessions.count,
                adherentSleepAverage: Self.average(adherentSessions.map(\.totalSleepTime)),
                missedSleepAverage: Self.average(missedSessions.map(\.totalSleepTime)),
                adherentScoreAverage: Self.average(adherentSessions.map(\.qualityScore.overall)),
                missedScoreAverage: Self.average(missedSessions.map(\.qualityScore.overall))
            )
        } catch {
            impactSummary = nil
        }
    }

    static func average(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    static let seedProtocols: [ProtocolItem] = [
        ProtocolItem(
            id: UUID(uuidString: "A1B2C3D4-0000-0000-0000-000000000001")!,
            name: "Magnesium Glycinate",
            dose: "400 mg",
            benefit: "Supports deep sleep and relaxation",
            instructions: "Take 30–60 min before bed with water.",
            isActive: true,
            sortOrder: 0,
            colorHex: "#5E5CE6"
        ),
        ProtocolItem(
            id: UUID(uuidString: "A1B2C3D4-0000-0000-0000-000000000002")!,
            name: "Melatonin",
            dose: "0.5 mg",
            benefit: "Signals sleep onset",
            instructions: "Take 1–2 hrs before target bedtime.",
            isActive: true,
            sortOrder: 1,
            colorHex: "#64D2FF"
        )
    ]
}
