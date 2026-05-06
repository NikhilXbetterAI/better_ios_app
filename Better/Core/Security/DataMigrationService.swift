import Foundation

/// Runs one-time, versioned data migrations.
///
/// Version 1 – Encrypts all legacy plain-JSON blobs in the SwiftData store.
/// The migration is idempotent: if interrupted it will re-run on the next launch
/// and safely re-encrypt already-encrypted data (PersistenceJSON.decode handles
/// the decrypt-then-re-encrypt round trip transparently).
struct DataMigrationService: Sendable {
    private static let migrationVersionKey = "betterStorageMigrationVersion"
    private static let currentVersion = 1

    private let repository: LocalDataRepositoryProtocol

    init(repository: LocalDataRepositoryProtocol) {
        self.repository = repository
    }

    // MARK: - Public

    func migrateIfNeeded() async {
        let completedVersion = UserDefaults.standard.integer(forKey: Self.migrationVersionKey)
        guard completedVersion < Self.currentVersion else { return }

        do {
            if completedVersion < 1 {
                try await repository.migrateToEncryptedStorage()
            }
            UserDefaults.standard.set(Self.currentVersion, forKey: Self.migrationVersionKey)
        } catch {
            // Migration will retry on next launch.  The app remains functional
            // because PersistenceJSON.decode falls back to plain JSON for any
            // records that weren't re-encrypted.
        }
    }

    /// Resets the migration version so the next launch will re-run all migrations.
    /// Used during "Delete all health data" so a fresh sync gets encrypted storage.
    static func resetMigrationVersion() {
        UserDefaults.standard.removeObject(forKey: migrationVersionKey)
    }
}
