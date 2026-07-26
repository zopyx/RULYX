import Foundation

/// Manages Bluesky authentication, session persistence, and authenticated request execution.
/// Implementations handle the full session lifecycle: login, token refresh, keychain persistence,
/// cache management, and automatic retry with credential recovery on 401 responses.
@MainActor
protocol BlueskySessionServicing {
    // MARK: - Authentication

    /// Authenticates with the Bluesky AT Protocol using a handle and app password.
    /// Resolves the PDS (Personal Data Server) URL via DID document lookup and
    /// creates a session with access and refresh JWTs.
    /// - Parameters:
    ///   - handle: The Bluesky handle (e.g. `user.bsky.social`).
    ///   - appPassword: The app password for authentication.
    ///   - entrywayURL: An optional custom entryway URL; if `nil`, resolves automatically via handle domain.
    ///   - authFactorToken: An optional 2FA verification code sent via email.
    /// - Returns: A `BlueskySession` containing DIDs, JWTs, and the resolved PDS URL.
    /// - Throws: `BlueskyAPIError.authFactorTokenRequired` if email 2FA code is needed.
    func authenticate(handle: String, appPassword: String, entrywayURL: URL?, authFactorToken: String?) async throws -> BlueskySession

    /// Persists a session to the keychain for the given account and caches it in memory.
    /// - Parameters:
    ///   - session: The session to persist.
    ///   - account: The account associated with the session.
    func persistSession(_ session: BlueskySession, for account: AppAccount) async throws

    /// Removes a persisted session from the keychain and clears the in-memory cache.
    /// - Parameter account: The account whose session to delete.
    func deletePersistedSession(for account: AppAccount) throws

    /// Restores sessions from the keychain for all provided accounts.
    /// Populates the in-memory cache so subsequent requests don't need keychain lookups.
    /// - Parameter accounts: The accounts whose sessions to restore.
    func restoreSessions(for accounts: [AppAccount]) async

    /// Clears all cached sessions from memory without touching keychain storage.
    func clearSessionCache()

    // MARK: - Authenticated Requests

    /// Executes an authenticated request, automatically handling token refresh and retry.
    /// On 401 responses, attempts to refresh the JWT via the refresh token; if that fails,
    /// re-authenticates with the app password. Posts `accountDeactivated` or `accountReactivated`
    /// notifications as appropriate.
    /// - Parameters:
    ///   - account: The account to authenticate as.
    ///   - appPassword: The app password for fallback re-authentication, or `nil`.
    ///   - operation: An async closure that receives a valid `BlueskySession` and returns a response.
    /// - Returns: The response from the operation.
    /// - Throws: `BlueskyAPIError.deactivated` if the account is deactivated, or `BlueskyAPIError.unauthorized`
    ///           if all retry attempts fail.
    func performAuthenticatedRequest<Response>(
        account: AppAccount,
        appPassword: String?,
        operation: (BlueskySession) async throws -> Response
    ) async throws -> Response
}

@MainActor
final class BlueskySessionService: BlueskySessionServicing {
    private let entrywayURL: URL
    private let requestExecutor: BlueskyRequestExecuting
    private let keychain: KeychainServicing
    private var cachedSessions: [String: BlueskySession] = [:]
    private let persistedSessionService = "com.ajung.RULYX.session"
    /// Deduplicates concurrent refreshSession calls per account.
    /// Multiple 401 responses arriving in the same time window share the same
    /// in-flight refresh task rather than starting N parallel refresh calls.
    private var pendingRefreshes: [AppAccount.ID: Task<BlueskySession, Error>] = [:]

    init(
        baseURL: URL = .bskySocial,
        requestExecutor: BlueskyRequestExecuting,
        keychain: KeychainServicing = KeychainService()
    ) {
        entrywayURL = baseURL
        self.requestExecutor = requestExecutor
        self.keychain = keychain
    }

