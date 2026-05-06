import CryptoKit
import XCTest
@testable import Better

final class EncryptionServiceTests: XCTestCase {
    /// Isolated Keychain account for this test instance — prevents parallel test
    /// runners from sharing state through the global production account.
    private var testAccount: String!
    private var service: EncryptionService!

    override func setUp() {
        super.setUp()
        testAccount = "test-\(UUID().uuidString)"
        service = EncryptionService(keychainAccount: testAccount)
        service.isEnabled = true
    }

    override func tearDown() {
        try? KeychainService.deleteKey(account: testAccount)
        service = nil
        testAccount = nil
        super.tearDown()
    }

    // MARK: - Round trip

    func testEncryptDecryptRoundTrip() throws {
        let original = "Sensitive sleep data: REM=1.5h, Deep=1.2h"
        let plaintext = Data(original.utf8)

        let ciphertext = try service.encrypt(plaintext)
        XCTAssertNotEqual(ciphertext, plaintext, "Encrypted bytes must differ from plaintext")

        let decrypted = try service.decrypt(ciphertext)
        XCTAssertEqual(decrypted, plaintext)
        XCTAssertEqual(String(data: decrypted, encoding: .utf8), original)
    }

    func testEncryptedDataIsNotReadableAsPlainText() throws {
        let secret = Data("my secret hrv value: 42ms".utf8)
        let encrypted = try service.encrypt(secret)

        XCTAssertNil(String(data: encrypted, encoding: .utf8), "Encrypted bytes should not decode as UTF-8 text")
    }

    func testEncryptProducesDifferentCiphertextsForSameInput() throws {
        let plain = Data("identical input".utf8)
        let first = try service.encrypt(plain)
        let second = try service.encrypt(plain)
        // AES-GCM uses a random nonce so two encryptions of the same data must differ.
        XCTAssertNotEqual(first, second)
    }

    // MARK: - Keychain key lifecycle

    func testKeyIsPersistedAcrossServiceInstances() throws {
        let plain = Data("baseline value".utf8)
        let ciphertext = try service.encrypt(plain)

        // A brand-new instance using the same isolated Keychain account must load
        // the persisted key and decrypt successfully.
        let freshService = EncryptionService(keychainAccount: testAccount)
        freshService.isEnabled = true
        let decrypted = try freshService.decrypt(ciphertext)
        XCTAssertEqual(decrypted, plain, "Fresh service must load the persisted Keychain key")
    }

    func testResetKeyMakesOldCiphertextUnreadable() throws {
        let plain = Data("sensitive".utf8)
        let ciphertext = try service.encrypt(plain)

        try service.resetKey()

        // After key reset, decrypt should fail (new key) or succeed with a new key
        // that produces different output. Either way, the old ciphertext is lost.
        XCTAssertThrowsError(try service.decrypt(ciphertext),
                             "Decryption with a new key must fail for data encrypted with the old key")
    }

    func testMissingKeychainKeyGeneratesNewKey() throws {
        // Delete key to simulate first-install scenario.
        try KeychainService.deleteKey(account: testAccount)

        let plain = Data("fresh install".utf8)
        let ciphertext = try service.encrypt(plain)
        let decrypted = try service.decrypt(ciphertext)
        XCTAssertEqual(decrypted, plain, "Should generate a new key and encrypt/decrypt successfully")

        // Key should now be persisted.
        XCTAssertNotNil(try KeychainService.loadKey(account: testAccount))
    }

    // MARK: - Disabled encryption (preview/test bypass)

    func testDisabledEncryptionPassesThroughData() throws {
        service.isEnabled = false
        let plain = Data("plaintext passthrough".utf8)
        XCTAssertEqual(try service.encrypt(plain), plain)
        XCTAssertEqual(try service.decrypt(plain), plain)
    }

    // MARK: - PersistenceJSON integration

    func testPersistenceJSONEncryptDecodeRoundTrip() throws {
        struct Payload: Codable, Equatable {
            var score: Double
            var label: String
        }
        let original = Payload(score: 87.5, label: "deep sleep anomaly")

        let encoded = try PersistenceJSON.encode(original)
        // Encoded bytes must not start with a JSON brace (they're AES-GCM combined form).
        XCTAssertFalse(encoded.starts(with: [UInt8(ascii: "{")]))

        let decoded = try PersistenceJSON.decode(Payload.self, from: encoded)
        XCTAssertEqual(decoded, original)
    }

    func testPersistenceJSONFallsBackToPlainJSONForLegacyData() throws {
        // Simulate pre-encryption plain JSON blob stored in the database.
        let plain = try JSONEncoder().encode(["key": "value"])
        let decoded = try PersistenceJSON.decode([String: String].self, from: plain)
        XCTAssertEqual(decoded["key"], "value", "Legacy plain-JSON data must still decode after encryption is enabled")
    }
}
