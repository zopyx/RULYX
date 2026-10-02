@testable import RULYX
import XCTest

/// `BlueskyAPICache.clear(for:)` must drop exactly one account's entries.
///
/// The cache file name carries the account prefix for that purpose; a key hashed from
/// account and URL together cannot be matched back to an account, which silently turned
/// per-account invalidation (account removal, test isolation) into a no-op.
final class BlueskyAPICacheAccountScopeTests: XCTestCase {
    func testClearForAccountLeavesOtherAccountsAlone() async {
        let cache = BlueskyAPICache.shared
        let mine = "did:plc:account-scope-a"
        let other = "did:plc:account-scope-b"
        let url = "constellation/blocked-by/\(mine)"

        await cache.write(accountDID: mine, url: url, data: Data("mine".utf8))
        await cache.write(accountDID: other, url: url, data: Data("other".utf8))

        await cache.clear(for: mine)

        let mineAfter = await cache.read(accountDID: mine, url: url, maxAge: 0)
        let otherAfter = await cache.read(accountDID: other, url: url, maxAge: 0)
        XCTAssertNil(mineAfter, "entries of the cleared account must be gone")
        XCTAssertNotNil(otherAfter, "entries of other accounts must survive")

        await cache.clear(for: other)
    }
}
