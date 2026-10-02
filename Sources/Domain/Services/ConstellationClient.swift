import Foundation

/// Read-only client for the Constellation backlink index (microcosm.blue).
///
/// Constellation crawls every record seen in the AT Protocol firehose and indexes
/// the links between them, so "who blocks me" can be answered from the
/// `app.bsky.graph.block` records themselves instead of from a curated blocker
/// database. RULYX uses it as the **second data source** for the "Blocked by" list:
/// Constellation is the source for questions that only a whole-firehose index can
/// answer: who links *to* a record, across every repository on the network.
///
/// Lives outside `LiveBlueskyClient` so that god class stays within its file-size
/// gate, and so the second source can be reasoned about — or dropped — on its own.
@MainActor
final class ConstellationClient {
    private let httpClient: HTTPClient

    /// Age (seconds) after which a cached blocker payload is treated as stale.
    /// Mutable so tests can force the stale branch deterministically.
    var cacheMaxAge: TimeInterval = BlueskyAPICache.DefaultTTL.relationship

    /// Maximum number of pages walked in one call.
    ///
    /// Constellation chains its cursors (pages cannot be requested in parallel) and
    /// answers in ~0.4 s per page, so an exhaustive walk of an account with thousands
    /// of blockers would take a minute or more. The cap keeps the fallback bounded;
    /// the reported total always comes from the index's own `total`, so the count
    /// stays exact even when the actor list is truncated.
    private static let maxPages = 50

    /// Maximum number of pages walked for the "Listed on" count (50 × 100 lists).
    /// A profile on more lists than that is rare; the walk reports what it collected.
    private static let maxListedOnPages = 50

    /// Maximum number of pages walked for the "Listed on" *member* walk (20 × 100).
    private static let maxListedOnMembershipPages = 20

    /// Batch size for profile resolution, matching `app.bsky.actor.getProfiles`.
    private static let profileBatchSize = 25

    /// Maximum number of profile batches in flight at once.
    private static let profileBatchConcurrency = 5

    init(httpClient: HTTPClient) {
        self.httpClient = httpClient
    }

    // MARK: - Public API

    /// Number of accounts blocking `actorDID`.
    /// One request — the index reports the total independently of the page size.
    func blockerCount(actorDID: String) async throws -> Int {
        try await backlinks(actorDID: actorDID, limit: 1, cursor: nil).total
    }

    /// DIDs of the accounts blocking `actorDID`.
    func blockerDIDs(actorDID: String) async throws -> Set<String> {
        try await Set(blockerEntries(actorDID: actorDID, onProgress: nil).entries.map(\.did))
    }

    /// Number of distinct lists `actorDID` appears on — the "Listed on" counter.
    ///
    /// A membership is an `app.bsky.graph.listitem` record linking the profile
    /// (`subject`) to its list. The index groups memberships by that second link, so the
    /// number of groups is the number of lists — not the number of membership records
    /// (a profile re-added to a list has one record per addition). The endpoint pages at
    /// 100 groups, so larger counts need a cursor walk.
    func listedOnListCount(actorDID: String) async throws -> Int {
        try await listedOnLists(actorDID: actorDID).count
    }

