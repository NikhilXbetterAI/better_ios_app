import Foundation
import SwiftUI
import OSLog

@MainActor
@Observable
final class ProtocolTimelineViewModel {
    struct VersionCard: Identifiable {
        var id: UUID { version.id }
        var version: ProtocolFormulaVersion
        var rollup: ProtocolVersionRollup?
        var firstDateKey: String?
        var lastDateKey: String?
        var takenLogCount: Int
        var skippedLogCount: Int
        var loggedNightCount: Int { takenLogCount + skippedLogCount }
        var hasMeasuredSleepData: Bool { (rollup?.nightCount ?? 0) > 0 }
        var restorativeDeltaMin: Double?
        var addins: [ProtocolFormulaComponent]
    }

    /// One cell of the 30-day heatmap strip. `status == nil` means unknown/no stored log.
    struct HeatmapCell: Identifiable {
        let id: String          // sleepDateKey
        let colorHex: String?
        let versionLabel: String?
        let status: ProtocolFormulaNightStatus?
    }

    var cards: [VersionCard] = []
    var baseline: ProtocolBaselineSnapshot?
    var totalNights: Int = 0
    var bestRestorativeLiftMin: Double?
    var errorMessage: String?
    var isLoading = false
    /// Last 30 days, oldest → newest. Cells reflect whichever version was logged that night.
    var heatmap: [HeatmapCell] = []

    private let repository: LocalDataRepositoryProtocol
    private let analysisService: ProtocolFormulaAnalysisService
    private let catalogService: ProtocolFormulaCatalogService
    private static let logger = Logger(subsystem: "Better", category: "ProtocolFormula")

    init(repository: LocalDataRepositoryProtocol) {
        self.repository = repository
        self.analysisService = ProtocolFormulaAnalysisService(repository: repository)
        self.catalogService = ProtocolFormulaCatalogService(repository: repository)
    }

    func onAppear() async { await reload() }

    func reload() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let versions = try await catalogService.ensureCatalogVersions()
                .reversed()
            baseline = try await repository.fetchBaselineSnapshot()
            let baselineExists = baseline != nil
            let baselineMissing = baseline?.extendedMetricReadinessSummary ?? "none"
            Self.logger.debug("timeline reload baseline exists=\(baselineExists, privacy: .public) missing=\(baselineMissing, privacy: .public)")
            let rollups = try await analysisService.allRollups()
            let rollupByVersion = Dictionary(uniqueKeysWithValues: rollups.map { ($0.versionID, $0) })
            let logs = try await repository.fetchNightLogs(from: "0000-00-00", to: "9999-12-31")
            let timelineLogs = logs.filter { $0.status != .unknown }
            let logsByVersion = Dictionary(grouping: timelineLogs, by: { $0.versionID })
            let addinsByVersion = Dictionary(grouping: timelineLogs, by: { $0.versionID })
                .mapValues { logs in
                    var seen: Set<String> = []
                    return logs.flatMap(\.addins).filter { addin in
                        let key = addin.name.lowercased()
                        if seen.contains(key) { return false }
                        seen.insert(key)
                        return true
                    }
                }

            totalNights = timelineLogs.count

            // Filter to versions the user has actually logged at least one night for.
            let loggedVersionIDs = Set(timelineLogs.map(\.versionID))
            let loggedVersions = versions.filter { loggedVersionIDs.contains($0.id) }

            // Build 30-day heatmap strip (oldest → newest).
            heatmap = Self.buildHeatmap(logs: timelineLogs, versions: Array(versions), days: 30)

