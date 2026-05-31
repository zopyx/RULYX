import CryptoKit
import Foundation

/// Proof Key for Code Exchange (PKCE) for the OAuth 2.0 Authorization Code flow.
/// Generates a cryptographically random `code_verifier` and its SHA-256 `code_challenge`,
/// both base64url-encoded without padding as required by RFC 7636.
struct OAuthPKCE {
    /// The raw `code_verifier` — 32 random bytes, base64url-encoded.
    let verifier: String
    /// The `code_challenge` — SHA-256 hash of `verifier`, base64url-encoded.
    let challenge: String
    /// The challenge method; always `"S256"`.
    let method = "S256"

    init() {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let data = Data(bytes)
        verifier = data.base64URLEncodedString()
        let hash = Data(SHA256.hash(data: Data(verifier.utf8)))
        challenge = hash.base64URLEncodedString()
    }

    /// Verifies that a `code_verifier` matches a given `code_challenge` using S256.
    static func verify(verifier: String, challenge: String) -> Bool {
        let hash = Data(SHA256.hash(data: Data(verifier.utf8)))
        return hash.base64URLEncodedString() == challenge
    }
}

// MARK: - Base64url Encoding

extension Data {
    /// Returns a base64url-encoded string (RFC 4648 §5) without padding characters.
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
