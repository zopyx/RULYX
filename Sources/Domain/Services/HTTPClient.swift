import CryptoKit
import Foundation

// MARK: - UploadProgressDelegate

private final class UploadProgressDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    let onProgress: @Sendable (Double) -> Void

    init(onProgress: @escaping @Sendable (Double) -> Void) {
        self.onProgress = onProgress
    }

    func urlSession(_: URLSession, task _: URLSessionTask, didSendBodyData _: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        guard totalBytesExpectedToSend > 0 else { return }
        onProgress(Double(totalBytesSent) / Double(totalBytesExpectedToSend))
    }
}

// MARK: - CertificatePinningDelegate

/// Validates server certificates against pinned SHA-256 public key hashes.
/// When no pins are configured, all connections are allowed (development mode).
///
/// Use `CertificatePinningDelegate.pinHashes(for:keyCount:)` to generate
/// pin hashes from PEM-encoded certificate data.
///
/// - Important: Pinning is opt-in. Pass an empty set or omit `pinnedHashes`
///   to disable pinning and allow all connections.
///
/// Also collects `URLSessionTaskMetrics` so URL-cache effectiveness is observable:
/// a transaction whose `resourceFetchType` is `.localCache` was answered by the URL cache —
/// such a request produces no observable network activity anywhere else.
private final class CertificatePinningDelegate: NSObject, URLSessionDelegate, URLSessionTaskDelegate, @unchecked Sendable {
    /// @unchecked Sendable: NSObject-based URLSession delegate; thread-safety
    /// is guaranteed by URLSession's serial delegate queue.
    private let pinnedHashes: Set<String>

    /// Receives `(cachedTransactions, totalTransactions)` after each task finishes.
    private let onTaskMetrics: (@Sendable (Int, Int) -> Void)?

    init(pinnedHashes: Set<String>, onTaskMetrics: (@Sendable (Int, Int) -> Void)? = nil) {
        self.pinnedHashes = pinnedHashes
        self.onTaskMetrics = onTaskMetrics
    }

    func urlSession(_: URLSession, task _: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        let transactions = metrics.transactionMetrics
        guard !transactions.isEmpty else { return }
        let cached = transactions.filter { $0.resourceFetchType == .localCache }.count
        onTaskMetrics?(cached, transactions.count)
    }

    func urlSession(
        _: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust
        else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        // If no pins are configured, allow all (development mode).
        guard !pinnedHashes.isEmpty else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        // Require valid certificate chain (TLS 1.2+).
        guard SecTrustEvaluateWithError(serverTrust, nil) else {
            AppLogger.http.error("Pinning: \(challenge.protectionSpace.host) → TLS evaluation failed")
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        // Check each certificate in the chain against the pinned hashes.
        let certificateCount = SecTrustGetCertificateCount(serverTrust)
        var checkedHashes: [String] = []
        let certificates = SecTrustCopyCertificateChain(serverTrust) as? [SecCertificate] ?? []
        for index in 0 ..< certificateCount {
            guard index < certificates.count else { continue }
            let certificate = certificates[index]
            let publicKeyHash = Self.sha256PublicKeyHash(for: certificate)
            checkedHashes.append(publicKeyHash)
            if pinnedHashes.contains(publicKeyHash) {
                completionHandler(.useCredential, URLCredential(trust: serverTrust))
                return
            }
        }

        // No matching pin found — reject the connection.
        AppLogger.http.error("Pinning: \(challenge.protectionSpace.host) → no match (checked: \(checkedHashes.joined(separator: ", ")))")
        completionHandler(.cancelAuthenticationChallenge, nil)
    }

    // MARK: - Public Key Hashing

    /// Compute the SHA-256 hash of a certificate's public key (SPKI).
    private static func sha256PublicKeyHash(for certificate: SecCertificate) -> String {
        guard let publicKey = SecCertificateCopyKey(certificate) else { return "" }

        var error: Unmanaged<CFError>?
        guard let publicKeyData = SecKeyCopyExternalRepresentation(publicKey, &error) as Data? else {
            return ""
        }

        return Data(SHA256.hash(data: publicKeyData)).base64EncodedString()
    }

    // MARK: - Pin Generation Utility

    /// Generate SHA-256 pin hashes from PEM-encoded certificate data.
    ///
    /// - Parameters:
    ///   - pemData: Raw PEM-encoded certificate data (one or more certificates).
    ///   - keyCount: Number of certificates to extract (default: all).
    /// - Returns: Set of base64-encoded SHA-256 public key hashes suitable for `pinnedHashes`.
    static func pinHashes(from pemData: Data, keyCount: Int = Int.max) -> Set<String> {
        var hashes = Set<String>()
        guard let pemString = String(data: pemData, encoding: .utf8) ?? String(data: pemData, encoding: .ascii) else {
            return hashes
        }
        var remaining = pemString[...]
        var extracted = 0

        while extracted < keyCount, let range = remaining.range(of: "-----BEGIN CERTIFICATE-----") {
            remaining = remaining[range.lowerBound...]
            guard let endRange = remaining.range(of: "-----END CERTIFICATE-----") else { break }

            let certBlock = String(remaining[..<endRange.upperBound])
            remaining = remaining[endRange.upperBound...]

            // Decode base64 body (skip the header/footer lines).
            let lines = certBlock.components(separatedBy: .newlines)
            let base64Body = lines.dropFirst().dropLast().joined()

            guard let certData = Data(base64Encoded: base64Body),
                  let certificate = SecCertificateCreateWithData(nil, certData as CFData)
            else { continue }

            hashes.insert(sha256PublicKeyHash(for: certificate))
            extracted += 1
        }

        return hashes
    }
}

// MARK: - InflightManager

private actor InflightManager {
    private var tasks: [String: Task<(Data, HTTPURLResponse), Error>] = [:]

    func dedup(key: String, operation: @escaping @Sendable () async throws -> (Data, HTTPURLResponse)) async throws -> (Data, HTTPURLResponse) {
        if let existing = tasks[key] {
            return try await existing.value
        }
        let task = Task { try await operation() }
        tasks[key] = task
        defer { tasks.removeValue(forKey: key) }
        return try await task.value
    }
}

// MARK: - HTTPClient

struct HTTPClient {
    private let session: URLSession
    private let debugStore: HTTPRequestDebugStore?

