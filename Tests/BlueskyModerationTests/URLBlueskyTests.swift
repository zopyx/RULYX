@testable import BlueskyModeration
import XCTest

final class URLBlueskyTests: XCTestCase {
    func testBskySocialURL() {
        XCTAssertEqual(URL.bskySocial.absoluteString, "https://bsky.social")
    }
}
