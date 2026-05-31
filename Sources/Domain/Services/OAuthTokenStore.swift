import Foundation

/// Manages Keychain persistence for OAuth sessions and DPoP keys.
///
/// Each account's OAuth session is stored under a Keychain service
/// `com.ajung.RULYX.oauth-session` keyed by the account's UUID string.
/// DPoP private keys are stored by a separate `OAuthDPoP` instance.
final class OAuthTokenStore: ObservableObject, @unchecked Sendable {
    private let keychain: KeychainServicing
    private static let sessionService = "com.ajung.RULYX.oauth-session"

    init(keychain: KeychainServicing = KeychainService()) {
        self.keychain = keychain
    }

    // MARK: - Session Persistence

    /// Saves an OAuth session to the Keychain for a given account ID.
    func saveSession(_ session: OAuthSession, for accountID: String) throws {
        let data = try JSONEncoder().encode(session)
        guard let value = String(data: data, encoding: .utf8) else {
            throw OAuthTokenStoreError.encodingFailed
        }
        try keychain.save(value, service: Self.sessionService, account: accountID)
    }

    /// Reads an OAuth session from the Keychain for a given account ID.
    func readSession(for accountID: String) throws -> OAuthSession? {
        guard let value = try keychain.read(service: Self.sessionService, account: accountID),
              let data = value.data(using: .utf8)
        else {
            return nil
        }
        return try JSONDecoder().decode(OAuthSession.self, from: data)
    }

    /// Deletes an OAuth session from the Keychain for a given account ID.
    func deleteSession(for accountID: String) throws {
        try keychain.delete(service: Self.sessionService, account: accountID)
    }

    /// Updates the access token, refresh token, expiry, and nonces in-place
    /// without rewriting the entire session object.
    func updateTokens(
        for accountID: String,
        accessToken: String,
        refreshToken: String,
        expiresAt: Date,
        asNonce: String?,
        rsNonce: String?
    ) throws {
        guard var session = try readSession(for: accountID) else {
            throw OAuthTokenStoreError.sessionNotFound
        }
        session.accessToken = accessToken
        session.refreshToken = refreshToken
        session.expiresAt = expiresAt
        session.asNonce = asNonce
        session.rsNonce = rsNonce
        try saveSession(session, for: accountID)
    }

    /// Updates only the nonces for the AS and RS.
    func updateNonces(for accountID: String, asNonce: String?, rsNonce: String?) throws {
        guard var session = try readSession(for: accountID) else {
            throw OAuthTokenStoreError.sessionNotFound
        }
        session.asNonce = asNonce
        session.rsNonce = rsNonce
        try saveSession(session, for: accountID)
    }

    // MARK: - Discovery Cache

    /// Caches well-known metadata responses so they aren't fetched on every launch.
    /// Keys are the URL of the well-known endpoint; values are the raw JSON data.
    private static let metadataCacheService = "com.ajung.RULYX.oauth-metadata"
    private static let metadataCacheAccount = "discovery-cache"

    func saveMetadataCache(_ json: String) throws {
        try keychain.save(json, service: Self.metadataCacheService, account: Self.metadataCacheAccount)
    }

    func readMetadataCache() throws -> String? {
        try keychain.read(service: Self.metadataCacheService, account: Self.metadataCacheAccount)
    }

    func clearMetadataCache() throws {
        try keychain.delete(service: Self.metadataCacheService, account: Self.metadataCacheAccount)
    }
}

// MARK: - Errors

enum OAuthTokenStoreError: Error {
    case encodingFailed
    case sessionNotFound
}
