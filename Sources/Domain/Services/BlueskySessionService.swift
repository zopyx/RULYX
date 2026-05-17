import Foundation

@MainActor
protocol BlueskySessionServicing {
    func authenticate(handle: String, appPassword: String, entrywayURL: URL?) async throws -> BlueskySession
    func persistSession(_ session: BlueskySession, for account: AppAccount) async throws
    func deletePersistedSession(for account: AppAccount) throws
    func restoreSessions(for accounts: [AppAccount]) async
    func clearSessionCache()
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
    private let persistedSessionService = "com.ajung.BlueskyModeration.session"

    init(
        baseURL: URL = .bskySocial,
        requestExecutor: BlueskyRequestExecuting,
        keychain: KeychainServicing = KeychainService()
    ) {
        entrywayURL = baseURL
        self.requestExecutor = requestExecutor
        self.keychain = keychain
    }

    func authenticate(handle: String, appPassword: String, entrywayURL: URL? = nil) async throws -> BlueskySession {
        let requestBody = CreateSessionRequest(identifier: handle, password: appPassword)
        let authURL: URL
        if let entrywayURL {
            authURL = entrywayURL
        } else {
            authURL = try await authenticationURL(forHandle: handle)
        }
        let response: CreateSessionResponse = try await requestExecutor.send(
            path: "com.atproto.server.createSession",
            method: "POST",
            queryItems: [],
            body: requestBody,
            accessToken: nil,
            hostURL: authURL
        )

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
            _ = try? await cachedSession(for: account, appPassword: nil)
        }
    }

    func clearSessionCache() {
        cachedSessions.removeAll()
    }

    func performAuthenticatedRequest<Response>(
        account: AppAccount,
        appPassword: String?,
        operation: (BlueskySession) async throws -> Response
    ) async throws -> Response {
        var authSession = try await cachedSession(for: account, appPassword: appPassword)

        do {
            return try await operation(authSession)
        } catch BlueskyAPIError.unauthorized {
            authSession = try await recoverSession(
                currentSession: authSession,
                for: account,
                appPassword: appPassword
            )
            return try await operation(authSession)
        }
    }

    private func cachedSession(
        for account: AppAccount,
        appPassword: String?
    ) async throws -> BlueskySession {
        let sessionKey = account.id.uuidString
        if let cachedSession = cachedSessions[sessionKey] {
            if shouldRefresh(cachedSession.accessJWT) {
                return try await recoverSession(
                    currentSession: cachedSession,
                    for: account,
                    appPassword: appPassword
                )
            }
            return cachedSession
        }

        if let restoredSession = try restoredSession(for: account) {
            cachedSessions[sessionKey] = restoredSession
            if shouldRefresh(restoredSession.accessJWT) {
                return try await recoverSession(
                    currentSession: restoredSession,
                    for: account,
                    appPassword: appPassword
                )
            }
            return restoredSession
        }

        guard let appPassword else {
            throw BlueskyAPIError.missingCredentials
        }

        let newSession = try await authenticate(handle: account.handle, appPassword: appPassword)
        cachedSessions[sessionKey] = newSession
        try await persistSession(newSession, for: account)
        return newSession
    }

    private func recoverSession(
        currentSession: BlueskySession,
        for account: AppAccount,
        appPassword: String?
    ) async throws -> BlueskySession {
        let sessionKey = account.id.uuidString

        if let refreshedSession = try await refreshSession(currentSession) {
            cachedSessions[sessionKey] = refreshedSession
            try await persistSession(refreshedSession, for: account)
            return refreshedSession
        }

        guard let appPassword else {
            throw BlueskyAPIError.unauthorized
        }

        let recreatedSession = try await authenticate(handle: account.handle, appPassword: appPassword)
        cachedSessions[sessionKey] = recreatedSession
        try await persistSession(recreatedSession, for: account)
        return recreatedSession
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

    private func authenticationURL(forHandle handle: String) async throws -> URL {
        if handle.lowercased().hasSuffix(".bsky.social") {
            return entrywayURL
        }

        if let domainEntryway = entrywayFromDomain(for: handle) {
            if let did = try? await resolveHandle(handle, hostURL: domainEntryway),
               let pdsURL = try? await resolvePDSURL(forDID: did)
            {
                return pdsURL
            }
            return domainEntryway
        }

        if let did = try? await resolveHandle(handle),
           let pdsURL = try? await resolvePDSURL(forDID: did)
        {
            return pdsURL
        }

        return entrywayURL
    }

    private func entrywayFromDomain(for handle: String) -> URL? {
        let components = handle.split(separator: "@").last?.split(separator: ".")
        guard let components, components.count >= 2 else { return nil }
        let domain = components.suffix(2).joined(separator: ".")
        guard domain != "bsky.social" else { return nil }
        return URL(string: "https://\(domain)")
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
}

struct CreateSessionResponse: Decodable {
    let did: String
    let handle: String
    let accessJWT: String
    let refreshJWT: String?
    let didDoc: DIDDocument?

    enum CodingKeys: String, CodingKey {
        case did
        case handle
        case accessJWT = "accessJwt"
        case refreshJWT = "refreshJwt"
        case didDoc
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
