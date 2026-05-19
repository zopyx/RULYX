@testable import RULYX
import XCTest

final class LiveBlueskyClientTests: XCTestCase {
    nonisolated(unsafe) private var client: LiveBlueskyClient!
    nonisolated(unsafe) private var sessionService: MockSessionService!
    nonisolated(unsafe) private var requestExecutor: MockRequestExecutor!
    nonisolated(unsafe) private var mockSession: URLSession!

    override func setUp() async throws {
        try await super.setUp()
        let setup = await MainActor.run { () -> (MockRequestExecutor, URLSession, MockSessionService, LiveBlueskyClient) in
            let requestExecutor = MockRequestExecutor()
            let config = URLSessionConfiguration.ephemeral
            config.protocolClasses = [MockURLProtocol.self]
            let mockSession = URLSession(configuration: config)
            let sessionService = MockSessionService()
            let client = LiveBlueskyClient(
                httpClient: HTTPClient(session: mockSession),
                requestExecutor: requestExecutor,
                sessionService: sessionService
            )
            return (requestExecutor, mockSession, sessionService, client)
        }
        requestExecutor = setup.0
        mockSession = setup.1
        sessionService = setup.2
        client = setup.3
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

        requestExecutor.onSend = { path, method, _, body, _, _ in
            XCTAssertEqual(path, "com.atproto.moderation.createReport")
            XCTAssertEqual(method, "POST")

            let requestBody = try XCTUnwrap(body as? CreateModerationReportRequest)
            XCTAssertEqual(requestBody.reasonType, ModerationReportReasonType.simplifiedDefault.rawValue)
            XCTAssertEqual(requestBody.reason, "spam list")
            XCTAssertNil(requestBody.subject.did)
            XCTAssertEqual(requestBody.subject.uri, list.id)
            XCTAssertEqual(requestBody.subject.cid, list.cid)
            expectation.fulfill()
            return CreateModerationReportResponse(
                id: 1,
                reasonType: requestBody.reasonType,
                reason: requestBody.reason,
                reportedBy: account.did ?? "",
                createdAt: "2026-05-18T10:00:00Z"
            )
        }

        try await client.reportList(list, reason: "spam list", account: account, appPassword: "pass")
        await fulfillment(of: [expectation], timeout: 1.0)
    }
}
