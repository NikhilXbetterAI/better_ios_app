import Foundation
import Observation

struct SleepPeriodSummary: Sendable {
    let nightCount: Int
    let averageSleepDuration: Double?
    let averageSleepScore: Double?
    let averageDeepSleep: Double?
    let averageREMSleep: Double?
}

enum ProtocolNightStatus: String, Hashable, Sendable {
    case taken
    case notTaken
    case unknown

    init(_ usageStatus: ProtocolUsageStatus) {
        switch usageStatus {
        case .taken:
            self = .taken
        case .notTaken:
            self = .notTaken
        case .unknown:
            self = .unknown
        }
    }
}

struct ProtocolChartPoint: Identifiable, Hashable, Sendable {
    var id: String { dateKey }
    let dateKey: String
    let date: Date
    let sleepScore: Double
    let sleepDuration: TimeInterval
    let deepSleep: TimeInterval?
    let remSleep: TimeInterval?
    let status: ProtocolNightStatus
}

@MainActor
@Observable
final class ProtocolViewModel {
    private let localRepository: LocalDataRepositoryProtocol
    private let healthRepository: HealthKitRepositoryProtocol
    private enum Keys {
        static let protocolEnabled = "better.protocol.enabled"
        static let protocolStartDate = "better.protocol.startDate"
    }

    var items: [ProtocolItem] = []
    var todayAdherence: [ProtocolAdherence] = []
    var adherenceHistory: [ProtocolAdherence] = []
    var adherenceStreak: Int = 0
    var selectedProtocol: ProtocolItem?
    var isLoading = false
    var errorMessage: String?

    var isProtocolEnabled: Bool = true
    var protocolStartDate: Date? = nil
    var beforeProtocolSummary: SleepPeriodSummary?
    var afterProtocolSummary: SleepPeriodSummary?
    var showStartDatePicker = false

    var todayContextEntry: SleepContextEntry? = nil
    var chartPoints: [ProtocolChartPoint] = []
    var isExporting = false
    var exportURL: URL?
    var exportError: String?
    var journalSaved = false

    var daysOnProtocol: Int {
        guard let startDate = protocolStartDate else { return 0 }
        let cal = Calendar.current
        let days = cal.dateComponents([.day],
            from: cal.startOfDay(for: startDate),
            to: cal.startOfDay(for: Date())).day ?? 0
        return max(0, days)
    }

    init(localRepository: LocalDataRepositoryProtocol, healthRepository: HealthKitRepositoryProtocol) {
        self.localRepository = localRepository
        self.healthRepository = healthRepository
        items = Self.loadSeedProtocols()
        selectedProtocol = items.first
        isProtocolEnabled = UserDefaults.standard.object(forKey: Keys.protocolEnabled) as? Bool ?? true
        protocolStartDate = UserDefaults.standard.object(forKey: Keys.protocolStartDate) as? Date
    }

    func onAppear() async {
        await loadTodayAdherence()
        await loadTodayContext()
        await updateChartPoints()
        if protocolStartDate != nil {
            await updateBeforeAfterSummary()
        }
    }

    func toggleEnabled() {
        isProtocolEnabled.toggle()
        UserDefaults.standard.set(isProtocolEnabled, forKey: Keys.protocolEnabled)
    }

    func setStartDate(_ date: Date) async {
        protocolStartDate = date
        UserDefaults.standard.set(date, forKey: Keys.protocolStartDate)
        await autoMarkPastDays(from: date)
        await updateBeforeAfterSummary()
    }

    func clearStartDate() {
        protocolStartDate = nil
        UserDefaults.standard.removeObject(forKey: Keys.protocolStartDate)
        beforeProtocolSummary = nil
        afterProtocolSummary = nil
    }

