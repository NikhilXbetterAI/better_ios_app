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
    var takenDateKeys: Set<String> = []
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

    private var lastLoadAt: Date?
    private static let refreshDebounceInterval: TimeInterval = 15

    func onAppear(force: Bool = false) async {
        if !force, let last = lastLoadAt, Date().timeIntervalSince(last) < Self.refreshDebounceInterval {
            return
        }
        await loadAll()
        lastLoadAt = Date()
    }

    /// Single batched load: one fetch per data type, all derived state computed off-main.
    private func loadAll() async {
        isLoading = true
        errorMessage = nil

        let now = Date()
        let calendar = Calendar.current
        let lookbackStart = calendar.date(byAdding: .day, value: -90, to: now)
            ?? now.addingTimeInterval(-90 * 86_400)
        let todayKey = Self.dateKey(for: now)
        let startDate = protocolStartDate

        do {
            async let sessionsTask = localRepository.fetchCachedSessions(from: lookbackStart, to: now)
            async let adherenceTask = localRepository.fetchAdherence(from: lookbackStart, to: now)
            async let contextTask: SleepContextEntry? = try? localRepository.fetchContextEntry(forSleepDateKey: todayKey)

            let sessions = try await sessionsTask
            let adherence = try await adherenceTask
            let contextEntry = await contextTask

            let derived = await Self.derive(
                sessions: sessions,
                adherence: adherence,
                todayKey: todayKey,
                protocolStartDate: startDate
            )

            self.adherenceHistory = adherence
            self.todayAdherence = derived.todayAdherence
            self.adherenceStreak = derived.streak
            self.takenDateKeys = derived.takenDateKeys
            self.chartPoints = derived.chartPoints
            self.beforeProtocolSummary = derived.beforeSummary
            self.afterProtocolSummary = derived.afterSummary
            self.todayContextEntry = contextEntry
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    /// Derive all view state off the MainActor on `Sendable` inputs.
    private nonisolated static func derive(
        sessions: [SleepSession],
        adherence: [ProtocolAdherence],
        todayKey: String,
        protocolStartDate: Date?
    ) async -> DerivedState {
        let todayAdherence = adherence.filter { $0.dateKey == todayKey }
        let takenKeys = Set(adherence.filter(\.taken).map(\.dateKey))
        let streak = Self.computeStreak(takenKeys: takenKeys)

        let adherenceByDate = Dictionary(grouping: adherence, by: \.dateKey)
        let chartPoints: [ProtocolChartPoint] = sessions
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

        var beforeSummary: SleepPeriodSummary?
        var afterSummary: SleepPeriodSummary?
        if let startDate = protocolStartDate {
            let beforeSessions = sessions.filter { $0.endDate <= startDate }
            let afterSessions = sessions.filter { $0.startDate >= startDate }
            beforeSummary = periodSummary(from: beforeSessions)
            afterSummary = periodSummary(from: afterSessions)
        }

        return DerivedState(
            todayAdherence: todayAdherence,
            streak: streak,
            takenDateKeys: takenKeys,
            chartPoints: chartPoints,
            beforeSummary: beforeSummary,
            afterSummary: afterSummary
        )
    }

    private nonisolated struct DerivedState: Sendable {
        let todayAdherence: [ProtocolAdherence]
        let streak: Int
        let takenDateKeys: Set<String>
        let chartPoints: [ProtocolChartPoint]
        let beforeSummary: SleepPeriodSummary?
        let afterSummary: SleepPeriodSummary?
    }

    func toggleEnabled() {
        isProtocolEnabled.toggle()
        UserDefaults.standard.set(isProtocolEnabled, forKey: Keys.protocolEnabled)
    }

    func setStartDate(_ date: Date) async {
        protocolStartDate = date
        UserDefaults.standard.set(date, forKey: Keys.protocolStartDate)
        await autoMarkPastDays(from: date)
        await onAppear(force: true)
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
            await onAppear(force: true)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func isTakenToday(_ item: ProtocolItem) -> Bool {
        todayAdherence.contains { $0.protocolID == item.id.uuidString && $0.taken }
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

    nonisolated static func dateKey(for date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}

private extension ProtocolViewModel {
    func autoMarkPastDays(from startDate: Date) async {
        guard let item = items.first else { return }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let rangeEnd = today

        // Fetch the full range once instead of per-day round-trips.
        let existing = (try? await localRepository.fetchAdherence(
            from: calendar.startOfDay(for: startDate),
            to: rangeEnd
        )) ?? []
        let takenKeys = Set(existing.filter(\.taken).map(\.dateKey))

        var current = calendar.startOfDay(for: startDate)
        while current < today {
            let key = ProtocolViewModel.dateKey(for: current)
            if !takenKeys.contains(key) {
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
    }

    nonisolated static func periodSummary(from sessions: [SleepSession]) -> SleepPeriodSummary {
        let detailedSessions = sessions.filter { $0.dataQuality == .detailedStages }
        return SleepPeriodSummary(
            nightCount: sessions.count,
            averageSleepDuration: average(sessions.map(\.totalSleepTime)),
            averageSleepScore: average(sessions.map(\.qualityScore.overall)),
            averageDeepSleep: detailedSessions.isEmpty ? nil : average(detailedSessions.map(\.deepDuration)),
            averageREMSleep: detailedSessions.isEmpty ? nil : average(detailedSessions.map(\.remDuration))
        )
    }

    nonisolated static func computeStreak(takenKeys: Set<String>) -> Int {
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

    nonisolated static func average(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }
}