    func authenticate(handle: String, appPassword: String, entrywayURL: URL? = nil, authFactorToken: String? = nil) async throws -> BlueskySession {
        let requestBody = CreateSessionRequest(identifier: handle, password: appPassword, authFactorToken: authFactorToken)
        let authURL: URL
        if let entrywayURL {
            // Explicit, user-entered custom PDS. Credentials are about to be sent
            // to this host, so HTTPS is mandatory (defense-in-depth on top of ATS).
            guard entrywayURL.scheme?.lowercased() == "https" else {
                throw BlueskyAPIError.server("PDS URL must use HTTPS.")
            }
            authURL = entrywayURL
        } else {
            authURL = try await authenticationURL(forHandle: handle)
        }
        let response: CreateSessionResponse
        do {
            response = try await requestExecutor.send(
                path: "com.atproto.server.createSession",
                method: "POST",
                queryItems: [],
                body: requestBody,
                accessToken: nil,
                hostURL: authURL
            )
        } catch let BlueskyAPIError.server(message) where message.contains("404") || message.contains("not found") {
            throw BlueskyAPIError.pdsUnreachable(authURL.host ?? "unknown")
        } catch BlueskyAPIError.invalidResponse {
            // createSession returning 404 with no parseable body → PDS unreachable
            throw BlueskyAPIError.pdsUnreachable(authURL.host ?? "unknown")
        } catch let error as URLError {
            if error.code == .cannotFindHost || error.code == .cannotConnectToHost ||
                error.code == .dnsLookupFailed || error.code == .timedOut ||
                error.code == .networkConnectionLost
            {
                throw BlueskyAPIError.pdsUnreachable(authURL.host ?? "unknown")
            }
            throw error
        }

        let pdsURL = try await resolvedPDSURL(
            from: response.didDoc,
            did: response.did,
            fallback: authURL
        )

        return BlueskySession(
            did: response.did,
            handle: response.handle,
            accessJWT: response.accessJWT,
            refreshJWT: response.refreshJWT,
            pdsURL: pdsURL
        )
    }

    func persistSession(_ authSession: BlueskySession, for account: AppAccount) async throws {
        guard session(authSession, belongsTo: account) else {
            throw BlueskyAPIError.unauthorized
        }
        let data = try JSONEncoder().encode(authSession)
        guard let value = String(data: data, encoding: .utf8) else {
            throw BlueskyAPIError.invalidResponse
        }
        try keychain.save(value, service: persistedSessionService, account: account.id.uuidString)
        cachedSessions[account.id.uuidString] = authSession
    }

    func deletePersistedSession(for account: AppAccount) throws {
        cachedSessions.removeValue(forKey: account.id.uuidString)
        try keychain.delete(service: persistedSessionService, account: account.id.uuidString)
    }

    func restoreSessions(for accounts: [AppAccount]) async {
        for account in accounts {
            _ = try? await cachedSession(for: account)
        }
    }

    func clearSessionCache() {
        cachedSessions.removeAll()
    }

    func performAuthenticatedRequest<Response>(
        account: AppAccount,
        appPassword _: String?,
        operation: (BlueskySession) async throws -> Response
    ) async throws -> Response {
        var authSession = try await cachedSession(for: account)
        for attempt in 0 ..< 3 {
            do {
                let response = try await operation(authSession)
                NotificationCenter.default.post(
                    name: .accountReactivated,
                    object: nil,
                    userInfo: ["accountID": account.id.uuidString]
                )
                return response
            } catch let BlueskyAPIError.deactivated(message) {
                NotificationCenter.default.post(
                    name: .accountDeactivated,
                    object: nil,
                    userInfo: ["accountID": account.id.uuidString]
                )
                throw BlueskyAPIError.deactivated(message)
            } catch BlueskyAPIError.unauthorized {
                guard attempt < 2 else { throw BlueskyAPIError.unauthorized }
                authSession = try await recoverSession(
                    currentSession: authSession,
                    for: account
                )
                let delay = pow(2.0, Double(attempt)) * Double.random(in: 0.8 ..< 1.2)
                try? await Task.sleep(for: .seconds(delay))
            } catch {
                // Don't retry PDS connectivity errors
                if let apiError = error as? BlueskyAPIError,
                   case .pdsUnreachable = apiError
                {
                    throw error
                }
                // All other errors: re-throw immediately, no retry
                throw error
            }
        }

        throw BlueskyAPIError.unauthorized
    }

