@testable import RULYX
import XCTest

/// "Listed on" is assembled from the AT Protocol alone: the list **memberships** come from
/// the Constellation index (`app.bsky.graph.listitem` records whose `subject` is the
/// profile) and the **list metadata** from the public AppView — one `getLists` request per
/// list owner instead of one per list.
final class ListedOnListsTests: XCTestCase {
    /// The profile whose lists are being resolved. Also the API-cache key.
    private let profileDID = "did:plc:listed-on-test"

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
            client.listedOnResolver.cacheMaxAge = 0
            return (mockSession, client)
        }
        mockSession = setup.0
        client = setup.1
    }

    override func tearDown() async throws {
        MockURLProtocol.requestHandler = nil
        client = nil
        mockSession = nil
        await BlueskyAPICache.shared.clear(for: profileDID)
        await BlueskyAPICache.shared.clear(for: "did:plc:owner-a")
        try await super.tearDown()
    }

    // MARK: - Count

    @MainActor func testListedOnCountCountsDistinctLists() async throws {
        MockURLProtocol.requestHandler = { request in
            let url = request.url!.absoluteString
            XCTAssertTrue(url.contains("getManyToManyCounts"), "counts memberships by list, got \(url)")
            XCTAssertTrue(url.contains(self.profileDID), "queries the profile, got \(url)")
            // Two groups, one of them with two membership records: the profile is on two
            // lists, not three.
            let json = #"""
            {"counts_by_other_subject":[
              {"subject":"at://did:plc:owner-a/app.bsky.graph.list/alpha","total":2,"distinct":1},
              {"subject":"at://did:plc:owner-a/app.bsky.graph.list/beta","total":1,"distinct":1}
            ],"cursor":null}
            """#
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data(json.utf8)
            )
        }

        let count = try await client.fetchListedOnCount(handle: "someone.bsky.social", did: profileDID)

        XCTAssertEqual(count, 2)
    }

    // MARK: - Entries

    @MainActor func testListedOnListsCombineIndexMembershipsWithAppViewMetadata() async throws {
        var listRequests = 0
        MockURLProtocol.requestHandler = { request in
            let url = request.url!.absoluteString
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            if url.contains("getLists") {
                listRequests += 1
                XCTAssertTrue(url.contains("actor=did:plc:owner-a"), "one request per owner, got \(url)")
                let json = #"""
                {"lists":[
                  {
                    "uri":"at://did:plc:owner-a/app.bsky.graph.list/alpha","name":"Alpha list",
                    "description":"first","purpose":"app.bsky.graph.defs#modlist",
                    "indexedAt":"2025-01-30T16:00:00Z","creator":{"did":"did:plc:owner-a"}
                  },
                  {
                    "uri":"at://did:plc:owner-a/app.bsky.graph.list/beta","name":"Beta list",
                    "description":null,"purpose":"app.bsky.graph.defs#curatelist",
                    "indexedAt":"2025-02-01T09:00:00Z","creator":{"did":"did:plc:owner-a"}
                  }
                ],"cursor":null}
                """#
                return (response, Data(json.utf8))
            }
            if url.contains("getList") {
                XCTFail("no straggler lookup expected, got \(url)")
                return (response, Data(#"{"list":{"uri":"","name":""}}"#.utf8))
            }
            XCTAssertTrue(url.contains("getManyToMany"), "memberships come from the index, got \(url)")
            // Three memberships on two lists; the re-added one must collapse to a single row
            // and the newest record key wins (3lgx… = 2025-01-30, 3jzf… = 2023-06-30).
            let json = #"""
            {"items":[
              {"linkRecord":{"did":"did:plc:owner-a","collection":"app.bsky.graph.listitem","rkey":"3lgxunk3mqu2z"},"otherSubject":"at://did:plc:owner-a/app.bsky.graph.list/alpha"},
              {"linkRecord":{"did":"did:plc:owner-a","collection":"app.bsky.graph.listitem","rkey":"3jzfcijpj2z2a"},"otherSubject":"at://did:plc:owner-a/app.bsky.graph.list/alpha"},
              {"linkRecord":{"did":"did:plc:owner-a","collection":"app.bsky.graph.listitem","rkey":"3mwu2mkp2zk2v"},"otherSubject":"at://did:plc:owner-a/app.bsky.graph.list/beta"}
            ],"cursor":null}
            """#
            return (response, Data(json.utf8))
        }

        let entries = try await client.fetchListedOnLists(handle: "someone.bsky.social", did: profileDID)

        XCTAssertEqual(entries.map(\.name), ["Beta list", "Alpha list"], "newest membership first")
        XCTAssertEqual(entries.map(\.did), ["did:plc:owner-a", "did:plc:owner-a"])
        XCTAssertEqual(listRequests, 1, "one AppView request covers every list of an owner")
        XCTAssertEqual(entries.filter { !$0.dateAdded.isEmpty }.count, 2, "membership dates come from the record key")
    }

    @MainActor func testUnresolvableListsAreDroppedInsteadOfRenderedEmpty() async throws {
        MockURLProtocol.requestHandler = { request in
            let url = request.url!.absoluteString
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            if url.contains("getLists") {
                // The owner's only list is gone: the membership cannot be rendered.
                return (response, Data(#"{"lists":[],"cursor":null}"#.utf8))
            }
            if url.contains("getList") {
                return (HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!, Data())
            }
            let json = #"""
            {"items":[
              {"linkRecord":{"did":"did:plc:owner-a","collection":"app.bsky.graph.listitem",
                             "rkey":"3lgxunk3mqu2z"},
               "otherSubject":"at://did:plc:owner-a/app.bsky.graph.list/deleted"}
            ],"cursor":null}
            """#
            return (response, Data(json.utf8))
        }

        let entries = try await client.fetchListedOnLists(handle: "someone.bsky.social", did: profileDID)

        XCTAssertTrue(entries.isEmpty, "a list that no longer resolves produces no row")
    }

    @MainActor func testMembershipWalkErrorPropagates() async throws {
        MockURLProtocol.requestHandler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 503, httpVersion: nil, headerFields: nil)!, Data())
        }

        do {
            _ = try await client.fetchListedOnLists(handle: "someone.bsky.social", did: profileDID)
            XCTFail("an unreachable index must surface instead of reporting no lists")
        } catch {
            // Expected.
        }
    }

    // MARK: - Progress

    /// The sheet shows how far the metadata walk is, so the phases must be reported: the
    /// membership walk first, then a monotonic "resolved / total lists" counter.
    @MainActor func testListedOnReportsMembershipThenMetadataProgress() async throws {
        let recorder = ProgressRecorder()
        MockURLProtocol.requestHandler = { request in
            let url = request.url!.absoluteString
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            if url.contains("getLists") {
                let owner = url.contains("owner-b") ? "did:plc:owner-b" : "did:plc:owner-a"
                let listID = url.contains("owner-b") ? "beta" : "alpha"
                let json = #"{"lists":[{"uri":"at://\#(owner)/app.bsky.graph.list/\#(listID)","name":"\#(listID) list","creator":{"did":"\#(owner)"}}],"cursor":null}"#
                return (response, Data(json.utf8))
            }
            if url.contains("getList") {
                XCTFail("no straggler lookup expected, got \(url)")
                return (response, Data(#"{"list":{"uri":"","name":""}}"#.utf8))
            }
            let json = #"""
            {"items":[
              {"linkRecord":{"did":"did:plc:owner-a","collection":"app.bsky.graph.listitem","rkey":"3lgxunk3mqu2z"},"otherSubject":"at://did:plc:owner-a/app.bsky.graph.list/alpha"},
              {"linkRecord":{"did":"did:plc:owner-b","collection":"app.bsky.graph.listitem","rkey":"3mwu2mkp2zk2v"},"otherSubject":"at://did:plc:owner-b/app.bsky.graph.list/beta"}
            ],"cursor":null}
            """#
            return (response, Data(json.utf8))
        }

        let entries = try await client.fetchListedOnLists(
            handle: "someone.bsky.social",
            did: profileDID
        ) { progress in
            recorder.record(progress)
        }

        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(recorder.events.first, .memberships, "the membership walk is reported first")
        XCTAssertEqual(
            recorder.events.dropFirst().first,
            .lists(resolved: 0, total: 2),
            "the total is known as soon as the memberships are"
        )
        XCTAssertEqual(
            recorder.events.last,
            .lists(resolved: 2, total: 2),
            "the last report covers every resolved list"
        )
        let resolvedSteps = recorder.events.compactMap { progress -> Int? in
            if case let .lists(resolved, _) = progress {
                return resolved
            }
            return nil
        }
        XCTAssertEqual(resolvedSteps, resolvedSteps.sorted(), "progress never goes backwards")
        XCTAssertEqual(recorder.events.first?.fraction, nil, "an unknown total shows as indeterminate")
        XCTAssertEqual(recorder.events.last?.fraction, 1.0)
    }

    // MARK: - Throttling

    /// A throttled (`429`) owner request is retried instead of being swallowed: the wide
    /// fan-out must not cost a list just because the AppView pushed back once.
    @MainActor func testThrottledOwnerRequestIsRetried() async throws {
        let probe = RequestProbe()
        MockURLProtocol.requestHandler = { request in
            let url = request.url!.absoluteString
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            if url.contains("getLists") {
                if probe.begin("lists") == 1 {
                    return (HTTPURLResponse(url: request.url!, statusCode: 429, httpVersion: nil, headerFields: nil)!, Data())
                }
                return (response, Data(#"{"lists":[{"uri":"at://did:plc:owner-a/app.bsky.graph.list/alpha","name":"Alpha","creator":{"did":"did:plc:owner-a"}}],"cursor":null}"#.utf8))
            }
            if url.contains("getList") {
                XCTFail("no straggler lookup expected, got \(url)")
                return (response, Data(#"{"list":{"uri":"","name":""}}"#.utf8))
            }
            let json = #"""
            {"items":[
              {"linkRecord":{"did":"did:plc:owner-a","collection":"app.bsky.graph.listitem","rkey":"3lgxunk3mqu2z"},
               "otherSubject":"at://did:plc:owner-a/app.bsky.graph.list/alpha"}
            ],"cursor":null}
            """#
            return (response, Data(json.utf8))
        }

        let entries = try await client.fetchListedOnLists(handle: "someone.bsky.social", did: profileDID)

        XCTAssertEqual(probe.hits("lists"), 2, "the throttled request is attempted twice")
        XCTAssertEqual(entries.map(\.name), ["Alpha"], "the list survives the throttle")
    }

    /// A non-transient answer (the list is gone) is not retried: `404` is final.
    @MainActor func testClientErrorIsNotRetried() async throws {
        let probe = RequestProbe()
        MockURLProtocol.requestHandler = { request in
            let url = request.url!.absoluteString
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            if url.contains("getLists") {
                probe.begin("lists")
                return (HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!, Data())
            }
            if url.contains("getList") {
                probe.begin("list")
                return (HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!, Data())
            }
            let json = #"""
            {"items":[
              {"linkRecord":{"did":"did:plc:owner-a","collection":"app.bsky.graph.listitem","rkey":"3lgxunk3mqu2z"},
               "otherSubject":"at://did:plc:owner-a/app.bsky.graph.list/gone"}
            ],"cursor":null}
            """#
            return (response, Data(json.utf8))
        }

        let entries = try await client.fetchListedOnLists(handle: "someone.bsky.social", did: profileDID)

        XCTAssertEqual(probe.hits("lists"), 1, "a 404 is the server's answer, not something to retry")
        XCTAssertEqual(probe.hits("list"), 1, "the straggler pass runs once per unresolved list")
        XCTAssertTrue(entries.isEmpty, "a list that no longer exists produces no row")
    }
}

/// Collects progress callbacks. A reference type so the `@Sendable` callback can hand them
/// over without capturing a mutable local.
@MainActor
private final class ProgressRecorder {
    private(set) var events: [ListedOnProgress] = []

    func record(_ progress: ListedOnProgress) {
        events.append(progress)
    }
}

/// Counts mocked requests: how many ran at the same time, and how often each kind ran.
/// The mock handler runs on URLSession's own threads, so the counters are locked.
private final class RequestProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var inFlight = 0
    private var peak = 0
    private var counts: [String: Int] = [:]

    /// Marks a request as started and returns how many of that kind have been seen.
    @discardableResult
    func begin(_ key: String) -> Int {
        lock.lock()
        defer { lock.unlock() }
        inFlight += 1
        peak = max(peak, inFlight)
        counts[key, default: 0] += 1
        return counts[key] ?? 0
    }

    /// Marks a request as finished.
    func end() {
        lock.lock()
        defer { lock.unlock() }
        inFlight -= 1
    }

    /// Highest number of simultaneous requests seen.
    var maxInFlight: Int {
        lock.lock()
        defer { lock.unlock() }
        return peak
    }

    /// How many requests of `key` have been seen.
    func hits(_ key: String) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return counts[key] ?? 0
    }
}
