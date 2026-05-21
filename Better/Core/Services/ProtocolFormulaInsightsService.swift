import Foundation

/// Generates narrative insights by comparing version rollups against the frozen baseline.
nonisolated struct ProtocolFormulaInsightsService: Sendable {
    private let repository: LocalDataRepositoryProtocol
    private let analysisService: ProtocolFormulaAnalysisService

    init(repository: LocalDataRepositoryProtocol) {
        self.repository = repository
        self.analysisService = ProtocolFormulaAnalysisService(repository: repository)
    }

    func insights(for versions: [ProtocolFormulaVersion]) async throws -> [ProtocolFormulaInsight] {
        guard !versions.isEmpty else { return [] }
        let baseline = try await repository.fetchBaselineSnapshot()
        let rollups = try await analysisService.allRollups()
        let rollupByVersion = Dictionary(uniqueKeysWithValues: rollups.map { ($0.versionID, $0) })

        guard let baseline else {
            return [ProtocolFormulaInsight(
                kind: .baselineUnavailable,
                headline: "Baseline not available yet",
                body: "Log 7 or more nights to unlock protocol impact insights.",
                isPositive: false
            )]
        }

        var insights: [ProtocolFormulaInsight] = []

        for version in versions where version.archivedAt == nil {
            guard let rollup = rollupByVersion[version.id] else { continue }
            let label = version.resolvedLabel

            if rollup.nightCount < 3 {
                insights.append(ProtocolFormulaInsight(
                    kind: .lowData,
                    versionID: version.id,
                    headline: "\(label): need more nights",
                    body: "You have \(rollup.nightCount) of 3 minimum nights on \(label). Keep logging to see impact.",
                    isPositive: false
                ))
                continue
            }

            if let myMean = rollup.meanRestorativeMin, let baseMean = baseline.meanRestorativeMin {
                let delta = myMean - baseMean
                if abs(delta) >= 5 {
                    let kind: ProtocolFormulaInsightKind = delta > 0 ? .restorativeImprovement : .restorativeRegression
                    let sign = delta > 0 ? "+" : ""
                    let isPositive = delta > 0
                    insights.append(ProtocolFormulaInsight(
                        kind: kind,
                        versionID: version.id,
                        headline: "\(label): \(sign)\(Self.fmt(delta)) min restorative sleep",
                        body: "Averaging \(Self.fmt(myMean)) min vs your \(Self.fmt(baseMean)) min baseline. \(ProtocolImpactSummary.causalityCaveat)",
                        isPositive: isPositive
                    ))
                }
            }

            if let myBlock = rollup.meanLongestRestorativeBlockMin, let baseBlock = baseline.meanLongestRestorativeBlockMin {
                let delta = myBlock - baseBlock
                if delta >= 10 {
                    insights.append(ProtocolFormulaInsight(
                        kind: .longestBlockImprovement,
                        versionID: version.id,
                        headline: "\(label): +\(Self.fmt(delta)) min longest restorative block",
                        body: "Your longest uninterrupted restorative block averaged \(Self.fmt(myBlock)) min on \(label) vs \(Self.fmt(baseBlock)) min at baseline. \(ProtocolImpactSummary.causalityCaveat)",
                        isPositive: true
                    ))
                }
            }
        }

        return insights
    }

    private static func fmt(_ value: Double) -> String {
        if abs(value) >= 10 { return String(Int(value.rounded())) }
        return String(format: "%.1f", value)
    }
}
