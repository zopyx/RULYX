@testable import RULYX
import XCTest

/// Behaviour of the API cache's freshness bookkeeping: a stale entry must be reported as
/// stale (not folded into the hit count, as it once was), a 304 must be able to revalidate
/// an entry in place, and origin freshness headers must round-trip.
///
/// Uses a private cache instance so the counters are not polluted by other tests running in
/// parallel against `BlueskyAPICache.shared`.
final class BlueskyAPICacheFreshnessTests: XCTestCase {
    private let cache = BlueskyAPICache()
    private let scope = BlueskyAPICache.Scope.shared

    override func tearDown() async throws {
        await cache.remove(scope: scope, url: "freshness/test")
        await cache.remove(scope: scope, url: "freshness/etag")
    }

    func testStaleEntryIsReportedStaleNotFresh() async {
        let url = "freshness/test"
        await cache.write(scope: scope, url: url, data: Data("payload".utf8))

        let fresh = await cache.read(scope: scope, url: url, maxAge: 3600)
        XCTAssertEqual(fresh?.isStale, false, "a just-written entry is fresh")

        let stale = await cache.read(scope: scope, url: url, maxAge: 0)
        XCTAssertEqual(stale?.isStale, true, "an entry past its TTL must report as stale")
        XCTAssertEqual(stale?.data, Data("payload".utf8), "stale data is still served")
    }

    func testMetricsSeparateFreshStaleAndMiss() async {
        await cache.write(scope: scope, url: "freshness/test", data: Data("x".utf8))

        _ = await cache.read(scope: scope, url: "freshness/test", maxAge: 3600) // fresh
        _ = await cache.read(scope: scope, url: "freshness/test", maxAge: 0) // stale
        _ = await cache.read(scope: scope, url: "freshness/absent", maxAge: 3600) // miss

        let snapshot = await cache.snapshot()
        XCTAssertEqual(snapshot.hitCount, 1, "only the fresh read counts as a fresh hit")
        XCTAssertEqual(snapshot.staleCount, 1, "the expired read counts as stale")
        XCTAssertEqual(snapshot.missCount, 1, "an absent entry counts as a miss")
        XCTAssertEqual(snapshot.freshHitRatio, 1.0 / 3.0, accuracy: 0.0001)
        XCTAssertEqual(snapshot.hitRatio, 2.0 / 3.0, accuracy: 0.0001)
    }

    func testMarkRevalidatedRefreshesStaleEntry() async {
        let url = "freshness/etag"
        await cache.write(scope: scope, url: url, data: Data("body".utf8), etag: "W/\"abc\"")

        // Force the entry past its TTL, then revalidate it as a 304 would.
        let stale = await cache.read(scope: scope, url: url, maxAge: 0)
        XCTAssertEqual(stale?.isStale, true)
        XCTAssertEqual(stale?.etag, "W/\"abc\"", "the stored validator must round-trip")

        await cache.markRevalidated(scope: scope, url: url)

        let afterRevalidation = await cache.read(scope: scope, url: url, maxAge: 3600)
        XCTAssertEqual(afterRevalidation?.isStale, false, "revalidation restarts the TTL")
        XCTAssertEqual(afterRevalidation?.data, Data("body".utf8), "the payload is preserved")
    }
}

/// The origin's freshness headers must be captured, since they drive conditional revalidation.
final class HTTPClientCacheMetadataTests: XCTestCase {
    func testCacheMetadataParsesEtagAndMaxAge() throws {
        let url = try XCTUnwrap(URL(string: "https://public.api.bsky.app/xrpc/app.bsky.actor.getProfile"))
        let response = try XCTUnwrap(HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: "HTTP/2",
            headerFields: [
                "ETag": "W/\"107-B8c\"",
                "Cache-Control": "public, max-age=30",
            ]
        ))

        let metadata = HTTPClient.cacheMetadata(from: response)
        XCTAssertEqual(metadata.etag, "W/\"107-B8c\"")
        XCTAssertEqual(metadata.serverMaxAge, 30)
        XCTAssertNil(metadata.lastModified)
    }

    func testCacheMetadataToleratesMissingHeaders() throws {
        let url = try XCTUnwrap(URL(string: "https://example.com"))
        let response = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/2", headerFields: [:]))

        let metadata = HTTPClient.cacheMetadata(from: response)
        XCTAssertNil(metadata.etag)
        XCTAssertNil(metadata.lastModified)
        XCTAssertNil(metadata.serverMaxAge)
    }
}

/// The account-switch reset contract requires every cache to be empty afterwards — including
/// the pinned API session's own URL cache, which is separate from `URLCache.shared` and was
/// introduced when the pinned session stopped being `.ephemeral`.
@MainActor
final class AccountSwitchCacheClearTests: XCTestCase {
    func testClearAllCachesEmptiesPinnedAPIURLCache() async throws {
        let url = try XCTUnwrap(URL(string: "https://public.api.bsky.app/xrpc/app.bsky.actor.getProfile?actor=did:plc:cache-clear"))
        let request = URLRequest(url: url)
        let response = try XCTUnwrap(HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: "HTTP/2",
            headerFields: ["Cache-Control": "public, max-age=60"]
        ))
        HTTPClient.apiURLCache.storeCachedResponse(CachedURLResponse(response: response, data: Data("{}".utf8)), for: request)
        XCTAssertNotNil(HTTPClient.apiURLCache.cachedResponse(for: request), "precondition: an entry is cached")

        let client = LiveBlueskyClient()
        await client.clearAllCaches()

        // `URLCache` applies `removeAllCachedResponses` asynchronously: the entry stays
        // readable for a moment after the call, so poll briefly instead of asserting at once.
        var cleared = false
        for _ in 0 ..< 20 {
            if HTTPClient.apiURLCache.cachedResponse(for: request) == nil {
                cleared = true
                break
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertTrue(cleared, "the pinned API URL cache must be cleared on an account switch")
    }
}
