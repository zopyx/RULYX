import AuthenticationServices
import CryptoKit
import Foundation

/// Orchestrates the full OAuth 2.0 Authorization Code flow + PKCE + DPoP
/// for Bluesky AT Protocol authentication.
///
/// Flow:
/// 1. Resolve handle → DID → PDS URL
/// 2. Fetch Authorization Server metadata from PDS well-known endpoints
/// 3. Generate PKCE challenge, DPoP key, and state token
/// 4. Submit PAR (Pushed Authorization Request)
/// 5. Open ASWebAuthenticationSession for user browser auth
/// 6. Handle callback → extract authorization code
/// 7. Exchange code for tokens via token endpoint
/// 8. Return OAuthSession
@MainActor
final class OAuthAuthorizationFlow: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {
    private let httpClient: HTTPClient
    private let keychain: KeychainServicing
    private let requestExecutor: BlueskyRequestExecuting
    private let tokenStore: OAuthTokenStore
    private let endpointResolver: OAuthEndpointResolver
    private let tokenRefresher: OAuthTokenRefresher

    /// The client_id for OAuth. Must be a public HTTPS URL hosting the client metadata JSON.
    /// Uses the raw GitHub URL by default for development. Override in production.
    private let clientID: String

    /// The custom URL scheme for the OAuth redirect callback.
    private let callbackScheme = "com.ajung.rulyx"
    /// The OAuth redirect URI path.
    private let callbackPath = "/oauth-callback"

    init(
        httpClient: HTTPClient = HTTPClient(),
        keychain: KeychainServicing = KeychainService(),
        requestExecutor: BlueskyRequestExecuting = BlueskyRequestExecutor(),
        tokenStore: OAuthTokenStore = OAuthTokenStore(),
        endpointResolver: OAuthEndpointResolver = OAuthEndpointResolver(),
        tokenRefresher: OAuthTokenRefresher = OAuthTokenRefresher(),
        clientID: String = "https://raw.githubusercontent.com/zopyx/RULYX/feat/oauth/oauth-client-metadata.json"
    ) {
        self.httpClient = httpClient
        self.keychain = keychain
        self.requestExecutor = requestExecutor
        self.tokenStore = tokenStore
        self.endpointResolver = endpointResolver
        self.tokenRefresher = tokenRefresher
        self.clientID = clientID
    }

    // MARK: - Full Auth Flow

    /// Runs the complete OAuth sign-in flow using a PDS entryway URL.
    /// The user authenticates directly on the provider's web page — no handle needed up front.
    /// The DID and handle are obtained from the OAuth token response after successful auth.
    /// - Parameter entrywayURL: The PDS entryway URL (e.g. `https://bsky.social` or `https://eurosky.social`).
    /// - Returns: An `OAuthSession` on success.
    func signIn(entrywayURL: URL) async throws -> OAuthSession {
        // 1. Resolve Authorization Server metadata from the PDS
        let asMetadata = try await endpointResolver.resolveAuthorizationServer(pdsURL: entrywayURL)
        let asURL = asMetadata.issuer

        // 2. Generate PKCE, DPoP key, state
        let pkce = OAuthPKCE()
        let state = UUID().uuidString
        let dpopKeyTag = UUID().uuidString
        let dpop = try OAuthDPoP(keyTag: dpopKeyTag, keychain: keychain)

        // 3. Submit PAR — no login_hint, user enters their handle on the provider's page
        let parURL = try await submitPAR(
            asMetadata: asMetadata,
            pkce: pkce,
            state: state,
            dpop: dpop,
            handle: nil
        )

        // 4. Open browser for user auth
        let callbackURL = try await openAuthenticationSession(authorizationURL: parURL)

        // 5. Handle callback — validate state, extract code
        let code = try handleCallback(callbackURL: callbackURL, expectedState: state)

        // 6. Exchange code for tokens — the DID comes from the `sub` claim
        let session = try await exchangeCode(
            code: code,
            pkce: pkce,
            dpop: dpop,
            dpopKeyTag: dpopKeyTag,
            asMetadata: asMetadata,
            did: nil,
            handle: nil,
            pdsURL: entrywayURL
        )

        return session
    }

