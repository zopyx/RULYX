@testable import BlueskyModeration
import XCTest

final class AppErrorTests: XCTestCase {
    func testAppErrorFromAppErrorReturnsSame() {
        let original = AppError(category: .network, message: "Network error")
        let result = AppError.from(original)
        XCTAssertEqual(result.category, .network)
        XCTAssertEqual(result.message, "Network error")
    }

    func testAppErrorFromBlueskyAPIInvalidURL() {
        let error = BlueskyAPIError.invalidURL
        let result = AppError.from(error)
        XCTAssertEqual(result.category, .validation)
    }

    func testAppErrorFromBlueskyAPIInvalidResponse() {
        let error = BlueskyAPIError.invalidResponse
        let result = AppError.from(error)
        XCTAssertEqual(result.category, .decoding)
    }

    func testAppErrorFromBlueskyAPIUnauthorized() {
        let error = BlueskyAPIError.unauthorized
        let result = AppError.from(error)
        XCTAssertEqual(result.category, .authentication)
    }

    func testAppErrorFromBlueskyAPIMissingCredentials() {
        let error = BlueskyAPIError.missingCredentials
        let result = AppError.from(error)
        XCTAssertEqual(result.category, .authentication)
    }

    func testAppErrorFromBlueskyAPIServer() {
        let error = BlueskyAPIError.server("Rate limited")
        let result = AppError.from(error)
        XCTAssertEqual(result.category, .server)
        XCTAssertTrue(result.message.contains("Rate limited"))
    }

    func testAppErrorFromDecodingError() {
        let error = DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Bad data"))
        let result = AppError.from(error)
        XCTAssertEqual(result.category, .decoding)
    }

    func testAppErrorFromURLErrorCancelled() {
        let error = URLError(.cancelled)
        let result = AppError.from(error)
        XCTAssertEqual(result.category, .cancellation)
    }

    func testAppErrorFromURLErrorNotConnected() {
        let error = URLError(.notConnectedToInternet)
        let result = AppError.from(error)
        XCTAssertEqual(result.category, .network)
    }

    func testAppErrorFromURLErrorTimeout() {
        let error = URLError(.timedOut)
        let result = AppError.from(error)
        XCTAssertEqual(result.category, .network)
    }

    func testAppErrorFromURLErrorCannotFindHost() {
        let error = URLError(.cannotFindHost)
        let result = AppError.from(error)
        XCTAssertEqual(result.category, .network)
    }

    func testAppErrorFromUnknownError() {
        let error = NSError(domain: "TestDomain", code: 999, userInfo: [NSLocalizedDescriptionKey: "Something weird"])
        let result = AppError.from(error)
        XCTAssertEqual(result.category, .unknown)
    }

    func testAppErrorFromCancellationError() {
        let error = CancellationError()
        let result = AppError.from(error)
        XCTAssertEqual(result.category, .cancellation)
    }

    func testIsCancellationWithCancellationError() {
        XCTAssertTrue(AppError.isCancellation(CancellationError()))
    }

    func testIsCancellationWithURLErrorCancelled() {
        XCTAssertTrue(AppError.isCancellation(URLError(.cancelled)))
    }

    func testIsCancellationWithNonCancellation() {
        XCTAssertFalse(AppError.isCancellation(BlueskyAPIError.unauthorized))
    }

    func testUserMessageDelegates() {
        let error = BlueskyAPIError.unauthorized
        let message = AppError.userMessage(from: error)
        XCTAssertEqual(message, AppError.from(error).message)
    }

    func testAppErrorDescription() {
        let error = AppError(category: .network, message: "Connection failed")
        XCTAssertEqual(error.errorDescription, "Connection failed")
    }

    func testAllCategoryValues() {
        let categories: [AppErrorCategory] = [.authentication, .network, .decoding, .validation, .server, .cancellation, .unknown]
        for cat in categories {
            switch cat {
            case .authentication, .network, .decoding, .validation, .server, .cancellation, .unknown:
                break
            }
        }
    }
}
