@testable import RULYX
import XCTest

@MainActor
final class MediaDownloadProgressStateTests: XCTestCase {
    func testAggregatesMonotonicItemProgress() {
        let state = MediaDownloadProgressState()
        state.start(total: 2)

        state.update(MediaAssetProgress(index: 0, filenameStem: "first", fractionCompleted: 0.5))
        XCTAssertEqual(state.fractionCompleted, 0.25, accuracy: 0.001)
        XCTAssertEqual(state.detail, "first")

        state.update(MediaAssetProgress(index: 0, filenameStem: "first", fractionCompleted: 0.25))
        XCTAssertEqual(state.fractionCompleted, 0.25, accuracy: 0.001)

        state.complete(index: 0, completed: 1, detail: "first.jpg")
        XCTAssertEqual(state.completedItems, 1)
        XCTAssertEqual(state.fractionCompleted, 0.5, accuracy: 0.001)

        state.update(MediaAssetProgress(index: 1, filenameStem: "second", fractionCompleted: 0.5))
        XCTAssertEqual(state.fractionCompleted, 0.75, accuracy: 0.001)

        state.complete(index: 1, completed: 2, detail: "second.mp4")
        XCTAssertEqual(state.completedItems, 2)
        XCTAssertEqual(state.fractionCompleted, 1, accuracy: 0.001)
    }

    func testStartResetsPreviousDownload() {
        let state = MediaDownloadProgressState()
        state.start(total: 1)
        state.complete(index: 0, completed: 1, detail: "done.jpg")

        state.start(total: 12)

        XCTAssertEqual(state.completedItems, 0)
        XCTAssertEqual(state.totalItems, 12)
        XCTAssertEqual(state.fractionCompleted, 0)
        XCTAssertNil(state.detail)
    }
}