    func markTaken(_ item: ProtocolItem, takenAt: Date = Date()) async {
        let key = Self.dateKey(for: Date())
        let adherence = ProtocolAdherence(
            protocolID: item.id.uuidString,
            dateKey: key,
            taken: true,
            takenAt: takenAt
        )
        do {
            try await localRepository.saveAdherence(adherence)
            await loadTodayAdherence()
            await updateChartPoints()
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
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func isTakenToday(_ item: ProtocolItem) -> Bool {
        todayAdherence.contains { $0.protocolID == item.id.uuidString && $0.taken }
    }

    func loadTodayContext() async {
        let key = Self.dateKey(for: Date())
        todayContextEntry = try? await localRepository.fetchContextEntry(forSleepDateKey: key)
    }

    func saveContextEntry(_ entry: SleepContextEntry) async {
        do {
            try await localRepository.saveContextEntry(entry)
            todayContextEntry = entry
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func saveJournalEntry(_ entry: SleepContextEntry) async {
        await saveContextEntry(entry)
        journalSaved = true
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            journalSaved = false
        }
    }

    func exportResearchData() async {
        guard !isExporting else { return }
        isExporting = true
        exportURL = nil
        exportError = nil

        do {
            let endDate = Date()
            let startDate = Calendar.current.date(byAdding: .day, value: -60, to: endDate)
                ?? endDate.addingTimeInterval(-60 * 86_400)
            let package = try await ResearchAnalysisService(
                localRepository: localRepository,
                healthRepository: healthRepository
            ).buildExportPackage(from: startDate, to: endDate, protocolItems: items)
            let profile = try await localRepository.fetchProfile()
            exportURL = try ResearchCSVExporter().writeZIP(
                package: package,
                displayName: profile.displayName
            )
        } catch {
            exportError = error.localizedDescription
        }

        isExporting = false
    }

    // MARK: - Date key (internal — used by ProtocolTabView for timeline)

    static func dateKey(for date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
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

    func updateChartPoints() async {
        do {
            let now = Date()
            let lookbackStart = Calendar.current.date(byAdding: .day, value: -60, to: now)
                ?? now.addingTimeInterval(-60 * 86_400)
            let sessions = try await localRepository.fetchCachedSessions(from: lookbackStart, to: now)
            let adherence = try await localRepository.fetchAdherence(from: lookbackStart, to: now)
            let adherenceByDate = Dictionary(grouping: adherence, by: \.dateKey)
            chartPoints = sessions
                .filter { BaselineEngine.isValidNight($0) }
                .sorted { $0.sleepDateKey < $1.sleepDateKey }
                .compactMap { session in
                    guard let date = SleepDateKey.date(from: session.sleepDateKey) else { return nil }
                    let hasDetailedStages = session.dataQuality == .detailedStages || session.dataQuality == .mixedSources
                    return ProtocolChartPoint(
                        dateKey: session.sleepDateKey,
                        date: date,
                        sleepScore: session.qualityScore.overall,
                        sleepDuration: session.totalSleepTime,
                        deepSleep: hasDetailedStages && session.deepDuration > 0 ? session.deepDuration : nil,
                        remSleep: hasDetailedStages && session.remDuration > 0 ? session.remDuration : nil,
                        status: ProtocolNightStatus(ProtocolComparisonService.status(for: adherenceByDate[session.sleepDateKey]))
                    )
                }
        } catch {
            chartPoints = []
        }
    }

    func updateBeforeAfterSummary() async {
        guard let startDate = protocolStartDate else {
            beforeProtocolSummary = nil
            afterProtocolSummary = nil
            return
        }
        do {
            let now = Date()
            let lookbackStart = Calendar.current.date(byAdding: .day, value: -90, to: startDate)
                ?? startDate.addingTimeInterval(-90 * 86_400)
            let sessions = try await localRepository.fetchCachedSessions(from: lookbackStart, to: now)
            let beforeSessions = sessions.filter { $0.endDate <= startDate }
            let afterSessions = sessions.filter { $0.startDate >= startDate }
            beforeProtocolSummary = Self.periodSummary(from: beforeSessions)
            afterProtocolSummary = Self.periodSummary(from: afterSessions)
            await updateChartPoints()
        } catch {
            beforeProtocolSummary = nil
            afterProtocolSummary = nil
        }
    }

    func autoMarkPastDays(from startDate: Date) async {
        guard let item = items.first else { return }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        var current = calendar.startOfDay(for: startDate)

        while current < today {
            let key = Self.dateKey(for: current)
            let dayEnd = calendar.date(byAdding: .day, value: 1, to: current) ?? current
            let existing = (try? await localRepository.fetchAdherence(from: current, to: dayEnd)) ?? []

            if !existing.contains(where: { $0.taken }) {
                let adherence = ProtocolAdherence(
                    protocolID: item.id.uuidString,
                    dateKey: key,
                    taken: true,
                    takenAt: current
                )
                try? await localRepository.saveAdherence(adherence)
            }
            current = calendar.date(byAdding: .day, value: 1, to: current) ?? current
        }
        await loadTodayAdherence()
    }

    static func periodSummary(from sessions: [SleepSession]) -> SleepPeriodSummary {
        let detailedSessions = sessions.filter { $0.dataQuality == .detailedStages }
        return SleepPeriodSummary(
            nightCount: sessions.count,
            averageSleepDuration: average(sessions.map(\.totalSleepTime)),
            averageSleepScore: average(sessions.map(\.qualityScore.overall)),
            averageDeepSleep: detailedSessions.isEmpty ? nil : average(detailedSessions.map(\.deepDuration)),
            averageREMSleep: detailedSessions.isEmpty ? nil : average(detailedSessions.map(\.remDuration))
        )
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

    static func loadSeedProtocols() -> [ProtocolItem] {
        ProtocolCatalog.load()
    }

    static func average(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }
}
