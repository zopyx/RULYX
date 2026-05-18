import Foundation

struct HTTPClient {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        var request = request
        request.setValue(UserAgentProvider.random, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BlueskyAPIError.invalidResponse
        }
        return (data, httpResponse)
    }

    func data(from url: URL) async throws -> (Data, HTTPURLResponse) {
        try await data(for: URLRequest(url: url))
    }

    func download(for request: URLRequest) async throws -> (URL, HTTPURLResponse) {
        var request = request
        request.setValue(UserAgentProvider.random, forHTTPHeaderField: "User-Agent")
        let (fileURL, response) = try await session.download(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BlueskyAPIError.invalidResponse
        }
        return (fileURL, httpResponse)
    }
}
