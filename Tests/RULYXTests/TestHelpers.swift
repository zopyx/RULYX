@testable import RULYX
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

@MainActor
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

final class MockKeychain: KeychainServicing, @unchecked Sendable {
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

    func authenticate(handle: String, appPassword _: String, entrywayURL _: URL? = nil, authFactorToken _: String? = nil) async throws -> BlueskySession {
        if shouldFailAuth {
            throw shouldFailAuthWith ?? BlueskyAPIError.unauthorized(nil)
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

final class MockRequestExecutor: @unchecked Sendable, BlueskyRequestExecuting {
    var onSend: (@Sendable (String, String, [URLQueryItem], Any?, String?, URL?) async throws -> Any)?

    func send<Response: Decodable>(
        path: String,
        method: String,
        queryItems: [URLQueryItem],
        body: (some Encodable)?,
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

    /// Repeatedly evaluates `condition` until it returns `true` or `timeout`
    /// seconds elapse. Useful for testing async @Published state transitions.
    func waitForCondition(
        timeout: TimeInterval = 3.0,
        interval: TimeInterval = 0.05,
        _ condition: @escaping () -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let start = Date()
        while !condition() {
            guard Date().timeIntervalSince(start) < timeout else {
                XCTFail("Timed out waiting for condition after \(timeout)s", file: file, line: line)
                return
            }
            RunLoop.current.run(until: Date(timeIntervalSinceNow: interval))
        }
    }

    /// Awaits a condition asynchronously, yielding between checks.
    func waitForConditionAsync(
        timeout: TimeInterval = 3.0,
        interval: TimeInterval = 0.05,
        _ condition: @escaping @MainActor () -> Bool
    ) async {
        let start = Date()
        while await !condition() {
            guard Date().timeIntervalSince(start) < timeout else { return }
            try? await Task.sleep(for: .seconds(interval))
        }
    }
}