    /// Runs the complete OAuth sign-in flow for a given handle.
    /// - Parameters:
    ///   - handle: The Bluesky handle to authenticate.
    ///   - entrywayURL: Optional PDS entryway URL. If provided, handle resolution
    ///     is routed through this PDS instead of the default bsky.social.
    /// - Returns: An `OAuthSession` on success.
    func signIn(handle: String, entrywayURL: URL? = nil) async throws -> OAuthSession {
        // 1. Resolve handle → DID → PDS URL
        let (did, pdsURL) = try await resolveAccount(handle: handle, entrywayURL: entrywayURL)

        // 2. Resolve Authorization Server metadata
        let asMetadata = try await endpointResolver.resolveAuthorizationServer(pdsURL: pdsURL)
        let asURL = asMetadata.issuer

        // 3. Generate PKCE, DPoP key, state
        let pkce = OAuthPKCE()
        let state = UUID().uuidString
        let dpopKeyTag = UUID().uuidString
        let dpop = try OAuthDPoP(keyTag: dpopKeyTag, keychain: keychain)

        // 4. Submit PAR
        let parURL = try await submitPAR(
            asMetadata: asMetadata,
            pkce: pkce,
            state: state,
            dpop: dpop,
            handle: handle
        )

        // 5. Open browser for user auth
        let callbackURL = try await openAuthenticationSession(authorizationURL: parURL)

        // 6. Handle callback — validate state, extract code
        let code = try handleCallback(callbackURL: callbackURL, expectedState: state)

        // 7. Exchange code for tokens
        let session = try await exchangeCode(
            code: code,
            pkce: pkce,
            dpop: dpop,
            dpopKeyTag: dpopKeyTag,
            asMetadata: asMetadata,
            did: did,
            handle: handle,
            pdsURL: pdsURL
        )

        return session
    }

    // MARK: - Step 1: Resolve Account

    private func resolveAccount(handle: String, entrywayURL: URL?) async throws -> (did: String, pdsURL: URL) {
        let hostURL = entrywayURL ?? URL(string: "https://bsky.social")!

        // Resolve handle to DID via the AT Protocol
        let did: String = try await requestExecutor.send(
            path: "com.atproto.identity.resolveHandle",
            method: "GET",
            queryItems: [URLQueryItem(name: "handle", value: handle)],
            accessToken: nil,
            hostURL: hostURL
        )

        // Resolve DID to PDS URL — use the entryway as hint, fall back to bsky.social
        let didHostURL = entrywayURL ?? URL(string: "https://bsky.social")!
        let didDocument: DIDDocument = try await requestExecutor.send(
            path: "com.atproto.identity.resolveDid",
            method: "GET",
            queryItems: [URLQueryItem(name: "did", value: did)],
            accessToken: nil,
            hostURL: didHostURL
        )

        guard let pdsEndpoint = didDocument.services.first(where: {
            $0.id.contains("#atproto_pds") || $0.type == "AtprotoPersonalDataServer"
        })?.serviceEndpoint else {
            throw OAuthFlowError.pdsURLNotFound
        }

        return (did, pdsEndpoint)
    }

    // MARK: - Step 2: Submit PAR

    private func submitPAR(
        asMetadata: OAuthAuthorizationServerMetadata,
        pkce: OAuthPKCE,
        state: String,
        dpop: OAuthDPoP,
        handle: String?
    ) async throws -> URL {
        guard let parEndpoint = asMetadata.pushedAuthorizationRequestEndpoint else {
            throw OAuthFlowError.parNotSupported
        }

        let dpopProof = try dpop.proof(
            httpMethod: "POST",
            httpURL: parEndpoint,
            accessTokenHash: nil,
            nonce: nil
        )

        let parBody = PARBody(
            clientID: clientID,
            responseType: "code",
            codeChallenge: pkce.challenge,
            codeChallengeMethod: pkce.method,
            state: state,
            redirectURI: "\(callbackScheme):\(callbackPath)",
            scope: "atproto transition:generic transition:chat.bsky",
            loginHint: handle
        )
        let bodyData = try JSONEncoder().encode(parBody)

        var request = URLRequest(url: parEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(dpopProof, forHTTPHeaderField: "DPoP")
        request.httpBody = bodyData

        let (data, httpResponse) = try await httpClient.data(for: request, source: "OAuth PAR")

        // Handle DPoP nonce error
        if httpResponse.statusCode == 401 {
            if let nonce = httpResponse.allHeaderFields["DPoP-Nonce"] as? String {
                let retryProof = try dpop.proof(
                    httpMethod: "POST",
                    httpURL: parEndpoint,
                    accessTokenHash: nil,
                    nonce: nonce
                )
                request.setValue(retryProof, forHTTPHeaderField: "DPoP")
                let (retryData, retryResponse) = try await httpClient.data(for: request, source: "OAuth PAR")
                guard (200 ..< 300).contains(retryResponse.statusCode) else {
                    throw OAuthFlowError.parFailed(retryResponse.statusCode)
                }
                let parResponse = try JSONDecoder().decode(PARResponse.self, from: retryData)
                return authorizationURL(asMetadata: asMetadata, requestURI: parResponse.requestURI)
            }
            throw OAuthFlowError.parFailed(httpResponse.statusCode)
        }

        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            throw OAuthFlowError.parFailed(httpResponse.statusCode)
        }

        let parResponse = try JSONDecoder().decode(PARResponse.self, from: data)
        return authorizationURL(asMetadata: asMetadata, requestURI: parResponse.requestURI)
    }

