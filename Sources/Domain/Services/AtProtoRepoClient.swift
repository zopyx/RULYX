import Foundation

// MARK: - RepoBlockRecord

/// One `app.bsky.graph.block` record from an account's own repository.
///
/// Field names mirror `BlocklistEntry` / `ConstellationBlockerEntry` on purpose:
/// every "Blocking" source feeds the same `BlueskyActor` conversion.
struct RepoBlockRecord: Codable, Sendable, Hashable {
    /// The blocked account (the record's `subject`).
    let did: String
    /// ISO 8601 creation date; `nil` on records written before `createdAt` was included.
    let createdAt: String?
}

// MARK: - AtProtoRepoClient

/// Read-only access to an account's **own** AT Protocol repository.
///
/// "Who do I block?" is a question about records *inside* one repo — the authoritative
/// source. The Constellation backlink index keys its data on the link *target*, so it
/// cannot enumerate a given account's block records; the repo itself is the only
/// authoritative, complete answer (see `BLOCK_BACK.md` §6.3).
///
/// Reads go to the account's PDS, which is host-specific (`bsky.social`,
/// `eurosky.social`, …), so this client uses a **deliberately unpinned** `HTTPClient`:
/// `HTTPClient.defaultPinnedHashes` contains only the app's fixed API hosts, and the
/// pinning delegate cancels any chain without a matching pin — i.e. every custom PDS
/// would fail with a silent cancellation.
@MainActor
final class AtProtoRepoClient {
    private let httpClient: HTTPClient

    /// Age (seconds) after which a cached payload is treated as stale.
    /// Mutable so tests can force the stale branch deterministically.
    var cacheMaxAge: TimeInterval = BlueskyAPICache.DefaultTTL.relationship

    /// `com.atproto.repo.listRecords` page size — the protocol's maximum.
    private static let pageSize = 100

    /// Upper bound on pages walked per call (100 × 100 records). Bounds the worst case
    /// for accounts with very large blocklists; the walk reports what it collected.
    private static let maxPages = 100

    init(httpClient: HTTPClient = HTTPClient()) {
        self.httpClient = httpClient
    }

    // MARK: - Public API

    /// Every `app.bsky.graph.block` record in the account's own repo, in PDS order
    /// (newest first). Paginates to the end and caches the result; serves the last good
    /// payload when a refresh fails. `forceRefresh` bypasses the cache read.
    func blockRecords(
        for account: AppAccount,
        onProgress: (@MainActor @Sendable (Int) async -> Void)?,
        forceRefresh: Bool = false
    ) async throws -> [RepoBlockRecord] {
        let repo = account.did ?? account.handle
        let cacheURL = "repo/blocklist/\(repo)"
        var staleFallback: [RepoBlockRecord]?
        if !forceRefresh,
           let cached = await BlueskyAPICache.shared.read(scope: .account(repo), url: cacheURL, maxAge: cacheMaxAge),
           let payload = try? JSONDecoder().decode([RepoBlockRecord].self, from: cached.data)
        {
            if !cached.isStale {
                AppLogger.performance.debug("Repo blocklist cache HIT for \(repo) (\(payload.count) records)")
                return payload
            }
            staleFallback = payload
        }

        do {
            let records = try await listBlockRecords(
                repo: repo,
                pdsURL: pdsURL(for: account),
                onProgress: onProgress
            )
            if let data = try? JSONEncoder().encode(records) {
                await BlueskyAPICache.shared.write(scope: .account(repo), url: cacheURL, data: data)
            }
            return records
        } catch let cancellation as CancellationError {
            throw cancellation
        } catch {
            guard let staleFallback, !staleFallback.isEmpty else { throw error }
            AppLogger.http.warning("Repo blocklist refresh failed (\(error.localizedDescription, privacy: .public)) — serving \(staleFallback.count) cached records")
            return staleFallback
        }
    }

    // MARK: - Private

    /// The PDS to read from. Accounts added through the app carry the URL resolved at
    /// login; older entries without one fall back to `bsky.social`.
    private func pdsURL(for account: AppAccount) -> URL {
        account.pdsURL ?? .bskySocial
    }

    private func listBlockRecords(
        repo: String,
        pdsURL: URL,
        onProgress: (@MainActor @Sendable (Int) async -> Void)?
    ) async throws -> [RepoBlockRecord] {
        var records: [RepoBlockRecord] = []
        var seen = Set<String>()
        var cursor: String?
        var page = 0

        repeat {
            try Task.checkCancellation()
            let response = try await listRecordsPage(repo: repo, pdsURL: pdsURL, cursor: cursor)
            for record in response.records where seen.insert(record.value.subject).inserted {
                records.append(RepoBlockRecord(did: record.value.subject, createdAt: record.value.createdAt))
            }
            await onProgress?(records.count)
            cursor = response.cursor
            page += 1
        } while cursor != nil && page < Self.maxPages

        if cursor != nil {
            AppLogger.http.warning("Repo blocklist \(repo) truncated at \(Self.maxPages) pages (\(records.count) records)")
        }
        AppLogger.http.info("Repo blocklist \(repo): \(records.count) block records in \(page) pages")
        return records
    }

    private func listRecordsPage(
        repo: String,
        pdsURL: URL,
        cursor: String?
    ) async throws -> RepoListRecordsResponse {
        guard var components = URLComponents(
            url: pdsURL.appendingPathComponent("xrpc/com.atproto.repo.listRecords"),
            resolvingAgainstBaseURL: false
        ) else {
            throw BlueskyAPIError.invalidURL
        }
        var queryItems = [
            URLQueryItem(name: "repo", value: repo),
            URLQueryItem(name: "collection", value: "app.bsky.graph.block"),
            URLQueryItem(name: "limit", value: String(Self.pageSize)),
        ]
        if let cursor, !cursor.isEmpty {
            queryItems.append(URLQueryItem(name: "cursor", value: cursor))
        }
        components.queryItems = queryItems
        guard let url = components.url else { throw BlueskyAPIError.invalidURL }

        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, httpResponse) = try await httpClient.data(for: request, source: "Repo Blocklist")
        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            AppLogger.http.error("Repo blocklist \(repo) → HTTP \(httpResponse.statusCode)")
            throw BlueskyAPIError.server("PDS returned HTTP \(httpResponse.statusCode)")
        }
        return try decode(data, repo: repo)
    }

    private func decode(_ data: Data, repo: String) throws -> RepoListRecordsResponse {
        guard let decoded = try? JSONDecoder().decode(RepoListRecordsResponse.self, from: data) else {
            let body = String(data: data, encoding: .utf8) ?? "empty"
            AppLogger.http.error("Repo blocklist \(repo) → decode failed: \(body.prefix(200))")
            throw BlueskyAPIError.invalidResponse
        }
        return decoded
    }
}

// MARK: - Wire DTOs

/// Page of `com.atproto.repo.listRecords`; only the fields this client needs.
private struct RepoListRecordsResponse: Decodable {
    let records: [Record]
    let cursor: String?

    struct Record: Decodable {
        let value: Value

        struct Value: Decodable {
            let subject: String
            let createdAt: String?
        }
    }
}
