import Foundation
import SwiftUI

@MainActor
@Observable
final class ProtocolVersionDiveViewModel {
    var versions: [ProtocolFormulaVersion] = []
    var selectedVersionID: UUID?
    var baseline: ProtocolBaselineSnapshot?
    var rollups: [ProtocolVersionRollup] = []
    var snapshots: [ProtocolNightMetricSnapshot] = []
    var errorMessage: String?
    var isLoading = false

    private let repository: LocalDataRepositoryProtocol
    private let analysisService: ProtocolFormulaAnalysisService
    private let catalogService: ProtocolFormulaCatalogService

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
            versions = try await catalogService.ensureCatalogVersions()
                .filter { $0.archivedAt == nil }
            if selectedVersionID == nil {
                selectedVersionID = versions.first(where: { $0.isActive })?.id ?? versions.last?.id
            }
            // V3: prefer per-version baseline. Fall back to the singleton row for
            // pre-V3 stores or versions that haven't had a baseline frozen yet.
            if let id = selectedVersionID,
               let perVersion = try await repository.fetchBaselineSnapshot(versionID: id) {
                baseline = perVersion
            } else {
                baseline = try await repository.fetchBaselineSnapshot()
            }
            rollups = try await analysisService.recentRollups()
            snapshots = try await analysisService.recentNightlySnapshots()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    var selectedVersion: ProtocolFormulaVersion? {
        versions.first { $0.id == selectedVersionID }
    }

    var selectedRollup: ProtocolVersionRollup? {
        rollups.first { $0.versionID == selectedVersionID }
    }

    var nightlyPoints: [ProtocolNightMetricSnapshot] {
        guard let id = selectedVersionID else { return [] }
        return snapshots.filter { $0.versionID == id }.sorted { $0.sleepDateKey < $1.sleepDateKey }
    }

    /// Comparison bar value for restorativePct: (you, baseline). Max for bar scaling.
    func restorativeComparison() -> (my: Double?, base: Double?) {
        (Self.sanitized(selectedRollup?.meanRestorativePctOfInBed), Self.sanitized(baseline?.meanRestorativePctOfInBed))
    }

    func longestBlockComparison() -> (my: Double?, base: Double?) {
        (Self.sanitized(selectedRollup?.meanLongestRestorativeBlockMin), Self.sanitized(baseline?.meanLongestRestorativeBlockMin))
    }

    func restorativeMinComparison() -> (my: Double?, base: Double?) {
        (Self.sanitized(selectedRollup?.meanRestorativeMin), Self.sanitized(baseline?.meanRestorativeMin))
    }

    /// Generic accessor for any `ProtocolFormulaMetric` — drives the full bar list.
    func comparison(for metric: ProtocolFormulaMetric) -> (my: Double?, base: Double?) {
        let my = selectedRollup.flatMap { metric.rollupMean(from: $0) }
        let base = baseline.flatMap { metric.baselineValue(from: $0) }
        return (Self.sanitized(my), Self.sanitized(base))
    }

    private static func sanitized(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value >= 0 else { return nil }
        return value
    }
}
