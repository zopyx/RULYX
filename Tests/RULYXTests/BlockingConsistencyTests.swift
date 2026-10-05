@testable import RULYX
import XCTest

/// Regression test for the AGENTS.md rule: the dashboard count and the detail-list count
/// must come from the **same source**, or the two screens disagree.
///
/// With ClearSky gone each direction has exactly one source, so the invariant is now
/// simply that the counting method and the listing method read the same records:
/// "Blocking" from the account's own repo, "Blocked by" from the Constellation index.
final class BlockingConsistencyTests: XCTestCase {
    private let ownerDID = "did:plc:consistency-test"

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
            client.constellation.cacheMaxAge = 0
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
        // `.shared`-scoped entries (profiles, backlinks) are not matched by `clear(for:)` —
        // reset the whole cache so they cannot leak into the next test.
        await BlueskyAPICache.shared.clearAll()
        try await super.tearDown()
    }

    /// "Blocking": dashboard count vs. detail list — both are the repo's block records.
    @MainActor func testBlockingCountMatchesDetailTotal() async throws {
        MockURLProtocol.requestHandler = { request in
            let url = request.url!.absoluteString
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            if url.contains("app.bsky.actor.getProfiles") {
                let json = #"{"profiles":[{"did":"did:plc:blocked-a","handle":"a.bsky.social"},{"did":"did:plc:blocked-b","handle":"b.bsky.social"}]}"#
                return (response, Data(json.utf8))
            }
            let json = #"{"records":[{"value":{"subject":"did:plc:blocked-a","createdAt":"2024-01-01T00:00:00Z"}},{"value":{"subject":"did:plc:blocked-b","createdAt":"2024-01-02T00:00:00Z"}}],"cursor":null}"#
            return (response, Data(json.utf8))
        }

        let count = try await client.fetchBlockingCount(for: makeAccount(did: ownerDID))
        let detail = try await client.fetchBlockedActors(account: makeAccount(did: ownerDID), appPassword: nil)

        XCTAssertEqual(count, detail.totalCount)
        XCTAssertEqual(count, detail.actors.count)
    }

    /// "Blocked by": dashboard count vs. detail list — both are the index's blockers.
    @MainActor func testBlockedByCountMatchesDetailTotal() async throws {
        MockURLProtocol.requestHandler = { request in
            let url = request.url!.absoluteString
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            if url.contains("app.bsky.actor.getProfiles") {
                let json = #"{"profiles":[{"did":"did:plc:blocker-a","handle":"a.bsky.social"},{"did":"did:plc:blocker-b","handle":"b.bsky.social"}]}"#
                return (response, Data(json.utf8))
            }
            let json = #"{"total":2,"records":[{"did":"did:plc:blocker-a","collection":"app.bsky.graph.block","rkey":"3lgxunk3mqu2z"},{"did":"did:plc:blocker-b","collection":"app.bsky.graph.block","rkey":"3jzfcijpj2z2a"}],"cursor":null}"#
            return (response, Data(json.utf8))
        }

        let count = try await client.fetchBlockedByCount(for: makeAccount(did: ownerDID))
        let detail = try await client.fetchBlockedByActors(account: makeAccount(did: ownerDID), appPassword: nil)

        XCTAssertEqual(count, detail.totalCount)
        XCTAssertEqual(count, detail.actors.count)
    }

    /// The two directions must never share a source: a blocked account is not a blocker.
    @MainActor func testBlockerDIDsAndBlockedDIDsAreIndependentSources() async throws {
        var collected = Set<String>()
        MockURLProtocol.requestHandler = { request in
            let url = request.url!.absoluteString
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            if url.contains("constellation.microcosm.blue") {
                collected.insert("index")
                let json = #"{"total":1,"records":[{"did":"did:plc:who-blocks-me","collection":"app.bsky.graph.block","rkey":"3lgxunk3mqu2z"}],"cursor":null}"#
                return (response, Data(json.utf8))
            }
            collected.insert("repo")
            let json = #"{"records":[{"value":{"subject":"did:plc:whom-i-block","createdAt":"2024-01-01T00:00:00Z"}}],"cursor":null}"#
            return (response, Data(json.utf8))
        }

        let blocked = try await client.fetchBlockedDIDs(for: makeAccount(did: ownerDID))
        let blockers = try await client.fetchBlockerDIDs(for: makeAccount(did: ownerDID))

        XCTAssertEqual(blocked, ["did:plc:whom-i-block"])
        XCTAssertEqual(blockers, ["did:plc:who-blocks-me"])
        XCTAssertEqual(collected, ["repo", "index"])
    }
}
