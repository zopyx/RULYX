@testable import RULYX
import XCTest

/// Integration tests that exercise LiveBlueskyClient end-to-end using
/// MockURLProtocol to simulate the full HTTP layer. These tests verify
/// that the client correctly orchestrates authentication, API calls,
/// response parsing, and request body construction for key flows.
@MainActor
final class ServiceIntegrationTests: XCTestCase {
    private nonisolated(unsafe) var client: LiveBlueskyClient!
    private nonisolated(unsafe) var mockSession: URLSession!
    private nonisolated(unsafe) var keychain: MockKeychain!

    override func setUp() async throws {
        try await super.setUp()
        let setup = await MainActor.run { () -> (URLSession, MockKeychain, LiveBlueskyClient) in
            let config = URLSessionConfiguration.ephemeral
            config.protocolClasses = [MockURLProtocol.self]
            let mockSession = URLSession(configuration: config)
            let keychain = MockKeychain()
            let httpClient = HTTPClient(session: mockSession)
            let client = LiveBlueskyClient(
                httpClient: httpClient,
                keychain: keychain
            )
            return (mockSession, keychain, client)
        }
        mockSession = setup.0
        keychain = setup.1
        client = setup.2
    }

    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        MockURLProtocol.mockResponses = [:]
        MockURLProtocol.config = .normal
        client = nil
        mockSession = nil
        keychain = nil
        super.tearDown()
    }

    // MARK: - Test 1: Authenticate + Fetch Profile

    func testAuthenticateAndFetchProfile() async throws {
        let handle = "test-auth.bsky.social"
        let did = "did:plc:test-auth"
        let appPassword = "test-password"
        let account = AppAccount(handle: handle, did: did)

        // Mock: createSession (POST)
        // Mock: getProfile (GET)
        MockURLProtocol.requestHandler = { request in
            let url = request.url!
            let path = url.path
            let method = request.httpMethod ?? "GET"

            // createSession endpoint
            if path == "/xrpc/com.atproto.server.createSession", method == "POST" {
                let json = """
                {
                    "did": "\(did)",
                    "handle": "\(handle)",
                    "accessJwt": "test-access-jwt",
                    "refreshJwt": "test-refresh-jwt"
                }
                """.data(using: .utf8)!
                let response = HTTPURLResponse(
                    url: url, statusCode: 200, httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!
                return (response, json)
            }

            // getProfile endpoint
            if path == "/xrpc/app.bsky.actor.getProfile", method == "GET" {
                XCTAssertTrue(
                    url.absoluteString.contains("actor=did:plc:target-profile"),
                    "getProfile should request the target DID"
                )
                // Verify Authorization header is present
                XCTAssertNotNil(
                    request.value(forHTTPHeaderField: "Authorization"),
                    "getProfile request should include Bearer token"
                )

                let json = """
                {
                    "did": "did:plc:target-profile",
                    "handle": "target.bsky.social",
                    "displayName": "Target User",
                    "description": "A test profile for integration testing",
                    "followersCount": 128,
                    "followsCount": 256,
                    "postsCount": 42,
                    "createdAt": "2024-06-15T10:30:00.000Z"
                }
                """.data(using: .utf8)!
                let response = HTTPURLResponse(
                    url: url, statusCode: 200, httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!
                return (response, json)
            }

            XCTFail("Unexpected request: \(method) \(url.absoluteString)")
            throw BlueskyAPIError.invalidURL
        }

        // Phase 1: Authenticate
        let session = try await client.authenticate(
            handle: handle,
            appPassword: appPassword
        )
        XCTAssertEqual(session.did, did)
        XCTAssertEqual(session.handle, handle)
        XCTAssertEqual(session.accessJWT, "test-access-jwt")
        XCTAssertEqual(session.refreshJWT, "test-refresh-jwt")

        // Phase 2: Fetch profile (triggers re-auth + getProfile)
        let profile = try await client.fetchProfile(
            did: "did:plc:target-profile",
            account: account,
            appPassword: appPassword
        )
        XCTAssertEqual(profile.did, "did:plc:target-profile")
        XCTAssertEqual(profile.handle, "target.bsky.social")
        XCTAssertEqual(profile.displayName, "Target User")
        XCTAssertEqual(profile.followersCount, 128)
        XCTAssertEqual(profile.followsCount, 256)
        XCTAssertEqual(profile.postsCount, 42)
        XCTAssertEqual(profile.description, "A test profile for integration testing")
    }

    // MARK: - Test 2: Fetch Lists

    func testFetchListsFlow() async throws {
        let handle = "test-lists.bsky.social"
        let did = "did:plc:test-lists"
        let appPassword = "test-password"
        let account = AppAccount(handle: handle, did: did)

        MockURLProtocol.requestHandler = { request in
            let url = request.url!
            let path = url.path
            let method = request.httpMethod ?? "GET"

            // createSession endpoint (triggered by performAuthenticatedRequest)
            if path == "/xrpc/com.atproto.server.createSession", method == "POST" {
                let json = """
                {
                    "did": "\(did)",
                    "handle": "\(handle)",
                    "accessJwt": "test-access-jwt",
                    "refreshJwt": "test-refresh-jwt"
                }
                """.data(using: .utf8)!
                let response = HTTPURLResponse(
                    url: url, statusCode: 200, httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!
                return (response, json)
            }

            // getLists endpoint
            if path == "/xrpc/app.bsky.graph.getLists", method == "GET" {
                let query = url.query ?? ""
                XCTAssertTrue(query.contains("actor=\(did)"), "getLists should filter by account DID")
                XCTAssertTrue(query.contains("limit=100"), "getLists should use limit=100")
                XCTAssertNotNil(
                    request.value(forHTTPHeaderField: "Authorization"),
                    "getLists request should include Bearer token"
                )

                let json = """
                {
                    "lists": [
                        {
                            "uri": "at://\(did)/app.bsky.graph.list/mod-1",
                            "cid": "cid-mod-1",
                            "name": "Spam Watch",
                            "description": "Block spammers and trolls",
                            "purpose": "app.bsky.graph.defs#modlist",
                            "listItemCount": 1500,
                            "indexedAt": "2025-01-15T08:00:00.000Z"
                        },
                        {
                            "uri": "at://\(did)/app.bsky.graph.list/cur-1",
                            "cid": "cid-cur-1",
                            "name": "Tech News",
                            "description": "Curated tech accounts",
                            "purpose": "app.bsky.graph.defs#curatelist",
                            "listItemCount": 300,
                            "avatar": "https://cdn.bsky.app/img/avatar/plain/did:plc:test-lists/abc@jpeg",
                            "indexedAt": "2025-03-20T12:00:00.000Z"
                        }
                    ]
                }
                """.data(using: .utf8)!
                let response = HTTPURLResponse(
                    url: url, statusCode: 200, httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!
                return (response, json)
            }

            XCTFail("Unexpected request: \(method) \(url.absoluteString)")
            throw BlueskyAPIError.invalidURL
        }

        let lists = try await client.fetchLists(
            for: account,
            appPassword: appPassword
        )

        XCTAssertEqual(lists.count, 2, "Should return two lists")

        // First list: moderation list
        let modList = lists[0]
        XCTAssertEqual(modList.name, "Spam Watch")
        XCTAssertEqual(modList.description, "Block spammers and trolls")
        XCTAssertEqual(modList.kind, .moderation)
        XCTAssertEqual(modList.memberCount, 1500)
        XCTAssertEqual(modList.id, "at://\(did)/app.bsky.graph.list/mod-1")

        // Second list: curation list
        let curList = lists[1]
        XCTAssertEqual(curList.name, "Tech News")
        XCTAssertEqual(curList.kind, .regular)
        XCTAssertEqual(curList.memberCount, 300)
        XCTAssertEqual(curList.avatarURL?.absoluteString, "https://cdn.bsky.app/img/avatar/plain/did:plc:test-lists/abc@jpeg")
    }

    // MARK: - Test 3: Block Actor

    func testBlockActorFlow() async throws {
        let handle = "test-blocker.bsky.social"
        let did = "did:plc:test-blocker"
        let appPassword = "test-password"
        let account = AppAccount(handle: handle, did: did)
        let targetDID = "did:plc:block-target"

        var createRecordBody: [String: Any]?

        MockURLProtocol.requestHandler = { request in
            let url = request.url!
            let path = url.path
            let method = request.httpMethod ?? "GET"

            // createSession endpoint (triggered by performAuthenticatedRequest)
            if path == "/xrpc/com.atproto.server.createSession", method == "POST" {
                let json = """
                {
                    "did": "\(did)",
                    "handle": "\(handle)",
                    "accessJwt": "test-access-jwt",
                    "refreshJwt": "test-refresh-jwt"
                }
                """.data(using: .utf8)!
                let response = HTTPURLResponse(
                    url: url, statusCode: 200, httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!
                return (response, json)
            }

            // createRecord endpoint (block actor)
            if path == "/xrpc/com.atproto.repo.createRecord", method == "POST" {
                // Capture and verify the request body
                let bodyData: Data
                if let httpBody = request.httpBody {
                    bodyData = httpBody
                } else if let stream = request.httpBodyStream {
                    stream.open()
                    defer { stream.close() }
                    var data = Data()
                    var buffer = [UInt8](repeating: 0, count: 1024)
                    var read = stream.read(&buffer, maxLength: buffer.count)
                    while read > 0 {
                        data.append(buffer, count: read)
                        read = stream.read(&buffer, maxLength: buffer.count)
                    }
                    bodyData = data
                } else {
                    bodyData = Data()
                }
                createRecordBody = try? JSONSerialization.jsonObject(
                    with: bodyData
                ) as? [String: Any]

                XCTAssertNotNil(
                    request.value(forHTTPHeaderField: "Authorization"),
                    "createRecord request should include Bearer token"
                )

                let json = """
                {
                    "uri": "at://\(did)/app.bsky.graph.block/rkey1",
                    "cid": "cid-block-1"
                }
                """.data(using: .utf8)!
                let response = HTTPURLResponse(
                    url: url, statusCode: 200, httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!
                return (response, json)
            }

            XCTFail("Unexpected request: \(method) \(url.absoluteString)")
            throw BlueskyAPIError.invalidURL
        }

        // Execute block
        try await client.blockActor(
            did: targetDID,
            account: account,
            appPassword: appPassword
        )

        // Verify the createRecord request body
        let body = try XCTUnwrap(createRecordBody, "createRecord request body should be captured")
        XCTAssertEqual(body["repo"] as? String, did, "repo should be the authenticated DID")
        XCTAssertEqual(
            body["collection"] as? String,
            "app.bsky.graph.block",
            "collection should be app.bsky.graph.block"
        )

        let record = try XCTUnwrap(body["record"] as? [String: Any], "record should be present")
        XCTAssertEqual(
            record["$type"] as? String,
            "app.bsky.graph.block",
            "record $type should be app.bsky.graph.block"
        )
        XCTAssertEqual(
            record["subject"] as? String,
            targetDID,
            "record subject should be the target DID"
        )
    }
}
