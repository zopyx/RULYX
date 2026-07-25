import CommonCrypto
import CryptoKit
import Foundation

// MARK: - AccountExportCrypto

/// Passphrase-based encryption for the account backup export.
///
/// The account export contains Bluesky app passwords, so it is never written
/// as plaintext JSON. Format (AES-256-GCM over a PBKDF2-derived key):
///
/// ```json
/// {
///   "version": 1,
///   "kdf": "pbkdf2-sha256",
///   "kdfIterations": 210000,
///   "salt": "<base64, 16 bytes>",
///   "combined": "<base64, AES-GCM nonce+ciphertext+tag>"
/// }
/// ```
///
/// - Key derivation: PBKDF2-HMAC-SHA256, 210k iterations (OWASP 2023 guidance).
/// - Salt: fresh 16-byte CSPRNG salt per export.
/// - Authenticated encryption: AES-GCM — tampering fails decryption outright.
enum AccountExportCrypto {
    static let currentVersion = 1
    static let kdfIterations = 210_000
    private static let keyLength = 32 // AES-256

    struct Envelope: Codable {
        let version: Int
        let kdf: String
        let kdfIterations: Int
        let salt: String
        let combined: String
    }

    enum CryptoError: Error {
        case invalidEnvelope
        case keyDerivationFailed
        case decryptionFailed
    }

    /// Returns true if `data` looks like an encrypted export envelope
    /// (as opposed to a legacy plaintext JSON array export).
    static func isEncrypted(_ data: Data) -> Bool {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return false
        }
        return object["combined"] != nil && object["salt"] != nil
    }

    /// Encrypts the export payload with a user-chosen passphrase.
    static func encrypt(_ plaintext: Data, passphrase: String) throws -> Data {
        // 16 random bytes from the platform CSPRNG.
        let salt = SymmetricKey(size: .bits128).withUnsafeBytes { Data($0) }
        let key = try deriveKey(passphrase: passphrase, salt: salt, iterations: kdfIterations)
        let sealed = try AES.GCM.seal(plaintext, using: key)
        guard let combined = sealed.combined else {
            throw CryptoError.keyDerivationFailed
        }
        let envelope = Envelope(
            version: currentVersion,
            kdf: "pbkdf2-sha256",
            kdfIterations: kdfIterations,
            salt: salt.base64EncodedString(),
            combined: combined.base64EncodedString()
        )
        return try JSONEncoder().encode(envelope)
    }

    /// Decrypts an encrypted export envelope. Throws `decryptionFailed` on a
    /// wrong passphrase or tampered data (AES-GCM authentication failure).
    static func decrypt(_ data: Data, passphrase: String) throws -> Data {
        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
              envelope.kdf == "pbkdf2-sha256",
              let salt = Data(base64Encoded: envelope.salt),
              let combined = Data(base64Encoded: envelope.combined)
        else {
            throw CryptoError.invalidEnvelope
        }
        let key = try deriveKey(passphrase: passphrase, salt: salt, iterations: envelope.kdfIterations)
        let box = try AES.GCM.SealedBox(combined: combined)
        do {
            return try AES.GCM.open(box, using: key)
        } catch {
            throw CryptoError.decryptionFailed
        }
    }

    // MARK: - PBKDF2-HMAC-SHA256 (CommonCrypto)

    private static func deriveKey(passphrase: String, salt: Data, iterations: Int) throws -> SymmetricKey {
        let passwordData = Data(passphrase.utf8)
        var derived = Data(count: keyLength)
        let status: Int32 = derived.withUnsafeMutableBytes { derivedPtr in
            salt.withUnsafeBytes { saltPtr in
                passwordData.withUnsafeBytes { passwordPtr in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordPtr.baseAddress?.assumingMemoryBound(to: Int8.self),
                        passwordData.count,
                        saltPtr.baseAddress,
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        UInt32(iterations),
                        derivedPtr.baseAddress,
                        keyLength
                    )
                }
            }
        }
        guard status == kCCSuccess else {
            throw CryptoError.keyDerivationFailed
        }
        return SymmetricKey(data: derived)
    }
}
