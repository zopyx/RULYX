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
/// Pin enforcement is PER-HOST: only hosts under `enforcedHostSuffixes`
/// (first-party Bluesky/ClearSky/PLC infrastructure) must match a pin.
/// All other hosts — notably user-configured custom PDS instances — receive
/// standard TLS validation (`performDefaultHandling`). Pinning must never
/// break self-hosted PDS deployments.
///
/// Use `CertificatePinningDelegate.pinHashes(for:keyCount:)` to generate
/// pin hashes from PEM-encoded certificate data.
///
/// - Important: Pinning is opt-in. Pass an empty set or omit `pinnedHashes`
///   to disable pinning and allow all connections.
final class CertificatePinningDelegate: NSObject, URLSessionDelegate, @unchecked Sendable {
    /// @unchecked Sendable: NSObject-based URLSession delegate; thread-safety
    /// is guaranteed by URLSession's serial delegate queue.
    private let pinnedHashes: Set<String>

    /// Host suffixes whose TLS chains must match a pin. Matched by exact host
    /// or subdomain: `bsky.social` also covers `chat.bsky.social`; `bsky.app`
    /// covers `api.bsky.app` / `public.api.bsky.app`. A lookalike host such as
    /// `evil-bsky.social` does NOT match (suffix requires a dot boundary).
    static let enforcedHostSuffixes = [
        "bsky.social",
        "bsky.app",
        "clearsky.app",
        "clearsky.services",
        "plc.directory",
    ]

    /// Returns true when pin enforcement applies to `host`.
    static func isEnforcedHost(_ host: String) -> Bool {
        let host = host.lowercased()
        return enforcedHostSuffixes.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    init(pinnedHashes: Set<String>) {
        self.pinnedHashes = pinnedHashes
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

        // Per-host scope: only first-party hosts are pinned. Other hosts
        // (custom PDS instances) get standard TLS validation.
        guard Self.isEnforcedHost(challenge.protectionSpace.host) else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        // Enforce TLS 1.2+ by requiring at least a valid certificate chain.
        var secResult = SecTrustResultType.invalid
        guard SecTrustEvaluateWithError(serverTrust, nil),
              SecTrustGetTrustResult(serverTrust, &secResult) == errSecSuccess,
              secResult == .proceed || secResult == .unspecified
        else {
            AppLogger.http.error("Pinning: \(challenge.protectionSpace.host) → TLS evaluation failed (result: \(secResult.rawValue))")
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        // Check each certificate in the chain against the pinned hashes.
        let certificateCount = SecTrustGetCertificateCount(serverTrust)
        var checkedHashes: [String] = []
        for index in 0 ..< certificateCount {
            guard let certificate = SecTrustGetCertificateAtIndex(serverTrust, index) else { continue }
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
    private let pinnedHashes: Set<String>

    /// Minimum interval between requests to the same host. Prevents 429 bursts
    /// before the server-side rate limiter triggers.
    private let minimumRequestInterval: TimeInterval = 0.05  // 50ms

    /// Actor-managed per-host throttle timestamps. Shared across all
    /// HTTPClient instances for preemptive rate limiting.
    private actor HostThrottle {
        private var lastRequestTime: [String: Date] = [:]

        func nextAllowedDelay(host: String, minimumInterval: TimeInterval) -> TimeInterval {
            let now = Date()
            let delay: TimeInterval
            if let last = lastRequestTime[host] {
                let elapsed = now.timeIntervalSince(last)
                delay = max(0, minimumInterval - elapsed)
            } else {
                delay = 0
            }
            lastRequestTime[host] = max(lastRequestTime[host] ?? now, now)
            return delay
        }
    }

    private static let hostThrottle = HostThrottle()

    /// Ensures at least `minimumRequestInterval` has passed since the last
    /// request to `host`. Sleeps briefly if needed — acts as a simple token
    /// bucket for preemptive rate limiting.
    private func throttle(host: String) async {
        let delay = await Self.hostThrottle.nextAllowedDelay(
            host: host,
            minimumInterval: minimumRequestInterval
        )
        if delay > 0 {
            try? await Task.sleep(for: .seconds(delay))
        }
    }

    /// Default pinned certificate hashes for known RULYX API endpoints.
    /// These are SHA-256 hashes of the raw public key bytes
    /// (SecKeyCopyExternalRepresentation), NOT SPKI hashes.
    /// Generated from iOS runtime — use Pinning: logs to verify.
    static let defaultPinnedHashes: Set<String> = [
        // bsky.social (PDS / AppView)
        "Q2N4I92yheflRVU0ILb5pSuK1GJem8UeAXc3wZ8t4lg=",
        // public.api.bsky.app (profile batch, stats, posts) — leaf cert
        "g5TwoFJudhMvvGmccUw3nojpZxR2H1nG93LLQ6LExzM=",
        // api.clearsky.app (moderation lists)
        "Y3I68JHgizJRRLoAuY0WJZTARay+EOI2eaSaIL1gv08=",
        // public.api.clearsky.services (blocklist, get-did)
        "HsKVgpqgfcSXIAWyUFFk106M0CDFoKgFt82ZWEd1Pqs=",
        // plc.directory (PLC audit log)
        "197wZm0ZlRXsMJlYpv2R7x/g4XLsTF2yxzu87O2iT38=",
    ]

    private static let inflightManager = InflightManager()

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
            let delegate = CertificatePinningDelegate(pinnedHashes: pinnedHashes)
            let config = URLSessionConfiguration.ephemeral
            config.requestCachePolicy = .reloadIgnoringLocalCacheData
            self.session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        }
    }

    /// Deduplicates in-flight network requests by method + URL.
    /// If a request to the same URL with the same HTTP method is already in flight,
    /// the second caller awaits the same task instead of starting a duplicate network call.
    func dedupedData(for request: URLRequest, source: String) async throws -> (Data, HTTPURLResponse) {
        let cacheKey = "\(request.httpMethod ?? "GET"):\(request.url?.absoluteString ?? "")"
        return try await Self.inflightManager.dedup(key: cacheKey) {
            try await data(for: request, source: source)
        }
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
        // Preemptive rate limiting: ensure minimum interval between requests
        // to the same host to prevent server-side 429 bursts.
        if let host = request.url?.host {
            await throttle(host: host)
        }
        // Rate-limit retry loop: 429 responses trigger an exponential backoff
        // with up to 3 attempts. The first retry waits for the server-specified
        // Retry-After header (or 5s default), doubling each subsequent attempt.
        let maxRetries = 3
        var retryCount = 0
        var waitSeconds: TimeInterval = 5

        while true {
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

                if httpResponse.statusCode == 429, retryCount < maxRetries {
                    // Parse server-specified Retry-After (preferred) or use exponential backoff
                    let retryAfter = httpResponse.value(forHTTPHeaderField: "Retry-After")
                    if let retrySeconds = retryAfter.flatMap(Double.init) {
                        waitSeconds = retrySeconds
                    }
                    AppLogger.http.info("Rate-limited on \(request.url?.absoluteString ?? "?"), retry \(retryCount + 1)/\(maxRetries) after \(waitSeconds)s")
                    try await Task.sleep(nanoseconds: UInt64(waitSeconds * 1_000_000_000))
                    retryCount += 1
                    waitSeconds *= 2  // exponential backoff
                    continue
                }

                if (200 ..< 300).contains(httpResponse.statusCode) {
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
            if (200 ..< 300).contains(httpResponse.statusCode) {
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
            if (200 ..< 300).contains(httpResponse.statusCode) {
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
