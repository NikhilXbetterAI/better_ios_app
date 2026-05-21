import Foundation
import SwiftUI

@MainActor
@Observable
final class ProtocolEditLogViewModel {
    var displayedMonth: Date
    var logs: [String: ProtocolNightLog] = [:]
    var versions: [ProtocolFormulaVersion] = []
    var selectedDateKey: String?
    var draftStatus: ProtocolFormulaNightStatus = .unknown
    var draftVersionID: UUID?
    var draftAddins: [ProtocolFormulaComponent] = []
    var draftAddinText: String = ""
    var draftNote: String = ""
    var errorMessage: String?

    private let localRepository: LocalDataRepositoryProtocol
    private let catalogService: ProtocolFormulaCatalogService
    private let calendar: Calendar

    init(localRepository: LocalDataRepositoryProtocol, calendar: Calendar = .current) {
        self.localRepository = localRepository
        self.catalogService = ProtocolFormulaCatalogService(repository: localRepository, calendar: calendar)
        self.calendar = calendar
        self.displayedMonth = Self.startOfMonth(for: Date(), calendar: calendar)
    }

    func onAppear() async { await reload() }

    func reload() async {
        do {
            versions = try await catalogService.ensureCatalogVersions()
            let range = monthRange()
            let logsList = try await localRepository.fetchNightLogs(
                from: Self.dateKey(for: range.lowerBound, calendar: calendar),
                to: Self.dateKey(for: range.upperBound, calendar: calendar)
            )
            logs = Dictionary(uniqueKeysWithValues: logsList.map { ($0.sleepDateKey, $0) })
        } catch {
            errorMessage = "Couldn't load logs: \(error.localizedDescription)"
        }
    }

    func previousMonth() {
        if let prev = calendar.date(byAdding: .month, value: -1, to: displayedMonth) {
            displayedMonth = prev
            Task { await reload() }
        }
    }

    func nextMonth() {
        if let next = calendar.date(byAdding: .month, value: 1, to: displayedMonth) {
            displayedMonth = next
            Task { await reload() }
        }
    }

    func select(dateKey: String) {
        selectedDateKey = dateKey
        if let log = logs[dateKey] {
            draftStatus = log.status
            draftVersionID = log.versionID
            draftAddins = log.addins
            draftNote = log.note ?? ""
        } else {
            draftStatus = .taken
            let selectable = selectableVersions
            draftVersionID = selectable.first(where: { $0.isActive })?.id ?? selectable.first?.id
            draftAddins = []
            draftNote = ""
        }
        draftAddinText = ""
    }

    /// Persist the draft and append an audit row to ProtocolLogEdit.
    func saveDraft() async {
        guard let key = selectedDateKey else { return }
        guard let versionID = draftVersionID else {
            errorMessage = "Pick a formula version first."
            return
        }
        let version = versions.first(where: { $0.id == versionID })
        let hash = version.map(ProtocolFormulaHashing.snapshotHash(for:)) ?? ProtocolNightLog.importedPlaceholderHash

        let existing = logs[key]
        let beforeData = existing.flatMap { try? JSONEncoder().encode($0) }
        let nextLog = ProtocolNightLog(
            id: existing?.id ?? UUID(),
            sleepDateKey: key,
            versionID: versionID,
            status: draftStatus,
            addins: draftStatus == .taken ? draftAddins : [],
            takenAt: draftStatus == .taken ? (existing?.takenAt ?? Date()) : nil,
            note: draftNote.isEmpty ? nil : draftNote,
            formulaSnapshotHash: hash,
            createdAt: existing?.createdAt ?? Date(),
            updatedAt: Date()
        )

        do {
            if draftStatus == .unknown {
                try await localRepository.deleteNightLog(forSleepDateKey: key)
            } else {
                try await localRepository.saveNightLog(nextLog)
                let edit = ProtocolLogEdit(
                    nightLogID: nextLog.id,
                    sleepDateKey: key,
                    beforeData: beforeData,
                    afterData: (try? JSONEncoder().encode(nextLog)) ?? Data(),
                    editedAt: Date(),
                    reason: nil
                )
                try await localRepository.saveLogEdit(edit)
            }
            await reload()
        } catch {
            errorMessage = "Couldn't save: \(error.localizedDescription)"
        }
    }

    /// Versions the editor should offer — excludes archived versions so users
    /// who only take current formulas don't see stale rows.
    var selectableVersions: [ProtocolFormulaVersion] {
        versions.filter { $0.archivedAt == nil }
    }

    var activeVersion: ProtocolFormulaVersion? {
        versions.first(where: { $0.isActive })
    }

    /// Save the active version as `.taken` for each of the past 7 days (including today)
    /// that doesn't yet have a log. Used by the "mark this week taken" shortcut.
    func markPastWeekTakenWithActiveVersion() async {
        guard let active = activeVersion else { return }
        let today = calendar.startOfDay(for: Date())
        let previousSelection = selectedDateKey
        let previousStatus = draftStatus
        let previousVersion = draftVersionID
        let previousAddins = draftAddins
        let previousNote = draftNote

        for offset in 0..<7 {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            let key = Self.dateKey(for: day, calendar: calendar)
            selectedDateKey = key
            let existing = logs[key]
            draftStatus = .taken
            draftVersionID = active.id
            draftAddins = existing?.addins ?? []
            draftNote = existing?.note ?? ""
            await saveDraft()
            if errorMessage != nil { break }
        }

        selectedDateKey = previousSelection
        draftStatus = previousStatus
        draftVersionID = previousVersion
        draftAddins = previousAddins
        draftNote = previousNote
    }

    func selectVersion(_ version: ProtocolFormulaVersion) {
        draftVersionID = version.id
        if draftStatus == .unknown {
            draftStatus = .taken
        }
    }

    func addDraftAddin() {
        let parts = draftAddinText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        for part in parts where draftAddins.contains(where: { $0.name.caseInsensitiveCompare(part) == .orderedSame }) == false {
            draftAddins.append(ProtocolFormulaComponent(name: part, role: .addin))
        }
        draftAddinText = ""
    }

    func removeDraftAddin(_ addin: ProtocolFormulaComponent) {
        draftAddins.removeAll { $0.id == addin.id }
    }

    // MARK: - Calendar helpers

    func monthRange() -> ClosedRange<Date> {
        let start = displayedMonth
        let end = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: start) ?? start
        return start...end
    }

    func daysInDisplayedMonth() -> [Date] {
        guard let interval = calendar.dateInterval(of: .month, for: displayedMonth) else { return [] }
        var dates: [Date] = []
        var cursor = interval.start
        while cursor < interval.end {
            dates.append(cursor)
            cursor = calendar.date(byAdding: .day, value: 1, to: cursor) ?? interval.end
        }
        return dates
    }

    func version(for log: ProtocolNightLog) -> ProtocolFormulaVersion? {
        versions.first(where: { $0.id == log.versionID })
    }

    static func dateKey(for date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d",
                      components.year ?? 0,
                      components.month ?? 0,
                      components.day ?? 0)
    }

    static func isFuture(_ date: Date, calendar: Calendar = .current) -> Bool {
        calendar.startOfDay(for: date) > calendar.startOfDay(for: Date())
    }

    private static func startOfMonth(for date: Date, calendar: Calendar) -> Date {
        let comps = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: comps) ?? date
    }
}
