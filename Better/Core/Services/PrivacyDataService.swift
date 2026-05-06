import Foundation

/// Orchestrates all user-visible privacy operations: data inventory, delete,
/// and re-sync.  Does NOT interact with Apple Health data directly — it only
/// manages data stored by this app.
@MainActor
@Observable
final class PrivacyDataService {
    private let localRepository: LocalDataRepositoryProtocol
    private let syncCoordinator: SyncCoordinator

    var inventory: LocalDataInventory?
    var isLoading = false
    var errorMessage: String?
    var deleteCompleted = false

    init(localRepository: LocalDataRepositoryProtocol, syncCoordinator: SyncCoordinator) {
        self.localRepository = localRepository
        self.syncCoordinator = syncCoordinator
    }

    // MARK: - Public API

    func loadInventory() async {
        isLoading = true
        errorMessage = nil
        do {
            inventory = try await localRepository.fetchDataInventory()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    /// Deletes all locally-stored health data, resets migration state so the
    /// next sync writes encrypted records, and clears the Keychain encryption key
    /// (a new key is generated automatically on the next encrypt call).
    func deleteAllLocalData() async {
        isLoading = true
        errorMessage = nil
        deleteCompleted = false
        do {
            try await localRepository.deleteAllHealthData()
            DataMigrationService.resetMigrationVersion()
            inventory = LocalDataInventory(
                sleepSessionCount: 0,
                baselineCount: 0,
                alertCount: 0,
                protocolAdherenceCount: 0,
                activityLogCount: 0,
                manualBiologyEntryCount: 0,
                contextEntryCount: 0
            )
            deleteCompleted = true
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    /// Triggers a full foreground re-sync from Apple Health.
    func resyncFromAppleHealth() async {
        isLoading = true
        errorMessage = nil
        await syncCoordinator.performForegroundRefresh()
        if case .failed(let message) = syncCoordinator.phase {
            errorMessage = message
        }
        await loadInventory()
        isLoading = false
    }
}
