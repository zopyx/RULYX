import Foundation

// MARK: - AppView list payloads

/// `app.bsky.graph.getLists` page. Only the fields the "Listed on" screen renders.
private struct AppViewListViewsResponse: Decodable {
    let lists: [AppViewListView]
    let cursor: String?
}

/// `app.bsky.graph.getList` response (the single-list variant).
private struct AppViewListResponse: Decodable {
    let list: AppViewListView
}

/// One `app.bsky.graph.defs#listView`. Codable so it can be cached per owner.
private struct AppViewListView: Codable, Sendable {
    let uri: String
    let name: String
    let description: String?
    let purpose: String?
    let indexedAt: String?
    let creator: Creator?

    struct Creator: Codable, Sendable {
        let did: String
    }
}

// MARK: - ListedOnListResolver

/// Resolves "which lists is this profile on" from public, third-party-free sources.
///
/// The app answers that question from the AT Protocol itself, in fewer requests than one
/// per list:
///
/// 1. **Memberships** come from the Constellation index — every `app.bsky.graph.listitem`
///    record whose `subject` is the profile, each carrying its list link and its record
///    key. A profile on ~150 lists needs 2 pages of 100.
/// 2. **List metadata** is fetched per list **owner**, not per list:
///    `app.bsky.graph.getLists?actor={owner}` returns up to 100 lists of that owner, so the
///    ~107 owners behind those 150 lists cost ~107 requests instead of 150. Results are
///    cached per owner under `appview/lists/{ownerDID}` — public data, shared by every
///    account that opens the same profile. All owners are queried **at once** (the requests
///    are independent), with transient AppView failures retried per owner.
/// 3. **Stragglers** (an owner with more than 100 lists, or a list record that has since
///    been deleted) are fetched in one parallel pass via
///    `app.bsky.graph.getList?list={uri}`. A list that no longer resolves is dropped: it
///    cannot be rendered, and no screen should invent a row for it.
///
/// The membership date (`dateAdded`) is decoded from the listitem record key, which is a
/// TID carrying its creation timestamp (`AtProtoTid`), accurate to ~1 s.
@MainActor
final class ListedOnListResolver {
    private let constellation: ConstellationClient
    private let httpClient: HTTPClient

    /// Age (seconds) after which a cached owner payload is treated as stale.
    /// Mutable so tests can force the stale branch deterministically.
    var cacheMaxAge: TimeInterval = BlueskyAPICache.DefaultTTL.list

    /// Attempts per AppView request before a list is given up on. Throttling and 5xx are
    /// retried (see `withTransientRetry`) — the fan-out queries every owner at once, so an
    /// unretried 429 would silently cost a list.
    private static let maxFetchAttempts = 3

    /// Backoff between retry attempts, multiplied by the attempt number.
    private static let retryBackoff: TimeInterval = 0.5

    /// Pages fetched per owner before a wanted list is treated as a straggler.
    private static let maxPagesPerOwner = 3

    /// Upper bound on straggler lookups, so a pathological profile cannot fan out.
    private static let maxStragglerLookups = 20

    private static let pageLimit = 100
    private static let appViewBaseURL = "https://public.api.bsky.app/xrpc/app.bsky.graph"

    init(constellation: ConstellationClient, httpClient: HTTPClient) {
        self.constellation = constellation
        self.httpClient = httpClient
    }

    // MARK: - Public API

