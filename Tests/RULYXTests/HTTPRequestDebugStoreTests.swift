@testable import RULYX
import XCTest

final class HTTPRequestDebugStoreTests: XCTestCase {
    func testSanitizeJSONRemovesJWT() {
        let json = #"{"accessJwt":"eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.dozjgNryP4J3jVmNHl0w5N_XgL0n3I9PlFUP0THsR8U","other":"value"}"#
        let result = HTTPRequestDebugStore.sanitizeErrorResponseJSON(json)
        XCTAssertNotNil(result)
        XCTAssertFalse(result?.contains("eyJhbGci") ?? true, "JWT should be redacted")
    }

    func testSanitizeJSONRemovesRefreshJWT() {
        let json = #"{"refreshJwt":"eyJhbGci.token.signature","ok":"yes"}"#
        let result = HTTPRequestDebugStore.sanitizeErrorResponseJSON(json)
        XCTAssertFalse(result?.contains("eyJhbGci") ?? true)
    }

    func testSanitizeJSONRemovesAuthorization() {
        let json = #"{"authorization":"Bearer secret","ok":"yes"}"#
        let result = HTTPRequestDebugStore.sanitizeErrorResponseJSON(json)
        XCTAssertFalse(result?.contains("secret") ?? true)
    }

    func testSanitizeJSONPreservesSafeContent() {
        let json = #"{"error":"InvalidRequest","message":"Bad request"}"#
        let result = HTTPRequestDebugStore.sanitizeErrorResponseJSON(json)
        XCTAssertTrue(result?.contains("InvalidRequest") ?? false)
    }

    func testSanitizeJSONNilInput() {
        XCTAssertNil(HTTPRequestDebugStore.sanitizeErrorResponseJSON(nil))
    }

    func testSanitizeJSONEmptyInput() {
        XCTAssertEqual(HTTPRequestDebugStore.sanitizeErrorResponseJSON(""), "")
    }

    func testSanitizeJSONNoSensitiveData() {
        let json = #"{"count":42}"#
        let result = HTTPRequestDebugStore.sanitizeErrorResponseJSON(json)
        XCTAssertEqual(result, json)
    }

    func testSanitizeJSONMultipleTokens() {
        let json = #"{"accessJwt":"a","refreshJwt":"b","authorization":"Bearer c"}"#
        let result = HTTPRequestDebugStore.sanitizeErrorResponseJSON(json)
        let redacted = result?.components(separatedBy: "[REDACTED]").count ?? 0
        XCTAssertEqual(redacted, 4, "3 redactions + trailing")
    }
}
