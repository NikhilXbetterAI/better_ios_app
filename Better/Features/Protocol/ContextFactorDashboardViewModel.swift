import Foundation
import Observation

@MainActor
@Observable
final class ContextFactorDashboardViewModel {
    private let localRepository: LocalDataRepositoryProtocol
    private let comparisonService: ContextComparisonService
    private let insightService:    ContextInsightService
    private let calendar: Calendar

    // MARK: - Published state

    var allResults:  [ContextComparisonResult] = []
    var topResults:  [ContextComparisonResult] = []   // meaningful, up to 3
    var selectedWindow: ProtocolComparisonWindow = .last30Days
    var isLoading  = false
    var errorMessage: String?

    /// The context entry for last night (or today's date key), pre-loaded for the UI.
    var lastNightEntry: SleepContextEntry?
    var lastNightDateKey: String = ""

    /// Set to true to present the check-in sheet.
    var showCheckIn = false

    init(
        localRepository: LocalDataRepositoryProtocol,
        comparisonService: ContextComparisonService? = nil,
        insightService: ContextInsightService = ContextInsightService(),
        calendar: Calendar = .current
    ) {
        self.localRepository   = localRepository
        self.comparisonService = comparisonService ?? ContextComparisonService(calendar: calendar)
        self.insightService    = insightService
        self.calendar          = calendar
    }

    // MARK: - Lifecycle

    func onAppear() async {
        await loadData(preferDefaultWindow: true)
    }

    func selectWindow(_ window: ProtocolComparisonWindow) async {
        selectedWindow = window
        await loadData(preferDefaultWindow: false)
    }

    func openCheckIn() {
        showCheckIn = true
    }

    // MARK: - Data loading

    func loadData(now: Date = Date(), preferDefaultWindow: Bool = false) async {
        isLoading    = true
        errorMessage = nil
        lastNightDateKey = Self.dateKey(for: calendar.date(byAdding: .day, value: -1, to: now) ?? now, calendar: calendar)

        let localRepository = self.localRepository
        let comparisonService = self.comparisonService
        let calendar = self.calendar
        let currentSelectedWindow = self.selectedWindow
        let lastNightDateKey = self.lastNightDateKey

        do {
            let (results, topResults, lastNight) = try await Task.detached(priority: .userInitiated) {
                let sixtyDaysAgo = calendar.date(byAdding: .day, value: -60, to: now)
                    ?? now.addingTimeInterval(-60 * 86_400)
                let startKey = Self.dateKey(for: sixtyDaysAgo, calendar: calendar)
                let endKey   = Self.dateKey(for: now, calendar: calendar)

                async let sessionsTask  = localRepository.fetchCachedSessions(from: sixtyDaysAgo, to: now)
                async let adherenceTask = localRepository.fetchAdherence(from: sixtyDaysAgo, to: now)
                async let contextTask   = localRepository.fetchContextEntries(from: startKey, to: endKey)
                async let entryTask     = localRepository.fetchContextEntry(forSleepDateKey: lastNightDateKey)

                let (sessions, adherence, contextEntries, lastNight) = try await (
                    sessionsTask, adherenceTask, contextTask, entryTask
                )

                var windowToUse = currentSelectedWindow
                if preferDefaultWindow {
                    let probe = comparisonService.compareAll(
                        sessions: sessions,
                        contextEntries: contextEntries,
                        adherence: adherence,
                        window: .last30Days,
                        endingAt: now
                    )
                    let hasData = probe.contains { $0.confidence != .unavailable }
                    windowToUse = hasData ? .last30Days : .all
                }

                let results = comparisonService.compareAll(
                    sessions: sessions,
                    contextEntries: contextEntries,
                    adherence: adherence,
                    window: windowToUse,
                    endingAt: now
                )

                let top = Array(results.filter(\.hasMeaningfulDifference).prefix(3))
                return (results, top, lastNight)
            }.value

            self.allResults = results
            self.topResults = topResults
            self.lastNightEntry = lastNight
            if preferDefaultWindow {
                self.selectedWindow = results.first?.window ?? .last30Days
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    // MARK: - Check-in save / clear

    func saveEntry(_ entry: SleepContextEntry) async {
        do {
            try await localRepository.saveContextEntry(entry)
            // Reload so UI reflects new entry immediately.
            if entry.sleepDateKey == lastNightDateKey {
                lastNightEntry = entry
            }
            await loadData(preferDefaultWindow: false)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func clearEntry(forDateKey key: String) async {
        let entryToClear: SleepContextEntry?
        if key == lastNightDateKey {
            entryToClear = lastNightEntry
        } else {
            entryToClear = try? await localRepository.fetchContextEntry(forSleepDateKey: key)
        }

        guard let entry = entryToClear else { return }
        do {
            try await localRepository.deleteContextEntry(id: entry.id)
            if key == lastNightDateKey { lastNightEntry = nil }
            await loadData(preferDefaultWindow: false)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Helpers

    nonisolated static func dateKey(for date: Date, calendar: Calendar = .current) -> String {
        let comps = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", comps.year ?? 0, comps.month ?? 0, comps.day ?? 0)
    }
}