    /// The list AT-URIs `actorDID` appears on, deduplicated. Cached; a failed refresh
    /// serves the last good payload.
    func listedOnLists(actorDID: String) async throws -> [String] {
        let cacheURL = "constellation/listed-on/\(actorDID)"
        var staleFallback: ConstellationListedOnCache?
        if let cached = await BlueskyAPICache.shared.read(
            accountDID: actorDID,
            url: cacheURL,
            maxAge: cacheMaxAge
        ),
            let payload = try? JSONDecoder().decode(ConstellationListedOnCache.self, from: cached.data)
        {
            if !cached.isStale {
                AppLogger.performance.debug("Constellation listed-on cache HIT for \(actorDID) (\(payload.lists.count) lists)")
                return payload.lists
            }
            staleFallback = payload
        }

        do {
            var lists: [String] = []
            var seen = Set<String>()
            var cursor: String?
            var page = 0
            repeat {
                try Task.checkCancellation()
                let response = try await manyToManyCounts(actorDID: actorDID, cursor: cursor)
                for group in response.countsByOtherSubject where seen.insert(group.subject).inserted {
                    lists.append(group.subject)
                }
                cursor = response.cursor
                page += 1
            } while cursor != nil && page < Self.maxListedOnPages

            let payload = ConstellationListedOnCache(lists: lists)
            if let data = try? JSONEncoder().encode(payload) {
                await BlueskyAPICache.shared.write(accountDID: actorDID, url: cacheURL, data: data)
                AppLogger.performance.debug("Constellation listed-on cache WRITE for \(actorDID) (\(lists.count) lists, \(page) pages)")
            }
            return lists
        } catch let cancellation as CancellationError {
            throw cancellation
        } catch {
            guard let staleFallback, !staleFallback.lists.isEmpty else { throw error }
            AppLogger.http.warning("Constellation listed-on refresh failed (\(error.localizedDescription, privacy: .public)) — serving \(staleFallback.lists.count) cached lists")
            return staleFallback.lists
        }
    }

    /// Every membership of `actorDID`: the list it is on plus the record key of the
    /// `app.bsky.graph.listitem` record that puts it there (a TID, so it dates the
    /// membership). Paginated and cached; a failed refresh serves the last good payload.
    ///
    /// This is the detail variant of `listedOnListCount`: it costs one `getManyToMany`
    /// page per 100 memberships and carries the record keys, which `getManyToManyCounts`
    /// does not.
    func listedOnMemberships(actorDID: String) async throws -> [ConstellationListedOnMembership] {
        let cacheURL = "constellation/listed-on-memberships/\(actorDID)"
        var staleFallback: ConstellationListedOnMembershipCache?
        if let cached = await BlueskyAPICache.shared.read(
            accountDID: actorDID,
            url: cacheURL,
            maxAge: cacheMaxAge
        ),
            let payload = try? JSONDecoder().decode(ConstellationListedOnMembershipCache.self, from: cached.data)
        {
            if !cached.isStale {
                AppLogger.performance.debug("Constellation listed-on memberships cache HIT for \(actorDID) (\(payload.memberships.count))")
                return payload.memberships
            }
            staleFallback = payload
        }

        do {
            var memberships: [ConstellationListedOnMembership] = []
            var seen = Set<ConstellationListedOnMembership>()
            var cursor: String?
            var page = 0
            repeat {
                try Task.checkCancellation()
                let response = try await manyToMany(actorDID: actorDID, cursor: cursor)
                for item in response.items {
                    let membership = ConstellationListedOnMembership(
                        listURI: item.otherSubject,
                        recordKey: item.linkRecord.rkey
                    )
                    if seen.insert(membership).inserted {
                        memberships.append(membership)
                    }
                }
                cursor = response.cursor
                page += 1
            } while cursor != nil && page < Self.maxListedOnMembershipPages

            let payload = ConstellationListedOnMembershipCache(memberships: memberships)
            if let data = try? JSONEncoder().encode(payload) {
                await BlueskyAPICache.shared.write(accountDID: actorDID, url: cacheURL, data: data)
                AppLogger.performance.debug("Constellation listed-on memberships cache WRITE for \(actorDID) (\(memberships.count), \(page) pages)")
            }
            return memberships
        } catch let cancellation as CancellationError {
            throw cancellation
        } catch {
            guard let staleFallback, !staleFallback.memberships.isEmpty else { throw error }
            AppLogger.http.warning("Constellation listed-on memberships refresh failed (\(error.localizedDescription, privacy: .public)) — serving \(staleFallback.memberships.count) cached memberships")
            return staleFallback.memberships
        }
    }

