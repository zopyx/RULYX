@testable import RULYX
import XCTest

@MainActor
final class PostEmbedViewTests: XCTestCase {
    func testSingleImageHeightUsesIntegralFallbackWhileImageIsLoading() {
        XCTAssertEqual(
            PostEmbedView.integralSingleImageHeight(width: 370.333, aspectRatio: nil),
            200
        )
    }

    func testSingleImageHeightRoundsFractionalAspectFitHeight() {
        XCTAssertEqual(
            PostEmbedView.integralSingleImageHeight(width: 370.333, aspectRatio: 4.0 / 3.0),
            278
        )
    }

    func testSingleImageHeightUsesFallbackForInvalidAspectRatio() {
        XCTAssertEqual(
            PostEmbedView.integralSingleImageHeight(width: 370.333, aspectRatio: 0),
            200
        )
    }
}
