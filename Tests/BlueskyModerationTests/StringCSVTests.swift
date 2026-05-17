@testable import BlueskyModeration
import XCTest

final class StringCSVTests: XCTestCase {
    func testCSVFieldWrapsInQuotes() {
        XCTAssertEqual("hello".csvField, "\"hello\"")
    }

    func testCSVFieldEscapesEmbeddedQuotes() {
        XCTAssertEqual("say \"hello\"".csvField, "\"say \"\"hello\"\"\"")
    }

    func testCSVFieldWithCommas() {
        XCTAssertEqual("a,b".csvField, "\"a,b\"")
    }

    func testCSVFieldEmpty() {
        XCTAssertEqual("".csvField, "\"\"")
    }
}