    /// Actors blocking `actorDID`, with profiles resolved best-effort and each block
    /// dated from its record key; the index equivalent of the
    /// `single-blocklist` payload.
    func blockerActors(
        actorDID: String,
        onProgress: (@MainActor @Sendable (Int) async -> Void)?
    ) async throws -> BlocklistResult {
        let payload = try await blockerEntries(actorDID: actorDID, onProgress: onProgress)
        guard !payload.entries.isEmpty else {
            return BlocklistResult(actors: [], totalCount: payload.total)
        }

        var blockedDates = [String: String]()
        for entry in payload.entries {
            blockedDates[entry.did] = entry.blockedDate
        }

        var actors = await resolveProfilesBestEffort(dids: Array(blockedDates.keys).sorted())
        for index in actors.indices {
            if let dateString = blockedDates[actors[index].did] {
                actors[index].blockedDate = parseDate(dateString)
            }
        }
        return BlocklistResult(actors: actors, totalCount: payload.total)
    }

    /// Every blocker entry for `actorDID` (DID + block date), paginated and cached,
    /// together with the index's own total. Serves the last good payload when a
    /// refresh fails.
    func blockerEntries(
        actorDID: String,
        onProgress: (@MainActor @Sendable (Int) async -> Void)?
    ) async throws -> ConstellationBlockerCache {
        let cacheURL = "constellation/blocked-by/\(actorDID)"
        var staleFallback: ConstellationBlockerCache?
        if let cached = await BlueskyAPICache.shared.read(
            accountDID: actorDID,
            url: cacheURL,
            maxAge: cacheMaxAge
        ),
            let payload = try? JSONDecoder().decode(ConstellationBlockerCache.self, from: cached.data)
        {
            if !cached.isStale {
                AppLogger.performance.debug("Constellation cache HIT for \(actorDID) (\(payload.entries.count) entries)")
                return payload
            }
            staleFallback = payload
        }

        do {
            var entries: [ConstellationBlockerEntry] = []
            var seenDIDs = Set<String>()
            var cursor: String?
            var total = 0
            var page = 0

            repeat {
                try Task.checkCancellation()
                let response = try await backlinks(
                    actorDID: actorDID,
                    limit: ConstellationEndpoints.maxLimit,
                    cursor: cursor
                )
                total = response.total
                for record in response.records where seenDIDs.insert(record.did).inserted {
                    // A record key that is not a decodable TID keeps the blocker, undated.
                    entries.append(ConstellationBlockerEntry(record: record) ?? ConstellationBlockerEntry(did: record.did, blockedDate: ""))
                }
                await onProgress?(seenDIDs.count)
                cursor = response.cursor
                page += 1
            } while cursor != nil && page < Self.maxPages

            // The firehose keeps moving while we page: never report fewer records than we hold.
            let payload = ConstellationBlockerCache(total: max(total, entries.count), entries: entries)
            if let data = try? JSONEncoder().encode(payload) {
                await BlueskyAPICache.shared.write(accountDID: actorDID, url: cacheURL, data: data)
                AppLogger.performance.debug("Constellation cache WRITE for \(actorDID) (\(entries.count)/\(payload.total) entries)")
            }
            return payload
        } catch let cancellation as CancellationError {
            throw cancellation
        } catch {
            guard let staleFallback, !staleFallback.entries.isEmpty else { throw error }
            AppLogger.http.warning("Constellation blocked-by refresh failed (\(error.localizedDescription, privacy: .public)) — serving \(staleFallback.entries.count) cached entries")
            return staleFallback
        }
    }

    // MARK: - Private