    /// SHA-256 hashes of expected certificate public keys for certificate pinning.
    /// When empty (the default), certificate pinning is disabled and all TLS connections are allowed.
    ///
    /// - Note: Use `CertificatePinningDelegate.pinHashes(from:keyCount:)` to generate
    ///   hashes from PEM-encoded certificate data.
    private let pinnedHashes: Set<String>

    /// Default pinned certificate hashes for known RULYX API endpoints.
    /// These are SHA-256 hashes of the public key bytes as returned by `SecKeyCopyExternalRepresentation`:
    /// - EC endpoints: uncompressed public key point.
    /// - RSA endpoints: PKCS#1 RSAPublicKey DER.
    /// Use the Swift Security framework or `scripts/ios-pin-hash.py` to compute; do not trust `openssl rsa` defaults.
    ///
    /// Includes leaf, intermediate, and root hashes so rotation of any single cert does not break the app.
    static let defaultPinnedHashes: Set<String> = [
        // bsky.social (PDS / AppView) — RSA leaf + Amazon intermediate + Amazon root
        "WFhJn2TdqWwdXy6GW6hkUx6z5lPgtdLTj4FKHxQ+DFE=",
        "6nxPsa2kTA3VkIjhZo/4AwlOJ2QHhMEFG2KpZqkgNGk=",
        "UAJ/9yOqq6nk4CX2QtZgDmyT6JHYlkBfihOzezH/8cs=",
        "Q2N4I92yheflRVU0ILb5pSuK1GJem8UeAXc3wZ8t4lg=",
        // public.api.bsky.app (profile batch, stats, posts) — RSA leaf + Let's Encrypt intermediate/root
        "eelLErHkHORHz4iW6dKQOy14LvowA1ScVtfDvl8jDpc=",
        "g5TwoFJudhMvvGmccUw3nojpZxR2H1nG93LLQ6LExzM=",
        "Hy81vkYUgs1Asa55LFV4+vfUaPt3QgaPuLTHTkAxqmE=",
        "3udbYNAibUAofT8NAf6ktVK0UZSjEhF99kRyhtyJ2yM=",
        "9Fk6HgfMnM7/vtnBHcUhg1b3gU2bIpSd50XmKZkMbGA=",
        // plc.directory (PLC audit log) — RSA leaf + Amazon intermediate + Amazon root
        "17wmhBIxAP8+6PakBtqWz1krJb43Mb+lvSqQIi6jl6I=",
        "/LWYS0bnqApLztW89p14Ilm/6JdJpH9mSOpWaxSNCL0=",
        "UAJ/9yOqq6nk4CX2QtZgDmyT6JHYlkBfihOzezH/8cs=",
        "197wZm0ZlRXsMJlYpv2R7x/g4XLsTF2yxzu87O2iT38=",
        // constellation.microcosm.blue (blocklist index) — EC leaf + Let's Encrypt
        // YE2 intermediate + ISRG Root X2. The leaf rotates every ~60 days, so the two
        // longer-lived hashes are what keep pinning alive across rotations.
        //
        // - Important: a host reached through a pinned client MUST have at least one of its
        //   chain hashes listed here. The delegate rejects every chain without a match, so a
        //   missing host does not fail loudly — it shows up as a cancelled request
        //   (`URLError.cancelled`, "Abgebrochen") and the feature silently has no data.
        "97OdXXK8RpY7f8DUwLIEhfxYFIx8tWNnEIuyg0IBL5I=",
        "uVnyjs8i8IbTN0j/dhQYuoLYVYfhIa0bczhBt2SP4GQ=",
        "+QHt0j1IgBr88CsiSG197KRsbAlprQDohcvoe1Za45Y=",
    ]

