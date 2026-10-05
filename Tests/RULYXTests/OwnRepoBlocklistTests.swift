@testable import RULYX
import XCTest

/// "Blocking" is read from the account's **own** repository: its
/// `app.bsky.graph.block` records are the blocklist, so the count and the detail list
/// always describe the same set of records — no third party, no snapshot lag.
final class OwnRepoBlocklistTests: XCTestCase {
    /// Account under test. Also the API-cache key, so `tearDown` can clear it.
    private let ownerDID = "did:plc:own-repo-test"

    private nonisolated(unsafe) var client: LiveBlueskyClient!
    private nonisolated(unsafe) var mockSession: URLSession!

    override func setUp() async throws {
        try await super.setUp()
        let setup = await MainActor.run { () -> (URLSession, LiveBlueskyClient) in
            let config = URLSessionConfiguration.ephemeral
            config.protocolClasses = [MockURLProtocol.self]
            let mockSession = URLSession(configuration: config)
            MockURLProtocol.config = .normal
            let client = LiveBlueskyClient(
                httpClient: HTTPClient(session: mockSession),
                requestExecutor: MockRequestExecutor(),
                sessionService: MockSessionService()
            )
            // Nothing counts as a fresh cache hit: every test exercises the network.
            client.repo.cacheMaxAge = 0
            return (mockSession, client)
        }
        mockSession = setup.0
        client = setup.1
    }

    override func tearDown() async throws {
        MockURLProtocol.requestHandler = nil
        client = nil
        mockSession = nil
        // Profile rows are cached in the `.shared` scope, which `clear(for:)` does not match —
        // reset the whole cache so a previous test's profiles cannot leak into this one.
        await BlueskyAPICache.shared.clearAll()
        try await super.tearDown()
    }

    // MARK: - Count and detail agree