    /// Fetches one page of the many-to-many join records (memberships with their record key).
    private func manyToMany(
        actorDID: String,
        cursor: String?
    ) async throws -> ConstellationManyToManyResponse {
        try Task.checkCancellation()
        guard let url = ConstellationEndpoints.manyToMany(subject: actorDID, cursor: cursor) else {
            throw BlueskyAPIError.invalidURL
        }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, httpResponse) = try await httpClient.data(for: request, source: "Constellation Many-To-Many")
        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            AppLogger.http.error("Constellation many-to-many records \(actorDID) → HTTP \(httpResponse.statusCode)")
            throw BlueskyAPIError.server("Constellation returned HTTP \(httpResponse.statusCode)")
        }
        guard let decoded = try? JSONDecoder().decode(ConstellationManyToManyResponse.self, from: data) else {
            let body = String(data: data, encoding: .utf8) ?? "empty"
            AppLogger.http.error("Constellation many-to-many records \(actorDID) → decode failed: \(body.prefix(200))")
            throw BlueskyAPIError.invalidResponse
        }
        AppLogger.http.info("Constellation many-to-many records \(actorDID): \(decoded.items.count) memberships")
        return decoded
    }

    /// Fetches one page of the many-to-many counts (list memberships grouped by list).
    private func manyToManyCounts(
        actorDID: String,
        cursor: String?
    ) async throws -> ConstellationManyToManyCountsResponse {
        try Task.checkCancellation()
        guard let url = ConstellationEndpoints.manyToManyCounts(subject: actorDID, cursor: cursor) else {
            throw BlueskyAPIError.invalidURL
        }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, httpResponse) = try await httpClient.data(for: request, source: "Constellation Many-To-Many")
        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            AppLogger.http.error("Constellation many-to-many \(actorDID) → HTTP \(httpResponse.statusCode)")
            throw BlueskyAPIError.server("Constellation returned HTTP \(httpResponse.statusCode)")
        }
        guard let decoded = try? JSONDecoder().decode(ConstellationManyToManyCountsResponse.self, from: data) else {
            let body = String(data: data, encoding: .utf8) ?? "empty"
            AppLogger.http.error("Constellation many-to-many \(actorDID) → decode failed: \(body.prefix(200))")
            throw BlueskyAPIError.invalidResponse
        }
        AppLogger.http.info("Constellation many-to-many \(actorDID): \(decoded.countsByOtherSubject.count) lists")
        return decoded
    }

    /// Fetches one page of the backlink index.
    private func backlinks(
        actorDID: String,
        limit: Int,
        cursor: String?
    ) async throws -> ConstellationBacklinksResponse {
        try Task.checkCancellation()
        guard let url = ConstellationEndpoints.backlinks(subject: actorDID, limit: limit, cursor: cursor) else {
            throw BlueskyAPIError.invalidURL
        }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, httpResponse) = try await httpClient.data(for: request, source: "Constellation Backlinks")
        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            AppLogger.http.error("Constellation backlinks \(actorDID) → HTTP \(httpResponse.statusCode)")
            throw BlueskyAPIError.server("Constellation returned HTTP \(httpResponse.statusCode)")
        }
        guard let decoded = try? JSONDecoder().decode(ConstellationBacklinksResponse.self, from: data) else {
            let body = String(data: data, encoding: .utf8) ?? "empty"
            AppLogger.http.error("Constellation backlinks \(actorDID) → decode failed: \(body.prefix(200))")
            throw BlueskyAPIError.invalidResponse
        }
        AppLogger.http.info("Constellation backlinks \(actorDID): \(decoded.records.count) records of \(decoded.total)")
        return decoded
    }

    /// Resolves profiles for a list of DIDs in parallel batches, ignoring failures:
    /// a blocker whose profile cannot be resolved still counts, it just renders
    /// without a handle.
    private func resolveProfilesBestEffort(dids: [String]) async -> [BlueskyActor] {
        guard !dids.isEmpty else { return [] }
        let chunks = stride(from: 0, to: dids.count, by: Self.profileBatchSize).map {
            Array(dids[$0 ..< min($0 + Self.profileBatchSize, dids.count)])
        }

        var actors: [BlueskyActor] = []
        var offset = 0
        while offset < chunks.count {
            let batch = Array(chunks[offset ..< min(offset + Self.profileBatchConcurrency, chunks.count)])
            offset += Self.profileBatchConcurrency

            await withTaskGroup(of: [BlueskyActor].self) { group in
                for chunk in batch {
                    group.addTask { [httpClient] in
                        do {
                            return try await LiveBlueskyClient.fetchProfileBatch(identifiers: chunk, httpClient: httpClient)
                        } catch {
                            AppLogger.performance.error("Constellation profile batch failed: \(error.localizedDescription, privacy: .public)")
                            return []
                        }
                    }
                }
                for await resolved in group {
                    actors.append(contentsOf: resolved)
                }
            }
        }
        return actors
    }
}