    private func authorizationURL(asMetadata: OAuthAuthorizationServerMetadata, requestURI: String) -> URL {
        var components = URLComponents(url: asMetadata.authorizationEndpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "request_uri", value: requestURI),
        ]
        return components.url!
    }

    // MARK: - Step 3: Open Browser

    private func openAuthenticationSession(authorizationURL: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { [weak self] continuation in
            guard let self else {
                continuation.resume(throwing: OAuthFlowError.deallocated)
                return
            }

            let session = ASWebAuthenticationSession(
                url: authorizationURL,
                callbackURLScheme: callbackScheme
            ) { callbackURL, error in
                if let error {
                    if let sessionError = error as? ASWebAuthenticationSessionError, sessionError.code == .canceledLogin {
                        continuation.resume(throwing: OAuthFlowError.userCancelled)
                    } else {
                        continuation.resume(throwing: error)
                    }
                    return
                }
                guard let callbackURL else {
                    continuation.resume(throwing: OAuthFlowError.missingCallback)
                    return
                }
                continuation.resume(returning: callbackURL)
            }

            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            session.start()
        }
    }

    func presentationAnchor(for _: ASWebAuthenticationSession) -> ASPresentationAnchor {
        ASPresentationAnchor()
    }

    // MARK: - Step 4: Handle Callback

    private func handleCallback(callbackURL: URL, expectedState: String) throws -> String {
        guard let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false) else {
            throw OAuthFlowError.invalidCallback
        }

        let params = components.queryItems ?? []

        if let error = params.first(where: { $0.name == "error" })?.value {
            throw OAuthFlowError.authorizationError(error)
        }

        let state = params.first(where: { $0.name == "state" })?.value
        guard state == expectedState else {
            throw OAuthFlowError.stateMismatch
        }

        guard let code = params.first(where: { $0.name == "code" })?.value else {
            throw OAuthFlowError.missingCode
        }

        return code
    }

    // MARK: - Step 5: Exchange Code for Tokens

    private func exchangeCode(
        code: String,
        pkce: OAuthPKCE,
        dpop: OAuthDPoP,
        dpopKeyTag: String,
        asMetadata: OAuthAuthorizationServerMetadata,
        did: String?,
        handle: String?,
        pdsURL: URL
    ) async throws -> OAuthSession {
        let tokenURL = asMetadata.tokenEndpoint

        let dpopProof = try dpop.proof(
            httpMethod: "POST",
            httpURL: tokenURL,
            accessTokenHash: nil,
            nonce: nil
        )

        let tokenBody = TokenExchangeBody(
            clientID: clientID,
            code: code,
            codeVerifier: pkce.verifier,
            redirectURI: "\(callbackScheme):\(callbackPath)"
        )
        let bodyData = try JSONEncoder().encode(tokenBody)

        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(dpopProof, forHTTPHeaderField: "DPoP")
        request.httpBody = bodyData

        let (data, httpResponse) = try await httpClient.data(for: request, source: "OAuth Token Exchange")

        // Handle DPoP nonce error
        if httpResponse.statusCode == 401 {
            if let nonce = httpResponse.allHeaderFields["DPoP-Nonce"] as? String {
                let retryProof = try dpop.proof(
                    httpMethod: "POST",
                    httpURL: tokenURL,
                    accessTokenHash: nil,
                    nonce: nonce
                )
                request.setValue(retryProof, forHTTPHeaderField: "DPoP")
                let (retryData, retryResponse) = try await httpClient.data(for: request, source: "OAuth Token Exchange")
                guard (200 ..< 300).contains(retryResponse.statusCode) else {
                    throw OAuthFlowError.tokenExchangeFailed(retryResponse.statusCode)
                }
                return try decodeTokenResponse(
                    data: retryData,
                    httpResponse: retryResponse,
                    dpopKeyTag: dpopKeyTag,
                    did: did,
                    handle: handle,
                    pdsURL: pdsURL,
                    asURL: asMetadata.issuer
                )
            }
            throw OAuthFlowError.tokenExchangeFailed(httpResponse.statusCode)
        }

        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            throw OAuthFlowError.tokenExchangeFailed(httpResponse.statusCode)
        }

        return try decodeTokenResponse(
            data: data,
            httpResponse: httpResponse,
            dpopKeyTag: dpopKeyTag,
            did: did,
            handle: handle,
            pdsURL: pdsURL,
            asURL: asMetadata.issuer
        )
    }

    private func decodeTokenResponse(
        data: Data,
        httpResponse: HTTPURLResponse,
        dpopKeyTag: String,
        did: String?,
        handle: String?,
        pdsURL: URL,
        asURL: URL
    ) throws -> OAuthSession {
        let response = try JSONDecoder().decode(TokenExchangeResponse.self, from: data)
        let nonce = httpResponse.allHeaderFields["DPoP-Nonce"] as? String

        // Use the DID from the `sub` claim if not provided (handle-first flow)
        let resolvedDID: String
        if let did, !did.isEmpty {
            resolvedDID = did
        } else if let sub = response.sub {
            resolvedDID = sub
        } else {
            throw OAuthFlowError.missingDID
        }

        guard let expiresIn = response.expiresIn, let expiry = expiryDate(expiresIn: expiresIn) else {
            throw OAuthFlowError.invalidExpiry
        }

        return OAuthSession(
            did: resolvedDID,
            handle: handle ?? resolvedDID,
            pdsURL: pdsURL,
            accessToken: response.accessToken,
            refreshToken: response.refreshToken,
            scope: response.scope ?? "atproto transition:generic transition:chat.bsky",
            expiresAt: expiry,
            dpopKeyTag: dpopKeyTag,
            asNonce: nonce,
            rsNonce: nil,
            authorizationServerURL: asURL
        )
    }

    private func expiryDate(expiresIn: Int) -> Date? {
        guard expiresIn > 0 else { return nil }
        return Date().addingTimeInterval(TimeInterval(expiresIn))
    }
}

