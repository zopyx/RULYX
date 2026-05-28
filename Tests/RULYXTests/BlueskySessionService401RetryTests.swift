@testable import RULYX
import XCTest

@MainActor
final class BlueskySessionService401RetryTests: XCTestCase {
    private var service: BlueskySessionService!
    private var requestExecutor: MockRequestExecutor!
    private var keychain: MockKeychain!
    private var account: AppAccount!

    override func setUp() {
        super.setUp()
        requestExecutor = MockRequestExecutor()
        keychain = MockKeychain()
        service = BlueskySessionService(requestExecutor: requestExecutor, keychain: keychain)
        account = makeAccount()
        try? keychain.save(try! JSONEncoder().encode(makeSession()).utf8String, service: "com.ajung.RULYX.session", account: account.id.uuidString)
    }

    override func tearDown() {
        service.clearSessionCache()
        requestExecutor = nil
        keychain = nil
        service = nil
        account = nil
        super.tearDown()
    }

    func test401TriggersRecoveryThenRetriesOperation() async throws {
        let session = makeSession()
        var operationAttempt = 0

        requestExecutor.onSend = { path, _, _, _, _, _ in
            if path == "com.atproto.server.refreshSession" {
                return try JSONDecoder().decode(CreateSessionResponse.self, from: """
                {"did": "\(session.did)", "handle": "\(session.handle)", "accessJwt": "refreshed-access-jwt", "refreshJwt": "refreshed-refresh-jwt"}
                """.data(using: .utf8)!)
            }
            throw BlueskyAPIError.invalidResponse
        }

        let result: EmptyTestResponse = try await service.performAuthenticatedRequest(
            account: account,
            appPassword: "test-password",
            operation: { _ in
                operationAttempt += 1
                if operationAttempt == 1 {
                    throw BlueskyAPIError.unauthorized
                }
                return EmptyTestResponse()
            }
        )

        XCTAssert(result is EmptyTestResponse)
    }

    func test401WithRecoveryFailureThrowsUnauthorized() async {
        requestExecutor.onSend = { _, _, _, _, _, _ in
            throw BlueskyAPIError.unauthorized
        }

        do {
            let _: EmptyTestResponse = try await service.performAuthenticatedRequest(
                account: account,
                appPassword: "test-password",
                operation: { _ in
                    throw BlueskyAPIError.unauthorized
                }
            )
            XCTFail("Expected unauthorized error")
        } catch BlueskyAPIError.unauthorized {
            // expected
        } catch {
            XCTFail("Expected unauthorized, got \(error)")
        }
    }

    func testNoRetryOnNon401Error() async {
        do {
            let _: EmptyTestResponse = try await service.performAuthenticatedRequest(
                account: account,
                appPassword: "test-password",
                operation: { _ in
                    throw BlueskyAPIError.server("Some server error")
                }
            )
            XCTFail("Expected server error")
        } catch BlueskyAPIError.server {
            // expected
        } catch {
            XCTFail("Expected server error, got \(error)")
        }
    }
}

private struct EmptyTestResponse: Decodable {}

private extension Data {
    var utf8String: String {
        String(data: self, encoding: .utf8)!
    }
}
