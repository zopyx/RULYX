import Foundation

/// Blocklist actors plus the source's total count (own repo or backlink index).
struct BlocklistResult {
    let actors: [BlueskyActor]
    let totalCount: Int
}

/// Response type for the `app.bsky.feed.searchPosts` endpoint.
struct SearchPostsResponse: Decodable {
    let cursor: String?
    let hitsTotal: Int?
    let posts: [RichPost]
}

/// Primary API client for Bluesky network operations. Provides authenticated access to
/// all major AT Protocol lexicons used by the app: lists, profiles, feeds, posts,
/// notifications, chat, moderation reports, and blocklist reads.
///
/// Conforms to `BlueskyAuthenticating`, `BlueskyListServicing`, and `BlueskyProfileInspecting`.
///
/// This class is marked `@MainActor` and all state mutations happen on the main actor.
/// **Note (P2-19):** This is intentionally a God class (2063 lines, 9 protocols) for now — splitting
/// into `ListClient`/`ProfileClient`/`FeedClient` actors is tracked as follow-up. Internal helpers
/// are grouped by `// MARK: -` sections; prefer adding new endpoints to the correct MARK section
/// and keeping call sites behind the protocol (`BlueskyListServicing` etc.) so the future split is mechanical.
@MainActor
class LiveBlueskyClient: ObservableObject,
    BlueskyAuthenticating,
    BlueskyListServicing,
    BlueskyProfileInspecting,
    BlueskyAuthServicing,
    BlueskyFeedServicing,
    BlueskyPostServicing,
    BlueskySocialServicing,
    BlueskyModerationServicing,
    BlueskyBlocklistServicing,
    BlueskyNotificationServicing,
    BlueskyIdentityServicing,
    BlueskyMediaServicing
{
    /// The AT Protocol service DID for the Bluesky App View proxy.
    private static let bskyAppViewServiceDID = "did:web:api.bsky.app#bsky_appview"
    /// The default base URL for the Bluesky PDS.
    private let baseURL: URL
    /// Internal (not private): `LiveBlueskyClient+Blocklist.swift` reads through it.
    let httpClient: HTTPClient
    /// HTTP client for AppView-proxied PDS requests. Pins the app's fixed API hosts via
    /// `HTTPClient.defaultPinnedHashes`; a host without a matching pin in the chain is
    /// **rejected** by `CertificatePinningDelegate` (not passed through), which surfaces
    /// as a cancelled request — so every host reached through this client needs its pins
    /// listed there.
    private let appViewHTTPClient = HTTPClient(session: URLSession.shared, pinnedHashes: HTTPClient.defaultPinnedHashes)
    private let session: URLSession
    private let requestExecutor: BlueskyRequestExecuting
    private let sessionService: BlueskySessionServicing
    /// Second data source for "Blocked by" — the Constellation backlink index.
    /// Internal so tests can shrink its cache age to exercise the stale branch.
    let constellation: ConstellationClient
    /// Source for "Blocking" — the account's own repo, read from its PDS.
    /// Internal so tests can shrink its cache age to exercise the stale branch.
    let repo: AtProtoRepoClient
    /// Resolves the "Listed on" screen from the index plus per-owner AppView metadata.
    /// Internal so tests can shrink its cache age.
    let listedOnResolver: ListedOnListResolver

    // MARK: - Init

    init(
        baseURL: URL = .bskySocial,
        httpClient: HTTPClient? = nil,
        keychain: KeychainServicing = KeychainService(),
        requestExecutor: BlueskyRequestExecuting? = nil,
        sessionService: BlueskySessionServicing? = nil,
        repoClient: AtProtoRepoClient? = nil
    ) {
        self.baseURL = baseURL
        let clientSession = URLSession.shared
        session = clientSession
        self.httpClient = httpClient ?? HTTPClient(session: clientSession, pinnedHashes: HTTPClient.defaultPinnedHashes)
        constellation = ConstellationClient(httpClient: self.httpClient)
        // Deliberately unpinned: it talks to the account's PDS, whose host varies per
        // account and is not (and should not be) part of the pinned host set. Tests
        // inject their own client, usually the same mock session as `httpClient`.
        repo = repoClient ?? AtProtoRepoClient(httpClient: httpClient ?? HTTPClient(session: clientSession))
        // List metadata comes from the public AppView, which is a pinned host — so this
        // resolver uses the AppView client (or the injected one, in tests).
        listedOnResolver = ListedOnListResolver(constellation: constellation, httpClient: httpClient ?? appViewHTTPClient)
        let executor = requestExecutor ?? BlueskyRequestExecutor(baseURL: baseURL, httpClient: self.httpClient)
        self.requestExecutor = executor
        self.sessionService = sessionService ?? BlueskySessionService(
            baseURL: baseURL,
            requestExecutor: executor,
            keychain: keychain
        )
    }

    // MARK: - Cache

    /// Clears all in-memory and on-disk URL cache responses plus the session cache and API cache.
    /// Awaits `BlueskyAPICache` clearing so callers (e.g. account switch) observe a fully cleared state.
    func clearAllCaches() async {
        session.configuration.urlCache?.removeAllCachedResponses()
        URLCache.shared.removeAllCachedResponses()
        sessionService.clearSessionCache()
        await BlueskyAPICache.shared.clearAll()
    }

    /// Legacy synchronous wrapper — retained for protocol conformance only.
    /// Prefer `clearAllCaches() async` for ordering-sensitive call sites.
    func clearCache() {
        session.configuration.urlCache?.removeAllCachedResponses()
        URLCache.shared.removeAllCachedResponses()
        sessionService.clearSessionCache()
        Task { await BlueskyAPICache.shared.clearAll() }
    }

    // MARK: - Authentication & Session

    /// Authenticates against the Bluesky PDS using a handle and app password.
    func authenticate(handle: String, appPassword: String, entrywayURL: URL? = nil, authFactorToken: String? = nil) async throws -> BlueskySession {
        try await sessionService.authenticate(handle: handle, appPassword: appPassword, entrywayURL: entrywayURL, authFactorToken: authFactorToken)
    }

    /// Persists the session token for an account to the Keychain.
    func persistSession(_ authSession: BlueskySession, for account: AppAccount) async throws {
        try await sessionService.persistSession(authSession, for: account)
    }

    /// Removes a persisted session from the Keychain.
    func deletePersistedSession(for account: AppAccount) throws {
        try sessionService.deletePersistedSession(for: account)
    }

    /// Restores sessions for all saved accounts from the Keychain.
    func restoreSessions(for accounts: [AppAccount]) async {
        await sessionService.restoreSessions(for: accounts)
    }

    // MARK: - List Operations

    /// Protocol conformance — delegates to cached variant.
    func fetchLists(for account: AppAccount, appPassword: String?) async throws -> [BlueskyList] {
        try await fetchLists(for: account, appPassword: appPassword, forceRefresh: false)
    }

    /// Fetches all lists owned by the authenticated account.
    /// Uses `BlueskyAPICache`; set `forceRefresh = true` to bypass cache.
    func fetchLists(for account: AppAccount, appPassword: String?, forceRefresh: Bool = false) async throws -> [BlueskyList] {
        // Cache check
        if !forceRefresh, let did = account.did {
            let cacheURL = "app.bsky.graph.getLists"
            if let cached = await BlueskyAPICache.shared.read(accountDID: did, url: cacheURL, maxAge: BlueskyAPICache.DefaultTTL.list) {
                if let lists = try? JSONDecoder().decode([BlueskyList].self, from: cached.data) {
                    if !cached.isStale {
                        return lists
                    }
                    // Stale: return cached but fire background refresh (strong capture — self is long-lived singleton;
                    // weak would silently drop refresh if LiveBlueskyClient were deallocated, leaving stale forever).
                    Task { [self] in
                        _ = try? await fetchListsNetwork(account: account, appPassword: appPassword)
                    }
                    return lists
                }
            }
        }

        return try await fetchListsNetwork(account: account, appPassword: appPassword)
    }

    /// Direct network fetch for lists, bypassing cache.
    private func fetchListsNetwork(account: AppAccount, appPassword: String?) async throws -> [BlueskyList] {
        let response: GetListsResponse = try await sessionService.performAuthenticatedRequest(
            account: account,
            appPassword: appPassword
        ) { authSession in
            try await requestExecutor.send(
                path: "app.bsky.graph.getLists",
                method: "GET",
                queryItems: [
                    URLQueryItem(name: "actor", value: authSession.did),
                    URLQueryItem(name: "limit", value: "100"),
                ],
                accessToken: authSession.accessJWT,
                hostURL: authSession.pdsURL
            )
        }

        let lists = response.lists.map { item in
            BlueskyList(
                id: item.uri,
                name: item.name,
                description: item.description ?? item.purpose.displayTitle,
                memberCount: item.listItemCount,
                kind: item.purpose.kind,
                avatarURL: URL(string: item.avatar ?? ""),
                cid: item.cid
            )
        }

        // Write to cache
        if let did = account.did, let encoded = try? JSONEncoder().encode(lists) {
            await BlueskyAPICache.shared.write(accountDID: did, url: "app.bsky.graph.getLists", data: encoded)
        }

        return lists
    }

    /// Fetches all lists owned by a specific actor (by DID or handle).
    func fetchActorLists(actor: String, account: AppAccount, appPassword: String?) async throws -> [BlueskyList] {
        let response: GetListsResponse = try await sessionService.performAuthenticatedRequest(
            account: account,
            appPassword: appPassword
        ) { authSession in
            try await requestExecutor.send(
                path: "app.bsky.graph.getLists",
                method: "GET",
                queryItems: [
                    URLQueryItem(name: "actor", value: actor),
                    URLQueryItem(name: "limit", value: "100"),
                ],
                accessToken: authSession.accessJWT,
                hostURL: authSession.pdsURL
            )
        }

        return response.lists.map { item in
            BlueskyList(
                id: item.uri,
                name: item.name,
                description: item.description ?? item.purpose.displayTitle,
                memberCount: item.listItemCount,
                kind: item.purpose.kind,
                avatarURL: URL(string: item.avatar ?? ""),
                cid: item.cid
            )
        }
    }

    /// Fetches a single list by URI via `app.bsky.graph.getList`.
    /// Returns `nil` if the list cannot be resolved.
    func fetchList(uri: String, account: AppAccount, appPassword: String?) async throws -> BlueskyList? {
        let response: GetListResponse = try await sessionService.performAuthenticatedRequest(
            account: account,
            appPassword: appPassword
        ) { authSession in
            let queryItems = [
                URLQueryItem(name: "list", value: uri),
                URLQueryItem(name: "limit", value: "1"),
            ]

            return try await requestExecutor.send(
                path: "app.bsky.graph.getList",
                method: "GET",
                queryItems: queryItems,
                accessToken: authSession.accessJWT,
                hostURL: authSession.pdsURL
            )
        }

        guard let list = response.list else { return nil }
        return BlueskyList(
            id: list.uri,
            name: list.name,
            description: list.description ?? "",
            memberCount: list.listItemCount,
            kind: list.purpose.kind,
            avatarURL: URL(string: list.avatar ?? ""),
            cid: list.cid
        )
    }

    /// Fetches all members of a list with automatic pagination (capped at 100 pages to prevent infinite loops on buggy PDS).
    func fetchListMembers(list: BlueskyList, account: AppAccount, appPassword: String?) async throws -> [BlueskyListMember] {
        var allMembers: [BlueskyListMember] = []
        var cursor: String?
        var previousCursor: String?
        var pageCount = 0
        let maxPages = 100

        repeat {
            let page = try await fetchListMembersPage(list: list, cursor: cursor, account: account, appPassword: appPassword)
            allMembers.append(contentsOf: page.members)
            previousCursor = cursor
            cursor = page.cursor
            pageCount += 1
            if pageCount >= maxPages {
                break
            }
            if let cur = cursor, cur == previousCursor {
                break
            }
        } while cursor != nil

        return allMembers
    }

    /// Fetches a single page of list members.
    /// - Parameters:
    ///   - list: The list to fetch members from.
    ///   - cursor: Pagination cursor. `nil` for the first page.
    /// - Returns: A page of members and the next cursor.
    func fetchListMembersPage(list: BlueskyList, cursor: String?, account: AppAccount, appPassword: String?) async throws -> PagedListMembers {
        let response: GetListResponse = try await sessionService.performAuthenticatedRequest(
            account: account,
            appPassword: appPassword
        ) { authSession in
            var queryItems = [
                URLQueryItem(name: "list", value: list.id),
                URLQueryItem(name: "limit", value: "100"),
            ]
            if let cursor {
                queryItems.append(URLQueryItem(name: "cursor", value: cursor))
            }

            return try await requestExecutor.send(
                path: "app.bsky.graph.getList",
                method: "GET",
                queryItems: queryItems,
                accessToken: authSession.accessJWT,
                hostURL: authSession.pdsURL
            )
        }

        return PagedListMembers(
            members: response.items.map {
                BlueskyListMember(
                    recordURI: $0.uri,
                    actor: BlueskyActor(
                        did: $0.subject.did,
                        handle: $0.subject.handle,
                        displayName: $0.subject.displayName,
                        avatarURL: URL(string: $0.subject.avatar ?? "")
                    ),
                    createdAt: parseDate($0.createdAt),
                    viewerState: mapViewerState($0.subject.viewer)
                )
            },
            cursor: response.cursor,
            memberCount: response.list?.listItemCount
        )
    }

    /// Fetches the metadata and creator for a list (without fetching all members).
    /// Returns the list object and the creator's actor information.
    /// - Throws: `BlueskyAPIError.server("List not found")` if the list does not exist.
    func fetchListDetails(uri: String, account: AppAccount, appPassword: String?) async throws -> (list: BlueskyList, creator: BlueskyActor) {
        let response: GetListResponse = try await sessionService.performAuthenticatedRequest(
            account: account,
            appPassword: appPassword
        ) { authSession in
            try await sendAppViewRequest(
                path: "app.bsky.graph.getList",
                method: "GET",
                queryItems: [
                    URLQueryItem(name: "list", value: uri),
                    URLQueryItem(name: "limit", value: "1"),
                ],
                accessToken: authSession.accessJWT,
                pdsURL: authSession.pdsURL
            )
        }

        guard let list = response.list else {
            throw BlueskyAPIError.server("List not found")
        }

        let blueskyList = BlueskyList(
            id: list.uri,
            name: list.name,
            description: list.description ?? "",
            memberCount: list.listItemCount,
            kind: list.purpose.kind,
            avatarURL: URL(string: list.avatar ?? ""),
            cid: list.cid
        )

        let creator = BlueskyActor(
            did: list.creator?.did ?? "",
            handle: list.creator?.handle ?? "unknown",
            displayName: list.creator?.displayName,
            avatarURL: URL(string: list.creator?.avatar ?? "")
        )

        return (blueskyList, creator)
    }

    /// Fetches all moderation lists the account has subscribed to (muted).
    /// Returns them sorted by subscription date descending, then alphabetically. Capped at 50 pages.
    func fetchSubscribedModerationLists(account: AppAccount, appPassword: String?) async throws -> [SubscribedListInfo] {
        var cursor: String?
        var allLists: [SubscribedListInfo] = []
        var previousCursor: String?
        var pageCount = 0
        let maxPages = 50

        repeat {
            let response: PagedListsResponse = try await sessionService.performAuthenticatedRequest(
                account: account,
                appPassword: appPassword
            ) { authSession in
                var queryItems = [URLQueryItem(name: "limit", value: "100")]
                if let cursor {
                    queryItems.append(URLQueryItem(name: "cursor", value: cursor))
                }
                return try await sendAppViewRequest(
                    path: "app.bsky.graph.getListMutes",
                    method: "GET",
                    queryItems: queryItems,
                    accessToken: authSession.accessJWT,
                    pdsURL: authSession.pdsURL
                )
            }

            allLists.append(contentsOf: response.lists.map(mapSubscribedListInfo(from:)))
            previousCursor = cursor
            cursor = response.cursor
            pageCount += 1
            if pageCount >= maxPages {
                break
            }
            if let cur = cursor, cur == previousCursor {
                break
            }
        } while cursor != nil

        return allLists.sorted { lhs, rhs in
            switch (lhs.subscribedAt, rhs.subscribedAt) {
            case let (left?, right?):
                left > right
            case (.some, .none):
                true
            case (.none, .some):
                false
            case (.none, .none):
                lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
        }
    }

    /// Checks whether the account is subscribed to (muted) a specific moderation list.
    func isSubscribedToModerationList(_ listURI: String, account: AppAccount, appPassword: String?) async throws -> Bool {
        let response: GetListResponse = try await sessionService.performAuthenticatedRequest(
            account: account,
            appPassword: appPassword
        ) { authSession in
            try await sendAppViewRequest(
                path: "app.bsky.graph.getList",
                method: "GET",
                queryItems: [
                    URLQueryItem(name: "list", value: listURI),
                    URLQueryItem(name: "limit", value: "1"),
                ],
                accessToken: authSession.accessJWT,
                pdsURL: authSession.pdsURL
            )
        }

        return response.list?.viewer?.muted ?? false
    }

    /// Subscribes to (mutes) a moderation list.
    func subscribeToModerationList(_ listURI: String, account: AppAccount, appPassword: String?) async throws {
        let _: EmptyResponse = try await sessionService.performAuthenticatedRequest(
            account: account,
            appPassword: appPassword
        ) { authSession in
            try await sendAppViewRequest(
                path: "app.bsky.graph.muteActorList",
                method: "POST",
                queryItems: [],
                body: ListReferenceRequest(list: listURI),
                accessToken: authSession.accessJWT,
                pdsURL: authSession.pdsURL
            )
        }
    }

    /// Unsubscribes from (unmutes) a moderation list.
    func unsubscribeFromModerationList(_ listURI: String, account: AppAccount, appPassword: String?) async throws {
        let _: EmptyResponse = try await sessionService.performAuthenticatedRequest(
            account: account,
            appPassword: appPassword
        ) { authSession in
            try await sendAppViewRequest(
                path: "app.bsky.graph.unmuteActorList",
                method: "POST",
                queryItems: [],
                body: ListReferenceRequest(list: listURI),
                accessToken: authSession.accessJWT,
                pdsURL: authSession.pdsURL
            )
        }
    }

    // MARK: - Actor Search

    /// Searches for actors using the typeahead endpoint (returns first page only).
    func searchActors(query: String, account: AppAccount, appPassword: String?) async throws -> [BlueskyActor] {
        let page = try await searchActorsPage(query: query, cursor: nil, account: account, appPassword: appPassword)
        return page.actors
    }

    /// Searches for actors using the full search endpoint (non-typeahead).
    func searchActorsFull(query: String, account: AppAccount, appPassword: String?) async throws -> [BlueskyActor] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return [] }

        struct SearchResponse: Decodable {
            let cursor: String?
            let actors: [ProfileViewDetailed]
        }

        let response: SearchResponse = try await sessionService.performAuthenticatedRequest(
            account: account,
            appPassword: appPassword
        ) { authSession in
            let queryItems = [
                URLQueryItem(name: "q", value: trimmedQuery),
                URLQueryItem(name: "limit", value: "25"),
            ]
            return try await requestExecutor.send(
                path: "app.bsky.actor.searchActors",
                method: "GET",
                queryItems: queryItems,
                accessToken: authSession.accessJWT,
                hostURL: authSession.pdsURL
            )
        }

        return response.actors.map {
            BlueskyActor(
                did: $0.did,
                handle: $0.handle,
                displayName: $0.displayName,
                avatarURL: URL(string: $0.avatar ?? ""),
                description: $0.description,
                viewerState: mapViewerState($0.viewer)
            )
        }
    }

    /// Searches for actors with pagination support (typeahead endpoint).
    /// Returns `PagedActorSearch` with actors and cursor for the next page.
    func searchActorsPage(query: String, cursor: String?, account: AppAccount, appPassword: String?) async throws -> PagedActorSearch {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            return PagedActorSearch(actors: [], cursor: nil)
        }

        let response: SearchActorsResponse = try await sessionService.performAuthenticatedRequest(
            account: account,
            appPassword: appPassword
        ) { authSession in
            var queryItems = [
                URLQueryItem(name: "q", value: trimmedQuery),
                URLQueryItem(name: "limit", value: "25"),
            ]
            if let cursor {
                queryItems.append(URLQueryItem(name: "cursor", value: cursor))
            }

            return try await requestExecutor.send(
                path: "app.bsky.actor.searchActorsTypeahead",
                method: "GET",
                queryItems: queryItems,
                accessToken: authSession.accessJWT,
                hostURL: authSession.pdsURL
            )
        }

        return PagedActorSearch(
            actors: response.actors.map {
                BlueskyActor(
                    did: $0.did,
                    handle: $0.handle,
                    displayName: $0.displayName,
                    avatarURL: URL(string: $0.avatar ?? ""),
                    description: $0.description,
                    viewerState: mapViewerState($0.viewer)
                )
            },
            cursor: response.cursor
        )
    }

    // MARK: - List Membership Mutations

    /// Adds an actor (by DID) to a list. Returns the record URI of the new list item.
    func addActor(did actorDID: String, to list: BlueskyList, account: AppAccount, appPassword: String?) async throws -> String {
        let response: CreateRecordResponse = try await sessionService.performAuthenticatedRequest(
            account: account,
            appPassword: appPassword
        ) { authSession in
            let body = CreateRecordRequest(
                repo: authSession.did,
                collection: "app.bsky.graph.listitem",
                record: ListItemRecord(createdAt: ISO8601DateFormatter().string(from: .now), list: list.id, subject: actorDID)
            )

            return try await requestExecutor.send(
                path: "com.atproto.repo.createRecord",
                method: "POST",
                queryItems: [],
                body: body,
                accessToken: authSession.accessJWT,
                hostURL: authSession.pdsURL
            )
        }
        return response.uri
    }

    /// Removes a member from a list by their list item record URI.
    func removeMember(recordURI: String, account: AppAccount, appPassword: String?) async throws {
        let record = try parseATURI(recordURI)
        let _: EmptyResponse = try await sessionService.performAuthenticatedRequest(
            account: account,
            appPassword: appPassword
        ) { authSession in
            let body = DeleteRecordRequest(repo: authSession.did, collection: record.collection, rkey: record.rkey)
            return try await requestExecutor.send(
                path: "com.atproto.repo.deleteRecord",
                method: "POST",
                queryItems: [],
                body: body,
                accessToken: authSession.accessJWT,
                hostURL: authSession.pdsURL
            )
        }
    }

    /// Creates a new list (curation or moderation). Returns the created `BlueskyList`.
    func createList(name: String, description: String, kind: BlueskyList.Kind, account: AppAccount, appPassword: String?) async throws -> BlueskyList {
        let response: CreateRecordResponse = try await sessionService.performAuthenticatedRequest(
            account: account,
            appPassword: appPassword
        ) { authSession in
            let body = CreateGenericRecordRequest(
                repo: authSession.did,
                collection: "app.bsky.graph.list",
                record: ListRecord(
                    type: "app.bsky.graph.list",
                    purpose: kind.purposeIdentifier,
                    name: name,
                    description: description.isEmpty ? nil : description,
                    createdAt: ISO8601DateFormatter().string(from: .now)
                )
            )
            return try await requestExecutor.send(
                path: "com.atproto.repo.createRecord",
                method: "POST",
                queryItems: [],
                body: body,
                accessToken: authSession.accessJWT,
                hostURL: authSession.pdsURL
            )
        }

        return BlueskyList(id: response.uri, name: name, description: description, memberCount: 0, kind: kind, cid: response.cid)
    }

    /// Deletes a list and all its members.
    func deleteList(list: BlueskyList, account: AppAccount, appPassword: String?) async throws {
        let record = try parseATURI(list.id)
        let _: EmptyResponse = try await sessionService.performAuthenticatedRequest(
            account: account,
            appPassword: appPassword
        ) { authSession in
            let body = DeleteRecordRequest(repo: authSession.did, collection: record.collection, rkey: record.rkey)
            return try await requestExecutor.send(
                path: "com.atproto.repo.deleteRecord",
                method: "POST",
                queryItems: [],
                body: body,
                accessToken: authSession.accessJWT,
                hostURL: authSession.pdsURL
            )
        }
    }

    /// Updates a list's name and description via `com.atproto.repo.putRecord`.
    func updateListMetadata(list: BlueskyList, title: String, description: String, account: AppAccount, appPassword: String?) async throws -> BlueskyList {
        let record = try parseATURI(list.id)
        let _: CreateRecordResponse = try await sessionService.performAuthenticatedRequest(
            account: account,
            appPassword: appPassword
        ) { authSession in
            let body = PutRecordRequest(
                repo: authSession.did,
                collection: record.collection,
                rkey: record.rkey,
                record: ListRecord(
                    type: "app.bsky.graph.list",
                    purpose: list.kind.purposeIdentifier,
                    name: title,
                    description: description.isEmpty ? nil : description,
                    createdAt: ISO8601DateFormatter().string(from: .now)
                )
            )

            return try await requestExecutor.send(
                path: "com.atproto.repo.putRecord",
                method: "POST",
                queryItems: [],
                body: body,
                accessToken: authSession.accessJWT,
                hostURL: authSession.pdsURL
            )
        }

        return BlueskyList(id: list.id, name: title, description: description, memberCount: list.memberCount, kind: list.kind, avatarURL: list.avatarURL, cid: list.cid)
    }

    // MARK: - Social Graph (Block / Mute / Follow)

    /// Blocks an actor by DID. Creates a `app.bsky.graph.block` record.
    func blockActor(did actorDID: String, account: AppAccount, appPassword: String?) async throws {
        let _: EmptyResponse = try await sessionService.performAuthenticatedRequest(
            account: account,
            appPassword: appPassword
        ) { authSession in
            let body = CreateGenericRecordRequest(
                repo: authSession.did,
                collection: "app.bsky.graph.block",
                record: SubjectRecord(type: "app.bsky.graph.block", subject: actorDID)
            )

            let _: CreateRecordResponse = try await requestExecutor.send(
                path: "com.atproto.repo.createRecord",
                method: "POST",
                queryItems: [],
                body: body,
                accessToken: authSession.accessJWT,
                hostURL: authSession.pdsURL
            )

            return EmptyResponse()
        }
    }

    func softBlockActor(did actorDID: String, account: AppAccount, appPassword: String?) async throws {
        let uri: String = try await sessionService.performAuthenticatedRequest(
            account: account,
            appPassword: appPassword
        ) { authSession in
            let body = CreateGenericRecordRequest(
                repo: authSession.did,
                collection: "app.bsky.graph.block",
                record: SubjectRecord(type: "app.bsky.graph.block", subject: actorDID)
            )

            let response: CreateRecordResponse = try await requestExecutor.send(
                path: "com.atproto.repo.createRecord",
                method: "POST",
                queryItems: [],
                body: body,
                accessToken: authSession.accessJWT,
                hostURL: authSession.pdsURL
            )

            return response.uri
        }
        try await unblockActor(recordURI: uri, account: account, appPassword: appPassword)
    }

    /// Fetches the set of DIDs currently blocked by the account directly from the PDS.
    /// Paginates through all `app.bsky.graph.block` records (capped at 100 pages).
    func fetchExistingBlockedDIDs(account: AppAccount, appPassword: String?) async throws -> Set<String> {
        try await sessionService.performAuthenticatedRequest(
            account: account,
            appPassword: appPassword
        ) { authSession in
            var allDIDs = Set<String>()
            var cursor: String?
            var previousCursor: String?
            var pageCount = 0
            let maxPages = 100

            repeat {
                var queryItems: [URLQueryItem] = [
                    URLQueryItem(name: "repo", value: authSession.did),
                    URLQueryItem(name: "collection", value: "app.bsky.graph.block"),
                    URLQueryItem(name: "limit", value: "100"),
                ]
                if let cursor {
                    queryItems.append(URLQueryItem(name: "cursor", value: cursor))
                }

                let response: BlockListRecordsResponse = try await requestExecutor.send(
                    path: "com.atproto.repo.listRecords",
                    method: "GET",
                    queryItems: queryItems,
                    accessToken: authSession.accessJWT,
                    hostURL: authSession.pdsURL
                )

                for entry in response.records {
                    allDIDs.insert(entry.value.subject)
                }
                previousCursor = cursor
                cursor = response.cursor
                pageCount += 1
                if pageCount >= maxPages {
                    break
                }
                if let cur = cursor, cur == previousCursor {
                    break
                }
            } while cursor != nil

            return allDIDs
        }
    }

    /// Fetches a mapping of blocked DID → block record URI from the PDS. Capped at 100 pages.
    func fetchExistingBlockRecordURIs(account: AppAccount, appPassword: String?) async throws -> [String: String] {
        try await sessionService.performAuthenticatedRequest(
            account: account,
            appPassword: appPassword
        ) { authSession in
            var result = [String: String]()
            var cursor: String?
            var previousCursor: String?
            var pageCount = 0
            let maxPages = 100

            repeat {
                var queryItems: [URLQueryItem] = [
                    URLQueryItem(name: "repo", value: authSession.did),
                    URLQueryItem(name: "collection", value: "app.bsky.graph.block"),
                    URLQueryItem(name: "limit", value: "100"),
                ]
                if let cursor {
                    queryItems.append(URLQueryItem(name: "cursor", value: cursor))
                }

                let response: BlockListRecordsResponse = try await requestExecutor.send(
                    path: "com.atproto.repo.listRecords",
                    method: "GET",
                    queryItems: queryItems,
                    accessToken: authSession.accessJWT,
                    hostURL: authSession.pdsURL
                )

                for entry in response.records {
                    result[entry.value.subject] = entry.uri
                }
                previousCursor = cursor
                cursor = response.cursor
                pageCount += 1
                if pageCount >= maxPages {
                    break
                }
                if let cur = cursor, cur == previousCursor {
                    break
                }
            } while cursor != nil

            return result
        }
    }

    /// Unblocks an actor by their block record URI. Delegates to `removeMember`.
    func unblockActor(recordURI: String, account: AppAccount, appPassword: String?) async throws {
        try await removeMember(recordURI: recordURI, account: account, appPassword: appPassword)
    }

    /// Follows an actor by DID. Creates a `app.bsky.graph.follow` record.
    @discardableResult
    func followActor(did actorDID: String, account: AppAccount, appPassword: String?) async throws -> String {
        try await sessionService.performAuthenticatedRequest(
            account: account,
            appPassword: appPassword
        ) { authSession in
            let body = CreateGenericRecordRequest(
                repo: authSession.did,
                collection: "app.bsky.graph.follow",
                record: SubjectRecord(type: "app.bsky.graph.follow", subject: actorDID)
            )

            let response: CreateRecordResponse = try await requestExecutor.send(
                path: "com.atproto.repo.createRecord",
                method: "POST",
                queryItems: [],
                body: body,
                accessToken: authSession.accessJWT,
                hostURL: authSession.pdsURL
            )

            return response.uri
        }
    }

    /// Unfollows an actor by their follow record URI. Delegates to `removeMember`.
    func unfollowActor(recordURI: String, account: AppAccount, appPassword: String?) async throws {
        try await removeMember(recordURI: recordURI, account: account, appPassword: appPassword)
    }

    /// Mutes an actor by DID.
    func muteActor(did actorDID: String, account: AppAccount, appPassword: String?) async throws {
        let _: EmptyResponse = try await sessionService.performAuthenticatedRequest(
            account: account,
            appPassword: appPassword
        ) { authSession in
            let body = ActorReferenceRequest(actor: actorDID)
            return try await requestExecutor.send(
                path: "app.bsky.graph.muteActor",
                method: "POST",
                queryItems: [],
                body: body,
                accessToken: authSession.accessJWT,
                hostURL: authSession.pdsURL
            )
        }
    }

    /// Unmutes an actor by DID.
    func unmuteActor(did actorDID: String, account: AppAccount, appPassword: String?) async throws {
        let _: EmptyResponse = try await sessionService.performAuthenticatedRequest(
            account: account,
            appPassword: appPassword
        ) { authSession in
            let body = ActorReferenceRequest(actor: actorDID)
            return try await requestExecutor.send(
                path: "app.bsky.graph.unmuteActor",
                method: "POST",
                queryItems: [],
                body: body,
                accessToken: authSession.accessJWT,
                hostURL: authSession.pdsURL
            )
        }
    }

    // MARK: - Private Helpers (List)

    /// Maps an API `ListView` into the app's `SubscribedListInfo` domain model.
    private func mapSubscribedListInfo(from item: ListView) -> SubscribedListInfo {
        SubscribedListInfo(
            id: item.uri,
            listURI: item.uri,
            name: item.name,
            description: item.description,
            ownerDID: item.creator?.did ?? "",
            ownerHandle: item.creator?.handle ?? "",
            ownerDisplayName: item.creator?.displayName,
            memberCount: item.listItemCount,
            kind: item.purpose.kind,
            subscribedAt: item.indexedAt.flatMap(SharedDateFormatters.parseISO8601)
        )
    }

    /// Sends a request proxied through the Bluesky App View. Used for endpoints that
    /// require the `atproto-proxy` header to route through `bsky_appview`.
    private func sendAppViewRequest<Response: Decodable>(
        path: String,
        method: String,
        queryItems: [URLQueryItem],
        accessToken: String,
        pdsURL: URL
    ) async throws -> Response {
        try await sendAppViewRequest(
            path: path,
            method: method,
            queryItems: queryItems,
            body: String?.none,
            accessToken: accessToken,
            pdsURL: pdsURL
        )
    }

    /// Sends a request proxied through the Bluesky App View, with optional request body.
    /// Sets the `atproto-proxy` header to route the request through the AppView service.
    private func sendAppViewRequest<Response: Decodable>(
        path: String,
        method: String,
        queryItems: [URLQueryItem],
        body: (some Encodable)?,
        accessToken: String,
        pdsURL: URL
    ) async throws -> Response {
        guard var components = URLComponents(url: pdsURL.appendingPathComponent("xrpc/\(path)"), resolvingAgainstBaseURL: false) else {
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
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(Self.bskyAppViewServiceDID, forHTTPHeaderField: "atproto-proxy")

        if let body {
            request.httpBody = try JSONEncoder().encode(body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let (data, httpResponse) = try await appViewHTTPClient.data(
            for: request,
            source: "Lists / Relationships",
            origin: "LiveBlueskyClient \(method) xrpc/\(path)"
        )

        if httpResponse.statusCode == 401 {
            throw BlueskyAPIError.unauthorized(
                (try? JSONDecoder().decode(APIErrorPayload.self, from: data))?.message
            )
        }

        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            if let errorPayload = try? JSONDecoder().decode(APIErrorPayload.self, from: data) {
                throw BlueskyAPIError.server(errorPayload.message ?? errorPayload.error ?? "Request failed")
            }
            throw BlueskyAPIError.invalidResponse
        }

        do {
            let decodedData = data.isEmpty ? Data("{}".utf8) : data
            return try JSONDecoder().decode(Response.self, from: decodedData)
        } catch {
            AppLogger.performance.debug("Decoding failure for \(path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            throw BlueskyAPIError.invalidResponse
        }
    }

    // MARK: - Moderation Reports

    /// The DID of the Ozone labeler used for moderation report proxy.
    private static let bskyLabelerDID = "did:plc:ar7c4by46qjdydhdevvrndac"

    /// Submits a moderation report against an account (by DID) with a specific reason type.
    func reportAccount(did targetDID: String, reasonType: String, reason: String?, account: AppAccount, appPassword: String?) async throws {
        let _: CreateModerationReportResponse = try await sessionService.performAuthenticatedRequest(
            account: account,
            appPassword: appPassword
        ) { authSession in
            let body = CreateModerationReportRequest(
                reasonType: reasonType,
                reason: reason,
                subject: ModerationReportSubject(did: targetDID, uri: nil, cid: nil),
                modTool: ModerationReportTool(
                    name: "RULYX/1.0",
                    meta: ["account": account.handle]
                )
            )
            let url = authSession.pdsURL.appendingPathComponent("xrpc/com.atproto.moderation.createReport")
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(authSession.accessJWT)", forHTTPHeaderField: "Authorization")
            request.setValue("\(Self.bskyLabelerDID)#atproto_labeler", forHTTPHeaderField: "atproto-proxy")
            request.httpBody = try JSONEncoder().encode(body)
            let (data, httpResponse) = try await httpClient.data(for: request, source: "Moderation Report")
            guard (200 ..< 300).contains(httpResponse.statusCode) else {
                if let errorPayload = try? JSONDecoder().decode(APIErrorPayload.self, from: data) {
                    throw BlueskyAPIError.server(errorPayload.message ?? errorPayload.error ?? "Report failed.")
                }
                throw BlueskyAPIError.invalidResponse
            }
            return try JSONDecoder().decode(CreateModerationReportResponse.self, from: data)
        }
    }

    /// Submits a moderation report against an account using the default reason type.
    func reportAccount(did targetDID: String, reason: String?, account: AppAccount, appPassword: String?) async throws {
        try await reportAccount(
            did: targetDID,
            selectedReason: nil,
            reason: reason,
            account: account,
            appPassword: appPassword
        )
    }

    /// Submits a moderation report against an account with a selectable reason type.
    func reportAccount(
        did targetDID: String,
        selectedReason: ModerationReportReasonType?,
        reason: String?,
        account: AppAccount,
        appPassword: String?
    ) async throws {
        try await reportAccount(
            did: targetDID,
            reasonType: (selectedReason ?? ModerationReportReasonType.simplifiedDefault).rawValue,
            reason: reason,
            account: account,
            appPassword: appPassword
        )
    }

    /// Submits a moderation report against a list using the default reason type.
    func reportList(_ list: BlueskyList, reason: String?, account: AppAccount, appPassword: String?) async throws {
        try await reportList(
            list,
            selectedReason: nil,
            reason: reason,
            account: account,
            appPassword: appPassword
        )
    }

    /// Submits a moderation report against a list with a selectable reason type.
    /// Proxied through the Ozone labeler service.
    func reportList(
        _ list: BlueskyList,
        selectedReason: ModerationReportReasonType?,
        reason: String?,
        account: AppAccount,
        appPassword: String?
    ) async throws {
        let _: CreateModerationReportResponse = try await sessionService.performAuthenticatedRequest(
            account: account,
            appPassword: appPassword
        ) { authSession in
            let body = CreateModerationReportRequest(
                reasonType: (selectedReason ?? ModerationReportReasonType.simplifiedDefault).rawValue,
                reason: reason,
                subject: ModerationReportSubject(did: nil, uri: list.id, cid: list.cid),
                modTool: ModerationReportTool(
                    name: Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "RULYX",
                    meta: nil
                )
            )
            let url = authSession.pdsURL.appendingPathComponent("xrpc/com.atproto.moderation.createReport")
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(authSession.accessJWT)", forHTTPHeaderField: "Authorization")
            request.setValue("\(Self.bskyLabelerDID)#atproto_labeler", forHTTPHeaderField: "atproto-proxy")
            request.httpBody = try JSONEncoder().encode(body)
            let (data, httpResponse) = try await httpClient.data(for: request, source: "Moderation Report")
            guard (200 ..< 300).contains(httpResponse.statusCode) else {
                if let errorPayload = try? JSONDecoder().decode(APIErrorPayload.self, from: data) {
                    throw BlueskyAPIError.server(errorPayload.message ?? errorPayload.error ?? "Report failed.")
                }
                throw BlueskyAPIError.invalidResponse
            }
            return try JSONDecoder().decode(CreateModerationReportResponse.self, from: data)
        }
    }

    /// Submits a moderation report against a specific record (post) by URI and CID.
    func reportRecord(
        uri: String,
        cid: String,
        reason: String?,
        selectedReason: ModerationReportReasonType? = nil,
        account: AppAccount,
        appPassword: String?
    ) async throws {
        let _: CreateModerationReportResponse = try await sessionService.performAuthenticatedRequest(
            account: account,
            appPassword: appPassword
        ) { authSession in
            let body = CreateModerationReportRequest(
                reasonType: (selectedReason ?? ModerationReportReasonType.simplifiedDefault).rawValue,
                reason: reason,
                subject: ModerationReportSubject(did: nil, uri: uri, cid: cid),
                modTool: ModerationReportTool(
                    name: Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "RULYX",
                    meta: nil
                )
            )
            let url = authSession.pdsURL.appendingPathComponent("xrpc/com.atproto.moderation.createReport")
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(authSession.accessJWT)", forHTTPHeaderField: "Authorization")
            request.setValue("\(Self.bskyLabelerDID)#atproto_labeler", forHTTPHeaderField: "atproto-proxy")
            request.httpBody = try JSONEncoder().encode(body)
            let (data, httpResponse) = try await httpClient.data(for: request, source: "Moderation Report")
            guard (200 ..< 300).contains(httpResponse.statusCode) else {
                if let errorPayload = try? JSONDecoder().decode(APIErrorPayload.self, from: data) {
                    throw BlueskyAPIError.server(errorPayload.message ?? errorPayload.error ?? "Report failed.")
                }
                throw BlueskyAPIError.invalidResponse
            }
            return try JSONDecoder().decode(CreateModerationReportResponse.self, from: data)
        }
    }

    // MARK: - Profile

    /// Protocol conformance — delegates to cached variant.
    func fetchProfile(did actorDID: String, account: AppAccount, appPassword: String?) async throws -> BlueskyProfile {
        try await fetchProfile(did: actorDID, account: account, appPassword: appPassword, forceRefresh: false)
    }

    /// Fetches a full profile by DID or handle for a given account context.
    /// Returns a `BlueskyProfile` with viewer state, labels, and associated counts.
    /// Uses `BlueskyAPICache` for instant re-visits; set `forceRefresh = true` to bypass cache.
    func fetchProfile(did actorDID: String, account: AppAccount, appPassword: String?, forceRefresh: Bool = false) async throws -> BlueskyProfile {
        // Cache check (unless forced refresh)
        if !forceRefresh, let did = account.did {
            let cacheURL = "app.bsky.actor.getProfile?actor=\(actorDID)"
            if let cached = await BlueskyAPICache.shared.read(accountDID: did, url: cacheURL, maxAge: BlueskyAPICache.DefaultTTL.profile) {
                if let profile = try? JSONDecoder().decode(BlueskyProfile.self, from: cached.data) {
                    if !cached.isStale {
                        return profile
                    }
                    // Stale: return profile but fire-and-forget a background refresh
                    Task { [weak self] in
                        _ = try? await self?.fetchProfileNetwork(actorDID: actorDID, account: account, appPassword: appPassword)
                    }
                    return profile
                }
            }
        }

        return try await fetchProfileNetwork(actorDID: actorDID, account: account, appPassword: appPassword)
    }

    /// Direct network fetch for profile data, bypassing cache.
    private func fetchProfileNetwork(actorDID: String, account: AppAccount, appPassword: String?) async throws -> BlueskyProfile {
        let response: ProfileViewDetailed = try await sessionService.performAuthenticatedRequest(
            account: account,
            appPassword: appPassword
        ) { authSession in
            try await requestExecutor.send(
                path: "app.bsky.actor.getProfile",
                method: "GET",
                queryItems: [URLQueryItem(name: "actor", value: actorDID)],
                accessToken: authSession.accessJWT,
                hostURL: authSession.pdsURL
            )
        }

        let profile = BlueskyProfile(
            id: response.did, did: response.did, handle: response.handle,
            displayName: response.displayName, description: response.description,
            websiteURL: URL(string: response.website ?? ""), avatarURL: URL(string: response.avatar ?? ""),
            bannerURL: URL(string: response.banner ?? ""),
            followersCount: response.followersCount, followsCount: response.followsCount, postsCount: response.postsCount,
            listsCount: response.associated?.lists, starterPacksCount: response.associated?.starterPacks,
            createdAt: parseDate(response.createdAt), labels: response.labels?.map(\.val) ?? [],
            viewerState: mapViewerState(response.viewer)
        )

        // Write to cache
        if let did = account.did, let encoded = try? JSONEncoder().encode(profile) {
            let cacheURL = "app.bsky.actor.getProfile?actor=\(actorDID)"
            await BlueskyAPICache.shared.write(accountDID: did, url: cacheURL, data: encoded)
        }

        return profile
    }

    // MARK: - Blocklist reads

    //
    // These entry points stay in the class body (not in `LiveBlueskyClient+Blocklist.swift`)
    // because `PreviewBlueskyClient` overrides them and Swift forbids overriding a member
    // declared in an extension. The sources they read live in that extension file:
    // "Blocking" from the account's own repo, "Blocked by" from the Constellation index.

    /// The actors the account has blocked — the `app.bsky.graph.block` records of its own
    /// repo, where the block record's `subject` *is* the blocked account.
    func fetchBlockedActors(account: AppAccount, appPassword _: String?) async throws -> BlocklistResult {
        try await fetchBlockedActors(account: account, appPassword: nil, onProgress: nil)
    }

    /// The actors the account has blocked, reporting partial counts as records load.
    func fetchBlockedActors(
        account: AppAccount,
        appPassword _: String?,
        onProgress: (@MainActor @Sendable (Int) async -> Void)?
    ) async throws -> BlocklistResult {
        try await repoBlockedActors(account: account, onProgress: onProgress)
    }

    /// The actors blocking the account, from the Constellation backlink index (the
    /// `app.bsky.graph.block` records that point at the account).
    func fetchBlockedByActors(account: AppAccount, appPassword _: String?) async throws -> BlocklistResult {
        try await fetchBlockedByActors(account: account, appPassword: nil, onProgress: nil)
    }

    /// The actors blocking the account, reporting partial counts as records load.
    func fetchBlockedByActors(
        account: AppAccount,
        appPassword _: String?,
        onProgress: (@MainActor @Sendable (Int) async -> Void)?
    ) async throws -> BlocklistResult {
        try await constellation.blockerActors(
            actorDID: resolveAccountDID(account),
            onProgress: onProgress
        )
    }

    /// Returns the total count of actors the account has blocked.
    /// DID-only (no profile resolution) — uses the same source as the detail view.
    func fetchBlockingCount(for account: AppAccount) async throws -> Int {
        try await fetchBlockingCount(for: account, forceRefresh: false)
    }

    /// Returns the total count of actors the account has blocked, optionally bypassing cache.
    func fetchBlockingCount(for account: AppAccount, forceRefresh: Bool) async throws -> Int {
        try await repo.blockRecords(for: account, onProgress: nil, forceRefresh: forceRefresh).count
    }

    /// Returns the total count of actors that have blocked the account.
    /// DID-only (no profile resolution) — uses the same source as the detail view.
    func fetchBlockedByCount(for account: AppAccount) async throws -> Int {
        try await fetchBlockedByCount(for: account, forceRefresh: false)
    }

    /// Returns the total count of actors that have blocked the account, optionally bypassing cache.
    /// The index reports its exact total independently of the page size.
    func fetchBlockedByCount(for account: AppAccount, forceRefresh _: Bool) async throws -> Int {
        try await constellation.blockerCount(actorDID: resolveAccountDID(account))
    }

    /// Returns the count of actors that block the account but are not blocked back.
    func fetchUnblockedBlockersCount(for account: AppAccount) async throws -> Int {
        try await fetchUnblockedBlockerActors(account: account, appPassword: nil).count
    }

    /// DIDs of the accounts the account has blocked — the `subject` of every
    /// `app.bsky.graph.block` record in its own repo.
    func fetchBlockedDIDs(for account: AppAccount) async throws -> Set<String> {
        try await repoBlockedDIDs(account: account)
    }

    /// DIDs of the accounts blocking the account, from the Constellation backlink index.
    func fetchBlockerDIDs(for account: AppAccount) async throws -> Set<String> {
        try await constellationBlockerDIDs(account: account)
    }

    /// Resolves profiles for a list of DIDs in parallel batches of 25.
    /// Silently ignores individual batch failures (best-effort resolution).
    /// Internal (not private): used by the blocklist extension file.
    func resolveProfilesBestEffort(dids: [String]) async -> [BlueskyActor] {
        let uniqueDIDs = Array(Set(dids)).sorted()
        return await withTaskGroup(of: [BlueskyActor].self) { group in
            var offset = 0
            while offset < uniqueDIDs.count {
                let chunk = Array(uniqueDIDs[offset ..< min(offset + 25, uniqueDIDs.count)])
                offset += 25
                group.addTask { [httpClient] in
                    do {
                        return try await Self.fetchProfileBatch(identifiers: chunk, httpClient: httpClient)
                    } catch {
                        AppLogger.performance.error("Profile batch lookup failed: \(error.localizedDescription, privacy: .public)")
                        return []
                    }
                }
            }

            var actors: [BlueskyActor] = []
            for await batch in group {
                actors.append(contentsOf: batch)
            }
            return actors
        }
    }

    /// Resolves the DID for an account. If the account already has a DID, returns it;
    /// otherwise resolves the handle via the AT Protocol.
    /// Internal (not private): used by the blocklist extension file.
    func resolveAccountDID(_ account: AppAccount) async throws -> String {
        if let did = account.did {
            return did
        }
        return try await resolveHandleToDID(handle: account.handle)
    }

    // MARK: - DID Resolution & PLC Audit

    /// Resolves profiles for an array of DIDs in parallel batches of 25.
    func fetchProfileBatch(identifiers: [String]) async throws -> [BlueskyActor] {
        try await Self.fetchProfileBatch(identifiers: identifiers, httpClient: httpClient)
    }

    /// Static batch profile lookup via `app.bsky.actor.getProfiles`. Bypasses authentication
    /// using the public API endpoint.
    /// Batches requests to stay within the API limit of 25 actors per call.
    static func fetchProfileBatch(identifiers: [String], httpClient: HTTPClient) async throws -> [BlueskyActor] {
        guard let profilesURL = URL(string: "https://public.api.bsky.app/xrpc/app.bsky.actor.getProfiles") else {
            throw BlueskyAPIError.invalidURL
        }

        var actors: [BlueskyActor] = []
        let batchSize = 25

        for offset in stride(from: 0, to: identifiers.count, by: batchSize) {
            let chunk = Array(identifiers[offset ..< min(offset + batchSize, identifiers.count)])
            let actorsParam = chunk.map { URLQueryItem(name: "actors", value: $0) }
            var components = URLComponents(url: profilesURL, resolvingAgainstBaseURL: false)!
            components.queryItems = actorsParam
            guard let finalURL = components.url else { throw BlueskyAPIError.invalidURL }
            var req = URLRequest(url: finalURL)
            req.setValue("application/json", forHTTPHeaderField: "Accept")
            req.timeoutInterval = 30
            let (data, httpResponse) = try await httpClient.data(for: req, source: "Profile Batch Lookup")
            guard (200 ..< 300).contains(httpResponse.statusCode) else {
                throw BlueskyAPIError.invalidResponse
            }
            let decoded = try JSONDecoder().decode(GetProfilesResponse.self, from: data)
            actors.append(contentsOf: decoded.profiles.map {
                BlueskyActor(
                    did: $0.did,
                    handle: $0.handle,
                    displayName: $0.displayName,
                    avatarURL: URL(string: $0.avatar ?? ""),
                    description: $0.description
                )
            })
        }

        return actors
    }

    /// Fetches stats (followers, following, posts, description) for an array of DIDs in batches.
    /// Reports progress via the optional callback. Non-isolated so it can be called from background contexts.
    nonisolated static func fetchProfileStats(dids: [String], onProgress: (@Sendable (Int, Int) -> Void)? = nil) async throws -> [String: (followers: Int, following: Int, posts: Int, description: String)] {
        var result: [String: (followers: Int, following: Int, posts: Int, description: String)] = [:]
        let httpClient = HTTPClient()
        let totalBatches = (dids.count + 24) / 25
        var batchIndex = 0

        for offset in stride(from: 0, to: dids.count, by: 25) {
            batchIndex += 1
            onProgress?(batchIndex, totalBatches)
            let chunk = Array(dids[offset ..< min(offset + 25, dids.count)])
            let actorsParam = chunk.map { URLQueryItem(name: "actors", value: $0) }
            guard let profilesURL = URL(string: "https://public.api.bsky.app/xrpc/app.bsky.actor.getProfiles") else {
                throw BlueskyAPIError.invalidURL
            }
            var components = URLComponents(url: profilesURL, resolvingAgainstBaseURL: false)!
            components.queryItems = actorsParam
            guard let finalURL = components.url else { throw BlueskyAPIError.invalidURL }
            var req = URLRequest(url: finalURL)
            req.setValue("application/json", forHTTPHeaderField: "Accept")
            req.timeoutInterval = 30
            let (data, httpResponse) = try await httpClient.data(for: req, source: "Profile Stats")
            guard (200 ..< 300).contains(httpResponse.statusCode) else {
                throw BlueskyAPIError.invalidResponse
            }
            let decoded = try JSONDecoder().decode(GetProfilesResponse.self, from: data)
            for profile in decoded.profiles {
                result[profile.did] = (
                    followers: profile.followersCount ?? 0,
                    following: profile.followsCount ?? 0,
                    posts: profile.postsCount ?? 0,
                    description: profile.description ?? ""
                )
            }
        }
        return result
    }

    /// Resolves a handle to a DID.
    ///
    /// Resolution runs on the AT Protocol (`com.atproto.identity.resolveHandle`), which
    /// is authoritative: opening a profile from the timeline, chat, search or a thread
    /// must keep working regardless of any third-party service.
    /// DIDs (prefix `did:`) are returned as-is without a network call — callers
    /// that already know the DID (e.g. from mention facets) skip resolution entirely.
    /// Internal (not private): used by the blocklist extension file.
    func resolveHandleToDID(handle: String) async throws -> String {
        if handle.hasPrefix("did:") {
            return handle
        }
        return try await resolveHandleViaATProtocol(handle)
    }

    /// Handle → DID via the public AT Protocol AppView (`public.api.bsky.app`).
    private func resolveHandleViaATProtocol(_ handle: String) async throws -> String {
        guard var components = URLComponents(string: "https://public.api.bsky.app/xrpc/com.atproto.identity.resolveHandle") else {
            throw BlueskyAPIError.invalidURL
        }
        components.queryItems = [URLQueryItem(name: "handle", value: handle)]
        guard let url = components.url else { throw BlueskyAPIError.invalidURL }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, httpResponse) = try await httpClient.data(for: request, source: "Handle Resolution")
        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            throw BlueskyAPIError.invalidResponse
        }
        return try JSONDecoder().decode(ResolveHandleResponse.self, from: data).did
    }

    /// Public wrapper to resolve a handle to a DID.
    func resolveHandle(_ handle: String) async throws -> String {
        try await resolveHandleToDID(handle: handle)
    }

    // MARK: - Author Feed

    /// Fetches an author's feed (used for image/media downloads).
    func fetchAuthorFeed(did: String, cursor: String? = nil, account: AppAccount, appPassword: String?) async throws -> GetAuthorFeedResponse {
        try await sessionService.performAuthenticatedRequest(
            account: account,
            appPassword: appPassword
        ) { authSession in
            var queryItems = [URLQueryItem(name: "actor", value: did), URLQueryItem(name: "limit", value: "100")]
            if let cursor {
                queryItems.append(URLQueryItem(name: "cursor", value: cursor))
            }
            return try await requestExecutor.send(
                path: "app.bsky.feed.getAuthorFeed",
                method: "GET",
                queryItems: queryItems,
                accessToken: authSession.accessJWT,
                hostURL: authSession.pdsURL
            )
        }
    }

    /// Fetches an author's feed with rich post content (used in the post browser).
    func fetchRichFeed(
        did: String,
        cursor: String? = nil,
        filter: String? = nil,
        account: AppAccount,
        appPassword: String?
    ) async throws -> RichFeedResponse {
        try await sessionService.performAuthenticatedRequest(
            account: account,
            appPassword: appPassword
        ) { authSession in
            var queryItems = [
                URLQueryItem(name: "actor", value: did),
                URLQueryItem(name: "limit", value: "100"),
            ]
            if let cursor {
                queryItems.append(URLQueryItem(name: "cursor", value: cursor))
            }
            if let filter {
                queryItems.append(URLQueryItem(name: "filter", value: filter))
            }
            return try await requestExecutor.send(
                path: "app.bsky.feed.getAuthorFeed",
                method: "GET",
                queryItems: queryItems,
                accessToken: authSession.accessJWT,
                hostURL: authSession.pdsURL
            )
        }
    }

    // MARK: - Posts & Threads

    /// Fetches a post thread by URI, with optional reply depth limit.
    func fetchPostThread(uri: String, depth: Int? = nil, account: AppAccount, appPassword: String?) async throws -> GetPostThreadResponse {
        try await sessionService.performAuthenticatedRequest(
            account: account,
            appPassword: appPassword
        ) { authSession in
            var queryItems = [URLQueryItem(name: "uri", value: uri)]
            if let depth {
                queryItems.append(URLQueryItem(name: "depth", value: "\(depth)"))
            }
            return try await requestExecutor.send(
                path: "app.bsky.feed.getPostThread",
                method: "GET",
                queryItems: queryItems,
                accessToken: authSession.accessJWT,
                hostURL: authSession.pdsURL
            )
        }
    }

    // MARK: - Timeline & Feeds

    /// Fetches the home timeline for the authenticated account.
    func fetchTimeline(cursor: String? = nil, limit: Int = 50, account: AppAccount, appPassword: String?) async throws -> RichFeedResponse {
        try await sessionService.performAuthenticatedRequest(
            account: account,
            appPassword: appPassword
        ) { authSession in
            var queryItems = [URLQueryItem(name: "limit", value: "\(limit)")]
            if let cursor {
                queryItems.append(URLQueryItem(name: "cursor", value: cursor))
            }
            return try await requestExecutor.send(
                path: "app.bsky.feed.getTimeline",
                method: "GET",
                queryItems: queryItems,
                accessToken: authSession.accessJWT,
                hostURL: authSession.pdsURL
            )
        }
    }

    /// Fetches a custom feed by AT URI (feed generator).
    func fetchFeed(feedURI: String, cursor: String? = nil, limit: Int = 50, account: AppAccount, appPassword: String?) async throws -> RichFeedResponse {
        try await sessionService.performAuthenticatedRequest(
            account: account,
            appPassword: appPassword
        ) { authSession in
            var queryItems = [
                URLQueryItem(name: "feed", value: feedURI),
                URLQueryItem(name: "limit", value: "\(limit)"),
            ]
            if let cursor {
                queryItems.append(URLQueryItem(name: "cursor", value: cursor))
            }
            return try await requestExecutor.send(
                path: "app.bsky.feed.getFeed",
                method: "GET",
                queryItems: queryItems,
                accessToken: authSession.accessJWT,
                hostURL: authSession.pdsURL
            )
        }
    }

    /// Fetches recent posts from the actors in a Bluesky list.
    func fetchListFeed(listURI: String, cursor: String? = nil, limit: Int = 50, account: AppAccount, appPassword: String?) async throws -> RichFeedResponse {
        try await sessionService.performAuthenticatedRequest(
            account: account,
            appPassword: appPassword
        ) { authSession in
            var queryItems = [
                URLQueryItem(name: "list", value: listURI),
                URLQueryItem(name: "limit", value: "\(limit)"),
            ]
            if let cursor {
                queryItems.append(URLQueryItem(name: "cursor", value: cursor))
            }
            return try await sendAppViewRequest(
                path: "app.bsky.feed.getListFeed",
                method: "GET",
                queryItems: queryItems,
                accessToken: authSession.accessJWT,
                pdsURL: authSession.pdsURL
            )
        }
    }

    // MARK: - PLC Audit

    /// Fetches the PLC directory audit log for a DID. Used for handle change history.
    func fetchPLCAuditLog(did: String) async throws -> [PLCAuditLogEntry] {
        guard let url = URL(string: "https://plc.directory/\(did)/log/audit") else {
            throw BlueskyAPIError.invalidURL
        }
        let request = URLRequest(url: url)
        let (data, httpResponse) = try await httpClient.data(for: request, source: "PLC Audit Log")
        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            throw BlueskyAPIError.invalidResponse
        }
        return try JSONDecoder().decode([PLCAuditLogEntry].self, from: data)
    }

    // MARK: - Followers / Following

    /// Fetches all followers for an actor with automatic pagination (up to 50 pages / ~5000 entries).
    func fetchFollowers(actor actorDID: String, account: AppAccount, appPassword: String?) async throws -> [BlueskyActor] {
        var all: [BlueskyActor] = []
        var cursor: String?
        var pageCount = 0
        let maxPages = 50
        var lastError: Error?
        repeat {
            do {
                let page = try await fetchFollowersPage(actor: actorDID, cursor: cursor, account: account, appPassword: appPassword)
                all.append(contentsOf: page.actors)
                cursor = page.cursor
                pageCount += 1
                if pageCount >= maxPages {
                    break
                }
                lastError = nil
            } catch {
                AppLogger.moderation.error("fetchFollowers page \(pageCount) failed: \(error.localizedDescription, privacy: .public)")
                // Retry once on transient failure
                if cursor != nil, lastError == nil {
                    lastError = error
                    continue
                }
                if cursor == nil {
                    throw error
                }
                break
            }
        } while cursor != nil
        if all.isEmpty, let lastError {
            throw lastError
        }
        return all
    }

    /// Fetches a single page of followers.
    func fetchFollowersPage(actor actorDID: String, cursor: String?, account: AppAccount, appPassword: String?) async throws -> PagedActorSearch {
        let response: GetFollowersResponse = try await sessionService.performAuthenticatedRequest(
            account: account,
            appPassword: appPassword
        ) { authSession in
            var queryItems = [
                URLQueryItem(name: "actor", value: actorDID),
                URLQueryItem(name: "limit", value: "100"),
            ]
            if let cursor {
                queryItems.append(URLQueryItem(name: "cursor", value: cursor))
            }
            return try await requestExecutor.send(
                path: "app.bsky.graph.getFollowers",
                method: "GET",
                queryItems: queryItems,
                accessToken: authSession.accessJWT,
                hostURL: authSession.pdsURL
            )
        }
        return PagedActorSearch(
            actors: response.followers.map {
                BlueskyActor(
                    did: $0.did,
                    handle: $0.handle,
                    displayName: $0.displayName,
                    avatarURL: URL(string: $0.avatar ?? ""),
                    createdAt: parseDate($0.createdAt),
                    description: $0.description,
                    viewerState: mapViewerState($0.viewer)
                )
            },
            cursor: response.cursor
        )
    }

    /// Fetches all accounts the given actor is following, with automatic pagination (up to 50 pages).
    func fetchFollowing(actor actorDID: String, account: AppAccount, appPassword: String?) async throws -> [BlueskyActor] {
        var all: [BlueskyActor] = []
        var cursor: String?
        var pageCount = 0
        let maxPages = 50
        var lastError: Error?
        repeat {
            do {
                let page = try await fetchFollowingPage(actor: actorDID, cursor: cursor, account: account, appPassword: appPassword)
                all.append(contentsOf: page.actors)
                cursor = page.cursor
                pageCount += 1
                if pageCount >= maxPages {
                    break
                }
                lastError = nil
            } catch {
                AppLogger.moderation.error("fetchFollowing page \(pageCount) failed: \(error.localizedDescription, privacy: .public)")
                // Retry once on transient failure
                if cursor != nil, lastError == nil {
                    lastError = error
                    continue
                }
                if cursor == nil {
                    throw error
                }
                break
            }
        } while cursor != nil
        if all.isEmpty, let lastError {
            throw lastError
        }
        return all
    }

    /// Fetches a single page of accounts the given actor follows.
    func fetchFollowingPage(actor actorDID: String, cursor: String?, account: AppAccount, appPassword: String?) async throws -> PagedActorSearch {
        let response: GetFollowsResponse = try await sessionService.performAuthenticatedRequest(
            account: account,
            appPassword: appPassword
        ) { authSession in
            var queryItems = [
                URLQueryItem(name: "actor", value: actorDID),
                URLQueryItem(name: "limit", value: "100"),
            ]
            if let cursor {
                queryItems.append(URLQueryItem(name: "cursor", value: cursor))
            }
            return try await requestExecutor.send(
                path: "app.bsky.graph.getFollows",
                method: "GET",
                queryItems: queryItems,
                accessToken: authSession.accessJWT,
                hostURL: authSession.pdsURL
            )
        }
        return PagedActorSearch(
            actors: response.follows.map {
                BlueskyActor(
                    did: $0.did,
                    handle: $0.handle,
                    displayName: $0.displayName,
                    avatarURL: URL(string: $0.avatar ?? ""),
                    createdAt: parseDate($0.createdAt),
                    description: $0.description,
                    viewerState: mapViewerState($0.viewer)
                )
            },
            cursor: response.cursor
        )
    }

    // MARK: - Profile Inspection

    /// Performs a comprehensive profile inspection: fetches the profile, list memberships,
    /// and starter pack memberships in parallel.
    func inspectProfile(query: String, account: AppAccount, appPassword: String?) async throws -> ProfileInspection {
        let actor = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !actor.isEmpty else {
            throw BlueskyAPIError.server("Enter a Bluesky handle or DID.")
        }

        // Fire off profile, list membership, and starter pack requests in parallel.
        let (profile, lists, starterPacks): (ProfileViewDetailed, ListsWithMembershipResponse?, StarterPacksWithMembershipResponse?) =
            try await sessionService.performAuthenticatedRequest(
                account: account,
                appPassword: appPassword
            ) { authSession in
                async let profileResponse: ProfileViewDetailed = requestExecutor.send(
                    path: "app.bsky.actor.getProfile", method: "GET",
                    queryItems: [URLQueryItem(name: "actor", value: actor)],
                    accessToken: authSession.accessJWT, hostURL: authSession.pdsURL
                )
                async let listMembershipResponse: ListsWithMembershipResponse? = try? requestExecutor.send(
                    path: "app.bsky.graph.getListsWithMembership", method: "GET",
                    queryItems: [URLQueryItem(name: "actor", value: actor), URLQueryItem(name: "limit", value: "100")],
                    accessToken: authSession.accessJWT, hostURL: authSession.pdsURL
                )
                async let starterPackMembershipResponse: StarterPacksWithMembershipResponse? = try? requestExecutor.send(
                    path: "app.bsky.graph.getStarterPacksWithMembership", method: "GET",
                    queryItems: [URLQueryItem(name: "actor", value: actor), URLQueryItem(name: "limit", value: "100")],
                    accessToken: authSession.accessJWT, hostURL: authSession.pdsURL
                )

                return try await (profileResponse, listMembershipResponse, starterPackMembershipResponse)
            }

        let mappedProfile = BlueskyProfile(
            id: profile.did, did: profile.did, handle: profile.handle,
            displayName: profile.displayName, description: profile.description,
            websiteURL: URL(string: profile.website ?? ""), avatarURL: URL(string: profile.avatar ?? ""),
            bannerURL: URL(string: profile.banner ?? ""),
            followersCount: profile.followersCount, followsCount: profile.followsCount, postsCount: profile.postsCount,
            listsCount: profile.associated?.lists, starterPacksCount: profile.associated?.starterPacks,
            createdAt: parseDate(profile.createdAt), labels: profile.labels?.map(\.val) ?? [],
            viewerState: mapViewerState(profile.viewer)
        )

        return ProfileInspection(
            profile: mappedProfile,
            listMemberships: lists?.listsWithMembership.map {
                ProfileListMembership(
                    listURI: $0.list.uri,
                    name: $0.list.name,
                    kind: $0.list.purpose.kind,
                    memberCount: $0.list.listItemCount,
                    isMember: $0.listItem != nil,
                    listItemRecordURI: $0.listItem?.uri
                )
            } ?? [],
            starterPackMemberships: starterPacks?.starterPacksWithMembership.map {
                ProfileStarterPackMembership(uri: $0.starterPack.uri, name: $0.starterPack.name ?? $0.starterPack.uri, memberCount: $0.starterPack.listItemCount, joinedAllTimeCount: $0.starterPack.joinedAllTimeCount, isMember: $0.listItem != nil)
            } ?? []
        )
    }

    /// Checks which of the account's lists contain a given target DID.
    /// Pages through up to 2 pages of each list to find the member.
    func fetchListMemberships(
        for targetDID: String,
        account: AppAccount,
        appPassword: String?
    ) async -> [ProfileListMembership] {
        guard let lists = try? await fetchLists(for: account, appPassword: appPassword) else {
            return []
        }

        // For each list owned by the account, check if the target DID is a member.
        return await withTaskGroup(of: ProfileListMembership?.self) { group in
            for list in lists {
                group.addTask {
                    var cursor: String?
                    var foundItem: BlueskyListMember?
                    var pagesChecked = 0

                    // Search up to 2 pages of members per list.
                    while foundItem == nil, pagesChecked < 2 {
                        guard let page = try? await self.fetchListMembersPage(
                            list: list, cursor: cursor,
                            account: account, appPassword: appPassword
                        ) else { break }
                        foundItem = page.members.first { $0.actor.did == targetDID }
                        cursor = page.cursor
                        pagesChecked += 1
                        if cursor == nil {
                            break
                        }
                    }

                    return ProfileListMembership(
                        listURI: list.id,
                        name: list.name,
                        kind: list.kind,
                        memberCount: list.memberCount,
                        isMember: foundItem != nil,
                        listItemRecordURI: foundItem?.recordURI
                    )
                }
            }

            var results: [ProfileListMembership] = []
            for await result in group {
                if let result {
                    results.append(result)
                }
            }
            return results
        }
    }

    // MARK: - Blob Upload

    /// Uploads binary data (image/video) to the PDS via `com.atproto.repo.uploadBlob`.
    func uploadBlob(data: Data, mimeType: String, account: AppAccount, appPassword: String?, progress: (@Sendable (Double) -> Void)? = nil) async throws -> UploadBlobResponse {
        try await sessionService.performAuthenticatedRequest(account: account, appPassword: appPassword) { authSession in
            let url = authSession.pdsURL.appendingPathComponent("xrpc/com.atproto.repo.uploadBlob")
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("Bearer \(authSession.accessJWT)", forHTTPHeaderField: "Authorization")
            request.setValue(mimeType, forHTTPHeaderField: "Content-Type")
            let (responseData, _) = try await httpClient.upload(for: request, from: data, source: "Blob Upload", progress: progress)
            return try JSONDecoder().decode(UploadBlobResponse.self, from: responseData)
        }
    }

    // MARK: - Profile Update

    /// Fetches the raw profile record for the authenticated account via
    /// `com.atproto.repo.getRecord`. Returns the record value including
    /// current blob refs for avatar/banner so they can be preserved during edits.
    /// Returns `nil` if the record does not exist (e.g. fresh account).
    func fetchMyProfileRecord(account: AppAccount, appPassword: String?) async throws -> ProfileRecordValue? {
        do {
            let response: GetProfileRecordResponse = try await sessionService.performAuthenticatedRequest(
                account: account,
                appPassword: appPassword
            ) { authSession in
                try await requestExecutor.send(
                    path: "com.atproto.repo.getRecord",
                    method: "GET",
                    queryItems: [
                        URLQueryItem(name: "repo", value: authSession.did),
                        URLQueryItem(name: "collection", value: "app.bsky.actor.profile"),
                        URLQueryItem(name: "rkey", value: "self"),
                    ],
                    accessToken: authSession.accessJWT,
                    hostURL: authSession.pdsURL
                )
            }
            return response.value
        } catch let error as BlueskyAPIError {
            if case .server = error {
                return nil
            }
            throw error
        } catch {
            return nil
        }
    }

    /// Writes a complete profile record via `com.atproto.repo.putRecord`.
    /// The caller is responsible for uploading new avatar/banner blobs first
    /// and merging with the current record to preserve unchanged fields.
    func putProfileRecord(_ record: ProfileRecord, account: AppAccount, appPassword: String?) async throws {
        let _: CreateRecordResponse = try await sessionService.performAuthenticatedRequest(
            account: account,
            appPassword: appPassword
        ) { authSession in
            let body = PutRecordRequest(
                repo: authSession.did,
                collection: "app.bsky.actor.profile",
                rkey: "self",
                record: record
            )

            return try await requestExecutor.send(
                path: "com.atproto.repo.putRecord",
                method: "POST",
                queryItems: [],
                body: body,
                accessToken: authSession.accessJWT,
                hostURL: authSession.pdsURL
            )
        }
    }

    // MARK: - Post Creation

    /// Creates a new post with optional images, video, reply context, quote, thread gate, and quote-gate.
    ///
    /// - Parameters:
    ///   - text: The post text content.
    ///   - images: Optional image attachments (must be pre-uploaded).
    ///   - video: Optional video attachment (must be pre-uploaded). Mutually exclusive with images.
    ///   - replyTo: Reply context (parent and root URIs/CIDs).
    ///   - quote: Post to quote (URI and CID).
    ///   - threadGate: Optional thread gate rule (who can reply).
    ///   - allowQuoting: Whether other users can quote this post. Set `false` to disable.
    /// - Returns: The `CreateRecordResponse` with the new post's URI and CID.
    ///
    /// Post-creation steps (when applicable):
    /// 1. Creates a `app.bsky.feed.threadgate` record if `threadGate` is set.
    /// 2. Creates a `app.bsky.feed.postgate` record with `disableRule` if `allowQuoting` is `false`.
    func createPost(
        text: String,
        images: [PostImageAttachment]? = nil,
        video: PostVideoAttachment? = nil,
        external: PostExternalAttachment? = nil,
        replyTo: (parentURI: String, parentCID: String, rootURI: String, rootCID: String)? = nil,
        quote: (uri: String, cid: String)? = nil,
        threadGate: ThreadGateRule? = nil,
        allowQuoting: Bool = true,
        account: AppAccount,
        appPassword: String?
    ) async throws -> CreateRecordResponse {
        let response = try await createPostRecord(
            text: text,
            images: images,
            video: video,
            external: external,
            replyTo: replyTo,
            quote: quote,
            account: account,
            appPassword: appPassword
        )
        if let threadGate {
            let rules: [ThreadGateRule] = if threadGate == .noReply {
                // An empty allow array means no one can reply.
                []
            } else {
                [threadGate]
            }
            _ = try await createThreadGate(
                postURI: response.uri,
                rules: rules,
                account: account,
                appPassword: appPassword
            )
        }
        if !allowQuoting {
            _ = try await createPostGate(
                postURI: response.uri,
                account: account,
                appPassword: appPassword
            )
        }
        return response
    }

    /// Creates the underlying `app.bsky.feed.post` record with text, embeds, and reply context.
    private func createPostRecord(
        text: String,
        images: [PostImageAttachment]?,
        video: PostVideoAttachment?,
        external: PostExternalAttachment?,
        replyTo: (parentURI: String, parentCID: String, rootURI: String, rootCID: String)?,
        quote: (uri: String, cid: String)?,
        account: AppAccount,
        appPassword: String?
    ) async throws -> CreateRecordResponse {
        try await sessionService.performAuthenticatedRequest(account: account, appPassword: appPassword) { authSession in
            let embed: FeedPostRecordEmbed? = {
                if let quote {
                    return .record(uri: quote.uri, cid: quote.cid)
                }
                if let video {
                    return .video(FeedPostVideoAttachment(blob: video.blob, alt: video.alt, aspectRatio: video.aspectRatio))
                }
                if let external {
                    return .external(FeedPostExternalAttachment(
                        uri: external.uri,
                        title: external.title,
                        description: external.description
                    ))
                }
                if let images {
                    guard !images.isEmpty else { return nil }
                    return .images(images.map { img in
                        FeedPostImage(
                            image: FeedPostImageRef(ref: img.blob.ref, mimeType: img.blob.mimeType, size: img.blob.size),
                            alt: img.alt
                        )
                    })
                }
                return nil
            }()
            let reply: FeedPostReplyRef? = replyTo.map {
                FeedPostReplyRef(
                    root: FeedPostTarget(uri: $0.rootURI, cid: $0.rootCID),
                    parent: FeedPostTarget(uri: $0.parentURI, cid: $0.parentCID)
                )
            }
            let body = CreateGenericRecordRequest(
                repo: authSession.did,
                collection: "app.bsky.feed.post",
                record: FeedPostRecord(
                    text: text,
                    createdAt: ISO8601DateFormatter().string(from: .now),
                    reply: reply,
                    embed: embed
                )
            )
            return try await requestExecutor.send(
                path: "com.atproto.repo.createRecord",
                method: "POST",
                queryItems: [],
                body: body,
                accessToken: authSession.accessJWT,
                hostURL: authSession.pdsURL
            )
        }
    }

    /// Creates a `app.bsky.feed.threadgate` record to control who can reply.
    func createThreadGate(
        postURI: String,
        rules: [ThreadGateRule],
        account: AppAccount,
        appPassword: String?
    ) async throws -> CreateRecordResponse {
        try await sessionService.performAuthenticatedRequest(account: account, appPassword: appPassword) { authSession in
            let components = try parseATURI(postURI)
            let body = CreateGenericRecordRequest(
                repo: authSession.did,
                collection: "app.bsky.feed.threadgate",
                record: ThreadGateRecord(
                    post: postURI,
                    allow: rules,
                    createdAt: ISO8601DateFormatter().string(from: .now)
                ),
                rkey: components.rkey
            )
            return try await requestExecutor.send(
                path: "com.atproto.repo.createRecord",
                method: "POST",
                queryItems: [],
                body: body,
                accessToken: authSession.accessJWT,
                hostURL: authSession.pdsURL
            )
        }
    }

    /// Creates a `app.bsky.feed.postgate` record to disable quote-embedding.
    func createPostGate(
        postURI: String,
        account: AppAccount,
        appPassword: String?
    ) async throws -> CreateRecordResponse {
        try await sessionService.performAuthenticatedRequest(account: account, appPassword: appPassword) { authSession in
            let components = try parseATURI(postURI)
            let body = CreateGenericRecordRequest(
                repo: authSession.did,
                collection: "app.bsky.feed.postgate",
                record: PostGateRecord(
                    post: postURI,
                    embeddingRules: [.disableRule],
                    createdAt: ISO8601DateFormatter().string(from: .now)
                ),
                rkey: components.rkey
            )
            return try await requestExecutor.send(
                path: "com.atproto.repo.createRecord",
                method: "POST",
                queryItems: [],
                body: body,
                accessToken: authSession.accessJWT,
                hostURL: authSession.pdsURL
            )
        }
    }

    // MARK: - Likes & Reposts

    /// Creates a like on a post.
    func createLike(uri: String, cid: String, account: AppAccount, appPassword: String?) async throws -> CreateRecordResponse {
        try await sessionService.performAuthenticatedRequest(account: account, appPassword: appPassword) { authSession in
            let body = CreateGenericRecordRequest(
                repo: authSession.did,
                collection: "app.bsky.feed.like",
                record: LikeRecord(
                    subject: FeedPostTarget(uri: uri, cid: cid),
                    createdAt: ISO8601DateFormatter().string(from: .now)
                )
            )
            return try await requestExecutor.send(
                path: "com.atproto.repo.createRecord",
                method: "POST",
                queryItems: [],
                body: body,
                accessToken: authSession.accessJWT,
                hostURL: authSession.pdsURL
            )
        }
    }

    /// Creates a repost of a post.
    func createRepost(uri: String, cid: String, account: AppAccount, appPassword: String?) async throws -> CreateRecordResponse {
        try await sessionService.performAuthenticatedRequest(account: account, appPassword: appPassword) { authSession in
            let body = CreateGenericRecordRequest(
                repo: authSession.did,
                collection: "app.bsky.feed.repost",
                record: RepostRecord(
                    subject: FeedPostTarget(uri: uri, cid: cid),
                    createdAt: ISO8601DateFormatter().string(from: .now)
                )
            )
            return try await requestExecutor.send(
                path: "com.atproto.repo.createRecord",
                method: "POST",
                queryItems: [],
                body: body,
                accessToken: authSession.accessJWT,
                hostURL: authSession.pdsURL
            )
        }
    }

    /// Fetches the list of likes on a post.
    func fetchLikes(uri: String, cursor: String? = nil, account: AppAccount, appPassword: String?) async throws -> GetLikesResponse {
        try await sessionService.performAuthenticatedRequest(account: account, appPassword: appPassword) { authSession in
            var queryItems = [URLQueryItem(name: "uri", value: uri), URLQueryItem(name: "limit", value: "100")]
            if let cursor {
                queryItems.append(URLQueryItem(name: "cursor", value: cursor))
            }
            return try await requestExecutor.send(
                path: "app.bsky.feed.getLikes",
                method: "GET",
                queryItems: queryItems,
                accessToken: authSession.accessJWT,
                hostURL: authSession.pdsURL
            )
        }
    }

    /// Batch-fetches posts by their URIs using the public API (no auth required).
    /// Automatically chunks URIs into groups of 25 and runs them in parallel.
    func fetchPosts(uris: [String]) async throws -> [RichPost] {
        guard let url = URL(string: "https://public.api.bsky.app/xrpc/app.bsky.feed.getPosts") else {
            throw BlueskyAPIError.invalidURL
        }
        let chunks = uris.chunked(maxLength: 25)
        return try await withThrowingTaskGroup(of: [RichPost].self) { group in
            for chunk in chunks {
                group.addTask {
                    var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
                    components.queryItems = chunk.map { URLQueryItem(name: "uris", value: $0) }
                    guard let finalURL = components.url else { throw BlueskyAPIError.invalidURL }
                    var req = URLRequest(url: finalURL)
                    req.setValue("application/json", forHTTPHeaderField: "Accept")
                    req.timeoutInterval = 30
                    let (data, httpResponse) = try await self.httpClient.data(for: req, source: "Post Lookup")
                    guard (200 ..< 300).contains(httpResponse.statusCode) else {
                        throw BlueskyAPIError.invalidResponse
                    }
                    let decoded = try JSONDecoder().decode(GetPostsResponse.self, from: data)
                    return decoded.posts
                }
            }
            var allPosts: [RichPost] = []
            for try await batch in group {
                allPosts.append(contentsOf: batch)
            }
            return allPosts
        }
    }

    // MARK: - Record Deletion

    /// Deletes any AT Protocol record by its AT URI.
    func deleteRecord(recordURI: String, account: AppAccount, appPassword: String?) async throws -> EmptyResponse {
        try await sessionService.performAuthenticatedRequest(account: account, appPassword: appPassword) { authSession in
            let components = try parseATURI(recordURI)
            let body = DeleteRecordRequest(repo: components.repo, collection: components.collection, rkey: components.rkey)
            return try await requestExecutor.send(
                path: "com.atproto.repo.deleteRecord",
                method: "POST",
                queryItems: [],
                body: body,
                accessToken: authSession.accessJWT,
                hostURL: authSession.pdsURL
            )
        }
    }

    // MARK: - Search Posts

    /// Searches posts using the `app.bsky.feed.searchPosts` endpoint.
    func searchPosts(q: String, mentions: String? = nil, sort: String? = nil, cursor: String? = nil, limit: Int = 25, account: AppAccount, appPassword: String?) async throws -> SearchPostsResponse {
        try await sessionService.performAuthenticatedRequest(account: account, appPassword: appPassword) { authSession in
            var queryItems = [
                URLQueryItem(name: "q", value: q),
                URLQueryItem(name: "limit", value: "\(limit)"),
            ]
            if let mentions {
                queryItems.append(URLQueryItem(name: "mentions", value: mentions))
            }
            if let sort {
                queryItems.append(URLQueryItem(name: "sort", value: sort))
            }
            if let cursor {
                queryItems.append(URLQueryItem(name: "cursor", value: cursor))
            }
            return try await requestExecutor.send(
                path: "app.bsky.feed.searchPosts",
                method: "GET",
                queryItems: queryItems,
                accessToken: authSession.accessJWT,
                hostURL: authSession.pdsURL
            )
        }
    }

    // MARK: - Notifications

    /// Fetches the account's notifications.
    func fetchNotifications(cursor: String? = nil, limit: Int = 50, account: AppAccount, appPassword: String?) async throws -> ListNotificationsResponse {
        try await sessionService.performAuthenticatedRequest(account: account, appPassword: appPassword) { authSession in
            var queryItems = [URLQueryItem(name: "limit", value: "\(limit)")]
            if let cursor {
                queryItems.append(URLQueryItem(name: "cursor", value: cursor))
            }
            return try await requestExecutor.send(
                path: "app.bsky.notification.listNotifications",
                method: "GET",
                queryItems: queryItems,
                accessToken: authSession.accessJWT,
                hostURL: authSession.pdsURL
            )
        }
    }

    /// Fetches the count of unread notifications.
    func getUnreadCount(account: AppAccount, appPassword: String?) async throws -> Int {
        let response: UnreadCountResponse = try await sessionService.performAuthenticatedRequest(account: account, appPassword: appPassword) { authSession in
            try await requestExecutor.send(
                path: "app.bsky.notification.getUnreadCount",
                method: "GET",
                queryItems: [],
                accessToken: authSession.accessJWT,
                hostURL: authSession.pdsURL
            )
        }
        return response.count
    }

    /// Marks the notification timestamp as seen.
    func updateSeen(at date: Date, account: AppAccount, appPassword: String?) async throws {
        let _: EmptyResponse = try await sessionService.performAuthenticatedRequest(account: account, appPassword: appPassword) { authSession in
            let body = UpdateSeenRequest(seenAt: ISO8601DateFormatter().string(from: date))
            return try await requestExecutor.send(
                path: "app.bsky.notification.updateSeen",
                method: "POST",
                queryItems: [],
                body: body,
                accessToken: authSession.accessJWT,
                hostURL: authSession.pdsURL
            )
        }
    }

    /// Resolves a repost AT URI to the original post URI.
    /// Parses the URI to extract repo/collection/rkey, fetches the repost record,
    /// and returns the `subject.uri` pointing to the original post.
    func resolveRepostToPostURI(_ repostURI: String, account: AppAccount, appPassword: String?) async throws -> String? {
        guard let url = URL(string: repostURI),
              url.scheme == "at",
              let repo = url.host else { return nil }
        // Path is like /app.bsky.feed.repost/rkey
        let components = url.pathComponents.dropFirst() // drop leading "/"
        guard components.count >= 2 else { return nil }
        let collection = components[0]
        let rkey = components[1]

        let response: RepostRecordResponse = try await sessionService.performAuthenticatedRequest(
            account: account, appPassword: appPassword
        ) { authSession in
            try await requestExecutor.send(
                path: "com.atproto.repo.getRecord",
                method: "GET",
                queryItems: [
                    URLQueryItem(name: "repo", value: repo),
                    URLQueryItem(name: "collection", value: collection),
                    URLQueryItem(name: "rkey", value: rkey),
                ],
                accessToken: authSession.accessJWT,
                hostURL: authSession.pdsURL
            )
        }
        return response.value.subject.uri
    }
}

// MARK: - Supporting Types

/// An image attachment for post creation (pre-uploaded blob + alt text).
struct PostImageAttachment {
    let blob: UploadedBlob
    let alt: String
}

/// Response from `com.atproto.repo.getRecord` for resolving a repost record.
private struct RepostRecordResponse: Decodable {
    let value: RepostRecordValue

    struct RepostRecordValue: Decodable {
        let subject: RepostSubject
    }

    struct RepostSubject: Decodable {
        let uri: String
    }
}

/// A video attachment for post creation (pre-uploaded blob + alt text + optional aspect ratio).
struct PostVideoAttachment {
    let blob: UploadedBlob
    let alt: String
    let aspectRatio: (width: Int, height: Int)?
}

/// An external link attachment for post creation.
struct PostExternalAttachment {
    let uri: String
    let title: String
    let description: String
}

private extension Array {
    /// Splits the array into chunks of the given maximum length.
    func chunked(maxLength: Int) -> [[Element]] {
        stride(from: 0, to: count, by: maxLength).map {
            Array(self[$0 ..< Swift.min($0 + maxLength, count)])
        }
    }
}
