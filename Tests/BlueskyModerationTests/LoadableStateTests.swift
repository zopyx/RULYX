@testable import BlueskyModeration
import XCTest

final class LoadableStateTests: XCTestCase {
    func testIdleInitialState() {
        let state = LoadableState<Int>.idle
        XCTAssertNil(state.value)
        XCTAssertFalse(state.isLoaded)
        XCTAssertFalse(state.isLoading)
        XCTAssertNil(state.error)
    }

    func testLoadingState() {
        var state = LoadableState<Int>.idle
        state.startLoading()
        XCTAssertNil(state.value)
        XCTAssertFalse(state.isLoaded)
        XCTAssertTrue(state.isLoading)
        XCTAssertNil(state.error)
    }

    func testLoadedState() {
        var state = LoadableState<String>.idle
        state.succeed(with: "hello")
        XCTAssertEqual(state.value, "hello")
        XCTAssertTrue(state.isLoaded)
        XCTAssertFalse(state.isLoading)
        XCTAssertNil(state.error)
    }

    func testFailedState() {
        var state = LoadableState<Int>.idle
        let error = AppError(category: .network, message: "fail")
        state.fail(with: error)
        XCTAssertNil(state.value)
        XCTAssertFalse(state.isLoaded)
        XCTAssertFalse(state.isLoading)
        XCTAssertEqual(state.error, error)
    }

    func testTransitionFromLoadedToLoading() {
        var state = LoadableState<Int>.idle
        state.succeed(with: 42)
        state.startLoading()
        XCTAssertTrue(state.isLoading)
        XCTAssertNil(state.value)
    }

    func testTransitionFromFailedToLoaded() {
        var state = LoadableState<String>.idle
        state.fail(with: AppError(category: .server, message: "err"))
        state.succeed(with: "recovered")
        XCTAssertEqual(state.value, "recovered")
        XCTAssertNil(state.error)
    }

    func testSendableConformance() {
        let state = LoadableState<Int>.loaded(42)
        let copy = state
        XCTAssertEqual(copy.value, 42)
    }

    func testErrorAccessorOnNonFailedState() {
        let state = LoadableState<Int>.loading
        XCTAssertNil(state.error)
    }
}
