@testable import RULYX
import XCTest

/// "Blocked by" is answered by the Constellation backlink index
/// (`https://constellation.microcosm.blue`): the `app.bsky.graph.block` records that point
/// at an account *are* the accounts blocking it, and the index reports their exact total.
///
/// The index is also the only source for that direction — a repository lists what its
/// owner blocked, never who blocked the owner.
final class ConstellationBlocklistTests: XCTestCase {
    /// Account under test. Also the API-cache key, so `tearDown` can clear it.
    private let ownerDID = "did:plc:constellation-test"

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
            client.constellation.cacheMaxAge = 0
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

    // MARK: - TID decoding

    func testAtProtoTidDecodesBlockRecordKey() {
        // Record key of a real app.bsky.graph.block record.
        let date = AtProtoTid.date(fromRecordKey: "3lgxunk3mqu2z")
        XCTAssertEqual(date.map { SharedDateFormatters.formatISO8601($0) }, "2025-01-30T16:09:35Z")

        XCTAssertNil(AtProtoTid.date(fromRecordKey: "3lgxunk3mqu2"), "too short")
        XCTAssertNil(AtProtoTid.date(fromRecordKey: "3lgxunk3mqu2zz"), "too long")
        XCTAssertNil(AtProtoTid.date(fromRecordKey: "3lgxunk3mqu2!"), "invalid alphabet")

        XCTAssertEqual(
            AtProtoTid.date(fromATURI: "at://did:plc:x/app.bsky.graph.block/3lgxunk3mqu2z"),
            AtProtoTid.date(fromRecordKey: "3lgxunk3mqu2z")
        )
    }

    // MARK: - Count

    @MainActor func testBlockedByCountComesFromTheIndexTotal() async throws {
        var requests = 0
        MockURLProtocol.requestHandler = { request in
            requests += 1
            let url = request.url!.absoluteString
            XCTAssertTrue(url.contains("app.bsky.graph.block"), "queries the block link, got \(url)")
            XCTAssertTrue(url.contains(self.ownerDID), "queries the own DID, got \(url)")
            let json = #"{"total":7,"records":[{"did":"did:plc:a","collection":"app.bsky.graph.block","rkey":"3lgxunk3mqu2z"}],"cursor":null}"#
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data(json.utf8)
            )
        }

        let count = try await client.fetchBlockedByCount(for: makeAccount(did: ownerDID))

        XCTAssertEqual(count, 7, "the index total, not the page size")
        XCTAssertEqual(requests, 1, "the count needs a single request")
    }

    @MainActor func testBlockedByCountPropagatesIndexError() async throws {
        MockURLProtocol.requestHandler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 503, httpVersion: nil, headerFields: nil)!, Data())
        }

        do {
            _ = try await client.fetchBlockedByCount(for: makeAccount(did: ownerDID))
            XCTFail("a failing index must surface instead of reporting zero blockers")
        } catch {
            // Expected: no source could answer.
        }
    }

    // MARK: - DIDs

    @MainActor func testBlockerDIDsWalkEveryPageAndDeduplicate() async throws {
        var pages = 0
        MockURLProtocol.requestHandler = { request in
            let url = request.url!.absoluteString
            pages += 1
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            // A short leading page with a cursor: the next page repeats a DID on purpose.
            let records = url.contains("page-2")
                ? [#"{"did":"did:plc:blocker-b","collection":"app.bsky.graph.block","rkey":"3jzfcijpj2z2a"}"#]
                : [
                    #"{"did":"did:plc:blocker-a","collection":"app.bsky.graph.block","rkey":"3lgxunk3mqu2z"}"#,
                    #"{"did":"did:plc:blocker-b","collection":"app.bsky.graph.block","rkey":"3lgxunk3mqu2z"}"#,
                ]
            let cursor = url.contains("page-2") ? "null" : #""page-2""#
            let json = #"{"total":2,"records":[\#(records.joined(separator: ","))],"cursor":\#(cursor)}"#
            return (response, Data(json.utf8))
        }

        let dids = try await client.fetchBlockerDIDs(for: makeAccount(did: ownerDID))

        XCTAssertEqual(dids, ["did:plc:blocker-a", "did:plc:blocker-b"])
        XCTAssertEqual(pages, 2, "the walk follows the cursor to the end")
    }

    // MARK: - Actors

    @MainActor func testBlockedByActorsResolveProfilesAndDates() async throws {
        MockURLProtocol.requestHandler = { request in
            let url = request.url!.absoluteString
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            if url.contains("constellation.microcosm.blue") {
                let json = #"""
                {"total":2,"records":[
                  {"did":"did:plc:blocker-a","collection":"app.bsky.graph.block","rkey":"3lgxunk3mqu2z"},
                  {"did":"did:plc:blocker-b","collection":"app.bsky.graph.block","rkey":"3jzfcijpj2z2a"}
                ],"cursor":null}
                """#
                return (response, Data(json.utf8))
            }
            if url.contains("app.bsky.actor.getProfiles") {
                let json = #"{"profiles":[{"did":"did:plc:blocker-a","handle":"a.bsky.social"},{"did":"did:plc:blocker-b","handle":"b.bsky.social"}]}"#
                return (response, Data(json.utf8))
            }
            return (HTTPURLResponse(url: request.url!, statusCode: 503, httpVersion: nil, headerFields: nil)!, Data())
        }

        let result = try await client.fetchBlockedByActors(account: makeAccount(did: ownerDID), appPassword: nil)

        XCTAssertEqual(result.totalCount, 2)
        XCTAssertEqual(Set(result.actors.map(\.handle)), ["a.bsky.social", "b.bsky.social"])
        XCTAssertEqual(result.actors.filter { $0.blockedDate != nil }.count, 2, "block dates come from the record key")
    }

    @MainActor func testBlockedByActorsServeLastGoodPayloadWhenRefreshFails() async throws {
        MockURLProtocol.requestHandler = { request in
            let url = request.url!.absoluteString
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            if url.contains("constellation.microcosm.blue") {
                let json = #"{"total":1,"records":[{"did":"did:plc:blocker-a","collection":"app.bsky.graph.block","rkey":"3lgxunk3mqu2z"}],"cursor":null}"#
                return (response, Data(json.utf8))
            }
            if url.contains("app.bsky.actor.getProfiles") {
                return (response, Data(#"{"profiles":[{"did":"did:plc:blocker-a","handle":"a.bsky.social"}]}"#.utf8))
            }
            return (HTTPURLResponse(url: request.url!, statusCode: 503, httpVersion: nil, headerFields: nil)!, Data())
        }
        let first = try await client.fetchBlockedByActors(account: makeAccount(did: ownerDID), appPassword: nil)
        XCTAssertEqual(first.actors.count, 1)

        // The index goes away and the cache entry is stale: the last good payload wins,
        // while profile resolution (a different host) still works.
        MockURLProtocol.requestHandler = { request in
            let url = request.url!.absoluteString
            if url.contains("app.bsky.actor.getProfiles") {
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (response, Data(#"{"profiles":[{"did":"did:plc:blocker-a","handle":"a.bsky.social"}]}"#.utf8))
            }
            return (HTTPURLResponse(url: request.url!, statusCode: 503, httpVersion: nil, headerFields: nil)!, Data())
        }

        let second = try await client.fetchBlockedByActors(account: makeAccount(did: ownerDID), appPassword: nil)

        XCTAssertEqual(second.totalCount, 1)
        XCTAssertEqual(second.actors.map(\.handle), ["a.bsky.social"])
    }
}
