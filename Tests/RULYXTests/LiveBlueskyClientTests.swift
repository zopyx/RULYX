@testable import RULYX
import XCTest

final class LiveBlueskyClientTests: XCTestCase {
    private nonisolated(unsafe) var client: LiveBlueskyClient!
    private nonisolated(unsafe) var sessionService: MockSessionService!
    private nonisolated(unsafe) var requestExecutor: MockRequestExecutor!
    private nonisolated(unsafe) var mockSession: URLSession!

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
            // Nothing counts as a fresh cache hit here: each test must exercise the network
            // it mocks, and a payload cached by an earlier test would otherwise be served.
            client.repo.cacheMaxAge = 0
            client.constellation.cacheMaxAge = 0
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

    @MainActor func testFetchBlockedActorsReadsTheOwnRepo() async throws {
        MockURLProtocol.requestHandler = { request in
            let url = request.url!.absoluteString
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            if url.contains("com.atproto.repo.listRecords") {
                XCTAssertTrue(url.contains("collection=app.bsky.graph.block"), "reads the block collection, got \(url)")
                let json = #"{"records":[{"value":{"subject":"did:plc:b1","createdAt":"2024-01-01T00:00:00Z"}}],"cursor":null}"#
                return (response, Data(json.utf8))
            }
            if url.contains("getProfiles") {
                return (response, Data(#"{"profiles":[{"did":"did:plc:b1","handle":"blocked.bsky.social"}]}"#.utf8))
            }
            throw BlueskyAPIError.invalidURL
        }

        let blocked = try await client.fetchBlockedActors(account: makeAccount(handle: "test.bsky.social"), appPassword: "pass")
        XCTAssertEqual(blocked.totalCount, 1)
        XCTAssertEqual(blocked.actors.map(\.handle), ["blocked.bsky.social"])
    }

    @MainActor func testFetchBlockedActorsEmpty() async throws {
        MockURLProtocol.requestHandler = { request in
            let json = #"{"records":[],"cursor":null}"#.data(using: .utf8)!
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, json)
        }

        let blocked = try await client.fetchBlockedActors(account: makeAccount(handle: "test.bsky.social"), appPassword: "pass")
        XCTAssertTrue(blocked.actors.isEmpty)
        XCTAssertEqual(blocked.totalCount, 0)
    }

    /// "Unblocked blockers" = the index's blockers minus the account's own block records.
    @MainActor func testFetchUnblockedBlockersCountSubtractsTheOwnBlocklist() async throws {
        MockURLProtocol.requestHandler = { request in
            let url = request.url!.absoluteString
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!

            if url.contains("constellation.microcosm.blue") {
                let json = #"""
                {"total":2,"records":[
                  {"did":"did:plc:shared","collection":"app.bsky.graph.block","rkey":"3lgxunk3mqu2z"},
                  {"did":"did:plc:only-blocked-by","collection":"app.bsky.graph.block","rkey":"3jzfcijpj2z2a"}
                ],"cursor":null}
                """#
                return (response, Data(json.utf8))
            }

            if url.contains("com.atproto.repo.listRecords") {
                let json = #"""
                {"records":[
                  {"value":{"subject":"did:plc:shared","createdAt":"2024-01-01T00:00:00Z"}},
                  {"value":{"subject":"did:plc:only-blocked","createdAt":"2024-01-02T00:00:00Z"}}
                ],"cursor":null}
                """#
                return (response, Data(json.utf8))
            }

            if url.contains("getProfiles") {
                // After subtraction only did:plc:only-blocked-by remains.
                XCTAssertTrue(url.contains("only-blocked-by"), "only the unblocked blocker is resolved, got \(url)")
                let json = #"{"profiles":[{"did":"did:plc:only-blocked-by","handle":"only-blocked-by.bsky.social"}]}"#
                return (response, Data(json.utf8))
            }

            throw BlueskyAPIError.invalidURL
        }

        let count = try await client.fetchUnblockedBlockersCount(for: makeAccount())
        XCTAssertEqual(count, 1)
    }

    @MainActor func testFetchUnblockedBlockersCountPropagatesIndexFailure() async throws {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 503, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        do {
            _ = try await client.fetchUnblockedBlockersCount(for: makeAccount())
            XCTFail("a failing index must surface instead of reporting zero unblocked blockers")
        } catch {
            // Expected.
        }
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

    // MARK: - Handle resolution (AT Protocol only)

    /// Handle resolution runs on the AT Protocol (`com.atproto.identity.resolveHandle`),
    /// which is authoritative: opening a profile must never depend on a third-party
    /// service being up.
    @MainActor func testResolveHandleUsesATProtocol() async throws {
        var requestedHosts: [String] = []
        MockURLProtocol.requestHandler = { request in
            requestedHosts.append(request.url?.host ?? "")
            if request.url?.path == "/xrpc/com.atproto.identity.resolveHandle" {
                XCTAssertEqual(request.url?.query, "handle=someone.bsky.social")
                let json = #"{"did":"did:plc:resolved"}"#.data(using: .utf8)!
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, json)
            }
            return (HTTPURLResponse(url: request.url!, statusCode: 502, httpVersion: nil, headerFields: nil)!, Data())
        }

        let did = try await client.resolveHandle("someone.bsky.social")

        XCTAssertEqual(did, "did:plc:resolved")
        XCTAssertEqual(requestedHosts, ["public.api.bsky.app"], "handle resolution is a single AT Protocol call")
    }

    @MainActor func testResolveHandleThrowsWhenATProtocolFails() async throws {
        MockURLProtocol.requestHandler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 503, httpVersion: nil, headerFields: nil)!, Data())
        }

        do {
            _ = try await client.resolveHandle("someone.bsky.social")
            XCTFail("resolution has no fallback source any more — the failure must surface")
        } catch {
            // Expected.
        }
    }

    @MainActor func testResolveHandlePassesThroughDIDWithoutNetwork() async throws {
        MockURLProtocol.requestHandler = { _ in
            XCTFail("no network call expected for DID input")
            throw BlueskyAPIError.invalidURL
        }

        let did = try await client.resolveHandle("did:plc:already-known")

        XCTAssertEqual(did, "did:plc:already-known")
    }

    // MARK: - Stale cache fallback (own repo)

    /// A failed refresh must serve the last cached blocklist instead of throwing — the
    /// repo cache is what keeps the screen populated when the PDS is briefly unavailable.
    @MainActor func testStaleRepoCacheIsServedWhenThePDSFails() async throws {
        let account = makeAccount(did: "did:plc:stalefallback")
        var refreshShouldFail = false
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            if refreshShouldFail {
                return (HTTPURLResponse(url: request.url!, statusCode: 502, httpVersion: nil, headerFields: nil)!, Data())
            }
            let json = #"""
            {"records":[
              {"value":{"subject":"did:plc:stale1","createdAt":"2024-01-01T00:00:00Z"}},
              {"value":{"subject":"did:plc:stale2","createdAt":"2024-01-02T00:00:00Z"}}
            ],"cursor":null}
            """#
            return (response, Data(json.utf8))
        }

        // 1) A successful fetch populates the cache.
        let fresh = try await client.fetchBlockingCount(for: account)
        XCTAssertEqual(fresh, 2)

        // 2) Age the cache out and make the refresh fail.
        client.repo.cacheMaxAge = 0
        refreshShouldFail = true

        // 3) The stale payload is served instead of an error.
        let stale = try await client.fetchBlockingCount(for: account)
        XCTAssertEqual(stale, 2, "stale cache must be served when the PDS refresh fails")

        await BlueskyAPICache.shared.clear(for: account.did ?? account.handle)
    }

    /// Explicit refreshes must not silently fall back to stale data.
    @MainActor func testForceRefreshStillThrowsWhenThePDSFails() async throws {
        let account = makeAccount(did: "did:plc:staleforcedecline")
        var refreshShouldFail = false
        MockURLProtocol.requestHandler = { request in
            if refreshShouldFail {
                return (HTTPURLResponse(url: request.url!, statusCode: 502, httpVersion: nil, headerFields: nil)!, Data())
            }
            let json = #"{"records":[{"value":{"subject":"did:plc:fresh","createdAt":"2024-01-01T00:00:00Z"}}],"cursor":null}"#.data(using: .utf8)!
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, json)
        }

        _ = try await client.fetchBlockingCount(for: account)
        refreshShouldFail = true

        do {
            _ = try await client.fetchBlockingCount(for: account, forceRefresh: true)
            XCTFail("forceRefresh must propagate the PDS failure")
        } catch {
            XCTAssertTrue(true)
        }

        await BlueskyAPICache.shared.clear(for: account.did ?? account.handle)
    }
}