            cards = loggedVersions.map { version in
                let rollup = rollupByVersion[version.id]
                let versionLogs = (logsByVersion[version.id] ?? []).sorted { $0.sleepDateKey < $1.sleepDateKey }
                let delta: Double? = {
                    guard let myMean = rollup?.meanRestorativeMin,
                          let baseMean = baseline?.meanRestorativeMin else { return nil }
                    return myMean - baseMean
                }()
                return VersionCard(
                    version: version,
                    rollup: rollup,
                    firstDateKey: versionLogs.first?.sleepDateKey,
                    lastDateKey: versionLogs.last?.sleepDateKey,
                    takenLogCount: versionLogs.filter { $0.status == .taken }.count,
                    skippedLogCount: versionLogs.filter { $0.status == .skipped }.count,
                    restorativeDeltaMin: delta,
                    addins: addinsByVersion[version.id] ?? []
                )
            }

            // Best-lift tile only renders when the comparison is meaningful:
            //   1. A baseline exists and clears the sufficiency threshold (>=7 nights).
            //   2. The contributing card has >= 3 taken nights (rollups are taken-only post-fix).
            //   3. The delta is positive (no "best regression" tile).
            // Otherwise we surface nil and the view hides the tile entirely.
            if let baseline, baseline.isInsufficient == false {
                bestRestorativeLiftMin = cards
                    .filter { ($0.rollup?.nightCount ?? 0) >= 3 }
                    .compactMap { $0.restorativeDeltaMin }
                    .filter { $0 > 0 }
                    .max()
            } else {
                bestRestorativeLiftMin = nil
            }
            let cardCount = cards.count
            let trackedNightCount = totalNights
            let bestLift = bestRestorativeLiftMin.map { Int($0.rounded()) } ?? -1
            Self.logger.debug("timeline reload cards=\(cardCount, privacy: .public) totalNights=\(trackedNightCount, privacy: .public) bestLift=\(bestLift, privacy: .public)")
        } catch {
            errorMessage = error.localizedDescription
            Self.logger.error("timeline reload failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func formattedDateRange(first: String?, last: String?) -> String {
        guard let first else { return "–" }
        let fDate = Self.date(fromKey: first)
        let lDate = last.flatMap(Self.date(fromKey:))
        // User-facing format: keep default locale so "MMM d" localizes properly.
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM d"
        let start = fDate.map { fmt.string(from: $0) } ?? first
        let end = lDate.map { fmt.string(from: $0) } ?? (last ?? "–")
        return "\(start) – \(end)"
    }

    private static func buildHeatmap(
        logs: [ProtocolNightLog],
        versions: [ProtocolFormulaVersion],
        days: Int
    ) -> [HeatmapCell] {
        let colorByVersion = Dictionary(uniqueKeysWithValues: versions.map { ($0.id, $0.colorHex) })
        let labelByVersion = Dictionary(uniqueKeysWithValues: versions.map { ($0.id, $0.resolvedLabel) })
        // Latest log per sleepDateKey wins (logs are unique-by-key in storage, but be safe).
        let logByKey = Dictionary(logs.map { ($0.sleepDateKey, $0) }, uniquingKeysWith: { _, b in b })

        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.calendar = Calendar(identifier: .gregorian)
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.timeZone = .current
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        let today = cal.startOfDay(for: Date())

        return (0..<days).reversed().compactMap { offset -> HeatmapCell? in
            guard let day = cal.date(byAdding: .day, value: -offset, to: today) else { return nil }
            let key = fmt.string(from: day)
            if let log = logByKey[key], log.status == .taken {
                return HeatmapCell(
                    id: key,
                    colorHex: colorByVersion[log.versionID],
                    versionLabel: labelByVersion[log.versionID],
                    status: log.status
                )
            }
            if let log = logByKey[key], log.status == .skipped {
                return HeatmapCell(
                    id: key,
                    colorHex: nil,
                    versionLabel: labelByVersion[log.versionID],
                    status: log.status
                )
            }
            return HeatmapCell(id: key, colorHex: nil, versionLabel: nil, status: nil)
        }
    }

    private static func date(fromKey key: String) -> Date? {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.calendar = Calendar(identifier: .gregorian)
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.timeZone = .current
        return fmt.date(from: key)
    }
}