// MARK: - Request / Response Models

private struct PARBody: Encodable {
    let clientID: String
    let responseType: String
    let codeChallenge: String
    let codeChallengeMethod: String
    let state: String
    let redirectURI: String
    let scope: String
    let loginHint: String?

    enum CodingKeys: String, CodingKey {
        case clientID = "client_id"
        case responseType = "response_type"
        case codeChallenge = "code_challenge"
        case codeChallengeMethod = "code_challenge_method"
        case state
        case redirectURI = "redirect_uri"
        case scope
        case loginHint = "login_hint"
    }
}

private struct PARResponse: Decodable {
    let requestURI: String

    enum CodingKeys: String, CodingKey {
        case requestURI = "request_uri"
    }
}

private struct TokenExchangeBody: Encodable {
    let grantType = "authorization_code"
    let clientID: String
    let code: String
    let codeVerifier: String
    let redirectURI: String

    enum CodingKeys: String, CodingKey {
        case grantType = "grant_type"
        case clientID = "client_id"
        case code
        case codeVerifier = "code_verifier"
        case redirectURI = "redirect_uri"
    }
}

private struct TokenExchangeResponse: Decodable {
    let accessToken: String
    let refreshToken: String
    let scope: String?
    let expiresIn: Int?
    let tokenType: String?
    let sub: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case scope
        case expiresIn = "expires_in"
        case tokenType = "token_type"
        case sub
    }
}

// MARK: - Errors

enum OAuthFlowError: Error, LocalizedError {
    case deallocated
    case userCancelled
    case missingCallback
    case invalidCallback
    case stateMismatch
    case missingCode
    case missingDID
    case parNotSupported
    case parFailed(Int)
    case tokenExchangeFailed(Int)
    case authorizationError(String)
    case invalidExpiry
    case pdsURLNotFound

    var errorDescription: String? {
        switch self {
        case .deallocated:
            "The sign-in flow was interrupted."
        case .userCancelled:
            "Sign-in was cancelled."
        case .missingCallback:
            "No callback URL was received."
        case .invalidCallback:
            "The callback URL was invalid."
        case .stateMismatch:
            "Security state mismatch. Please try again."
        case .missingCode:
            "No authorization code was returned."
        case .missingDID:
            "The authorization response did not include a DID."
        case .parNotSupported:
            "This PDS does not support OAuth."
        case .parFailed(let code):
            "The authorization request failed (HTTP \(code))."
        case .tokenExchangeFailed(let code):
            "The token exchange failed (HTTP \(code))."
        case .authorizationError(let error):
            "Authorization error: \(error)"
        case .invalidExpiry:
            "The session has an invalid expiry."
        case .pdsURLNotFound:
            "Could not find the PDS URL for this account."
        }
    }
}
