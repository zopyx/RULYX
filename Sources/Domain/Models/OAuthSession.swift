import Foundation

/// Represents an active OAuth 2.0 session for a Bluesky account.
///
/// Unlike the legacy `BlueskySession` (which stores a Bearer JWT), this model
/// holds DPoP-bound tokens and the metadata needed to refresh them and make
/// authenticated requests to the PDS.
struct OAuthSession: Codable {
    // MARK: - Account Identity

    /// The account's DID (Decentralized Identifier).
    let did: String
    /// The account's handle (e.g. `user.bsky.social`).
    let handle: String
    /// The PDS (Personal Data Server) URL for XRPC requests.
    let pdsURL: URL

    // MARK: - Tokens

    /// The current access token (DPoP-bound JWT, short-lived).
    var accessToken: String
    /// The current refresh token (single-use, rotated on each refresh).
    var refreshToken: String
    /// The space-separated scope string granted during authorization.
    let scope: String

    // MARK: - Timing

    /// The date when the access token expires.
    var expiresAt: Date

    /// Whether the access token is expired.
    var isExpired: Bool { Date() >= expiresAt }

    // MARK: - Keychain Reference

    /// The Keychain tag used to store the DPoP private key for this session.
    let dpopKeyTag: String

    // MARK: - Nonces

    /// The most recent DPoP nonce from the Authorization Server (for token endpoint).
    var asNonce: String?
    /// The most recent DPoP nonce from the Resource Server / PDS (for XRPC endpoints).
    var rsNonce: String?

    // MARK: - Authorization Server

    /// The resolved Authorization Server URL (from well-known metadata).
    let authorizationServerURL: URL

    // MARK: - Init

    init(
        did: String,
        handle: String,
        pdsURL: URL,
        accessToken: String,
        refreshToken: String,
        scope: String,
        expiresAt: Date,
        dpopKeyTag: String,
        asNonce: String? = nil,
        rsNonce: String? = nil,
        authorizationServerURL: URL
    ) {
        self.did = did
        self.handle = handle
        self.pdsURL = pdsURL
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.scope = scope
        self.expiresAt = expiresAt
        self.dpopKeyTag = dpopKeyTag
        self.asNonce = asNonce
        self.rsNonce = rsNonce
        self.authorizationServerURL = authorizationServerURL
    }
}