    @MainActor func testBlockingCountEqualsRecordCountAndDetailUsesTheSameRecords() async throws {
        var repoRequests = 0
        MockURLProtocol.requestHandler = { request in
            let url = request.url!.absoluteString
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            if url.contains("app.bsky.actor.getProfiles") {
                let json = #"""
                {"profiles":[
                  {"did":"did:plc:blocked-a","handle":"a.bsky.social"},
                  {"did":"did:plc:blocked-b","handle":"b.bsky.social"},
                  {"did":"did:plc:blocked-c","handle":"c.bsky.social"}
                ]}
                """#
                return (response, Data(json.utf8))
            }
            XCTAssertTrue(url.contains("com.atproto.repo.listRecords"), "reads the own repo, got \(url)")
            XCTAssertTrue(url.contains("collection=app.bsky.graph.block"), "reads the block collection, got \(url)")
            repoRequests += 1
            let records = url.contains("cursor=page-2")
                ? [#"{"value":{"subject":"did:plc:blocked-c","createdAt":"2025-02-01T10:00:00Z"}}"#]
                : [
                    #"{"value":{"subject":"did:plc:blocked-a","createdAt":"2025-01-30T16:09:35Z"}}"#,
                    #"{"value":{"subject":"did:plc:blocked-b","createdAt":"2025-01-31T08:00:00Z"}}"#,
                ]
            let cursor = url.contains("cursor=page-2") ? "null" : #""page-2""#
            let json = #"{"records":[\#(records.joined(separator: ","))],"cursor":\#(cursor)}"#
            return (response, Data(json.utf8))
        }

        let count = try await client.fetchBlockingCount(for: makeAccount(did: ownerDID))
        let result = try await client.fetchBlockedActors(account: makeAccount(did: ownerDID), appPassword: nil)

        XCTAssertEqual(count, 3, "every block record counts, across pages")
        XCTAssertEqual(result.totalCount, count, "dashboard count and detail list describe the same records")
        XCTAssertEqual(Set(result.actors.map(\.did)), ["did:plc:blocked-a", "did:plc:blocked-b", "did:plc:blocked-c"])
        XCTAssertEqual(result.actors.filter { $0.blockedDate != nil }.count, 3, "block dates come from the record")
        XCTAssertEqual(repoRequests % 2, 0, "each call walks the two record pages")
    }

    // MARK: - DIDs

    @MainActor func testBlockedDIDsReturnsRecordSubjects() async throws {
        MockURLProtocol.requestHandler = { request in
            let json = #"{"records":[{"value":{"subject":"did:plc:blocked-a"}},{"value":{"subject":"did:plc:blocked-b"}}],"cursor":null}"#
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data(json.utf8)
            )
        }

        let dids = try await client.fetchBlockedDIDs(for: makeAccount(did: ownerDID))

        XCTAssertEqual(dids, ["did:plc:blocked-a", "did:plc:blocked-b"])
    }

    @MainActor func testBlockedActorsDeduplicateRepeatedSubjects() async throws {
        MockURLProtocol.requestHandler = { request in
            let url = request.url!.absoluteString
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            if url.contains("app.bsky.actor.getProfiles") {
                let json = #"{"profiles":[{"did":"did:plc:blocked-a","handle":"a.bsky.social"}]}"#
                return (response, Data(json.utf8))
            }
            // The same subject twice: the app never renders a duplicate row.
            let json = #"""
            {"records":[
              {"value":{"subject":"did:plc:blocked-a","createdAt":"2025-01-30T16:09:35Z"}},
              {"value":{"subject":"did:plc:blocked-a","createdAt":"2025-01-30T16:09:35Z"}}
            ],"cursor":null}
            """#
            return (response, Data(json.utf8))
        }

        let result = try await client.fetchBlockedActors(account: makeAccount(did: ownerDID), appPassword: nil)

        XCTAssertEqual(result.actors.count, 1)
        XCTAssertEqual(result.totalCount, 1)
    }

    // MARK: - Cache

    @MainActor func testFreshCacheAnswersWithoutTouchingTheNetwork() async throws {
        var requests = 0
        MockURLProtocol.requestHandler = { request in
            requests += 1
            let json = #"{"records":[{"value":{"subject":"did:plc:blocked-a","createdAt":"2025-01-30T16:09:35Z"}}],"cursor":null}"#
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data(json.utf8)
            )
        }
        client.repo.cacheMaxAge = 3600

        let first = try await client.fetchBlockingCount(for: makeAccount(did: ownerDID))
        let second = try await client.fetchBlockingCount(for: makeAccount(did: ownerDID))

        XCTAssertEqual([first, second], [1, 1])
        XCTAssertEqual(requests, 1)
    }

    @MainActor func testForceRefreshBypassesTheCache() async throws {
        var requests = 0
        MockURLProtocol.requestHandler = { request in
            requests += 1
            let json = #"{"records":[{"value":{"subject":"did:plc:blocked-a","createdAt":"2025-01-30T16:09:35Z"}}],"cursor":null}"#
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data(json.utf8)
            )
        }
        client.repo.cacheMaxAge = 3600

        _ = try await client.fetchBlockingCount(for: makeAccount(did: ownerDID))
        _ = try await client.fetchBlockingCount(for: makeAccount(did: ownerDID), forceRefresh: true)

        XCTAssertEqual(requests, 2)
    }

    @MainActor func testStaleCacheIsServedWhenThePDSFails() async throws {
        MockURLProtocol.requestHandler = { request in
            let json = #"{"records":[{"value":{"subject":"did:plc:blocked-a","createdAt":"2025-01-30T16:09:35Z"}}],"cursor":null}"#
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data(json.utf8)
            )
        }
        let first = try await client.fetchBlockedActors(account: makeAccount(did: ownerDID), appPassword: nil)
        XCTAssertEqual(first.totalCount, 1)

        MockURLProtocol.requestHandler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 503, httpVersion: nil, headerFields: nil)!, Data())
        }

        // cacheMaxAge is 0 here, so the entry is stale: the refresh is attempted, fails,
        // and the last good payload is served instead of an error.
        let second = try await client.fetchBlockedActors(account: makeAccount(did: ownerDID), appPassword: nil)

        XCTAssertEqual(second.totalCount, 1)
    }

    @MainActor func testEmptyCacheIsNotServedAsAFallback() async throws {
        MockURLProtocol.requestHandler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 503, httpVersion: nil, headerFields: nil)!, Data())
        }

        do {
            _ = try await client.fetchBlockedActors(account: makeAccount(did: ownerDID), appPassword: nil)
            XCTFail("without a cached payload the error must surface")
        } catch {
            // Expected.
        }
    }
}
