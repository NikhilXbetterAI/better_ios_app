import Foundation
import SwiftUI

@MainActor
@Observable
final class ProtocolOnboardingViewModel {
    var versions: [ProtocolFormulaVersion] = []
    var selectedVersionID: UUID?
    var currentVersionID: UUID?
    var displayedMonth: Date
    var paintedDateKeysByVersionID: [UUID: Set<String>] = [:]
    var skippedVersionIDs: Set<UUID> = []
    var pendingRangeStartKey: String?
    var isCompleted: Bool = false
    var errorMessage: String?

    private let localRepository: LocalDataRepositoryProtocol
    private let baselineService: ProtocolBaselineService
    private let catalogService: ProtocolFormulaCatalogService
    private let calendar: Calendar
    private let historicalRefresh: (() async -> Void)?

    init(
        localRepository: LocalDataRepositoryProtocol,
        baselineService: ProtocolBaselineService? = nil,
        calendar: Calendar = .current,
        historicalRefresh: (() async -> Void)? = nil
    ) {
        self.localRepository = localRepository
        self.baselineService = baselineService ?? ProtocolBaselineService(repository: localRepository)
        self.catalogService = ProtocolFormulaCatalogService(repository: localRepository, calendar: calendar)
        self.calendar = calendar
        self.historicalRefresh = historicalRefresh
        self.displayedMonth = Self.startOfMonth(for: Date(), calendar: calendar)
    }

    func onAppear() async {
        // Display-only versions built from the in-memory catalog spec — no rows
        // are persisted until `finish()` calls `seedHistory`. This avoids
        // fabricating shippedOn dates for versions the user never paints.
        versions = ProtocolFormulaCatalog.specs.map { spec in
            ProtocolFormulaVersion(
                id: spec.id,
                displayLabel: spec.label,
                ordinalLabel: spec.label,
                formulaText: spec.formulaText,
                components: [],
                shippedOn: Date(),
                colorHex: spec.colorHex,
                isActive: false
            )
        }
        selectedVersionID = selectedVersionID ?? versions.first?.id
        currentVersionID = currentVersionID ?? versions.last?.id
    }

    func selectVersion(_ version: ProtocolFormulaVersion) {
        selectedVersionID = version.id
        skippedVersionIDs.remove(version.id)
        pendingRangeStartKey = nil
    }

    func setCurrentVersion(_ version: ProtocolFormulaVersion) {
        currentVersionID = version.id
        skippedVersionIDs.remove(version.id)
    }

    func toggleNeverUsed(_ version: ProtocolFormulaVersion) {
        if skippedVersionIDs.contains(version.id) {
            skippedVersionIDs.remove(version.id)
        } else {
            skippedVersionIDs.insert(version.id)
            paintedDateKeysByVersionID[version.id] = []
            if selectedVersionID == version.id {
                pendingRangeStartKey = nil
            }
        }
    }

    func tapDate(_ date: Date) {
        guard let selectedVersionID,
              skippedVersionIDs.contains(selectedVersionID) == false else { return }
        let key = Self.dateKey(for: date, calendar: calendar)
        guard !Self.isFuture(date, calendar: calendar) else { return }

        if let start = pendingRangeStartKey,
           let startDate = Self.date(fromKey: start, calendar: calendar) {
            let keys = Self.dateKeys(from: startDate, to: date, calendar: calendar)
            for existingVersionID in Array(paintedDateKeysByVersionID.keys) {
                paintedDateKeysByVersionID[existingVersionID]?.subtract(keys)
            }
            paintedDateKeysByVersionID[selectedVersionID, default: []].formUnion(keys)
            pendingRangeStartKey = nil
        } else {
            pendingRangeStartKey = key
        }
    }

    func clearSelectedRangeStart() {
        pendingRangeStartKey = nil
    }

    func previousMonth() {
        if let prev = calendar.date(byAdding: .month, value: -1, to: displayedMonth) {
            displayedMonth = prev
            pendingRangeStartKey = nil
        }
    }

    func nextMonth() {
        if let next = calendar.date(byAdding: .month, value: 1, to: displayedMonth), next <= Date() {
            displayedMonth = next
            pendingRangeStartKey = nil
        }
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

    func version(forDate date: Date) -> ProtocolFormulaVersion? {
        let key = Self.dateKey(for: date, calendar: calendar)
        guard let id = paintedDateKeysByVersionID.first(where: { $0.value.contains(key) })?.key else {
            return nil
        }
        return versions.first { $0.id == id }
    }

    func paintedCount(for version: ProtocolFormulaVersion) -> Int {
        paintedDateKeysByVersionID[version.id]?.count ?? 0
    }

    func finish() async {
        do {
            let seed = ProtocolFormulaHistorySeed(
                dateKeysByVersionID: paintedDateKeysByVersionID.filter { skippedVersionIDs.contains($0.key) == false },
                currentVersionID: currentVersionID
            )
            try await catalogService.seedHistory(seed)
            versions = try await catalogService.loadExistingVersions(currentVersionID: currentVersionID)
            if let firstKey = paintedDateKeysByVersionID.values.flatMap({ $0 }).min() {
                await historicalRefresh?()
                _ = try await baselineService.freezeBaseline(beforeSleepDateKey: firstKey)
            }
            isCompleted = true
        } catch {
            errorMessage = "Couldn't save protocol history: \(error.localizedDescription)"
        }
    }

    static func dateKey(for date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d",
                      components.year ?? 0,
                      components.month ?? 0,
                      components.day ?? 0)
    }

    static func date(fromKey key: String, calendar: Calendar = .current) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    private static func dateKeys(from first: Date, to second: Date, calendar: Calendar) -> Set<String> {
        let start = min(first, second)
        let end = max(first, second)
        var keys: Set<String> = []
        var cursor = calendar.startOfDay(for: start)
        let endDay = calendar.startOfDay(for: end)
        while cursor <= endDay {
            keys.insert(dateKey(for: cursor, calendar: calendar))
            cursor = calendar.date(byAdding: .day, value: 1, to: cursor) ?? endDay.addingTimeInterval(1)
        }
        return keys
    }

    private static func startOfMonth(for date: Date, calendar: Calendar) -> Date {
        let comps = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: comps) ?? date
    }

    static func isFuture(_ date: Date, calendar: Calendar = .current) -> Bool {
        calendar.startOfDay(for: date) > calendar.startOfDay(for: Date())
    }
}