    /// One `ListedOnListEntry` per list the profile is on, newest membership first.
    /// Fields match what the "Listed on" screen renders: name, description, list
    /// AT-URI, owner DID and the date the profile was added.
    ///
    /// `onProgress` reports the phase the walk is in and, once the memberships are known, how
    /// many of their lists have been resolved — the metadata phase makes one request per
    /// owning repo, so a profile on ~150 lists waits on ~100 requests.
    func entries(
        for actorDID: String,
        onProgress: (@MainActor @Sendable (ListedOnProgress) async -> Void)? = nil
    ) async throws -> [ListedOnListEntry] {
        await onProgress?(.memberships)
        let memberships = try await constellation.listedOnMemberships(actorDID: actorDID)
        guard !memberships.isEmpty else { return [] }

        // One metadata request per repo that holds several of the wanted lists.
        var wantedByOwner: [String: [ConstellationListedOnMembership]] = [:]
        for membership in memberships {
            guard let owner = Self.ownerDID(ofListURI: membership.listURI) else {
                AppLogger.http.warning("Listed-on: unresolvable list URI \(membership.listURI, privacy: .public)")
                continue
            }
            wantedByOwner[owner, default: []].append(membership)
        }

        let work = wantedByOwner
            .map { (owner: $0.key, wanted: Set($0.value.map(\.listURI))) }
            .sorted { $0.owner < $1.owner }
        let listURIs = Set(memberships.map(\.listURI))
        let totalLists = listURIs.count
        await onProgress?(.lists(resolved: 0, total: totalLists))

        // Every owner is queried at once. The requests are independent lookups against the
        // public AppView (one per repo), and a profile on ~150 lists sits behind ~100 owners:
        // batching them by 5 turned that into ~20 sequential rounds and dominated the screen's
        // load time. Throttled responses are retried per owner instead of being tolerated
        // (see `withTransientRetry`), so the wide fan-out cannot silently drop a list.
        var views: [String: AppViewListView] = [:]
        await withTaskGroup(of: (String, [AppViewListView]).self) { group in
            for item in work {
                group.addTask { [self] in
                    await (item.owner, lists(ownerDID: item.owner, wanted: item.wanted))
                }
            }
            for await (owner, ownerLists) in group {
                for view in ownerLists where wantedByOwner[owner]?.contains(where: { $0.listURI == view.uri }) == true {
                    views[view.uri] = view
                }
                // One report per owner, so the bar keeps moving while they land.
                await onProgress?(.lists(resolved: listURIs.filter { views[$0] != nil }.count, total: totalLists))
            }
        }

        let missing = memberships.filter { views[$0.listURI] == nil }
        if !missing.isEmpty {
            let stragglers = try await stragglerViews(uris: missing.map(\.listURI))
            for (uri, view) in stragglers {
                views[uri] = view
            }
        }
        // The stragglers can still move the bar; the count excludes deleted lists on purpose.
        await onProgress?(.lists(resolved: listURIs.filter { views[$0] != nil }.count, total: totalLists))

        let unresolved = memberships.filter { views[$0.listURI] == nil }
        if !unresolved.isEmpty {
            AppLogger.http.warning("Listed-on: \(unresolved.count) of \(memberships.count) memberships did not resolve (list deleted or owner unavailable)")
        }

        // A profile can hold more than one membership record per list (re-added); the
        // newest one wins so the screen shows one row per list.
        var newestByList: [String: ConstellationListedOnMembership] = [:]
        for membership in memberships where views[membership.listURI] != nil {
            if let existing = newestByList[membership.listURI], existing.recordKey >= membership.recordKey {
                continue
            }
            newestByList[membership.listURI] = membership
        }

        let entries = newestByList.values.compactMap { membership -> ListedOnListEntry? in
            guard let view = views[membership.listURI] else { return nil }
            return ListedOnListEntry(
                name: view.name,
                description: view.description,
                did: view.creator?.did ?? Self.ownerDID(ofListURI: membership.listURI) ?? "",
                url: view.uri,
                // The list view carries no `createdAt`; `indexedAt` is the only timestamp
                // the AppView exposes. The screen sorts and displays `dateAdded`, not this.
                createdDate: view.indexedAt ?? "",
                dateAdded: Self.dateAdded(fromRecordKey: membership.recordKey)
            )
        }
        return entries.sorted { Self.sortKey($0) > Self.sortKey($1) }
    }

    // MARK: - Owner metadata

    /// All lists of `ownerDID` the cache and the AppView can supply, stopping early once
    /// every wanted URI is present. Best effort: a failure yields what is already known,
    /// because the detail screen is an enrichment of the index walk, not its precondition.
    private func lists(ownerDID: String, wanted: Set<String>) async -> [AppViewListView] {
        let cacheURL = "appview/lists/\(ownerDID)"
        var cached: [AppViewListView] = []
        var cacheIsFresh = false
        if let entry = await BlueskyAPICache.shared.read(accountDID: ownerDID, url: cacheURL, maxAge: cacheMaxAge),
           let payload = try? JSONDecoder().decode([AppViewListView].self, from: entry.data)
        {
            cached = payload
            cacheIsFresh = !entry.isStale
        }

        if cacheIsFresh, wanted.isSubset(of: Set(cached.map(\.uri))) {
            AppLogger.performance.debug("Listed-on: owner cache HIT for \(ownerDID) (\(cached.count) lists)")
            return cached
        }

        var lists = cached
        var known = Set(cached.map(\.uri))
        var cursor: String?
        do {
            var page = 0
            repeat {
                let response = try await withTransientRetry { try await ownerPage(ownerDID: ownerDID, cursor: cursor) }
                for view in response.lists where known.insert(view.uri).inserted {
                    lists.append(view)
                }
                cursor = response.cursor
                page += 1
            } while cursor != nil && page < Self.maxPagesPerOwner && !wanted.isSubset(of: known)

            if let data = try? JSONEncoder().encode(lists) {
                await BlueskyAPICache.shared.write(accountDID: ownerDID, url: cacheURL, data: data)
            }
        } catch let cancellation as CancellationError {
            _ = cancellation
        } catch {
            AppLogger.http.warning("Listed-on: owner \(ownerDID) unavailable (\(error.localizedDescription, privacy: .public)) — using \(cached.count) cached lists")
        }
        return lists
    }

