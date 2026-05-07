import Foundation
import Security

/// Stores and retrieves the per-install AES-256 encryption key from the iOS Keychain.
/// Items are bound to this device only and require the device to be unlocked for access.
enum KeychainService: Sendable {
    nonisolated static func storeKey(_ keyData: Data, account: String? = nil) throws {
        let resolvedAccount = Self.resolvedAccount(account)
        let baseQuery = Self.baseQuery(account: resolvedAccount)
        let insertQuery = baseQuery.merging([
            kSecValueData: keyData,
            kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ] as [CFString: Any]) { _, new in new }

        let status = SecItemAdd(insertQuery as CFDictionary, nil)
        if status == errSecDuplicateItem {
            let updateAttributes: [CFString: Any] = [kSecValueData: keyData]
            let updateStatus = SecItemUpdate(baseQuery as CFDictionary, updateAttributes as CFDictionary)
            guard updateStatus == errSecSuccess else {
                throw KeychainError.updateFailed(updateStatus)
            }
        } else if status != errSecSuccess {
            throw KeychainError.storeFailed(status)
        }
    }

    nonisolated static func loadKey(account: String? = nil) throws -> Data? {
        let resolvedAccount = Self.resolvedAccount(account)
        let query = Self.baseQuery(account: resolvedAccount).merging([
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ] as [CFString: Any]) { _, new in new }

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else {
            throw KeychainError.loadFailed(status)
        }
        return result as? Data
    }

    nonisolated static func deleteKey(account: String? = nil) throws {
        let resolvedAccount = Self.resolvedAccount(account)
        let query = Self.baseQuery(account: resolvedAccount)
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status)
        }
    }

    nonisolated private static func resolvedAccount(_ account: String?) -> String {
        account ?? "healthDataEncryptionKey.v1"
    }

    nonisolated private static func baseQuery(account: String) -> [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: "ai.better-health.Better",
            kSecAttrAccount: account
        ]
    }
}

enum KeychainError: LocalizedError {
    case storeFailed(OSStatus)
    case loadFailed(OSStatus)
    case updateFailed(OSStatus)
    case deleteFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .storeFailed(let status): "Keychain store failed: \(Self.describe(status))"
        case .loadFailed(let status): "Keychain load failed: \(Self.describe(status))"
        case .updateFailed(let status): "Keychain update failed: \(Self.describe(status))"
        case .deleteFailed(let status): "Keychain delete failed: \(Self.describe(status))"
        }
    }

    private static func describe(_ status: OSStatus) -> String {
        SecCopyErrorMessageString(status, nil).map { $0 as String } ?? "OSStatus \(status)"
    }
}
