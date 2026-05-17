import CryptoKit
import Foundation

protocol BlueskyRequestExecuting: Sendable {
    func send<Response: Decodable>(
        path: String,
        method: String,
        queryItems: [URLQueryItem],
        body: (some Encodable)?,
        accessToken: String?,
        hostURL: URL?
    ) async throws -> Response

    func send<Response: Decodable>(
        path: String,
        method: String,
        queryItems: [URLQueryItem],
        accessToken: String?,
        hostURL: URL?
    ) async throws -> Response
}

struct BlueskyRequestExecutor: BlueskyRequestExecuting {
    static func makePinnedSession() -> URLSession {
        let delegate = PinningDelegate()
        return URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)
    }

    private let baseURL: URL
    private let session: URLSession

    init(baseURL: URL = .bskySocial, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
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
        request.setValue(UserAgentProvider.random, forHTTPHeaderField: "User-Agent")

        if let accessToken {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }

        if let body {
            request.httpBody = try JSONEncoder().encode(body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BlueskyAPIError.invalidResponse
        }

        if httpResponse.statusCode == 401 {
            throw BlueskyAPIError.unauthorized
        }

        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            if let errorPayload = try? JSONDecoder().decode(APIErrorPayload.self, from: data) {
                throw BlueskyAPIError.server(errorPayload.message ?? errorPayload.error ?? "Bluesky request failed.")
            }
            throw BlueskyAPIError.invalidResponse
        }

        AppLogger.performance.debug("\(method, privacy: .public) \(path, privacy: .public) took \(CFAbsoluteTimeGetCurrent() - start, format: .fixed(precision: 2))s (\(httpResponse.statusCode))")

        do {
            let decodedData = data.isEmpty ? Data("{}".utf8) : data
            return try JSONDecoder().decode(Response.self, from: decodedData)
        } catch {
            AppLogger.performance.debug("Decoding failure for \(path, privacy: .public): \(error.localizedDescription, privacy: .public)")
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

private final class PinningDelegate: NSObject, URLSessionDelegate {
    private static let pinnedSPKIHashes = [
        "Va6hs2tSCkc4CWC91P6Bga2S05J/R2R+Tp4WPAv7Hlc=",
    ]

    func urlSession(
        _: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.host == "bsky.social" else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        guard let serverTrust = challenge.protectionSpace.serverTrust else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        guard SecTrustEvaluateWithError(serverTrust, nil) else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        guard let certificateChain = SecTrustCopyCertificateChain(serverTrust) as? [SecCertificate],
              let leafCertificate = certificateChain.first else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        let certData = SecCertificateCopyData(leafCertificate) as Data
        guard let spki = extractSPKI(from: certData) else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        let hash = Data(SHA256.hash(data: spki)).base64EncodedString()
        guard Self.pinnedSPKIHashes.contains(hash) else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        completionHandler(.useCredential, URLCredential(trust: serverTrust))
    }
}

private func extractSPKI(from certDER: Data) -> Data? {
    var index = certDER.startIndex
    guard certDER[index] == 0x30 else { return nil }
    index += 1
    guard readLength(from: certDER, index: &index) != nil else { return nil }

    guard certDER[index] == 0x30 else { return nil }
    index += 1
    guard let tbsLen = readLength(from: certDER, index: &index) else { return nil }
    let tbsEnd = index + tbsLen

    var lastSeqStart = index
    var lastSeqTagLen = 0

    while index < tbsEnd {
        let fieldStart = index
        guard let tag = certDER[safe: index] else { return nil }
        index += 1
        guard let len = readLength(from: certDER, index: &index) else { return nil }
        index += len

        if tag == 0x30 {
            lastSeqStart = fieldStart
            lastSeqTagLen = index - fieldStart
        }
        if tag == 0xA1 || tag == 0xA2 || tag == 0xA3 {
            guard lastSeqTagLen > 0 else { return nil }
            return certDER[lastSeqStart ..< fieldStart]
        }
    }
    guard lastSeqTagLen > 0 else { return nil }
    return certDER[lastSeqStart ..< tbsEnd]
}

private func readLength(from data: Data, index: inout Data.Index) -> Int? {
    guard let first = data[safe: index] else { return nil }
    index += 1
    if first & 0x80 == 0 {
        return Int(first)
    }
    let numBytes = Int(first & 0x7F)
    guard numBytes <= 4 else { return nil }
    var length = 0
    for _ in 0 ..< numBytes {
        guard let byte = data[safe: index] else { return nil }
        index += 1
        length = (length << 8) | Int(byte)
    }
    return length
}

private extension Data {
    subscript(safe index: Index) -> UInt8? {
        indices.contains(index) ? self[index] : nil
    }
}
