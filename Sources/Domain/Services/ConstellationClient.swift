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
            scope: .shared,
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
                await BlueskyAPICache.shared.write(scope: .shared, url: cacheURL, data: data)
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
            scope: .shared,
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
                await BlueskyAPICache.shared.write(scope: .shared, url: cacheURL, data: data)
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

    /// One page of the blocker walk, emitted as the walk proceeds.
    struct BlockerPage: Sendable {
        /// Entries first seen on this page (DID + block date).
        let entries: [ConstellationBlockerEntry]
        /// Distinct blockers seen so far — the running `onProgress` value for this page.
        let seenCount: Int
        /// The index's own total for the subject.
        let total: Int
    }

    /// Actors blocking `actorDID`, with profiles resolved best-effort and each block
    /// dated from its record key; the index equivalent of the
    /// `single-blocklist` payload.
    ///
    /// Pagination and profile resolution overlap: each page's DIDs are handed to the
    /// resolver as soon as the page arrives, instead of waiting for the whole (sequential)
    /// walk to finish. `onActors` receives each resolved batch as it completes, so a caller
    /// can render the list incrementally rather than waiting for every profile.
    ///
    /// The fan-out stays bounded (`profileBatchConcurrency` batches in flight), so a large
    /// blocklist cannot flood the AppView. `totalCount` always comes from the index's own
    /// total, even while the actor list is still growing.
    func blockerActors(
        actorDID: String,
        onProgress: (@MainActor @Sendable (Int) async -> Void)?,
        onActors: (@MainActor @Sendable ([BlueskyActor]) async -> Void)? = nil
    ) async throws -> BlocklistResult {
        var collected: [BlueskyActor] = []
        var blockedDates: [String: String] = [:]
        var total = 0

        try await withThrowingTaskGroup(of: [BlueskyActor].self) { group in
            var inFlight = 0
            for try await page in blockerEntryPages(actorDID: actorDID) {
                total = page.total
                await onProgress?(page.seenCount)
                for entry in page.entries {
                    blockedDates[entry.did] = entry.blockedDate
                }
                guard !page.entries.isEmpty else { continue }

                for offset in stride(from: 0, to: page.entries.count, by: Self.profileBatchSize) {
                    let dids = page.entries[offset ..< min(offset + Self.profileBatchSize, page.entries.count)].map(\.did)
                    group.addTask { [httpClient] in
                        await Self.resolveProfileChunk(dids: dids, httpClient: httpClient)
                    }
                    inFlight += 1
                    // Keep at most one window of batches in flight: drain one as soon as
                    // the window is full, emitting it before fetching more.
                    if inFlight >= Self.profileBatchConcurrency, let batch = try await group.next() {
                        inFlight -= 1
                        let resolved = dated(batch, blockedDates: blockedDates)
                        collected.append(contentsOf: resolved)
                        await onActors?(resolved)
                    }
                }
            }
            // Drain the tail in completion order — each batch is emitted as it resolves.
            for try await batch in group {
                let resolved = dated(batch, blockedDates: blockedDates)
                collected.append(contentsOf: resolved)
                await onActors?(resolved)
            }
        }

        return BlocklistResult(actors: collected, totalCount: max(total, collected.count))
    }

    /// Stamps each resolved actor with the block date carried by its index entry, so the
    /// list can be ordered newest-block-first as it streams in.
    private func dated(_ batch: [BlueskyActor], blockedDates: [String: String]) -> [BlueskyActor] {
        batch.map { actor in
            var actor = actor
            if let raw = blockedDates[actor.did] {
                actor.blockedDate = parseDate(raw)
            }
            return actor
        }
    }

    /// Walks the blocker backlink index page by page, emitting each page as it arrives.
    ///
    /// Serves and refreshes the same on-disk payload as `blockerEntries`; a fresh cache hit
    /// is emitted as a single page, and the last good payload is served when the index fails
    /// mid-walk. Streaming the pages is what lets a caller resolve profiles while the
    /// (cursor-chained, therefore sequential) walk is still running.
    func blockerEntryPages(actorDID: String) -> AsyncThrowingStream<BlockerPage, Error> {
        AsyncThrowingStream { continuation in
            let task = Task { @MainActor [self] in
                let cacheURL = "constellation/blocked-by/\(actorDID)"
                var staleFallback: ConstellationBlockerCache?
                if let cached = await BlueskyAPICache.shared.read(
                    scope: .shared,
                    url: cacheURL,
                    maxAge: cacheMaxAge
                ),
                    let payload = try? JSONDecoder().decode(ConstellationBlockerCache.self, from: cached.data)
                {
                    if !cached.isStale {
                        AppLogger.performance.debug("Constellation cache HIT for \(actorDID) (\(payload.entries.count) entries)")
                        continuation.yield(BlockerPage(entries: payload.entries, seenCount: payload.entries.count, total: payload.total))
                        continuation.finish()
                        return
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
                        var pageEntries: [ConstellationBlockerEntry] = []
                        for record in response.records where seenDIDs.insert(record.did).inserted {
                            // A record key that is not a decodable TID keeps the blocker, undated.
                            pageEntries.append(ConstellationBlockerEntry(record: record) ?? ConstellationBlockerEntry(did: record.did, blockedDate: ""))
                        }
                        entries.append(contentsOf: pageEntries)
                        continuation.yield(BlockerPage(entries: pageEntries, seenCount: entries.count, total: total))
                        cursor = response.cursor
                        page += 1
                    } while cursor != nil && page < Self.maxPages

                    // The firehose keeps moving while we page: never report fewer records than we hold.
                    let payload = ConstellationBlockerCache(total: max(total, entries.count), entries: entries)
                    if let data = try? JSONEncoder().encode(payload) {
                        await BlueskyAPICache.shared.write(scope: .shared, url: cacheURL, data: data)
                        AppLogger.performance.debug("Constellation cache WRITE for \(actorDID) (\(entries.count)/\(payload.total) entries)")
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    guard let staleFallback, !staleFallback.entries.isEmpty else {
                        continuation.finish(throwing: error)
                        return
                    }
                    AppLogger.http.warning("Constellation blocked-by refresh failed (\(error.localizedDescription, privacy: .public)) — serving \(staleFallback.entries.count) cached entries")
                    continuation.yield(BlockerPage(entries: staleFallback.entries, seenCount: staleFallback.entries.count, total: staleFallback.total))
                    continuation.finish()
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Every blocker entry for `actorDID` (DID + block date), paginated and cached,
    /// together with the index's own total. Serves the last good payload when a
    /// refresh fails.
    func blockerEntries(
        actorDID: String,
        onProgress: (@MainActor @Sendable (Int) async -> Void)?
    ) async throws -> ConstellationBlockerCache {
        var entries: [ConstellationBlockerEntry] = []
        var total = 0
        for try await page in blockerEntryPages(actorDID: actorDID) {
            entries.append(contentsOf: page.entries)
            total = page.total
            await onProgress?(page.seenCount)
        }
        return ConstellationBlockerCache(total: max(total, entries.count), entries: entries)
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

    /// Resolves one profile batch (≤ `profileBatchSize` DIDs), serving already-cached
    /// profiles from `BlueskyAPICache` and fetching only the misses. Ignoring failures is
    /// deliberate: a blocker whose profile cannot be resolved still counts, it just renders
    /// without a handle.
    ///
    /// Public profile data is viewer-independent, so entries live in the `.shared` scope:
    /// every account reuses the same profile row, and removing a single account
    /// (`clear(for:)`) leaves them intact. A full account *switch* still clears everything,
    /// as the state-reset contract requires.
    nonisolated static func resolveProfileChunk(
        dids: [String],
        httpClient: HTTPClient
    ) async -> [BlueskyActor] {
        guard !dids.isEmpty else { return [] }

        var resolved: [BlueskyActor] = []
        var misses: [String] = []
        for did in dids {
            if let cached = await BlueskyAPICache.shared.read(
                scope: .shared,
                url: profileCacheURL(for: did),
                maxAge: BlueskyAPICache.DefaultTTL.profile
            ),
                let actor = try? JSONDecoder().decode(BlueskyActor.self, from: cached.data)
            {
                resolved.append(actor)
            } else {
                misses.append(did)
            }
        }

        guard !misses.isEmpty else { return resolved }

        // One retry: a transient AppView hiccup must not silently drop a blocker from the
        // list. A DID still unresolved after both attempts leaves the resolved list shorter
        // than the index total, which `RelationshipsView` surfaces as "Loaded X of Y".
        let maxAttempts = 2
        for attempt in 1 ... maxAttempts {
            do {
                let fetched = try await LiveBlueskyClient.fetchProfileBatch(identifiers: misses, httpClient: httpClient)
                for actor in fetched where !actor.did.isEmpty {
                    if let data = try? JSONEncoder().encode(actor) {
                        await BlueskyAPICache.shared.write(
                            scope: .shared,
                            url: profileCacheURL(for: actor.did),
                            data: data
                        )
                    }
                }
                return resolved + fetched
            } catch {
                guard attempt < maxAttempts else {
                    AppLogger.performance.error("Constellation profile batch failed after \(attempt) attempts: \(error.localizedDescription, privacy: .public)")
                    return resolved
                }
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
        return resolved
    }

    /// Cache key for one profile lookup — shared by the read and the write path so a
    /// resolved profile is reused on the next visit. Delegates to `BlueskyAPICache` so the
    /// blocker walk and the batch lookup cannot drift apart.
    nonisolated static func profileCacheURL(for did: String) -> String {
        BlueskyAPICache.profileKey(for: did)
    }
}
