import Foundation
import Observation

@MainActor
@Observable
final class SettingsViewModel {
    private let localRepository: LocalDataRepositoryProtocol
    private let healthRepository: HealthKitRepositoryProtocol
    private let syncCoordinator: SyncCoordinator
    private let analysisService: ResearchAnalysisService
    private let csvExporter: ResearchCSVExporter

    var profile: UserProfile = UserProfile()
    var healthAvailability: Bool = false
    var lastSuccessfulSync: Date?
    var connectedSources: [SleepSource] = []
    var exportURL: URL?
    var insightSummary: ResearchInsightSummary?
    var isExporting = false
    var isLoading = false
    var errorMessage: String?

    init(
        localRepository: LocalDataRepositoryProtocol,
        healthRepository: HealthKitRepositoryProtocol,
        syncCoordinator: SyncCoordinator
    ) {
        self.localRepository = localRepository
        self.healthRepository = healthRepository
        self.syncCoordinator = syncCoordinator
        self.analysisService = ResearchAnalysisService(localRepository: localRepository, healthRepository: healthRepository)
        self.csvExporter = ResearchCSVExporter()
    }

    func onAppear() async {
        await loadSettings()
    }

    func saveProfile() async {
        do {
            var updated = profile
            updated.updatedAt = Date()
            try await localRepository.saveProfile(updated)
            profile = updated
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func exportCSV(sessions: [SleepSession]) async {
        isExporting = true
        errorMessage = nil
        exportURL = nil
        do {
            guard let startDate = sessions.map(\.startDate).min(),
                  let endDate = sessions.map(\.endDate).max()
            else {
                throw ResearchExportError.noSessions
            }
            let package = try await analysisService.buildExportPackage(
                from: startDate,
                to: endDate,
                protocolItems: ProtocolCatalog.load()
            )
            exportURL = try csvExporter.writeZIP(package: package)
            insightSummary = package.insightSummary
        } catch {
            errorMessage = error.localizedDescription
        }
        isExporting = false
    }

    func exportRecentCSV() async {
        isExporting = true
        errorMessage = nil
        exportURL = nil
        do {
            let now = Date()
            let start = Calendar.current.date(byAdding: .day, value: -90, to: now)
                ?? now.addingTimeInterval(-90 * 86_400)
            let package = try await analysisService.buildExportPackage(
                from: start,
                to: now,
                protocolItems: ProtocolCatalog.load()
            )
            exportURL = try csvExporter.writeZIP(package: package)
            insightSummary = package.insightSummary
        } catch {
            errorMessage = error.localizedDescription
        }
        isExporting = false
    }

    func loadSettings() async {
        isLoading = true
        errorMessage = nil
        do {
            profile = try await localRepository.fetchProfile()
            healthAvailability = healthRepository.isHealthDataAvailable()
            lastSuccessfulSync = syncCoordinator.lastSyncedAt
            let now = Date()
            let startDate = Calendar.current.date(byAdding: .day, value: -30, to: now)
                ?? now.addingTimeInterval(-30 * 86_400)
            connectedSources = try await healthRepository.fetchSourceSummaries(from: startDate, to: now)
            await loadResearchInsight(now: now)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func loadResearchInsight(now: Date = Date()) async {
        do {
            let start = Calendar.current.date(byAdding: .day, value: -30, to: now)
                ?? now.addingTimeInterval(-30 * 86_400)
            let package = try await analysisService.buildExportPackage(
                from: start,
                to: now,
                protocolItems: ProtocolCatalog.load(),
                generatedAt: now
            )
            insightSummary = package.insightSummary
        } catch {
            insightSummary = nil
        }
    }
}

enum ResearchExportError: LocalizedError {
    case noSessions

    var errorDescription: String? {
        switch self {
        case .noSessions:
            "No cached sleep sessions are available to export."
        }
    }
}
