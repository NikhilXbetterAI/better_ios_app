import Foundation
import SwiftUI
import OSLog

@MainActor
@Observable
final class ProtocolAllMetricsViewModel {
    /// Local alias — the canonical metric definition lives on `ProtocolFormulaMetric` so
    /// Version Dive bars + Timeline tiles can share the same enum + color/unit tokens.
    typealias Metric = ProtocolFormulaMetric

    var activeMetric: Metric = .restorativePct {
        didSet {
            guard activeMetric != oldValue else { return }
            recomputeChartPoints()
        }
    }
    var versions: [ProtocolFormulaVersion] = []
    /// O(1) version lookup; rebuilt on each `reload()` so chart point
    /// generation doesn't scan `versions` linearly per snapshot.
    var versionsByID: [UUID: ProtocolFormulaVersion] = [:]
    var rollups: [ProtocolVersionRollup] = []
    var snapshots: [ProtocolNightMetricSnapshot] = []
    var baseline: ProtocolBaselineSnapshot?
    var bestVersion: ProtocolFormulaBestVersion?
    var errorMessage: String?
    var isLoading = false
    /// Stored derived state. Was a computed `var` that re-filtered + re-scanned
    /// `versions` on every SwiftUI body re-evaluation; now refreshed only when
    /// inputs change.
    private(set) var chartPoints: [ChartPoint] = []

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
            versions = try await catalogService.ensureCatalogVersions()
            versionsByID = Dictionary(uniqueKeysWithValues: versions.map { ($0.id, $0) })
            baseline = try await repository.fetchBaselineSnapshot()
            let hasBaseline = baseline != nil
            let missingFields = baseline?.extendedMetricReadinessSummary ?? "none"
            rollups = try await analysisService.recentRollups()
            snapshots = try await analysisService.recentNightlySnapshots()
            bestVersion = ProtocolFormulaCatalogService.bestVersion(
                versions: versions,
                rollups: rollups,
                baseline: baseline
            )
            recomputeChartPoints()
            let versionCount = versions.count
            let rollupCount = rollups.count
            let snapshotCount = snapshots.count
            let activeMetricLabel = activeMetric.shortLabel
            Self.logger.debug("all metrics reload baseline exists=\(hasBaseline, privacy: .public) missing=\(missingFields, privacy: .public) versions=\(versionCount, privacy: .public) rollups=\(rollupCount, privacy: .public) snapshots=\(snapshotCount, privacy: .public) activeMetric=\(activeMetricLabel, privacy: .public)")
        } catch {
            errorMessage = error.localizedDescription
            Self.logger.error("all metrics reload failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func recomputeChartPoints() {
        chartPoints = snapshots.compactMap { snap in
            guard let value = activeMetric.value(from: snap),
                  value.isFinite,
                  value >= 0,
                  let versionID = snap.versionID,
                  let version = versionsByID[versionID] else { return nil }
            return ChartPoint(dateKey: snap.sleepDateKey, value: value, version: version)
        }
    }

    var baselineValue: Double? {
        guard let value = baseline.flatMap({ activeMetric.baselineValue(from: $0) }),
              value.isFinite,
              value >= 0 else { return nil }
        return value
    }

    func rollup(for version: ProtocolFormulaVersion) -> ProtocolVersionRollup? {
        rollups.first { $0.versionID == version.id }
    }

    struct ChartPoint: Identifiable {
        var id: String { dateKey }
        var dateKey: String
        var value: Double
        var version: ProtocolFormulaVersion
    }
}