    private func cachedSession(
        for account: AppAccount
    ) async throws -> BlueskySession {
        let sessionKey = account.id.uuidString
        if let cachedSession = cachedSessions[sessionKey] {
            guard session(cachedSession, belongsTo: account) else {
                cachedSessions.removeValue(forKey: sessionKey)
                try? keychain.delete(service: persistedSessionService, account: sessionKey)
                return try await recreateSession(for: account)
            }
            if shouldRefresh(cachedSession.accessJWT) {
                return try await recoverSession(
                    currentSession: cachedSession,
                    for: account
                )
            }
            return cachedSession
        }

        if let restoredSession = try restoredSession(for: account) {
            guard session(restoredSession, belongsTo: account) else {
                try? keychain.delete(service: persistedSessionService, account: sessionKey)
                return try await recreateSession(for: account)
            }
            cachedSessions[sessionKey] = restoredSession
            if shouldRefresh(restoredSession.accessJWT) {
                return try await recoverSession(
                    currentSession: restoredSession,
                    for: account
                )
            }
            return restoredSession
        }

        return try await recreateSession(for: account)
    }

    private func recreateSession(
        for account: AppAccount
    ) async throws -> BlueskySession {
        let passwordService = "com.ajung.RULYX.password"
        guard let value = try? keychain.read(service: passwordService, account: account.id.uuidString),
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw BlueskyAPIError.missingCredentials
        }