    private static let inflightManager = InflightManager()

    /// On-disk URL cache shared by every pinned API session.
    ///
    /// The pinned session used to be `.ephemeral` with `reloadIgnoringLocalCacheData`,
    /// which discarded the origin's `Cache-Control: public, max-age=…` entirely — every
    /// request went to the network even though the API advertises a 30 s freshness window.
    /// A dedicated cache (rather than `URLCache.shared`, which the media pipelines use)
    /// keeps API entries evictable independently and gives `clearAllCaches()` something
    /// precise to purge on an account switch.
    static let apiURLCache = URLCache(
        memoryCapacity: 64 * 1024 * 1024,
        diskCapacity: 256 * 1024 * 1024,
        diskPath: "bluesky-api-cache"
    )

    /// Extracts origin freshness metadata so callers can persist it and revalidate later.
    static func cacheMetadata(from response: HTTPURLResponse) -> (etag: String?, lastModified: String?, serverMaxAge: TimeInterval?) {
        let etag = response.value(forHTTPHeaderField: "ETag")
        let lastModified = response.value(forHTTPHeaderField: "Last-Modified")
        var serverMaxAge: TimeInterval?
        if let cacheControl = response.value(forHTTPHeaderField: "Cache-Control") {
            for directive in cacheControl.split(separator: ",") {
                let part = directive.trimmingCharacters(in: .whitespaces).lowercased()
                guard part.hasPrefix("max-age=") else { continue }
                serverMaxAge = TimeInterval(part.dropFirst("max-age=".count))
            }
        }
        return (etag, lastModified, serverMaxAge)
    }

    /// Creates an HTTP client with optional certificate pinning and debug store logging.
    ///
    /// - Parameters:
    ///   - session: The `URLSession` to use for requests. When `pinnedHashes` is non-empty,
    ///     this session is ignored and a new session is created with the pinning delegate.
    ///   - debugStore: Optional debug store for tracking HTTP request lifecycle.
    ///   - pinnedHashes: SHA-256 hashes of expected certificate public keys.
    ///     Leave empty to disable certificate pinning.
    init(
        session: URLSession = .shared,
        debugStore: HTTPRequestDebugStore? = HTTPRequestDebugStore.shared,
        pinnedHashes: Set<String> = []
    ) {
        self.debugStore = debugStore
        self.pinnedHashes = pinnedHashes

        if pinnedHashes.isEmpty {
            self.session = session
        } else {
            // Cookies and credentials stay out of persistent storage (the reason the
            // session was ephemeral), but the URL cache is kept so origin-declared
            // freshness is honoured instead of re-fetching on every call.
            let store = debugStore
            let delegate = CertificatePinningDelegate(pinnedHashes: pinnedHashes) { cached, total in
                Task { await store?.recordURLCacheTransactions(cached: cached, total: total) }
            }
            let config = URLSessionConfiguration.default
            config.requestCachePolicy = .useProtocolCachePolicy
            config.urlCache = Self.apiURLCache
            config.httpCookieStorage = nil
            config.httpShouldSetCookies = false
            config.urlCredentialStorage = nil
            self.session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        }
    }