    private func ownerPage(ownerDID: String, cursor: String?) async throws -> AppViewListViewsResponse {
        var components = URLComponents(string: "\(Self.appViewBaseURL).getLists")
        var queryItems = [
            URLQueryItem(name: "actor", value: ownerDID),
            URLQueryItem(name: "limit", value: String(Self.pageLimit)),
        ]
        if let cursor, !cursor.isEmpty {
            queryItems.append(URLQueryItem(name: "cursor", value: cursor))
        }
        components?.queryItems = queryItems
        guard let url = components?.url else { throw BlueskyAPIError.invalidURL }
        return try await fetch(AppViewListViewsResponse.self, url: url, source: "AppView Lists")
    }

    // MARK: - Stragglers

    /// Resolves individual lists in one parallel pass (bounded by `maxStragglerLookups`).
    /// Returns the ones that answered; everything else is left unresolved by design.
    private func stragglerViews(uris: [String]) async throws -> [String: AppViewListView] {
        let bounded = Array(Set(uris)).sorted().prefix(Self.maxStragglerLookups)
        guard !bounded.isEmpty else { return [:] }

        var resolved: [String: AppViewListView] = [:]
        await withTaskGroup(of: (String, AppViewListView?).self) { group in
            for uri in bounded {
                group.addTask { [self] in await (uri, singleList(uri: uri)) }
            }
            for await (uri, view) in group {
                if let view {
                    resolved[uri] = view
                }
            }
        }
        return resolved
    }

    private func singleList(uri: String) async -> AppViewListView? {
        var components = URLComponents(string: "\(Self.appViewBaseURL).getList")
        components?.queryItems = [
            URLQueryItem(name: "list", value: uri),
            URLQueryItem(name: "limit", value: "1"),
        ]
        guard let url = components?.url else { return nil }
        do {
            return try await withTransientRetry {
                try await fetch(AppViewListResponse.self, url: url, source: "AppView List")
            }.list
        } catch {
            AppLogger.http.warning("Listed-on: list \(uri, privacy: .public) did not resolve (\(error.localizedDescription, privacy: .public))")
            return nil
        }
    }

    // MARK: - Helpers

    private func fetch<T: Decodable>(_: T.Type, url: URL, source: String) async throws -> T {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, httpResponse) = try await httpClient.data(for: request, source: source)
        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            throw AppViewError.status(httpResponse.statusCode)
        }
        guard let decoded = try? JSONDecoder().decode(T.self, from: data) else {
            throw AppViewError.malformed
        }
        return decoded
    }

    /// Runs `operation`, retrying transient AppView failures (throttling, 5xx) with a short
    /// backoff. Every owner is queried at once, so one dropped response would silently cost a
    /// list — the retry is what makes that fan-out safe.
    private func withTransientRetry<T>(_ operation: () async throws -> T) async rethrows -> T {
        var attempt = 1
        while true {
            do {
                return try await operation()
            } catch let error as AppViewError where error.isTransient && attempt < Self.maxFetchAttempts {
                let delay = Self.retryBackoff * Double(attempt)
                AppLogger.http.warning(
                    "Listed-on: transient AppView failure (\(error.localizedDescription, privacy: .public)) — retry \(attempt + 1)/\(Self.maxFetchAttempts) in \(delay, privacy: .public)s"
                )
                try await Task.sleep(for: .seconds(delay))
                attempt += 1
            }
        }
    }

    /// `at://{ownerDID}/app.bsky.graph.list/{rkey}` → `{ownerDID}`.
    private static func ownerDID(ofListURI uri: String) -> String? {
        let parts = uri.split(separator: "/", omittingEmptySubsequences: true)
        guard parts.count >= 3, parts[0] == "at:" else { return nil }
        return String(parts[1])
    }

    /// The membership date, decoded from the listitem record key (a TID).
    private static func dateAdded(fromRecordKey recordKey: String) -> String {
        guard let date = AtProtoTid.date(fromRecordKey: recordKey) else { return "" }
        return SharedDateFormatters.formatISO8601(date)
    }

    /// Newest membership first; ties broken by name so the order is stable.
    private static func sortKey(_ entry: ListedOnListEntry) -> String {
        "\(entry.dateAdded)|\(entry.name)"
    }
}

// MARK: - AppViewError

/// Failure modes of the AppView metadata fetch. Typed so the retry can tell a throttle or a
/// server hiccup (worth retrying) from the server's final answer.
private enum AppViewError: Error, LocalizedError {
    /// Non-2xx response from the AppView.
    case status(Int)
    /// 2xx response whose body did not match the expected shape.
    case malformed

    /// Throttling and 5xx are transient; any other status is the server's answer.
    var isTransient: Bool {
        guard case let .status(code) = self else { return false }
        return code == 429 || (500 ..< 600).contains(code)
    }

    var errorDescription: String? {
        switch self {
        case let .status(code): "AppView returned HTTP \(code)"
        case .malformed: "AppView returned an undecodable response"
        }
    }
}
