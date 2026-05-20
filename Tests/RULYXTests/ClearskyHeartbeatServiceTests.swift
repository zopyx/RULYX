@testable import RULYX
import XCTest

@MainActor
final class ClearskyHeartbeatServiceTests: XCTestCase {
    override func setUp() {
        super.setUp()
        MockURLProtocol.requestHandler = nil
        URLProtocol.registerClass(MockURLProtocol.self)
    }

    override func tearDown() {
        ClearskyHeartbeatService.shared.stop()
        MockURLProtocol.requestHandler = nil
        URLProtocol.unregisterClass(MockURLProtocol.self)
        super.tearDown()
    }

    func testPingSetsAvailableOn2xx() async {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        await ClearskyHeartbeatService.shared.ping()
        XCTAssertTrue(ClearskyHeartbeatService.shared.isClearskyAvailable)
    }

    func testPingSetsUnavailableOn5xx() async {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 503, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        await ClearskyHeartbeatService.shared.ping()
        XCTAssertFalse(ClearskyHeartbeatService.shared.isClearskyAvailable)
    }

    func testPingSetsUnavailableOnNetworkError() async {
        MockURLProtocol.requestHandler = { _ in
            throw URLError(.notConnectedToInternet)
        }

        await ClearskyHeartbeatService.shared.ping()
        XCTAssertFalse(ClearskyHeartbeatService.shared.isClearskyAvailable)
    }

    func testPingSetsUnavailableOnTimeout() async {
        MockURLProtocol.requestHandler = { _ in
            throw URLError(.timedOut)
        }

        await ClearskyHeartbeatService.shared.ping()
        XCTAssertFalse(ClearskyHeartbeatService.shared.isClearskyAvailable)
    }
}
