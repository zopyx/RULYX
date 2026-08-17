@testable import RULYX
import XCTest

final class LiveBlueskyClientTests: XCTestCase {
    private nonisolated(unsafe) var client: LiveBlueskyClient!
    private nonisolated(unsafe) var sessionService: MockSessionService!
    private nonisolated(unsafe) var requestExecutor: MockRequestExecutor!
    private nonisolated(unsafe) var mockSession: URLSession!
    private nonisolated(unsafe) var clearskyHeartbeat: ClearskyHeartbeatService!

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
                // Only return the profiles whose DIDs are actually requested in the URL.
                // The implementation should only request the unblocked-blocker DIDs after subtraction.
                let json = if url.contains("actors=did:plc:only-blocked-by&")
                    || url.hasSuffix("actors=did:plc:only-blocked-by")
                {
                    """
                    {"profiles": [{"did": "did:plc:only-blocked-by", "handle": "only-blocked-by.bsky.social"}]}
                    """
                } else {
                    """
                    {"profiles": [
                        {"did": "did:plc:shared", "handle": "shared.bsky.social"},
                        {"did": "did:plc:only-blocked", "handle": "only-blocked.bsky.social"},
                        {"did": "did:plc:only-blocked-by", "handle": "only-blocked-by.bsky.social"}
                    ]}
                    """
                }
                return (response, json.data(using: .utf8)!)
            }

            throw BlueskyAPIError.invalidURL
        }

        let count = try await client.fetchUnblockedBlockersCount(for: makeAccount())
        XCTAssertEqual(count, 1)
    }

    @MainActor func testFetchUnblockedBlockersCountPaginatesClearskyResponses() async throws {
        let actorDID = "did:plc:unblock"
        MockURLProtocol.requestHandler = { request in
            let url = request.url!.absoluteString
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!

            if url.contains("/blocklist/\(actorDID)/2") {
                let json = """
                {"data": {"blocklist": [
                    {"did": "did:plc:block-only", "blocked_date": "2024-01-01T00:00:00Z"}
                ]}}
                """.data(using: .utf8)!
                return (response, json)
            }

            if url.contains("/blocklist/\(actorDID)"), !url.contains("/single-blocklist/") {
                let entries = (0 ..< 100).map { index in
                    #"{"did":"did:plc:shared\#(index)","blocked_date":"2024-01-01T00:00:00Z"}"#
                }.joined(separator: ",")
                let json = #"{"data":{"blocklist":[\#(entries)]}}"#.data(using: .utf8)!
                return (response, json)
            }

            if url.contains("/single-blocklist/\(actorDID)/2") {
                let notFound = HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!
                return (notFound, Data())
            }

            if url.contains("/single-blocklist/\(actorDID)") {
                let entries = (0 ..< 100).map { index in
                    #"{"did":"did:plc:shared\#(index)","blocked_date":"2024-01-01T00:00:00Z"}"#
                }.joined(separator: ",")
                let json = #"{"data":{"blocklist":[\#(entries)]}}"#.data(using: .utf8)!
                return (response, json)
            }

            if url.contains("getProfiles") {
                // After subtraction, only did:plc:block-only should remain.
                // Return only the profiles whose DIDs are actually requested.
                let json: Data
                if url.contains("did:plc:block-only"), !url.contains("did:plc:shared"), !url.contains("did:plc:blocker-only") {
                    json = #"{"profiles":[{"did":"did:plc:block-only","handle":"block-only.bsky.social"}]}"#.data(using: .utf8)!
                } else {
                    var profiles = (0 ..< 100).map { index in
                        #"{"did":"did:plc:shared\#(index)","handle":"shared\#(index).bsky.social"}"#
                    }
                    profiles.append(#"{"did":"did:plc:block-only","handle":"block-only.bsky.social"}"#)
                    json = #"{"profiles":[\#(profiles.joined(separator: ","))]}"#.data(using: .utf8)!
                }
                return (response, json)
            }

            throw BlueskyAPIError.invalidURL
        }

        let count = try await client.fetchUnblockedBlockersCount(for: makeAccount(did: actorDID))
        XCTAssertEqual(count, 1)
    }

    @MainActor func testFetchBlockedByCountRetriesTransientServerError() async throws {
        var page2Attempts = 0
        MockURLProtocol.requestHandler = { request in
            let url = request.url!.absoluteString
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!

            if url.contains("/single-blocklist/did:plc:test/2") {
                page2Attempts += 1
                if page2Attempts < 2 {
                    let failureResponse = HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!
                    return (failureResponse, Data())
                }
                let json = """
                {"data": {"blocklist": [{"did": "did:plc:page2", "blocked_date": "2024-01-01T00:00:00Z"}]}}
                """.data(using: .utf8)!
                return (response, json)
            }

            if url.contains("/single-blocklist/did:plc:test") {
                let entries = (0 ..< 100).map { index in
                    #"{"did":"did:plc:page1-\#(index)","blocked_date":"2024-01-01T00:00:00Z"}"#
                }.joined(separator: ",")
                let json = #"{"data":{"blocklist":[\#(entries)]}}"#.data(using: .utf8)!
                return (response, json)
            }

            throw BlueskyAPIError.invalidURL
        }

        let count = try await client.fetchBlockedByCount(for: makeAccount(), forceRefresh: true)
        XCTAssertEqual(count, 101)
        XCTAssertEqual(page2Attempts, 2, "page 2 should be retried once before succeeding")
    }

    @MainActor func testFetchBlockedByCountThrowsAfterRetriesExhausted() async throws {
        var page2Attempts = 0
        MockURLProtocol.requestHandler = { request in
            let url = request.url!.absoluteString

            if url.contains("/single-blocklist/did:plc:test/2") {
                page2Attempts += 1
                let response = HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!
                return (response, Data())
            }

            if url.contains("/single-blocklist/did:plc:test") {
                let entries = (0 ..< 100).map { index in
                    #"{"did":"did:plc:page1-\#(index)","blocked_date":"2024-01-01T00:00:00Z"}"#
                }.joined(separator: ",")
                let json = #"{"data":{"blocklist":[\#(entries)]}}"#.data(using: .utf8)!
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (response, json)
            }

            throw BlueskyAPIError.invalidURL
        }

        do {
            _ = try await client.fetchBlockedByCount(for: makeAccount(), forceRefresh: true)
            XCTFail("Expected fetchBlockedByCount to throw after retries")
        } catch {
            XCTAssertGreaterThanOrEqual(page2Attempts, 2)
        }
    }

    @MainActor func testFetchBlockedActorsToleratesPartialError() async throws {
        MockURLProtocol.requestHandler = { request in
            let url = request.url!.absoluteString
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!

            if url.contains("/single-blocklist/did:plc:partial/2") {
                let failureResponse = HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!
                return (failureResponse, Data())
            }

            if url.contains("/single-blocklist/did:plc:partial") {
                let entries = (0 ..< 10).map { index in
                    #"{"did":"did:plc:page1-\#(index)","blocked_date":"2024-01-01T00:00:00Z"}"#
                }.joined(separator: ",")
                let json = #"{"data":{"blocklist":[\#(entries)]}}"#.data(using: .utf8)!
                return (response, json)
            }

            if url.contains("getProfiles") {
                let components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!
                let dids = components.queryItems?.filter { $0.name == "actors" }.compactMap(\.value) ?? []
                let profiles = dids.map { did in
                    #"{"did":"\#(did)","handle":"profile.bsky.social"}"#
                }.joined(separator: ",")
                let json = #"{"profiles":[\#(profiles)]}"#.data(using: .utf8)!
                return (response, json)
            }

            throw BlueskyAPIError.invalidURL
        }

        let result = try await client.fetchBlockedByActors(account: makeAccount(did: "did:plc:partial"), appPassword: "pass")
        XCTAssertEqual(result.totalCount, 10)
        XCTAssertEqual(result.actors.count, 10)
    }

    @MainActor func testFetchBlockedByCountStopsAt404() async throws {
        MockURLProtocol.requestHandler = { request in
            let url = request.url!.absoluteString

            if url.contains("/single-blocklist/did:plc:test/2") {
                let response = HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!
                return (response, Data())
            }

            if url.contains("/single-blocklist/did:plc:test") {
                let entries = (0 ..< 100).map { index in
                    #"{"did":"did:plc:page1-\#(index)","blocked_date":"2024-01-01T00:00:00Z"}"#
                }.joined(separator: ",")
                let json = #"{"data":{"blocklist":[\#(entries)]}}"#.data(using: .utf8)!
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (response, json)
            }

            throw BlueskyAPIError.invalidURL
        }

        let count = try await client.fetchBlockedByCount(for: makeAccount(), forceRefresh: true)
        XCTAssertEqual(count, 100)
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
            return try (response, JSONSerialization.data(withJSONObject: body))
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

    @MainActor func testFetchSubscribedModerationListsUsesListMutes() async throws {
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.path, "/xrpc/app.bsky.graph.getListMutes")
            XCTAssertEqual(request.value(forHTTPHeaderField: "atproto-proxy"), "did:web:api.bsky.app#bsky_appview")

            let json = """
            {
              "lists": [
                {
                  "uri": "at://did:plc:owner/app.bsky.graph.list/mod-1",
                  "cid": "cid-1",
                  "name": "Spam Watch",
                  "description": "Muted moderation list",
                  "purpose": "app.bsky.graph.defs#modlist",
                  "listItemCount": 42,
                  "indexedAt": "2026-05-20T10:00:00Z",
                  "creator": {
                    "did": "did:plc:owner",
                    "handle": "owner.bsky.social",
                    "displayName": "Owner"
                  }
                }
              ]
            }
            """.data(using: .utf8)!
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, json)
        }

        let lists = try await client.fetchSubscribedModerationLists(account: makeAccount(), appPassword: "pass")
        XCTAssertEqual(lists.count, 1)
        XCTAssertEqual(lists[0].listURI, "at://did:plc:owner/app.bsky.graph.list/mod-1")
        XCTAssertEqual(lists[0].kind, .moderation)
        XCTAssertEqual(lists[0].ownerHandle, "owner.bsky.social")
        XCTAssertEqual(lists[0].memberCount, 42)
        XCTAssertNotNil(lists[0].subscribedAt)
    }

    @MainActor func testIsSubscribedToModerationListReadsViewerMuteState() async throws {
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.path, "/xrpc/app.bsky.graph.getList")

            let json = """
            {
              "list": {
                "uri": "at://did:plc:owner/app.bsky.graph.list/mod-1",
                "cid": "cid-1",
                "name": "Spam Watch",
                "purpose": "app.bsky.graph.defs#modlist",
                "viewer": {
                  "muted": true
                }
              },
              "items": []
            }
            """.data(using: .utf8)!
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, json)
        }

        let isSubscribed = try await client.isSubscribedToModerationList(
            "at://did:plc:owner/app.bsky.graph.list/mod-1",
            account: makeAccount(),
            appPassword: "pass"
        )
        XCTAssertTrue(isSubscribed)
    }

    @MainActor func testSubscribeToModerationListUsesMuteActorList() async throws {
        let expectedURI = "at://did:plc:owner/app.bsky.graph.list/mod-1"

        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.path, "/xrpc/app.bsky.graph.muteActorList")
            XCTAssertEqual(request.httpMethod, "POST")

            let bodyData: Data
            if let httpBody = request.httpBody {
                bodyData = httpBody
            } else if let stream = request.httpBodyStream {
                stream.open()
                defer { stream.close() }
                var data = Data()
                while stream.hasBytesAvailable {
                    var buffer = [UInt8](repeating: 0, count: 1024)
                    let read = stream.read(&buffer, maxLength: buffer.count)
                    if read > 0 {
                        data.append(buffer, count: read)
                    } else {
                        break
                    }
                }
                bodyData = data
            } else {
                XCTFail("Expected request body (neither httpBody nor httpBodyStream)")
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (response, Data("{}".utf8))
            }
            let payload = try JSONDecoder().decode(ListReferenceRequest.self, from: bodyData)
            XCTAssertEqual(payload.list, expectedURI)

            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data("{}".utf8))
        }

        try await client.subscribeToModerationList(expectedURI, account: makeAccount(), appPassword: "pass")
    }

    @MainActor func testUnsubscribeFromModerationListUsesUnmuteActorList() async throws {
        let expectedURI = "at://did:plc:owner/app.bsky.graph.list/mod-1"

        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.path, "/xrpc/app.bsky.graph.unmuteActorList")
            XCTAssertEqual(request.httpMethod, "POST")

            let bodyData: Data
            if let httpBody = request.httpBody {
                bodyData = httpBody
            } else if let stream = request.httpBodyStream {
                stream.open()
                defer { stream.close() }
                var data = Data()
                while stream.hasBytesAvailable {
                    var buffer = [UInt8](repeating: 0, count: 1024)
                    let read = stream.read(&buffer, maxLength: buffer.count)
                    if read > 0 {
                        data.append(buffer, count: read)
                    } else {
                        break
                    }
                }
                bodyData = data
            } else {
                XCTFail("Expected request body (neither httpBody nor httpBodyStream)")
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (response, Data("{}".utf8))
            }
            let payload = try JSONDecoder().decode(ListReferenceRequest.self, from: bodyData)
            XCTAssertEqual(payload.list, expectedURI)

            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data("{}".utf8))
        }

        try await client.unsubscribeFromModerationList(expectedURI, account: makeAccount(), appPassword: "pass")
    }
}
