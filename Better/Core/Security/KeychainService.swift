import Foundation
import Security

/// Stores and retrieves the per-install AES-256 encryption key from the iOS Keychain.
/// Items are bound to this device only and require the device to be unlocked for access.
enum KeychainService: Sendable {
    private static let service = Bundle.main.bundleIdentifier ?? "com.better.app"
    private static let defaultAccount = "healthDataEncryptionKey.v1"

    nonisolated static func storeKey(_ keyData: Data, account: String? = nil) throws {
        let resolvedAccount = account ?? defaultAccount
        let baseQuery: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: resolvedAccount
        ]
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
        let resolvedAccount = account ?? defaultAccount
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: resolvedAccount,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else {
            throw KeychainError.loadFailed(status)
        }
        return result as? Data
    }

    nonisolated static func deleteKey(account: String? = nil) throws {
        let resolvedAccount = account ?? defaultAccount
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: resolvedAccount
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status)
        }
    }
}

enum KeychainError: LocalizedError {
    case storeFailed(OSStatus)
    case loadFailed(OSStatus)
    case updateFailed(OSStatus)
    case deleteFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .storeFailed(let status): "Keychain store failed: \(status)"
        case .loadFailed(let status): "Keychain load failed: \(status)"
        case .updateFailed(let status): "Keychain update failed: \(status)"
        case .deleteFailed(let status): "Keychain delete failed: \(status)"
        }
    }
}
