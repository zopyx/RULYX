@testable import RULYX
import XCTest

final class LiveBlueskyClientTests: XCTestCase {
    nonisolated(unsafe) private var client: LiveBlueskyClient!
    nonisolated(unsafe) private var sessionService: MockSessionService!
    nonisolated(unsafe) private var requestExecutor: MockRequestExecutor!
    nonisolated(unsafe) private var mockSession: URLSession!
    nonisolated(unsafe) private var clearskyHeartbeat: ClearskyHeartbeatService!

    override func setUp() async throws {
        try await super.setUp()
        let setup = await MainActor.run { () -> (MockRequestExecutor, URLSession, MockSessionService, LiveBlueskyClient, ClearskyHeartbeatService) in
            let requestExecutor = MockRequestExecutor()
            let config = URLSessionConfiguration.ephemeral
            config.protocolClasses = [MockURLProtocol.self]
            let mockSession = URLSession(configuration: config)
            let sessionService = MockSessionService()
            let clearskyHeartbeat = ClearskyHeartbeatService()
            let client = LiveBlueskyClient(
                httpClient: HTTPClient(session: mockSession),
                requestExecutor: requestExecutor,
                sessionService: sessionService,
                clearskyHeartbeat: clearskyHeartbeat
            )
            return (requestExecutor, mockSession, sessionService, client, clearskyHeartbeat)
        }
        requestExecutor = setup.0
        mockSession = setup.1
        sessionService = setup.2
        client = setup.3
        clearskyHeartbeat = setup.4
    }

    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        client = nil
        sessionService = nil
        requestExecutor = nil
        mockSession = nil
        super.tearDown()
    }

    @MainActor func testFetchPLCAuditLog() async throws {
        let json = """
        [{"did": "did:plc:test", "operation": {"type": "plc_operation", "alsoKnownAs": ["at://handle.bsky.social"]}, "cid": "cid1", "nullified": false, "createdAt": "2024-01-01T00:00:00Z"}]
        """.data(using: .utf8)!
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, json)
        }
        let auditedClient = try LiveBlueskyClient(
            baseURL: XCTUnwrap(URL(string: "https://bsky.social")),
            httpClient: HTTPClient(session: mockSession)
        )

        let entries = try await auditedClient.fetchPLCAuditLog(did: "did:plc:test")
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].did, "did:plc:test")
    }

    @MainActor func testClearCache() {
        client.clearCache()
    }

    @MainActor func testAuthenticateDelegates() async throws {
        let session = makeSession()
        sessionService.sessionToReturn = session
        let result = try await client.authenticate(handle: "test.bsky.social", appPassword: "pass")
        XCTAssertEqual(result.did, session.did)
    }

    @MainActor func testPersistSessionDelegates() async throws {
        let session = makeSession()
        let account = makeAccount()
        try await client.persistSession(session, for: account)
        XCTAssertEqual(sessionService.persistedSessions[account.id.uuidString]?.did, session.did)
    }

    @MainActor func testDeletePersistedSessionDelegates() throws {
        let account = makeAccount()
        try client.deletePersistedSession(for: account)
    }

    @MainActor func testRestoreSessionsDelegates() async {
        await client.restoreSessions(for: [makeAccount()])
    }

    @MainActor func testFetchBlocks() async throws {
        MockURLProtocol.requestHandler = { request in
            let url = request.url!.absoluteString
            if url.contains("blocklist/") {
                let json = """
                {"data": {"blocklist": [{"did": "did:plc:b1", "blocked_date": "2024-01-01T00:00:00Z"}]}}
                """.data(using: .utf8)!
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (response, json)
            }
            if url.contains("getProfiles") {
                let json = """
                {"profiles": [{"did": "did:plc:b1", "handle": "blocked.bsky.social"}]}
                """.data(using: .utf8)!
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (response, json)
            }
            throw BlueskyAPIError.invalidURL
        }

        let blocked = try await client.fetchBlockedActors(account: makeAccount(handle: "test.bsky.social"), appPassword: "pass")
        XCTAssertEqual(blocked.actors.count, 1)
        XCTAssertEqual(blocked.actors[0].handle, "blocked.bsky.social")
    }

    @MainActor func testFetchBlocksEmpty() async throws {
        MockURLProtocol.requestHandler = { request in
            let json = """
            {"data": {"blocklist": []}}
            """.data(using: .utf8)!
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, json)
        }

        let blocked = try await client.fetchBlockedActors(account: makeAccount(handle: "test.bsky.social"), appPassword: "pass")
        XCTAssertTrue(blocked.actors.isEmpty)
    }

    @MainActor func testFetchUnblockedBlockersCountSubtractsBlockingSet() async throws {
        MockURLProtocol.requestHandler = { request in
            let url = request.url!.absoluteString
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!

            if url.contains("/blocklist/") {
                let json = """
                {"data": {"blocklist": [
                    {"did": "did:plc:shared", "blocked_date": "2024-01-01T00:00:00Z"},
                    {"did": "did:plc:only-blocked", "blocked_date": "2024-01-02T00:00:00Z"}
                ]}}
                """.data(using: .utf8)!
                return (response, json)
            }

            if url.contains("/single-blocklist/") {
                let json = """
                {"data": {"blocklist": [
                    {"did": "did:plc:shared", "blocked_date": "2024-01-03T00:00:00Z"},
                    {"did": "did:plc:only-blocked-by", "blocked_date": "2024-01-04T00:00:00Z"}
                ]}}
                """.data(using: .utf8)!
                return (response, json)
            }

            if url.contains("getProfiles") {
                let json = """
                {"profiles": [
                    {"did": "did:plc:shared", "handle": "shared.bsky.social"},
                    {"did": "did:plc:only-blocked", "handle": "only-blocked.bsky.social"},
                    {"did": "did:plc:only-blocked-by", "handle": "only-blocked-by.bsky.social"}
                ]}
                """.data(using: .utf8)!
                return (response, json)
            }

            throw BlueskyAPIError.invalidURL
        }

        let count = try await client.fetchUnblockedBlockersCount(for: makeAccount())
        XCTAssertEqual(count, 1)
    }

    @MainActor func testFetchUnblockedBlockersCountPaginatesClearskyResponses() async throws {
        MockURLProtocol.requestHandler = { request in
            let url = request.url!.absoluteString
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!

            if url.contains("/blocklist/did:plc:test/2") {
                let json = """
                {"data": {"blocklist": [
                    {"did": "did:plc:block-only", "blocked_date": "2024-01-01T00:00:00Z"}
                ]}}
                """.data(using: .utf8)!
                return (response, json)
            }

            if url.contains("/blocklist/did:plc:test"), !url.contains("/single-blocklist/") {
                let entries = (0..<100).map { index in
                    #"{"did":"did:plc:shared\#(index)","blocked_date":"2024-01-01T00:00:00Z"}"#
                }.joined(separator: ",")
                let json = #"{"data":{"blocklist":[\#(entries)]}}"#.data(using: .utf8)!
                return (response, json)
            }

            if url.contains("/single-blocklist/did:plc:test/2") {
                let json = """
                {"data": {"blocklist": [
                    {"did": "did:plc:blocker-only", "blocked_date": "2024-01-01T00:00:00Z"}
                ]}}
                """.data(using: .utf8)!
                return (response, json)
            }

            if url.contains("/single-blocklist/did:plc:test") {
                let entries = (0..<100).map { index in
                    #"{"did":"did:plc:shared\#(index)","blocked_date":"2024-01-01T00:00:00Z"}"#
                }.joined(separator: ",")
                let json = #"{"data":{"blocklist":[\#(entries)]}}"#.data(using: .utf8)!
                return (response, json)
            }

            if url.contains("getProfiles") {
                var profiles = (0..<100).map { index in
                    #"{"did":"did:plc:shared\#(index)","handle":"shared\#(index).bsky.social"}"#
                }
                profiles.append(#"{"did":"did:plc:block-only","handle":"block-only.bsky.social"}"#)
                profiles.append(#"{"did":"did:plc:blocker-only","handle":"blocker-only.bsky.social"}"#)
                let json = #"{"profiles":[\#(profiles.joined(separator: ","))]}"#.data(using: .utf8)!
                return (response, json)
            }

            throw BlueskyAPIError.invalidURL
        }

        let count = try await client.fetchUnblockedBlockersCount(for: makeAccount())
        XCTAssertEqual(count, 1)
    }

    @MainActor func testReportListUsesListRecordSubject() async throws {
        let account = makeAccount()
        let list = BlueskyList(
            id: "at://did:plc:list/app.bsky.graph.list/abc123",
            name: "Spam Watch",
            description: "Test",
            memberCount: 3,
            kind: .moderation,
            cid: "cid-list-123"
        )
        let expectation = expectation(description: "report list request captured")

        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body: [String: Any] = [
                "id": 1,
                "reasonType": ModerationReportReasonType.simplifiedDefault.rawValue,
                "reason": "spam list",
                "reportedBy": account.did ?? "",
                "createdAt": "2026-05-18T10:00:00Z",
            ]
            return (response, try JSONSerialization.data(withJSONObject: body))
        }

        sessionService.onAuthenticatedRequest = { _, _ in
            CreateModerationReportResponse(
                id: 1,
                reasonType: ModerationReportReasonType.simplifiedDefault.rawValue,
                reason: "spam list",
                reportedBy: account.did ?? "",
                createdAt: "2026-05-18T10:00:00Z"
            )
        }

        try await client.reportList(list, reason: "spam list", account: account, appPassword: "pass")
        expectation.fulfill()
        await fulfillment(of: [expectation], timeout: 1.0)
    }
}