    /// Deduplicates in-flight network requests by method + auth + canonicalized URL.
    /// Query items are sorted alphabetically so `?a=1&b=2` and `?b=2&a=1` share a key.
    /// Body and auth are intentionally excluded — only idempotent GETs should use `dedupedData`.
    func dedupedData(
        for request: URLRequest,
        authToken: String? = nil,
        source: String,
        origin: String? = nil
    ) async throws -> (Data, HTTPURLResponse) {
        // The auth token is part of the key: the same URL fetched by two signed-in accounts
        // returns viewer-relative payloads, and collapsing those into one response would
        // hand one account the other's viewer state.
        let auth = Self.authDiscriminator(authToken)
        let cacheKey = "\(request.httpMethod ?? "GET"):\(auth):\(Self.canonicalURLString(for: request.url))"
        return try await Self.inflightManager.dedup(key: cacheKey) {
            try await data(for: request, source: source, origin: origin)
        }
    }

    private static func authDiscriminator(_ authToken: String?) -> String {
        guard let authToken else { return "-" }
        let digest = SHA256.hash(data: Data(authToken.utf8))
        return digest.prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    private static func canonicalURLString(for url: URL?) -> String {
        guard let url, var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url?.absoluteString ?? ""
        }
        if let items = components.queryItems, !items.isEmpty {
            components.queryItems = items.sorted { ($0.name, $0.value ?? "") < ($1.name, $1.value ?? "") }
        }
        return components.url?.absoluteString ?? url.absoluteString
    }

