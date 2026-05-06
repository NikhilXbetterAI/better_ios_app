import Foundation
import Observation

nonisolated enum ProtocolComparisonDashboardStatus: Hashable, Sendable {
    case loading
    case enoughData
    case notEnoughData
    case unknownProtocolData
    case baselineBuilding
    case error(String)
}

nonisolated struct ProtocolComparisonMetricRow: Identifiable, Hashable, Sendable {
    var id: String { title }
    var title: String
    var takenValue: String
    var notTakenValue: String
    var deltaText: String?
    var isMeaningful: Bool
}

nonisolated struct ProtocolComparisonDashboardState: Hashable, Sendable {
    var status: ProtocolComparisonDashboardStatus
    var selectedWindow: ProtocolComparisonWindow
    var takenNightCount: Int
    var notTakenNightCount: Int
    var unknownNightCount: Int
    var confidence: ComparisonConfidence
    var metricRows: [ProtocolComparisonMetricRow]
    var insights: [SleepInsight]
    var stageDataAvailable: Bool
    var baselineValidNights: Int

    static let empty = ProtocolComparisonDashboardState(
        status: .loading,
        selectedWindow: .last30Days,
        takenNightCount: 0,
        notTakenNightCount: 0,
        unknownNightCount: 0,
        confidence: .unavailable,
        metricRows: [],
        insights: [],
        stageDataAvailable: false,
        baselineValidNights: 0
    )
}

@MainActor
@Observable
final class ProtocolComparisonDashboardViewModel {
    private let localRepository: LocalDataRepositoryProtocol
    private let comparisonService: ProtocolComparisonService
    private let insightService: ProtocolInsightService
    private let processor: SleepDataProcessor
    private let calendar: Calendar

    var selectedWindow: ProtocolComparisonWindow = .last30Days
    var state: ProtocolComparisonDashboardState = .empty
    var isLoading = false
    var errorMessage: String?

    init(
        localRepository: LocalDataRepositoryProtocol,
        comparisonService: ProtocolComparisonService? = nil,
        insightService: ProtocolInsightService = ProtocolInsightService(),
        processor: SleepDataProcessor = SleepDataProcessor(),
        calendar: Calendar = .current
    ) {
        self.localRepository = localRepository
        self.comparisonService = comparisonService ?? ProtocolComparisonService(calendar: calendar)
        self.insightService = insightService
        self.processor = processor
        self.calendar = calendar
    }

    func onAppear() async {
        await loadData(preferDefaultWindow: true)
    }

    func selectWindow(_ window: ProtocolComparisonWindow) async {
        selectedWindow = window
        await loadData(preferDefaultWindow: false)
    }

    func loadData(now: Date = Date(), preferDefaultWindow: Bool = false) async {
        isLoading = true
        errorMessage = nil
        
        let comparisonService = self.comparisonService
        let insightService = self.insightService
        let localRepository = self.localRepository
        let processor = self.processor
        let calendar = self.calendar
        let currentSelectedWindow = self.selectedWindow

        do {
            let state = try await Task.detached(priority: .userInitiated) {
                let profile = try await localRepository.fetchProfile()
                let sixtyDaysAgo = calendar.date(byAdding: .day, value: -60, to: now)
                    ?? now.addingTimeInterval(-60 * 86_400)
                let startDate = max(profile.createdAt, sixtyDaysAgo)
                let sessions = try await localRepository.fetchCachedSessions(from: startDate, to: now)
                let adherence = try await localRepository.fetchAdherence(from: startDate, to: now)
                let baselineSelection = BaselineEngine(processor: processor, calendar: calendar).selectBaseline(
                    from: sessions,
                    generatedAt: now
                )

                var windowToUse = currentSelectedWindow
                if preferDefaultWindow {
                    let thirtyDayResult = comparisonService.compare(
                        sessions: sessions,
                        adherence: adherence,
                        window: .last30Days,
                        endingAt: now
                    )
                    windowToUse = thirtyDayResult.confidence == .unavailable ? .all : .last30Days
                }

                let result = comparisonService.compare(
                    sessions: sessions,
                    adherence: adherence,
                    window: windowToUse,
                    endingAt: now
                )
                
                return Self.makeState(
                    result: result,
                    insights: insightService.insights(from: result),
                    baselineSelection: baselineSelection
                )
            }.value
            
            self.state = state
            self.selectedWindow = state.selectedWindow
        } catch {
            errorMessage = error.localizedDescription
            state = ProtocolComparisonDashboardState(
                status: .error(error.localizedDescription),
                selectedWindow: selectedWindow,
                takenNightCount: 0,
                notTakenNightCount: 0,
                unknownNightCount: 0,
                confidence: .unavailable,
                metricRows: [],
                insights: [],
                stageDataAvailable: false,
                baselineValidNights: 0
            )
        }
        isLoading = false
    }
}

