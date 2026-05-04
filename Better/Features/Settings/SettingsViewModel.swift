import Foundation
import Observation

@MainActor
@Observable
final class SettingsViewModel {
    private let localRepository: LocalDataRepositoryProtocol
    private let healthRepository: HealthKitRepositoryProtocol
    private let syncCoordinator: SyncCoordinator

    var profile: UserProfile = UserProfile()
    var healthAvailability: Bool = false
    var lastSuccessfulSync: Date?
    var connectedSources: [SleepSource] = []
    var exportURL: URL?
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
        let rows = Self.buildCSVRows(from: sessions)
        let csv = rows.joined(separator: "\n")
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("better_sleep_export.csv")
        do {
            try csv.write(to: temp, atomically: true, encoding: .utf8)
            exportURL = temp
        } catch {
            errorMessage = error.localizedDescription
        }
        isExporting = false
    }

    func exportRecentCSV() async {
        isExporting = true
        errorMessage = nil
        do {
            let now = Date()
            let start = Calendar.current.date(byAdding: .day, value: -90, to: now)
                ?? now.addingTimeInterval(-90 * 86_400)
            let sessions = try await localRepository.fetchCachedSessions(from: start, to: now)
            let rows = Self.buildCSVRows(from: sessions)
            let temp = FileManager.default.temporaryDirectory
                .appendingPathComponent("better_sleep_export.csv")
            try rows.joined(separator: "\n").write(to: temp, atomically: true, encoding: .utf8)
            exportURL = temp
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
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

private extension SettingsViewModel {
    static func buildCSVRows(from sessions: [SleepSession]) -> [String] {
        var rows = ["date,total_sleep_hrs,efficiency_pct,deep_hrs,rem_hrs,waso_min,latency_min,score,hrv_avg,resp_rate"]
        for s in sessions.sorted(by: { $0.sleepDateKey < $1.sleepDateKey }) {
            let deepHrs = s.dataQuality == .detailedStages
                ? String(format: "%.2f", s.deepDuration / 3_600) : ""
            let remHrs = s.dataQuality == .detailedStages
                ? String(format: "%.2f", s.remDuration / 3_600) : ""
            let parts: [String] = [
                s.sleepDateKey,
                String(format: "%.2f", s.totalSleepTime / 3_600),
                String(format: "%.1f", s.efficiency * 100),
                deepHrs,
                remHrs,
                String(format: "%.0f", s.waso / 60),
                String(format: "%.0f", s.sleepLatency / 60),
                String(format: "%.0f", s.qualityScore.overall),
                s.biometrics?.hrvAverage.map { String(format: "%.1f", $0) } ?? "",
                s.biometrics?.respiratoryRateAverage.map { String(format: "%.1f", $0) } ?? ""
            ]
            rows.append(parts.joined(separator: ","))
        }
        return rows
    }
}
