@testable import RULYX
import XCTest

final class ChaosIntegrationTests: XCTestCase {
    private var session: URLSession!

    override func setUp() {
        super.setUp()
        MockURLProtocol.config = .normal
        MockURLProtocol.mockResponses = [:]
        MockURLProtocol.requestHandler = nil
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        session = URLSession(configuration: config)
        URLProtocol.registerClass(MockURLProtocol.self)
    }

    override func tearDown() {
        MockURLProtocol.config = .normal
        MockURLProtocol.mockResponses = [:]
        MockURLProtocol.requestHandler = nil
        session = nil
        URLProtocol.unregisterClass(MockURLProtocol.self)
        super.tearDown()
    }

    // MARK: - Latency Injection

    func testLatencyInjectionDelaysResponse() async {
        let latency: UInt64 = 100_000_000
        MockURLProtocol.config = .init(injectedLatency: latency, failureProbability: 0, statusCodeOverride: nil)
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, "{}".data(using: .utf8)!)
        }

        let start = Date()
        let result: EmptyChaosResponse? = try? await makeRequest()
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertGreaterThanOrEqual(elapsed, 0.09)
        XCTAssertNotNil(result)
    }

    // MARK: - Failure Injection

    func testFailureProbabilityTriggersNetworkError() async {
        MockURLProtocol.config = .init(injectedLatency: 0, failureProbability: 1.0, statusCodeOverride: nil)
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        do {
            let _: EmptyChaosResponse = try await makeRequest()
            XCTFail("Expected network error from chaos injection")
        } catch let error as URLError {
            XCTAssertEqual(error.code, .networkConnectionLost)
        } catch {
            XCTFail("Expected URLError, got \(error)")
        }
    }

    func testFailureProbabilityDoesNotAlwaysFail() async {
        MockURLProtocol.config = .init(injectedLatency: 0, failureProbability: 0, statusCodeOverride: nil)
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        let _: EmptyChaosResponse? = try? await makeRequest()
    }

    // MARK: - Status Code Override

    func testStatusCodeOverrideReplacesResponseCode() async {
        MockURLProtocol.config = .init(injectedLatency: 0, failureProbability: 0, statusCodeOverride: 500)
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, "{}".data(using: .utf8)!)
        }

        let result = try? await makeRequest()
        XCTAssertNotNil(result)
        // Verify the HTTPClient received the overridden status code
        let entry = await MainActor.run { HTTPRequestDebugStore.shared.entries.first }
        XCTAssertEqual(entry?.statusCode, 500)
        XCTAssertEqual(entry?.state, .failed)
    }

    // MARK: - Helpers

    private func makeRequest() async throws -> EmptyChaosResponse {
        let httpClient = HTTPClient(session: session)
        guard let url = URL(string: "https://test.bsky.social/xrpc/test") else {
            throw BlueskyAPIError.invalidURL
        }
        let request = URLRequest(url: url)
        let (data, _) = try await httpClient.data(for: request, source: "Chaos Test")
        return try JSONDecoder().decode(EmptyChaosResponse.self, from: data)
    }
}

private struct EmptyChaosResponse: Decodable {}
