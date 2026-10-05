@testable import RULYX
import XCTest

/// Cache scope isolation: `clear(for:)` must drop exactly one account's entries, while the
/// `.shared` scope (viewer-independent public data) survives an account-scoped clear.
///
/// The cache file name carries the scope prefix for that purpose; a key hashed from the
/// scope and URL together cannot be matched back to an account, which silently turned
/// per-account invalidation (account removal, test isolation) into a no-op.
final class BlueskyAPICacheAccountScopeTests: XCTestCase {
    func testClearForAccountLeavesOtherAccountsAlone() async {
        let cache = BlueskyAPICache.shared
        let mine = "did:plc:account-scope-a"
        let other = "did:plc:account-scope-b"
        let url = "constellation/blocked-by/\(mine)"

        await cache.write(scope: .account(mine), url: url, data: Data("mine".utf8))
        await cache.write(scope: .account(other), url: url, data: Data("other".utf8))

        await cache.clear(for: mine)

        let mineAfter = await cache.read(scope: .account(mine), url: url, maxAge: 0)
        let otherAfter = await cache.read(scope: .account(other), url: url, maxAge: 0)
        XCTAssertNil(mineAfter, "entries of the cleared account must be gone")
        XCTAssertNotNil(otherAfter, "entries of other accounts must survive")

        await cache.clear(for: other)
    }

    func testClearForAccountKeepsSharedEntries() async {
        let cache = BlueskyAPICache.shared
        let account = "did:plc:account-scope-shared"
        let sharedURL = "public.api.bsky.app/getProfiles?actor=did:plc:subject"

        await cache.write(scope: .shared, url: sharedURL, data: Data("public".utf8))
        await cache.write(scope: .account(account), url: sharedURL, data: Data("private".utf8))

        await cache.clear(for: account)

        let sharedAfter = await cache.read(scope: .shared, url: sharedURL, maxAge: 0)
        let accountAfter = await cache.read(scope: .account(account), url: sharedURL, maxAge: 0)
        XCTAssertNotNil(sharedAfter, "viewer-independent entries must survive an account clear")
        XCTAssertNil(accountAfter, "account-scoped entries must be dropped")

        await cache.remove(scope: .shared, url: sharedURL)
    }

    func testSameURLCachedPerAccountIsIsolated() async {
        let cache = BlueskyAPICache.shared
        let a = "did:plc:isolation-a"
        let b = "did:plc:isolation-b"
        let url = "app.bsky.actor.getProfile?actor=did:plc:target"

        await cache.write(scope: .account(a), url: url, data: Data("a".utf8))
        await cache.write(scope: .account(b), url: url, data: Data("b".utf8))

        let forA = await cache.read(scope: .account(a), url: url, maxAge: 3600)
        let forB = await cache.read(scope: .account(b), url: url, maxAge: 3600)
        XCTAssertEqual(forA?.data, Data("a".utf8), "each account must see its own payload")
        XCTAssertEqual(forB?.data, Data("b".utf8), "each account must see its own payload")

        await cache.clear(for: a)
        await cache.clear(for: b)
    }
}
