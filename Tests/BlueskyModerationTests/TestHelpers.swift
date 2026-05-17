@testable import BlueskyModeration
import XCTest

func makeAccount(handle: String = "test.bsky.social", did: String = "did:plc:test") -> AppAccount {
    AppAccount(handle: handle, did: did)
}

func makeActor(did: String = "did:plc:actor", handle: String = "actor.bsky.social", displayName: String? = nil) -> BlueskyActor {
    BlueskyActor(did: did, handle: handle, displayName: displayName)
}

func makeMember(did: String = "did:plc:member", handle: String = "member.bsky.social", recordURI: String? = nil) -> BlueskyListMember {
    BlueskyListMember(
        recordURI: recordURI ?? "at://did:plc:owner/app.bsky.graph.listitem/\(did)",
        actor: makeActor(did: did, handle: handle)
    )
}

func makeList(id: String = "at://list/1", name: String = "Test List", kind: BlueskyList.Kind = .moderation, memberCount: Int? = nil) -> BlueskyList {
    BlueskyList(id: id, name: name, description: kind.title, memberCount: memberCount, kind: kind)
}

func makeProfile(
    did: String = "did:plc:profile",
    handle: String = "profile.bsky.social",
    displayName: String? = "Profile",
    followersCount: Int? = 100,
    followsCount: Int? = 50
) -> BlueskyProfile {
    BlueskyProfile(
        id: did,
        did: did,
        handle: handle,
        displayName: displayName,
        description: nil,
        websiteURL: nil,
        avatarURL: nil,
        bannerURL: nil,
        followersCount: followersCount,
        followsCount: followsCount,
        postsCount: nil,
        listsCount: nil,
        starterPacksCount: nil,
        createdAt: nil,
        labels: [],
        viewerState: nil
    )
}

final class MockKeychain: KeychainServicing {
    var savedValues: [String: String] = [:]

    func save(_ value: String, service: String, account: String) throws {
        savedValues["\(service):\(account)"] = value
    }

    func read(service: String, account: String) throws -> String? {
        savedValues["\(service):\(account)"]
    }

    func delete(service: String, account: String) throws {
        savedValues.removeValue(forKey: "\(service):\(account)")
    }
}

@MainActor
final class MockSessionService: BlueskySessionServicing {
    var sessionToReturn: BlueskySession?
    var shouldFailAuth = false
    var shouldFailAuthWith: Error?
    var persistedSessions: [String: BlueskySession] = [:]
    var onAuthenticatedRequest: ((AppAccount, String?) async throws -> Any)?

    func authenticate(handle: String, appPassword _: String, entrywayURL _: URL? = nil) async throws -> BlueskySession {
        if shouldFailAuth {
            throw shouldFailAuthWith ?? BlueskyAPIError.unauthorized
        }
        return sessionToReturn ?? BlueskySession(
            did: "did:plc:session",
            handle: handle,
            accessJWT: "access-jwt",
            refreshJWT: nil,
            pdsURL: URL(string: "https://bsky.social")!
        )
    }

    func persistSession(_ session: BlueskySession, for account: AppAccount) async throws {
        persistedSessions[account.id.uuidString] = session
    }

    func deletePersistedSession(for account: AppAccount) throws {
        persistedSessions.removeValue(forKey: account.id.uuidString)
    }

    func restoreSessions(for _: [AppAccount]) async {}

    func clearSessionCache() {
        persistedSessions.removeAll()
    }

    func performAuthenticatedRequest<Response>(
        account: AppAccount,
        appPassword: String?,
        operation: (BlueskySession) async throws -> Response
    ) async throws -> Response {
        if let onAuthenticatedRequest {
            // swiftlint:disable:next force_cast
            return try await onAuthenticatedRequest(account, appPassword) as! Response
        }
        let session = sessionToReturn ?? BlueskySession(
            did: "did:plc:session",
            handle: account.handle,
            accessJWT: "access-jwt",
            refreshJWT: nil,
            pdsURL: URL(string: "https://bsky.social")!
        )
        return try await operation(session)
    }
}

struct MockRequestExecutor: BlueskyRequestExecuting {
    var onSend: (@Sendable (String, String, [URLQueryItem], Any?, String?, URL?) async throws -> Any)?

    func send<Response: Decodable, Body: Encodable>(
        path: String,
        method: String,
        queryItems: [URLQueryItem],
        body: Body?,
        accessToken: String?,
        hostURL: URL?
    ) async throws -> Response {
        if let onSend {
            // swiftlint:disable:next force_cast
            return try await onSend(path, method, queryItems, body, accessToken, hostURL) as! Response
        }
        throw BlueskyAPIError.invalidResponse
    }

    func send<Response: Decodable>(
        path: String,
        method: String,
        queryItems: [URLQueryItem],
        accessToken: String?,
        hostURL: URL?
    ) async throws -> Response {
        try await send(path: path, method: method, queryItems: queryItems, body: String?.none, accessToken: accessToken, hostURL: hostURL)
    }
}

struct EmptyDecodable: Decodable {}

final class MockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with _: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = MockURLProtocol.requestHandler else {
            fatalError("No request handler set")
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

extension XCTestCase {
    func makeSession(for handle: String = "test.bsky.social") -> BlueskySession {
        BlueskySession(
            did: "did:plc:\(handle.replacingOccurrences(of: ".", with: "-"))",
            handle: handle,
            accessJWT: "test-access-jwt",
            refreshJWT: "test-refresh-jwt",
            pdsURL: URL(string: "https://bsky.social")!
        )
    }
}
