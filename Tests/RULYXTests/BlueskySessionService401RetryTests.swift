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
        let session = makeSession()
        account = makeAccount(handle: session.handle, did: session.did)
        if let data = try? JSONEncoder().encode(session),
           let encodedSession = String(data: data, encoding: .utf8)
        {
            try? keychain.save(encodedSession, service: "com.ajung.RULYX.session", account: account.id.uuidString)
        }
        try? keychain.save("test-password", service: "com.ajung.RULYX.password", account: account.id.uuidString)
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
                    throw BlueskyAPIError.unauthorized(nil)
                }
                return EmptyTestResponse()
            }
        )

        XCTAssert(result is EmptyTestResponse)
    }

    func test401WithRecoveryFailureThrowsUnauthorized() async {
        requestExecutor.onSend = { _, _, _, _, _, _ in
            throw BlueskyAPIError.unauthorized(nil)
        }
        let notificationExpectation = expectation(forNotification: .authenticationFailed, object: nil) { notification in
            (notification.userInfo?["accountID"] as? String) == self.account.id.uuidString
        }

        do {
            let _: EmptyTestResponse = try await service.performAuthenticatedRequest(
                account: account,
                appPassword: "test-password",
                operation: { _ in
                    throw BlueskyAPIError.unauthorized(nil)
                }
            )
            XCTFail("Expected unauthorized error")
        } catch BlueskyAPIError.unauthorized(nil) {
            // expected
        } catch {
            XCTFail("Expected unauthorized, got \(error)")
        }
        await fulfillment(of: [notificationExpectation], timeout: 1)
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

    func testRevokedTokenRequiresExplicitReauthentication() async {
        requestExecutor.onSend = { path, _, _, _, _, _ in
            if path == "com.atproto.server.refreshSession" {
                throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Refresh must not run for a revoked token"])
            }
            throw BlueskyAPIError.unauthorized("Token has been revoked")
        }
        let notificationExpectation = expectation(forNotification: .authenticationFailed, object: nil) { notification in
            notification.userInfo?["message"] as? String == "Token has been revoked"
        }

        do {
            let _: EmptyTestResponse = try await service.performAuthenticatedRequest(
                account: account,
                appPassword: "test-password",
                operation: { _ in
                    throw BlueskyAPIError.unauthorized("Token has been revoked")
                }
            )
            XCTFail("Expected revoked token error")
        } catch let BlueskyAPIError.unauthorized(message) {
            XCTAssertEqual(message, "Token has been revoked")
        } catch {
            XCTFail("Expected revoked token error, got \(error)")
        }

        await fulfillment(of: [notificationExpectation], timeout: 1)
    }

    func testExpiredServerMessageRequiresExplicitReauthentication() async {
        let notificationExpectation = expectation(forNotification: .authenticationFailed, object: nil) { notification in
            notification.userInfo?["message"] as? String == "Token has expired"
        }

        do {
            let _: EmptyTestResponse = try await service.performAuthenticatedRequest(
                account: account,
                appPassword: "test-password",
                operation: { _ in
                    throw BlueskyAPIError.server("Token has expired")
                }
            )
            XCTFail("Expected expired token error")
        } catch let BlueskyAPIError.server(message) {
            XCTAssertEqual(message, "Token has expired")
        } catch {
            XCTFail("Expected expired token error, got \(error)")
        }

        await fulfillment(of: [notificationExpectation], timeout: 1)
    }
}

private struct EmptyTestResponse: Decodable {}

private extension Data {
    var utf8String: String {
        String(data: self, encoding: .utf8)!
    }
}
