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

    /// Regression: the probe must hit a real API route, not the site root. During the
    /// September 2026 ClearSky outage the root answered `200` while every `/api/...`
    /// route returned `502`, so a root probe reported "available".
    func testPingProbesTheApiRouteNotTheSiteRoot() async {
        var probedPath = ""
        MockURLProtocol.requestHandler = { request in
            probedPath = request.url?.path ?? ""
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data())
        }

        await ClearskyHeartbeatService.shared.ping()

        XCTAssertTrue(probedPath.hasPrefix("/api/"), "heartbeat must probe the API route, got '\(probedPath)'")
    }

    /// `404` (probe account has no blocklist) is a healthy answer — only `5xx` and
    /// transport failures mean ClearSky is down.
    func testPingTreatsNotFoundAsAvailable() async {
        MockURLProtocol.requestHandler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!, Data())
        }

        await ClearskyHeartbeatService.shared.ping()
        XCTAssertTrue(ClearskyHeartbeatService.shared.isClearskyAvailable)
    }
}
