import CryptoKit
import Foundation
import Security

/// Manages a DPoP (Demonstration of Proof-of-Possession) keypair for a single OAuth session.
///
/// Generates an ES256 (P-256) keypair, stores the private key securely in the Keychain,
/// and produces DPoP proof JWTs bound to specific HTTP requests.
///
/// Each OAuth session gets its own `OAuthDPoP` instance with a unique `keyTag`.
/// The private key never leaves the Keychain — all signing operations happen via
/// the Security framework.
final class OAuthDPoP {
    private let keyTag: String
    private let keychain: KeychainServicing

    /// The base64url-encoded JWK Thumbprint (SHA-256 of the JWK) used as the `ath` claim.
    private(set) var jwkThumbprint: String?

    // MARK: - Init

    /// Creates a new DPoP manager. If no existing key is found for `keyTag`, a new one is generated.
    /// - Parameters:
    ///   - keyTag: Unique identifier for the key in the Keychain (e.g. the account UUID).
    ///   - keychain: The Keychain service for storage.
    init(keyTag: String, keychain: KeychainServicing = KeychainService()) throws {
        self.keyTag = "com.ajung.RULYX.dpop.\(keyTag)"
        self.keychain = keychain

        if try !keyExists() {
            try generateAndStoreKey()
        }
        jwkThumbprint = try computeJWKThumbprint()
    }

    // MARK: - DPoP Proof

    /// Creates a DPoP proof JWT for the given HTTP request.
    /// - Parameters:
    ///   - httpMethod: The HTTP method (e.g. "GET", "POST").
    ///   - httpURL: The full URL being requested.
    ///   - accessTokenHash: Base64url-encoded SHA-256 hash of the access token (`ath`).
    ///   - nonce: An optional server-provided nonce.
    /// - Returns: A signed DPoP proof JWT string.
    func proof(httpMethod: String, httpURL: URL, accessTokenHash: String?, nonce: String?) throws -> String {
        let jti = UUID().uuidString
        let iat = Int(Date().timeIntervalSince1970)

        let header = DPoPHeader(jwk: try jwk())
        let payload = DPoPPayload(
            jti: jti,
            htm: httpMethod,
            htu: httpURL.absoluteString,
            iat: iat,
            ath: accessTokenHash,
            nonce: nonce
        )

        let encodedHeader = try JSONEncoder().encode(header).base64URLEncodedString()
        let encodedPayload = try JSONEncoder().encode(payload).base64URLEncodedString()
        let signingInput = "\(encodedHeader).\(encodedPayload)"

        let signature = try sign(input: signingInput)
        let encodedSignature = signature.base64URLEncodedString()

        return "\(signingInput).\(encodedSignature)"
    }

    /// Removes the DPoP key from the Keychain.
    func deleteKey() throws {
        try keychain.delete(service: keychainService, account: keychainAccount)
    }

    // MARK: - Private

    private var keychainService: String { "com.ajung.RULYX.dpop" }
    private var keychainAccount: String { keyTag }

    private func keyExists() throws -> Bool {
        try keychain.read(service: keychainService, account: keychainAccount) != nil
    }

    private func generateAndStoreKey() throws {
        let privateKey = P256.Signing.PrivateKey(compactRepresentable: true)
        let rawBytes = privateKey.x963Representation
        try keychain.save(rawBytes.base64EncodedString(), service: keychainService, account: keychainAccount)
    }

    private func loadKey() throws -> P256.Signing.PrivateKey {
        guard let stored = try keychain.read(service: keychainService, account: keychainAccount),
              let data = Data(base64Encoded: stored)
        else {
            throw OAuthDPoPError.keyNotFound
        }
        return try P256.Signing.PrivateKey(x963Representation: data)
    }

    private func sign(input: String) throws -> Data {
        let privateKey = try loadKey()
        let inputData = Data(input.utf8)
        let signature = try privateKey.signature(for: inputData)
        return signature.rawRepresentation
    }

    private func jwk() throws -> JWK {
        let privateKey = try loadKey()
        let publicKey = privateKey.publicKey
        let raw = publicKey.x963Representation
        // x963 representation: 0x04 || X || Y (65 bytes for P-256)
        guard raw.count == 65 else {
            throw OAuthDPoPError.invalidKey
        }
        let x = raw[1..<33].base64URLEncodedString()
        let y = raw[33..<65].base64URLEncodedString()
        return JWK(kty: "EC", crv: "P-256", x: x, y: y)
    }

    private func computeJWKThumbprint() throws -> String? {
        let jwk = try jwk()
        let thumbprintInput = try JSONEncoder().encode(jwk)
        let hash = Data(SHA256.hash(data: thumbprintInput))
        return hash.base64URLEncodedString()
    }
}

// MARK: - Models

private struct DPoPHeader: Encodable {
    let typ = "dpop+jwt"
    let alg = "ES256"
    let jwk: JWK
}

private struct DPoPPayload: Encodable {
    let jti: String
    let htm: String
    let htu: String
    let iat: Int
    let ath: String?
    let nonce: String?

    enum CodingKeys: String, CodingKey {
        case jti, htm, htu, iat, ath, nonce
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(jti, forKey: .jti)
        try container.encode(htm, forKey: .htm)
        try container.encode(htu, forKey: .htu)
        try container.encode(iat, forKey: .iat)
        try container.encodeIfPresent(ath, forKey: .ath)
        try container.encodeIfPresent(nonce, forKey: .nonce)
    }
}

/// Minimal JWK representation for an EC P-256 public key.
private struct JWK: Encodable {
    let kty: String
    let crv: String
    let x: String
    let y: String
}

// MARK: - Errors

enum OAuthDPoPError: Error {
    case keyNotFound
    case invalidKey
}
