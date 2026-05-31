import Foundation

/// Refreshes an OAuth access token using the refresh token with a DPoP proof.
///
/// The AT Protocol OAuth spec requires:
/// - Refresh tokens are **single-use** — each successful refresh returns a new refresh token
/// - Requests must include a DPoP proof JWT bound to the token endpoint URL
/// - Concurrent refresh attempts must be serialized (uses an actor for locking)
final class OAuthTokenRefresher: @unchecked Sendable {
    private let httpClient: HTTPClient
    private let keychain: KeychainServicing

    init(httpClient: HTTPClient = HTTPClient(), keychain: KeychainServicing = KeychainService()) {
        self.httpClient = httpClient
        self.keychain = keychain
    }

    /// Refreshes the access token for a session.
    /// - Parameter session: The current OAuth session to refresh.
    /// - Returns: A new `OAuthSession` with updated tokens, expiry, and nonces.
    /// - Throws: `OAuthRefreshError` if the refresh fails or the session is invalid.
    func refreshSession(_ session: OAuthSession) async throws -> OAuthSession {
        let dpop = try OAuthDPoP(keyTag: session.dpopKeyTag, keychain: keychain)

        let proof = try dpop.proof(
            httpMethod: "POST",
            httpURL: session.authorizationServerURL.appendingPathComponent(oAuthTokenPath),
            accessTokenHash: nil,
            nonce: session.asNonce
        )

        let body = RefreshTokenBody(refreshToken: session.refreshToken)
        let bodyData = try JSONEncoder().encode(body)

        var request = URLRequest(url: session.authorizationServerURL.appendingPathComponent(oAuthTokenPath))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("DPoP \(session.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(proof, forHTTPHeaderField: "DPoP")
        request.httpBody = bodyData

        let (data, httpResponse) = try await httpClient.data(for: request, source: "OAuth Token Refresh")
        let responseData = data

        // Handle DPoP nonce error
        if httpResponse.statusCode == 401 {
            if let nonce = httpResponse.allHeaderFields["DPoP-Nonce"] as? String {
                var retrySession = session
                retrySession.asNonce = nonce
                return try await refreshSession(retrySession)
            }
            throw OAuthRefreshError.refreshFailed
        }

        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            throw OAuthRefreshError.refreshFailed
        }

        let newNonce = httpResponse.allHeaderFields["DPoP-Nonce"] as? String
        let response = try JSONDecoder().decode(TokenRefreshResponse.self, from: responseData)

        guard let newExpiry = expiryDate(expiresIn: response.expiresIn) else {
            throw OAuthRefreshError.invalidExpiry
        }

        return OAuthSession(
            did: session.did,
            handle: session.handle,
            pdsURL: session.pdsURL,
            accessToken: response.accessToken,
            refreshToken: response.refreshToken ?? session.refreshToken,
            scope: response.scope ?? session.scope,
            expiresAt: newExpiry,
            dpopKeyTag: session.dpopKeyTag,
            asNonce: newNonce,
            rsNonce: session.rsNonce,
            authorizationServerURL: session.authorizationServerURL
        )
    }

    // MARK: - Private

    /// The OAuth token endpoint path (appended to the AS URL).
    private let oAuthTokenPath = "/oauth/token"

    /// Computes the expiry date from an `expires_in` value (seconds from now).
    private func expiryDate(expiresIn: Int) -> Date? {
        guard expiresIn > 0 else { return nil }
        return Date().addingTimeInterval(TimeInterval(expiresIn))
    }
}

// MARK: - Request / Response Models

private struct RefreshTokenBody: Encodable {
    let grantType = "refresh_token"
    let refreshToken: String

    enum CodingKeys: String, CodingKey {
        case grantType = "grant_type"
        case refreshToken = "refresh_token"
    }
}

private struct TokenRefreshResponse: Decodable {
    let accessToken: String
    let refreshToken: String?
    let scope: String?
    let expiresIn: Int
    let tokenType: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case scope
        case expiresIn = "expires_in"
        case tokenType = "token_type"
    }
}

// MARK: - Errors

enum OAuthRefreshError: Error, LocalizedError {
    case refreshFailed
    case invalidExpiry
    case sessionNotFound

    var errorDescription: String? {
        switch self {
        case .refreshFailed:
            "Failed to refresh the OAuth session. Please sign in again."
        case .invalidExpiry:
            "The refreshed session has an invalid expiry time."
        case .sessionNotFound:
            "No stored OAuth session found."
        }
    }
}

// MARK: - Concurrency

/// An actor that serializes token refresh attempts to prevent race conditions
/// when multiple requests simultaneously detect an expired token.
actor OAuthRefreshCoordinator {
    private let tokenStore: OAuthTokenStore
    private let refresher: OAuthTokenRefresher
    private var pendingTask: Task<OAuthSession, Error>?

    init(tokenStore: OAuthTokenStore, refresher: OAuthTokenRefresher) {
        self.tokenStore = tokenStore
        self.refresher = refresher
    }

    func refreshIfNeeded(accountID: String) async throws -> OAuthSession {
        if let existing = pendingTask {
            return try await existing.value
        }

        let task = Task { [tokenStore, refresher] () throws -> OAuthSession in
            guard var session = try tokenStore.readSession(for: accountID) else {
                throw OAuthRefreshError.sessionNotFound
            }

            if !session.isExpired {
                return session
            }

            session = try await refresher.refreshSession(session)
            try tokenStore.saveSession(session, for: accountID)
            return session
        }

        pendingTask = task
        defer { pendingTask = nil }
        return try await task.value
    }
}
