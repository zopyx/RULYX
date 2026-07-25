import Foundation

/// Executes HTTP requests to the Bluesky AT Protocol XRPC endpoints.
/// Implementations handle URL construction, JSON encoding/decoding, authentication headers,
/// HTTP status code validation, and error mapping to `BlueskyAPIError`.
protocol BlueskyRequestExecuting: Sendable {
    /// Sends a request with an optional JSON-encoded body to an XRPC endpoint.
    /// - Parameters:
    ///   - path: The XRPC method path (e.g. `"com.atproto.server.createSession"`).
    ///   - method: The HTTP method (e.g. `"GET"`, `"POST"`).
    ///   - queryItems: URL query parameters for the request.
    ///   - body: An optional `Encodable` value to serialize as the JSON request body.
    ///   - accessToken: An optional Bearer token for authenticated endpoints.
    ///   - hostURL: The base URL for the request; if `nil`, uses the default PDS URL.
    /// - Returns: The decoded response of type `Response`.
    /// - Throws: `BlueskyAPIError` for HTTP errors, decoding failures, or network errors.
    func send<Response: Decodable>(
        path: String,
        method: String,
        queryItems: [URLQueryItem],
        body: (some Encodable)?,
        accessToken: String?,
        hostURL: URL?
    ) async throws -> Response

    /// Sends a request without a body to an XRPC endpoint.
    /// - Parameters:
    ///   - path: The XRPC method path.
    ///   - method: The HTTP method.
    ///   - queryItems: URL query parameters for the request.
    ///   - accessToken: An optional Bearer token for authenticated endpoints.
    ///   - hostURL: The base URL for the request; if `nil`, uses the default PDS URL.
    /// - Returns: The decoded response of type `Response`.
    /// - Throws: `BlueskyAPIError` for HTTP errors, decoding failures, or network errors.
    func send<Response: Decodable>(
        path: String,
        method: String,
        queryItems: [URLQueryItem],
        accessToken: String?,
        hostURL: URL?
    ) async throws -> Response
}

struct BlueskyRequestExecutor: BlueskyRequestExecuting {
    private let baseURL: URL
    private let httpClient: HTTPClient

    init(baseURL: URL = .bskySocial, httpClient: HTTPClient = HTTPClient()) {
        self.baseURL = baseURL
        self.httpClient = httpClient
    }

    func send<Response: Decodable>(
        path: String,
        method: String,
        queryItems: [URLQueryItem] = [],
        body: (some Encodable)?,
        accessToken: String?,
        hostURL: URL?
    ) async throws -> Response {
        let start = CFAbsoluteTimeGetCurrent()
        let targetURL = hostURL ?? baseURL
        guard var components = URLComponents(url: targetURL.appendingPathComponent("xrpc/\(path)"), resolvingAgainstBaseURL: false) else {
            throw BlueskyAPIError.invalidURL
        }
        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }
        guard let url = components.url else {
            throw BlueskyAPIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if let accessToken {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }

        if let body {
            request.httpBody = try JSONEncoder().encode(body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let (data, httpResponse) = try await httpClient.data(
            for: request,
            source: Self.sourceLabel(for: path),
            origin: Self.originLabel(for: path, method: method)
        )

        if httpResponse.statusCode == 401 {
            if let errorPayload = try? JSONDecoder().decode(APIErrorPayload.self, from: data),
               let errorCode = errorPayload.error
            {
                if errorCode == "AccountTakedown" || errorCode == "Deactivated" {
                    throw BlueskyAPIError.deactivated(errorPayload.message ?? errorCode)
                }
                if errorCode == "AuthFactorTokenRequired" {
                    throw BlueskyAPIError.authFactorTokenRequired
                }
            }
            throw BlueskyAPIError.unauthorized
        }

        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            if let errorPayload = try? JSONDecoder().decode(APIErrorPayload.self, from: data) {
                let errorCode = errorPayload.error ?? ""
                if errorCode == "AccountTakedown" || errorCode == "Deactivated" {
                    throw BlueskyAPIError.deactivated(errorPayload.message ?? errorCode)
                }
                if errorCode == "AuthFactorTokenRequired" {
                    throw BlueskyAPIError.authFactorTokenRequired
                }
                throw BlueskyAPIError.server(errorPayload.message ?? errorCode)
            }
            let bodyPreview = String(decoding: data.prefix(500), as: UTF8.self)
            AppLogger.moderation.error(
                "BlueskyRequestExecutor got HTTP \(httpResponse.statusCode) for \(method) xrpc/\(path): \(bodyPreview)"
            )
            throw BlueskyAPIError.invalidResponse
        }

        AppLogger.performance.debug("\(method, privacy: .public) \(path, privacy: .public) took \(CFAbsoluteTimeGetCurrent() - start, format: .fixed(precision: 2))s (\(httpResponse.statusCode))")

        do {
            let decodedData = data.isEmpty ? Data("{ }".utf8) : data
            return try JSONDecoder().decode(Response.self, from: decodedData)
        } catch {
            let bodyPreview = String(decoding: data.prefix(500), as: UTF8.self)
            AppLogger.performance.debug(
                "Decoding failure for \(path, privacy: .public): \(error.localizedDescription, privacy: .public). Body: \(bodyPreview)"
            )
            throw BlueskyAPIError.invalidResponse
        }
    }

    func send<Response: Decodable>(
        path: String,
        method: String,
        queryItems: [URLQueryItem] = [],
        accessToken: String?,
        hostURL: URL?
    ) async throws -> Response {
        try await send(
            path: path,
            method: method,
            queryItems: queryItems,
            body: String?.none,
            accessToken: accessToken,
            hostURL: hostURL
        )
    }
}

private extension BlueskyRequestExecutor {
    static func sourceLabel(for path: String) -> String {
        if path.contains("chat.") {
            return "Chat"
        }
        if path.contains(".graph.") {
            return "Lists / Relationships"
        }
        if path.contains(".actor.") || path.contains(".identity.") {
            return "Profiles / Search"
        }
        if path.contains(".feed.") {
            return "Timeline / Posts"
        }
        if path.contains(".notification.") {
            return "Notifications"
        }
        if path.contains(".repo.") {
            return "Composer / Records"
        }
        if path.contains(".moderation.") {
            return "Moderation"
        }
        if path.contains(".server.") {
            return "Authentication / Session"
        }
        return "Bluesky API"
    }

    static func originLabel(for path: String, method: String) -> String {
        "BlueskyRequestExecutor \(method) xrpc/\(path)"
    }
}
