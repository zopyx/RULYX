import Foundation

@MainActor
final class MockURLProtocol: URLProtocol {
    override nonisolated static func canInit(with _: URLRequest) -> Bool {
        true
    }

    override nonisolated static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    /// Backward-compatible request handler
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    /// Chaos injection configuration
    struct ChaosConfig {
        let injectedLatency: UInt64
        let failureProbability: Double
        let statusCodeOverride: Int?

        static let normal = ChaosConfig(injectedLatency: 0, failureProbability: 0, statusCodeOverride: nil)
    }

    nonisolated(unsafe) static var config: ChaosConfig = .normal
    nonisolated(unsafe) static var mockResponses: [String: (Data, HTTPURLResponse)] = [:]

    override func startLoading() {
        let delay = Self.config.injectedLatency
        if delay > 0 {
            Thread.sleep(forTimeInterval: Double(delay) / 1_000_000_000)
        }

        if Double.random(in: 0 ... 1) < Self.config.failureProbability {
            client?.urlProtocol(self, didFailWithError: URLError(.networkConnectionLost))
            client?.urlProtocolDidFinishLoading(self)
            return
        }

        if let handler = Self.requestHandler {
            do {
                let (response, data) = try handler(request)
                let finalResponse: HTTPURLResponse = if let statusCodeOverride = Self.config.statusCodeOverride {
                    HTTPURLResponse(url: response.url ?? request.url!, statusCode: statusCodeOverride, httpVersion: "HTTP/1.1", headerFields: [:])!
                } else {
                    response
                }
                client?.urlProtocol(self, didReceive: finalResponse, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: data)
            } catch {
                client?.urlProtocol(self, didFailWithError: error)
            }
            client?.urlProtocolDidFinishLoading(self)
            return
        }

        let url = request.url?.absoluteString ?? ""
        if let (data, response) = Self.mockResponses[url] {
            let finalResponse: HTTPURLResponse = if let statusCodeOverride = Self.config.statusCodeOverride {
                HTTPURLResponse(url: response.url ?? request.url!, statusCode: statusCodeOverride, httpVersion: "HTTP/1.1", headerFields: [:])!
            } else {
                response
            }
            client?.urlProtocol(self, didReceive: finalResponse, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
        }

        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