        let newSession = try await authenticate(handle: account.handle, appPassword: value)
        try await persistSession(newSession, for: account)
        return newSession
    }

    private func recoverSession(
        currentSession: BlueskySession,
        for account: AppAccount
    ) async throws -> BlueskySession {
        let sessionKey = account.id.uuidString

        // If a refresh is already in-flight for this account, await it
        // instead of starting a duplicate refresh.
        if let existing = pendingRefreshes[account.id] {
            return try await existing.value
        }

        let task = Task<BlueskySession, Error> {
            defer { pendingRefreshes[account.id] = nil }
            if let refreshedSession = try await refreshSession(currentSession) {
                guard session(refreshedSession, belongsTo: account) else {
                    return try await recreateSession(for: account)
                }
                cachedSessions[sessionKey] = refreshedSession
                try await persistSession(refreshedSession, for: account)
                return refreshedSession
            }
            return try await recreateSession(for: account)
        }
        pendingRefreshes[account.id] = task
        return try await task.value
    }

    private func refreshSession(_ existingSession: BlueskySession) async throws -> BlueskySession? {
        guard let refreshJWT = existingSession.refreshJWT, !refreshJWT.isEmpty else {
            return nil
        }

        do {
            let response: CreateSessionResponse = try await requestExecutor.send(
                path: "com.atproto.server.refreshSession",
                method: "POST",
                queryItems: [],
                body: String?.none,
                accessToken: refreshJWT,
                hostURL: existingSession.pdsURL
            )

            let pdsURL = try await resolvedPDSURL(
                from: response.didDoc,
                did: response.did,
                fallback: existingSession.pdsURL
            )

            return BlueskySession(
                did: response.did,
                handle: response.handle,
                accessJWT: response.accessJWT,
                refreshJWT: response.refreshJWT ?? refreshJWT,
                pdsURL: pdsURL
            )
        } catch BlueskyAPIError.unauthorized {
            return nil
        }
    }

    private func restoredSession(for account: AppAccount) throws -> BlueskySession? {
        guard let value = try keychain.read(service: persistedSessionService, account: account.id.uuidString),
              let data = value.data(using: .utf8)
        else {
            return nil
        }

        var restored = try JSONDecoder().decode(BlueskySession.self, from: data)
        if restored.pdsURL.absoluteString.isEmpty, let pdsURL = account.pdsURL {
            restored = BlueskySession(
                did: restored.did,
                handle: restored.handle,
                accessJWT: restored.accessJWT,
                refreshJWT: restored.refreshJWT,
                pdsURL: pdsURL
            )
        }
        return restored
    }

    private func session(_ session: BlueskySession, belongsTo account: AppAccount) -> Bool {
        if let did = account.did, !did.isEmpty {
            return session.did == did
        }
        return session.handle.caseInsensitiveCompare(account.handle) == .orderedSame
    }

    /// Determines where `createSession` credentials are sent for a handle.
    ///
    /// Security contract: the PDS endpoint is taken exclusively from the
    /// verified DID document, resolved through the trusted entryway resolver
    /// (`bsky.social` performs both DNS TXT `_atproto.` and HTTPS well-known
    /// handle verification server-side). The credential endpoint is NEVER
    /// derived from the handle string itself — a hostile or parked domain must
    /// not be able to receive the user's app password.
    private func authenticationURL(forHandle handle: String) async throws -> URL {
        if handle.lowercased().hasSuffix(".bsky.social") {
            return entrywayURL
        }

        if let did = try? await resolveHandle(handle),
           let pdsURL = try? await resolvePDSURL(forDID: did)
        {
            return pdsURL
        }

        return entrywayURL
    }

    private func resolveHandle(_ handle: String, hostURL: URL? = nil) async throws -> String {
        let response: ResolveHandleResponse = try await requestExecutor.send(
            path: "com.atproto.identity.resolveHandle",
            method: "GET",
            queryItems: [URLQueryItem(name: "handle", value: handle)],
            accessToken: nil,
            hostURL: hostURL ?? entrywayURL
        )
        return response.did
    }

    private func resolvePDSURL(forDID did: String) async throws -> URL {
        let didDocument: DIDDocument = try await requestExecutor.send(
            path: "com.atproto.identity.resolveDid",
            method: "GET",
            queryItems: [URLQueryItem(name: "did", value: did)],
            accessToken: nil,
            hostURL: entrywayURL
        )
        return try await resolvedPDSURL(from: didDocument, did: did, fallback: nil)
    }

    private func resolvedPDSURL(
        from didDocument: DIDDocument?,
        did: String,
        fallback: URL?
    ) async throws -> URL {
        if let serviceEndpoint = didDocument?.services.first(where: {
            $0.id.contains("#atproto_pds") || $0.type == "AtprotoPersonalDataServer"
        })?.serviceEndpoint {
            guard serviceEndpoint.scheme == "https" else {
                throw BlueskyAPIError.server("PDS URL must use HTTPS.")
            }
            return serviceEndpoint
        }

        if let fallback {
            return fallback
        }

        return try await resolvePDSURL(forDID: did)
    }

    private func shouldRefresh(_ jwt: String) -> Bool {
        guard let expiry = jwtExpiryDate(jwt) else {
            return false
        }

        return expiry <= Date().addingTimeInterval(60)
    }

    private func jwtExpiryDate(_ jwt: String) -> Date? {
        let segments = jwt.split(separator: ".")
        guard segments.count >= 2 else { return nil }
        var payload = String(segments[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = payload.count % 4
        if remainder != 0 {
            payload += String(repeating: "=", count: 4 - remainder)
        }
        guard let data = Data(base64Encoded: payload),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let exp = json["exp"] as? TimeInterval
        else {
            return nil
        }
        return Date(timeIntervalSince1970: exp)
    }
}

struct CreateSessionRequest: Encodable {
    let identifier: String
    let password: String
    let authFactorToken: String?

    init(identifier: String, password: String, authFactorToken: String? = nil) {
        self.identifier = identifier
        self.password = password
        self.authFactorToken = authFactorToken
    }
}

struct CreateSessionResponse: Decodable {
    let did: String
    let handle: String
    let accessJWT: String
    let refreshJWT: String?
    let didDoc: DIDDocument?
    let email: String?
    let emailAuthFactor: Bool?

    enum CodingKeys: String, CodingKey {
        case did
        case handle
        case accessJWT = "accessJwt"
        case refreshJWT = "refreshJwt"
        case didDoc
        case email
        case emailAuthFactor
    }

    init(
        did: String,
        handle: String,
        accessJWT: String,
        refreshJWT: String?,
        didDoc: DIDDocument?,
        email: String? = nil,
        emailAuthFactor: Bool? = nil
    ) {
        self.did = did
        self.handle = handle
        self.accessJWT = accessJWT
        self.refreshJWT = refreshJWT
        self.didDoc = didDoc
        self.email = email
        self.emailAuthFactor = emailAuthFactor
    }
}

struct ResolveHandleResponse: Decodable {
    let did: String
}

struct DIDDocument: Codable {
    let services: [DIDService]

    enum CodingKeys: String, CodingKey {
        case services = "service"
    }
}

struct DIDService: Codable {
    let id: String
    let type: String
    let serviceEndpoint: URL
}

extension Notification.Name {
    static let accountDeactivated = Notification.Name("accountDeactivated")
    static let accountReactivated = Notification.Name("accountReactivated")
}
