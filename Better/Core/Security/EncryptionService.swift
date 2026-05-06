import CryptoKit
import Foundation

/// AES-256-GCM encryption service.  The symmetric key is generated once per
/// install and stored in the iOS Keychain under
/// `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`.
final class EncryptionService: @unchecked Sendable {
    nonisolated static let shared = EncryptionService()

    private nonisolated(unsafe) var cachedKey: SymmetricKey?
    private let lock = NSLock()
    private let keychainAccount: String?

    /// Set to false during unit tests that should bypass encryption
    /// (e.g. testing plain-JSON fallback path without needing real Keychain).
    nonisolated(unsafe) var isEnabled: Bool = true

    /// `keychainAccount`: pass a non-nil string in tests to use an isolated
    /// Keychain slot instead of the shared production account.  Leave nil for
    /// production use.
    init(keychainAccount: String? = nil) {
        self.keychainAccount = keychainAccount
    }

    // MARK: - Public API

    nonisolated func encrypt(_ data: Data) throws -> Data {
        lock.lock()
        let enabled = isEnabled
        lock.unlock()
        guard enabled else { return data }
        let key = try loadOrCreateKey()
        let sealedBox = try AES.GCM.seal(data, using: key)
        guard let combined = sealedBox.combined else {
            throw EncryptionError.sealingFailed
        }
        return combined
    }

    nonisolated func decrypt(_ data: Data) throws -> Data {
        lock.lock()
        let enabled = isEnabled
        lock.unlock()
        guard enabled else { return data }
        let key = try loadOrCreateKey()
        let sealedBox = try AES.GCM.SealedBox(combined: data)
        return try AES.GCM.open(sealedBox, using: key)
    }

    /// Deletes the Keychain key and clears the in-memory cache.
    /// After this call, a new key will be generated on the next encrypt/decrypt.
    func resetKey() throws {
        lock.lock()
        defer { lock.unlock() }
        cachedKey = nil
        try KeychainService.deleteKey(account: keychainAccount)
    }

    // MARK: - Private

    nonisolated private func loadOrCreateKey() throws -> SymmetricKey {
        lock.lock()
        defer { lock.unlock() }

        if let key = cachedKey { return key }

        if let keyData = try KeychainService.loadKey(account: keychainAccount) {
            let key = SymmetricKey(data: keyData)
            cachedKey = key
            return key
        }

        let newKey = SymmetricKey(size: .bits256)
        let keyData = newKey.withUnsafeBytes { Data($0) }
        try KeychainService.storeKey(keyData, account: keychainAccount)
        cachedKey = newKey
        return newKey
    }
}

enum EncryptionError: LocalizedError {
    case sealingFailed
    case decryptionFailed

    var errorDescription: String? {
        switch self {
        case .sealingFailed: "Encryption failed to produce a sealed output."
        case .decryptionFailed: "Decryption failed — data may be corrupted or key unavailable."
        }
    }
}
