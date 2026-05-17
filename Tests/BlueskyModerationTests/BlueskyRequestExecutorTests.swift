@testable import BlueskyModeration
import XCTest

final class BlueskyRequestExecutorTests: XCTestCase {
    private var executor: BlueskyRequestExecutor!
    private var session: URLSession!

    override func setUp() {
        super.setUp()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        session = URLSession(configuration: config)
        executor = BlueskyRequestExecutor(baseURL: URL(string: "https://test.bsky.social")!, session: session)
    }

    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        session = nil
        executor = nil
        super.tearDown()
    }

    func testSuccessfulResponseDecoding() async throws {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            let data = """
            {"did": "did:plc:test", "handle": "test.bsky.social"}
            """.data(using: .utf8)!
            return (response, data)
        }

        struct TestResponse: Decodable {
            let did: String
            let handle: String
        }

        let result: TestResponse = try await executor.send(
            path: "app.bsky.actor.getProfile",
            method: "GET",
            queryItems: [URLQueryItem(name: "actor", value: "test")],
            accessToken: nil,
            hostURL: nil
        )

        XCTAssertEqual(result.did, "did:plc:test")
        XCTAssertEqual(result.handle, "test.bsky.social")
    }

    func testUnauthorizedThrowsError() async {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 401,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data())
        }

        do {
            let _: EmptyTestResponse = try await executor.send(
                path: "app.bsky.actor.getProfile",
                method: "GET",
                queryItems: [],
                accessToken: "bad-token",
                hostURL: nil
            )
            XCTFail("Expected error")
        } catch let error as BlueskyAPIError {
            if case .unauthorized = error {
                // expected
            } else {
                XCTFail("Expected unauthorized, got \(error)")
            }
        } catch {
            XCTFail("Expected BlueskyAPIError, got \(error)")
        }
    }

    func testServerErrorWithPayload() async {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 429,
                httpVersion: nil,
                headerFields: nil
            )!
            let data = """
            {"error": "RateLimitExceeded", "message": "Rate limit exceeded"}
            """.data(using: .utf8)!
            return (response, data)
        }

        do {
            let _: EmptyTestResponse = try await executor.send(
                path: "app.bsky.graph.getList",
                method: "GET",
                queryItems: [],
                accessToken: nil,
                hostURL: nil
            )
            XCTFail("Expected error")
        } catch let error as BlueskyAPIError {
            if case let .server(message) = error {
                XCTAssertEqual(message, "Rate limit exceeded")
            } else {
                XCTFail("Expected server error, got \(error)")
            }
        } catch {
            XCTFail("Expected BlueskyAPIError, got \(error)")
        }
    }

    func testDecodingFailureThrowsInvalidResponse() async {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            let data = "not json".data(using: .utf8)!
            return (response, data)
        }

        struct TestResponse: Decodable {
            let did: String
        }

        do {
            let _: TestResponse = try await executor.send(
                path: "test",
                method: "GET",
                queryItems: [],
                accessToken: nil,
                hostURL: nil
            )
            XCTFail("Expected error")
        } catch let error as BlueskyAPIError {
            if case .invalidResponse = error {
                // expected
            } else {
                XCTFail("Expected invalidResponse, got \(error)")
            }
        } catch {
            XCTFail("Expected BlueskyAPIError, got \(error)")
        }
    }

    func testRequestIncludesAuthorizationHeader() async throws {
        var capturedRequest: URLRequest?
        MockURLProtocol.requestHandler = { request in
            capturedRequest = request
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, "{}".data(using: .utf8)!)
        }

        let _: EmptyTestResponse = try await executor.send(
            path: "test",
            method: "GET",
            queryItems: [],
            accessToken: "test-token",
            hostURL: nil
        )

        XCTAssertEqual(capturedRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
    }

    func testRequestBodyEncoding() async throws {
        var capturedRequest: URLRequest?
        MockURLProtocol.requestHandler = { request in
            capturedRequest = request
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, "{}".data(using: .utf8)!)
        }

        struct TestBody: Codable {
            let name: String
        }

        let _: EmptyTestResponse = try await executor.send(
            path: "test",
            method: "POST",
            queryItems: [],
            body: TestBody(name: "hello"),
            accessToken: nil,
            hostURL: nil
        )

        XCTAssertEqual(capturedRequest?.value(forHTTPHeaderField: "Content-Type"), "application/json")
        if let bodyData = capturedRequest?.httpBody {
            let decoded = try JSONDecoder().decode(TestBody.self, from: bodyData)
            XCTAssertEqual(decoded.name, "hello")
        } else if let stream = capturedRequest?.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var data = Data()
            while stream.hasBytesAvailable {
                var buffer = [UInt8](repeating: 0, count: 1024)
                let read = stream.read(&buffer, maxLength: buffer.count)
                if read > 0 {
                    data.append(buffer, count: read)
                } else {
                    break
                }
            }
            let decoded = try JSONDecoder().decode(TestBody.self, from: data)
            XCTAssertEqual(decoded.name, "hello")
        } else {
            XCTFail("Expected request body")
        }
    }
}

private struct EmptyTestResponse: Decodable {}