    func data(
        for request: URLRequest,
        source: String? = nil,
        origin: String? = nil,
        originFileID: String = #fileID,
        originFunction: String = #function,
        originLine: Int = #line
    ) async throws -> (Data, HTTPURLResponse) {
        var request = request
        request.setValue(UserAgentProvider.random, forHTTPHeaderField: "User-Agent")
        let entryID = await debugStore?.begin(
            request: request,
            source: source,
            origin: origin ?? Self.makeOrigin(fileID: originFileID, function: originFunction, line: originLine)
        )
        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                await debugStore?.fail(
                    id: entryID ?? UUID(),
                    errorMessage: AppError.userMessage(from: BlueskyAPIError.invalidResponse)
                )
                AppLogger.http.error("\(request.httpMethod ?? "?") \(request.url?.absoluteString ?? "?") → invalid response (not HTTP)")
                throw BlueskyAPIError.invalidResponse
            }
            if Self.isSuccess(httpResponse.statusCode) {
                await debugStore?.succeed(id: entryID ?? UUID(), statusCode: httpResponse.statusCode)
            } else {
                let bodyPreview = Self.prettyPrintedJSON(from: data) ?? String(data: data, encoding: .utf8) ?? ""
                await debugStore?.fail(
                    id: entryID ?? UUID(),
                    statusCode: httpResponse.statusCode,
                    errorMessage: HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode),
                    errorResponseJSON: Self.prettyPrintedJSON(from: data)
                )
                AppLogger.http.error("\(request.httpMethod ?? "?") \(request.url?.absoluteString ?? "?") → HTTP \(httpResponse.statusCode)\n\(bodyPreview.prefix(500))")
            }
            return (data, httpResponse)
        } catch {
            await debugStore?.fail(
                id: entryID ?? UUID(),
                errorMessage: AppError.userMessage(from: error)
            )
            AppLogger.http.error("\(request.httpMethod ?? "?") \(request.url?.absoluteString ?? "?") → \(error.localizedDescription)")
            throw error
        }
    }

    func data(
        from url: URL,
        source: String? = nil,
        origin: String? = nil,
        originFileID: String = #fileID,
        originFunction: String = #function,
        originLine: Int = #line
    ) async throws -> (Data, HTTPURLResponse) {
        try await data(
            for: URLRequest(url: url),
            source: source,
            origin: origin,
            originFileID: originFileID,
            originFunction: originFunction,
            originLine: originLine
        )
    }

    func download(
        for request: URLRequest,
        source: String? = nil,
        origin: String? = nil,
        originFileID: String = #fileID,
        originFunction: String = #function,
        originLine: Int = #line
    ) async throws -> (URL, HTTPURLResponse) {
        var request = request
        request.setValue(UserAgentProvider.random, forHTTPHeaderField: "User-Agent")
        let entryID = await debugStore?.begin(
            request: request,
            source: source,
            origin: origin ?? Self.makeOrigin(fileID: originFileID, function: originFunction, line: originLine)
        )
        do {
            let (fileURL, response) = try await session.download(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                await debugStore?.fail(
                    id: entryID ?? UUID(),
                    errorMessage: AppError.userMessage(from: BlueskyAPIError.invalidResponse)
                )
                throw BlueskyAPIError.invalidResponse
            }
            if Self.isSuccess(httpResponse.statusCode) {
                await debugStore?.succeed(id: entryID ?? UUID(), statusCode: httpResponse.statusCode)
            } else {
                let responseData = try? Data(contentsOf: fileURL)
                await debugStore?.fail(
                    id: entryID ?? UUID(),
                    statusCode: httpResponse.statusCode,
                    errorMessage: HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode),
                    errorResponseJSON: responseData.flatMap(Self.prettyPrintedJSON(from:))
                )
            }
            return (fileURL, httpResponse)
        } catch {
            await debugStore?.fail(
                id: entryID ?? UUID(),
                errorMessage: AppError.userMessage(from: error)
            )
            throw error
        }
    }

    func upload(
        for request: URLRequest,
        from bodyData: Data,
        source: String? = nil,
        origin: String? = nil,
        progress: (@Sendable (Double) -> Void)? = nil,
        originFileID: String = #fileID,
        originFunction: String = #function,
        originLine: Int = #line
    ) async throws -> (Data, HTTPURLResponse) {
        var request = request
        request.setValue(UserAgentProvider.random, forHTTPHeaderField: "User-Agent")
        let entryID = await debugStore?.begin(
            request: request,
            source: source,
            origin: origin ?? Self.makeOrigin(fileID: originFileID, function: originFunction, line: originLine)
        )
        do {
            let delegate = progress.map { UploadProgressDelegate(onProgress: $0) }
            let (data, response) = try await session.upload(for: request, from: bodyData, delegate: delegate)
            guard let httpResponse = response as? HTTPURLResponse else {
                await debugStore?.fail(
                    id: entryID ?? UUID(),
                    errorMessage: AppError.userMessage(from: BlueskyAPIError.invalidResponse)
                )
                AppLogger.http.error("\(request.httpMethod ?? "?") \(request.url?.absoluteString ?? "?") → invalid response (not HTTP)")
                throw BlueskyAPIError.invalidResponse
            }
            if Self.isSuccess(httpResponse.statusCode) {
                await debugStore?.succeed(id: entryID ?? UUID(), statusCode: httpResponse.statusCode)
            } else {
                let bodyPreview = Self.prettyPrintedJSON(from: data) ?? String(data: data, encoding: .utf8) ?? ""
                await debugStore?.fail(
                    id: entryID ?? UUID(),
                    statusCode: httpResponse.statusCode,
                    errorMessage: HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode),
                    errorResponseJSON: Self.prettyPrintedJSON(from: data)
                )
                AppLogger.http.error("\(request.httpMethod ?? "?") \(request.url?.absoluteString ?? "?") → HTTP \(httpResponse.statusCode)\n\(bodyPreview.prefix(500))")
            }
            return (data, httpResponse)
        } catch {
            await debugStore?.fail(
                id: entryID ?? UUID(),
                errorMessage: AppError.userMessage(from: error)
            )
            AppLogger.http.error("\(request.httpMethod ?? "?") \(request.url?.absoluteString ?? "?") → \(error.localizedDescription)")
            throw error
        }
    }

    /// Whether a status code counts as a successful outcome.
    ///
    /// `304 Not Modified` is a success for a conditional request: it confirms the cached
    /// payload is still valid, and the caller keeps its cached body.
    private static func isSuccess(_ statusCode: Int) -> Bool {
        (200 ..< 300).contains(statusCode) || statusCode == 304
    }

    private static func makeOrigin(fileID: String, function: String, line: Int) -> String {
        "\(fileID):\(line) \(function)"
    }

    private static func prettyPrintedJSON(from data: Data) -> String? {
        guard !data.isEmpty,
              let object = try? JSONSerialization.jsonObject(with: data),
              JSONSerialization.isValidJSONObject(object),
              let prettyData = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
              let string = String(data: prettyData, encoding: .utf8)
        else {
            return nil
        }
        return string
    }
}