extension ProtocolComparisonDashboardViewModel {
    nonisolated static func makeState(
        result: ProtocolComparisonResult,
        insights: [SleepInsight],
        baselineSelection: BaselineSelection
    ) -> ProtocolComparisonDashboardState {
        let status: ProtocolComparisonDashboardStatus
        if baselineSelection.isBuilding {
            status = .baselineBuilding
        } else if result.takenNightCount == 0, result.notTakenNightCount == 0, result.unknownNightCount > 0 {
            status = .unknownProtocolData
        } else if result.confidence == .unavailable {
            status = .notEnoughData
        } else {
            status = .enoughData
        }

        let rows = [
            durationRow(result),
            efficiencyRow(result),
            stageRow(title: "Deep Sleep", taken: result.averageDeepSleepTaken, notTaken: result.averageDeepSleepNotTaken, delta: result.deltaDeepSleep),
            stageRow(title: "REM Sleep", taken: result.averageREMSleepTaken, notTaken: result.averageREMSleepNotTaken, delta: result.deltaREMSleep),
            stageRow(title: "Awake Time", taken: result.averageAwakeTimeTaken, notTaken: result.averageAwakeTimeNotTaken, delta: result.deltaAwakeTime, threshold: ProtocolInsightService.meaningfulAwakeDelta)
        ].compactMap { $0 }

        return ProtocolComparisonDashboardState(
            status: status,
            selectedWindow: result.window,
            takenNightCount: result.takenNightCount,
            notTakenNightCount: result.notTakenNightCount,
            unknownNightCount: result.unknownNightCount,
            confidence: result.confidence,
            metricRows: rows,
            insights: insights,
            stageDataAvailable: result.deltaDeepSleep != nil || result.deltaREMSleep != nil,
            baselineValidNights: baselineSelection.validNightCount
        )
    }

    nonisolated static func durationRow(_ result: ProtocolComparisonResult) -> ProtocolComparisonMetricRow? {
        guard let taken = result.averageTotalSleepTaken, let notTaken = result.averageTotalSleepNotTaken else { return nil }
        let delta = result.deltaTotalSleep
        return ProtocolComparisonMetricRow(
            title: "Sleep Duration",
            takenValue: formatDuration(taken),
            notTakenValue: formatDuration(notTaken),
            deltaText: delta.map { formatSignedMinutes($0) },
            isMeaningful: delta.map { abs($0) >= ProtocolInsightService.meaningfulDurationDelta } ?? false
        )
    }

    nonisolated static func efficiencyRow(_ result: ProtocolComparisonResult) -> ProtocolComparisonMetricRow? {
        guard let taken = result.averageEfficiencyTaken, let notTaken = result.averageEfficiencyNotTaken else { return nil }
        let delta = result.deltaEfficiency
        return ProtocolComparisonMetricRow(
            title: "Efficiency",
            takenValue: formatPercent(taken),
            notTakenValue: formatPercent(notTaken),
            deltaText: delta.map { formatSignedPercentagePoints($0) },
            isMeaningful: delta.map { abs($0) >= ProtocolInsightService.meaningfulEfficiencyDelta } ?? false
        )
    }

    nonisolated static func stageRow(
        title: String,
        taken: TimeInterval?,
        notTaken: TimeInterval?,
        delta: TimeInterval?,
        threshold: TimeInterval = ProtocolInsightService.meaningfulStageDelta
    ) -> ProtocolComparisonMetricRow? {
        guard let taken, let notTaken else { return nil }
        return ProtocolComparisonMetricRow(
            title: title,
            takenValue: formatDuration(taken),
            notTakenValue: formatDuration(notTaken),
            deltaText: delta.map { formatSignedMinutes($0) },
            isMeaningful: delta.map { abs($0) >= threshold } ?? false
        )
    }

    nonisolated static func formatDuration(_ duration: TimeInterval) -> String {
        let totalMinutes = max(0, Int((duration / 60).rounded()))
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
    }

    nonisolated static func formatPercent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }

    nonisolated static func formatSignedMinutes(_ duration: TimeInterval) -> String {
        let minutes = Int((duration / 60).rounded())
        return "\(minutes >= 0 ? "+" : "")\(minutes)m"
    }

    nonisolated static func formatSignedPercentagePoints(_ value: Double) -> String {
        let points = Int((value * 100).rounded())
        return "\(points >= 0 ? "+" : "")\(points)pp"
    }
}
