@testable import RULYX
import XCTest

/// Tests for the passphrase-based account export encryption.
final class AccountExportCryptoTests: XCTestCase {
    private func makePayload() throws -> Data {
        let entries: [[String: String]] = [
            ["handle": "alice.bsky.social", "displayName": "Alice", "appPassword": "aaaa-bbbb-cccc-dddd"],
            [
                "handle": "bob.example.com",
                "displayName": "Bob",
                "appPassword": "eeee-ffff-gggg-hhhh",
                "entrywayURL": "pds.example.com",
            ],
        ]
        return try JSONSerialization.data(withJSONObject: entries, options: [.prettyPrinted, .sortedKeys])
    }

    func testEncryptDecryptRoundtrip() throws {
        let plaintext = try makePayload()
        let encrypted = try AccountExportCrypto.encrypt(plaintext, passphrase: "correct horse battery staple")
        XCTAssertTrue(AccountExportCrypto.isEncrypted(encrypted))
        XCTAssertFalse(AccountExportCrypto.isEncrypted(plaintext))
        // No secret material may appear in the envelope.
        let envelopeText = String(decoding: encrypted, as: UTF8.self)
        XCTAssertFalse(envelopeText.contains("aaaa-bbbb"))
        XCTAssertFalse(envelopeText.contains("alice.bsky.social"))
        let decrypted = try AccountExportCrypto.decrypt(encrypted, passphrase: "correct horse battery staple")
        XCTAssertEqual(decrypted, plaintext)
    }

    func testWrongPassphraseFails() throws {
        let encrypted = try AccountExportCrypto.encrypt(makePayload(), passphrase: "right")
        XCTAssertThrowsError(try AccountExportCrypto.decrypt(encrypted, passphrase: "wrong")) { error in
            XCTAssertEqual(error as? AccountExportCrypto.CryptoError, .decryptionFailed)
        }
    }

    func testTamperedCiphertextFails() throws {
        let encrypted = try AccountExportCrypto.encrypt(makePayload(), passphrase: "pw")
        var envelope = try XCTUnwrap(JSONSerialization.jsonObject(with: encrypted) as? [String: Any])
        var combined = try XCTUnwrap(try Data(base64Encoded: XCTUnwrap(envelope["combined"] as? String)))
        combined[combined.count - 5] ^= 0xFF
        envelope["combined"] = combined.base64EncodedString()
        let tampered = try JSONSerialization.data(withJSONObject: envelope)
        XCTAssertThrowsError(try AccountExportCrypto.decrypt(tampered, passphrase: "pw"))
    }

    func testSaltIsRandomPerExport() throws {
        let plaintext = try makePayload()
        let first = try AccountExportCrypto.encrypt(plaintext, passphrase: "pw")
        let second = try AccountExportCrypto.encrypt(plaintext, passphrase: "pw")
        XCTAssertNotEqual(first, second)
    }

    func testCorruptedEnvelopeThrowsInvalidEnvelope() {
        let garbage = Data("{\"combined\":\"!!!\",\"salt\":\"???\"}".utf8)
        XCTAssertTrue(AccountExportCrypto.isEncrypted(garbage))
        XCTAssertThrowsError(try AccountExportCrypto.decrypt(garbage, passphrase: "pw")) { error in
            XCTAssertEqual(error as? AccountExportCrypto.CryptoError, .invalidEnvelope)
        }
    }

    func testLegacyPlaintextIsNotDetectedAsEncrypted() throws {
        XCTAssertFalse(try AccountExportCrypto.isEncrypted(makePayload()))
    }
}
