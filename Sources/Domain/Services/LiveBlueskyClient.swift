import Foundation

/// Result from fetching actors via ClearSky (blocklist or single-blocklist endpoint).
struct ClearskyBlocklistResult {
    let actors: [BlueskyActor]
    let totalCount: Int
}

/// Primary API client for Bluesky network operations. Provides authenticated access to
/// all major AT Protocol lexicons used by the app: lists, profiles, feeds, posts,
/// notifications, chat, moderation reports, and ClearSky integration.
///
/// Conforms to `BlueskyAuthenticating`, `BlueskyListServicing`, and `BlueskyProfileInspecting`.
///
/// This class is marked `@MainActor` and all state mutations happen on the main actor.
@MainActor
class LiveBlueskyClient: ObservableObject, BlueskyAuthenticating, BlueskyListServicing, BlueskyProfileInspecting {
    /// The AT Protocol service DID for the Bluesky App View proxy.
    private static let bskyAppViewServiceDID = "did:web:api.bsky.app#bsky_appview"
    /// The default base URL for the Bluesky PDS.
    private let baseURL: URL
    private let httpClient: HTTPClient
    private let session: URLSession
    private let requestExecutor: BlueskyRequestExecuting
    private let sessionService: BlueskySessionServicing
    private let clearskyHeartbeat: ClearskyHeartbeatService

    // MARK: - Init

    init(
        baseURL: URL = .bskySocial,
        httpClient: HTTPClient? = nil,
        keychain: KeychainServicing = KeychainService(),
        requestExecutor: BlueskyRequestExecuting? = nil,
        sessionService: BlueskySessionServicing? = nil,
        clearskyHeartbeat: ClearskyHeartbeatService = .shared
    ) {
        self.baseURL = baseURL
        let clientSession = URLSession.shared
        session = clientSession
        self.httpClient = httpClient ?? HTTPClient(session: clientSession)
        self.clearskyHeartbeat = clearskyHeartbeat
        let executor = requestExecutor ?? BlueskyRequestExecutor(baseURL: baseURL, httpClient: self.httpClient)
        self.requestExecutor = executor
        self.sessionService = sessionService ?? BlueskySessionService(
            baseURL: baseURL,
            requestExecutor: executor,
            keychain: keychain
        )
    }

    // MARK: - Cache

    /// Clears all in-memory and on-disk URL cache responses plus the session cache.
    func clearCache() {
        session.configuration.urlCache?.removeAllCachedResponses()
        URLCache.shared.removeAllCachedResponses()
        sessionService.clearSessionCache()
    }

    // MARK: - Authentication & Session

    /// Authenticates against the Bluesky PDS using a handle and app password.
    func authenticate(handle: String, appPassword: String, entrywayURL: URL? = nil) async throws -> BlueskySession {
        try await sessionService.authenticate(handle: handle, appPassword: appPassword, entrywayURL: entrywayURL)
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

    /// Fetches all lists owned by the authenticated account.
    func fetchLists(for account: AppAccount, appPassword: String?) async throws -> [BlueskyList] {
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

    /// Fetches a single list by URI via the owning account's list fetch.
    /// Returns `nil` if the list is not found among the account's lists.
    func fetchList(uri: String, account: AppAccount, appPassword: String?) async throws -> BlueskyList? {
        let lists = try await fetchLists(for: account, appPassword: appPassword)
        return lists.first { $0.id == uri }
    }

    /// Fetches all members of a list with automatic pagination.
    func fetchListMembers(list: BlueskyList, account: AppAccount, appPassword: String?) async throws -> [BlueskyListMember] {
        var allMembers: [BlueskyListMember] = []
        var cursor: String?

        repeat {
            let page = try await fetchListMembersPage(list: list, cursor: cursor, account: account, appPassword: appPassword)
            allMembers.append(contentsOf: page.members)
            cursor = page.cursor
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
                BlueskyListMember(recordURI: $0.uri, actor: BlueskyActor(did: $0.subject.did, handle: $0.subject.handle, displayName: $0.subject.displayName, avatarURL: URL(string: $0.subject.avatar ?? "")), createdAt: parseDate($0.createdAt))
            },
            cursor: response.cursor
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
    /// Returns them sorted by subscription date descending, then alphabetically.
    func fetchSubscribedModerationLists(account: AppAccount, appPassword: String?) async throws -> [SubscribedListInfo] {
        var cursor: String?
        var allLists: [SubscribedListInfo] = []

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
            cursor = response.cursor
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
                description: $0.description
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
            actors: response.actors.map { BlueskyActor(did: $0.did, handle: $0.handle, displayName: $0.displayName, avatarURL: URL(string: $0.avatar ?? "")) },
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

    /// Unblocks an actor by their block record URI. Delegates to `removeMember`.
    func unblockActor(recordURI: String, account: AppAccount, appPassword: String?) async throws {
        try await removeMember(recordURI: recordURI, account: account, appPassword: appPassword)
    }

    /// Follows an actor by DID. Creates a `app.bsky.graph.follow` record.
    func followActor(did actorDID: String, account: AppAccount, appPassword: String?) async throws {
        let _: EmptyResponse = try await sessionService.performAuthenticatedRequest(
            account: account,
            appPassword: appPassword
        ) { authSession in
            let body = CreateGenericRecordRequest(
                repo: authSession.did,
                collection: "app.bsky.graph.follow",
                record: SubjectRecord(type: "app.bsky.graph.follow", subject: actorDID)
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

        let (data, httpResponse) = try await httpClient.data(
            for: request,
            source: "Lists / Relationships",
            origin: "LiveBlueskyClient \(method) xrpc/\(path)"
        )

        if httpResponse.statusCode == 401 {
            throw BlueskyAPIError.unauthorized
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

    /// Fetches a full profile by DID or handle for a given account context.
    /// Returns a `BlueskyProfile` with viewer state, labels, and associated counts.
    func fetchProfile(did actorDID: String, account: AppAccount, appPassword: String?) async throws -> BlueskyProfile {
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

        return BlueskyProfile(
            id: response.did, did: response.did, handle: response.handle,
            displayName: response.displayName, description: response.description,
            websiteURL: URL(string: response.website ?? ""), avatarURL: URL(string: response.avatar ?? ""),
            bannerURL: URL(string: response.banner ?? ""),
            followersCount: response.followersCount, followsCount: response.followsCount, postsCount: response.postsCount,
            listsCount: response.associated?.lists, starterPacksCount: response.associated?.starterPacks,
            createdAt: parseDate(response.createdAt), labels: response.labels?.map(\.val) ?? [],
            viewerState: mapViewerState(response.viewer)
        )
    }

    // MARK: - Clearsky Integration

    /// Checks that ClearSky service is available; throws if the heartbeat has failed.
    private func guardClearskyAvailable() throws {
        guard clearskyHeartbeat.isClearskyAvailable else {
            throw BlueskyAPIError.server("ClearSky is temporarily unavailable")
        }
    }

    /// Fetches the list of actors blocked by the account (the "my blocklist" view).
    func fetchBlockedActors(account: AppAccount, appPassword _: String?) async throws -> ClearskyBlocklistResult {
        try await fetchClearskyActors(account: account, endpoint: "blocklist")
    }

    /// Fetches the list of actors that have blocked the account (the "blocked by" view).
    func fetchBlockedByActors(account: AppAccount, appPassword _: String?) async throws -> ClearskyBlocklistResult {
        try await fetchClearskyActors(account: account, endpoint: "single-blocklist")
    }

    /// Returns the total count of actors the account has blocked.
    func fetchBlockingCount(for account: AppAccount) async throws -> Int {
        try await fetchClearskyActors(account: account, endpoint: "blocklist").totalCount
    }

    /// Returns the total count of actors that have blocked the account.
    func fetchBlockedByCount(for account: AppAccount) async throws -> Int {
        try await fetchClearskyActors(account: account, endpoint: "single-blocklist").totalCount
    }

    /// Returns the count of actors that block the account but are not blocked back.
    func fetchUnblockedBlockersCount(for account: AppAccount) async throws -> Int {
        try await fetchUnblockedBlockerActors(account: account, appPassword: nil).count
    }

    /// Fetches the set of DIDs from a ClearSky endpoint (no profile resolution).
    private func fetchClearskyDIDs(actorDID: String, endpoint: String) async throws -> Set<String> {
        let entries = try await fetchClearskyEntries(actorDID: actorDID, endpoint: endpoint)
        return Set(entries.map(\.did))
    }

    /// Paginates through all pages of a ClearSky endpoint.
    /// Stops early if a page returns fewer than 100 entries (last page).
    private func fetchClearskyEntries(actorDID: String, endpoint: String) async throws -> [ClearskyBlocklistEntry] {
        var allEntries: [ClearskyBlocklistEntry] = []
        var page = 1
        repeat {
            let urlString = page == 1
                ? "https://public.api.clearsky.services/api/v1/anon/\(endpoint)/\(actorDID)"
                : "https://public.api.clearsky.services/api/v1/anon/\(endpoint)/\(actorDID)/\(page)"
            guard let url = URL(string: urlString) else { throw BlueskyAPIError.invalidURL }
            var request = URLRequest(url: url)
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.timeoutInterval = 30
            let (data, httpResponse) = try await httpClient.data(for: request, source: "Clearsky Blocklists")
            guard (200 ..< 300).contains(httpResponse.statusCode) else {
                return []
            }
            guard let decoded = try? JSONDecoder().decode(ClearskyBlocklistResponse.self, from: data) else {
                return []
            }
            let entries = decoded.data.blocklist
            allEntries.append(contentsOf: entries)
            // If fewer than 100 entries, this was the last page.
            if entries.count < 100 { break }
            page += 1
        } while true
        return allEntries
    }

    /// Fetches actors that block the account but are not blocked back.
    /// Resolves profiles in parallel batches and sorts by block date descending.
    func fetchUnblockedBlockerActors(account: AppAccount, appPassword _: String?) async throws -> [BlueskyActor] {
        try guardClearskyAvailable()
        let actorDID = try await resolveAccountDID(account)

        // Fetch blocked (actors we block) and blocked-by (actors that block us) in parallel.
        async let blockedDIDsTask = fetchClearskyDIDs(actorDID: actorDID, endpoint: "blocklist")
        async let blockedByEntriesTask = fetchClearskyEntries(actorDID: actorDID, endpoint: "single-blocklist")
        let (blockedDIDs, blockedByEntries) = try await (blockedDIDsTask, blockedByEntriesTask)

        // Filter to only those that block us but aren't on our blocklist.
        let candidateEntries = blockedByEntries.filter { !blockedDIDs.contains($0.did) }
        guard !candidateEntries.isEmpty else { return [] }

        var blockedDates = [String: String]()
        for entry in candidateEntries {
            blockedDates[entry.did] = entry.blockedDate
        }

        var result = await resolveProfilesBestEffort(dids: candidateEntries.map(\.did))
        for index in result.indices {
            if let dateString = blockedDates[result[index].did] {
                result[index].blockedDate = parseDate(dateString)
            }
        }

        return result.sorted { ($0.blockedDate ?? .distantPast) > ($1.blockedDate ?? .distantPast) }
    }

    /// Resolves profiles for a list of DIDs in parallel batches of 25.
    /// Silently ignores individual batch failures (best-effort resolution).
    private func resolveProfilesBestEffort(dids: [String]) async -> [BlueskyActor] {
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
    /// otherwise resolves the handle to a DID via ClearSky.
    private func resolveAccountDID(_ account: AppAccount) async throws -> String {
        if let did = account.did { return did }
        return try await resolveHandleToDID(handle: account.handle)
    }

    /// Fetches ClearSky blocklist entries and resolves all actor profiles.
    private func fetchClearskyActors(account: AppAccount, endpoint: String) async throws -> ClearskyBlocklistResult {
        try guardClearskyAvailable()
        let actorDID = try await resolveAccountDID(account)

        let entries = try await fetchClearskyEntries(actorDID: actorDID, endpoint: endpoint)
        var allDIDs = Set<String>()
        var blockedDates = [String: String]()
        for entry in entries {
            allDIDs.insert(entry.did)
            blockedDates[entry.did] = entry.blockedDate
        }

        guard !allDIDs.isEmpty else {
            return ClearskyBlocklistResult(actors: [], totalCount: 0)
        }

        // If profile resolution fails entirely, still return a partial result with the total count.
        guard let actors = try? await resolveProfiles(dids: Array(allDIDs).sorted()) else {
            return ClearskyBlocklistResult(actors: [], totalCount: allDIDs.count)
        }
        var result = actors
        for i in result.indices {
            if let dateStr = blockedDates[result[i].did] {
                result[i].blockedDate = parseDate(dateStr)
            }
        }
        return ClearskyBlocklistResult(actors: result, totalCount: allDIDs.count)
    }

    /// Fetches all ClearSky moderation lists for a given handle with pagination.
    func fetchClearskyLists(handle: String) async throws -> [ClearskyListEntry] {
        try guardClearskyAvailable()
        var allLists: [ClearskyListEntry] = []
        var page = 1
        repeat {
            let urlString = page == 1
                ? "https://api.clearsky.app/csky/api/v1/get-list/\(handle)"
                : "https://api.clearsky.app/csky/api/v1/get-list/\(handle)/\(page)"
            AppLogger.performance.debug("Fetching Clearsky lists page \(page) from: \(urlString, privacy: .public)")
            guard let url = URL(string: urlString) else { throw BlueskyAPIError.invalidURL }
            var request = URLRequest(url: url)
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.timeoutInterval = 30
            let (data, httpResponse) = try await httpClient.data(for: request, source: "Clearsky Lists")
            guard (200 ..< 300).contains(httpResponse.statusCode) else {
                if page == 1 {
                    if let body = String(data: data, encoding: .utf8) {
                        AppLogger.performance.error("Clearsky lists API returned \(httpResponse.statusCode): \(body, privacy: .public)")
                    }
                    throw BlueskyAPIError.server("Clearsky returned HTTP \(httpResponse.statusCode)")
                }
                break
            }
            let decoded = try JSONDecoder().decode(ClearskyListsResponse.self, from: data)
            allLists += decoded.data.lists
            if decoded.data.lists.count < 100 { break }
            page += 1
        } while true
        return allLists
    }

    // MARK: - DID Resolution & PLC Audit

    /// Resolves profiles for an array of DIDs in parallel batches of 25.
    /// Throws on the first batch failure.
    private func resolveProfiles(dids: [String]) async throws -> [BlueskyActor] {
        try await withThrowingTaskGroup(of: [BlueskyActor].self) { group in
            var offset = 0
            while offset < dids.count {
                let chunk = dids[offset ..< min(offset + 25, dids.count)]
                offset += 25
                group.addTask { [httpClient] in
                    try await Self.fetchProfileBatch(identifiers: Array(chunk), httpClient: httpClient)
                }
            }
            var actors: [BlueskyActor] = []
            for try await batch in group {
                actors.append(contentsOf: batch)
            }
            return actors
        }
    }

    /// Fetches profiles for an array of identifiers via the instance method (will be used by other parts of the app).
    func fetchProfileBatch(identifiers: [String]) async throws -> [BlueskyActor] {
        try await Self.fetchProfileBatch(identifiers: identifiers, httpClient: httpClient)
    }

    /// Static batch profile lookup via `app.bsky.actor.getProfiles`. Bypasses authentication
    /// using the public API endpoint. Used by ClearSky resolution paths.
    static func fetchProfileBatch(identifiers: [String], httpClient: HTTPClient) async throws -> [BlueskyActor] {
        let actorsParam = identifiers.map { URLQueryItem(name: "actors", value: $0) }
        guard let profilesURL = URL(string: "https://public.api.bsky.app/xrpc/app.bsky.actor.getProfiles") else {
            throw BlueskyAPIError.invalidURL
        }
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
        return decoded.profiles.map {
            BlueskyActor(did: $0.did, handle: $0.handle, displayName: $0.displayName, avatarURL: URL(string: $0.avatar ?? ""))
        }
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

    /// Resolves a handle to a DID via the ClearSky `get-did` endpoint.
    private func resolveHandleToDID(handle: String) async throws -> String {
        try guardClearskyAvailable()
        guard let url = URL(string: "https://public.api.clearsky.services/api/v1/anon/get-did/\(handle)") else {
            throw BlueskyAPIError.invalidURL
        }
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 30
        let (data, httpResponse) = try await httpClient.data(for: request, source: "Handle Resolution")
        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            throw BlueskyAPIError.invalidResponse
        }
        struct ClearskyDIDResponse: Decodable {
            let data: ClearskyDIDData
        }
        struct ClearskyDIDData: Decodable {
            let didIdentifier: String
            enum CodingKeys: String, CodingKey { case didIdentifier = "did_identifier" }
        }
        let decoded = try JSONDecoder().decode(ClearskyDIDResponse.self, from: data)
        return decoded.data.didIdentifier
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
    func fetchRichFeed(did: String, cursor: String? = nil, account: AppAccount, appPassword: String?) async throws -> RichFeedResponse {
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
                if pageCount >= maxPages { break }
                lastError = nil
            } catch {
                lastError = error
                // If we have a cursor, we can continue from the error; if no cursor, rethrow.
                if cursor == nil { throw error }
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
            if let cursor { queryItems.append(URLQueryItem(name: "cursor", value: cursor)) }
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
                BlueskyActor(did: $0.did, handle: $0.handle, displayName: $0.displayName, avatarURL: URL(string: $0.avatar ?? ""), createdAt: parseDate($0.createdAt))
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
                if pageCount >= maxPages { break }
                lastError = nil
            } catch {
                lastError = error
                if cursor == nil { throw error }
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
            if let cursor { queryItems.append(URLQueryItem(name: "cursor", value: cursor)) }
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
                BlueskyActor(did: $0.did, handle: $0.handle, displayName: $0.displayName, avatarURL: URL(string: $0.avatar ?? ""), createdAt: parseDate($0.createdAt))
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
        let (profile, _, starterPacks): (ProfileViewDetailed, ListsWithMembershipResponse?, StarterPacksWithMembershipResponse?) =
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

        // Fetch list memberships separately (paginated through the account's own lists).
        let listMemberships = await fetchListMemberships(for: profile.did, account: account, appPassword: appPassword)

        return ProfileInspection(
            profile: mappedProfile,
            listMemberships: listMemberships,
            starterPackMemberships: starterPacks?.starterPacksWithMembership.map {
                ProfileStarterPackMembership(uri: $0.starterPack.uri, name: $0.starterPack.name ?? $0.starterPack.uri, memberCount: $0.starterPack.listItemCount, joinedAllTimeCount: $0.starterPack.joinedAllTimeCount, isMember: $0.listItem != nil)
            } ?? []
        )
    }

    /// Checks which of the account's lists contain a given target DID.
    /// Pages through up to 5 pages of each list to find the member.
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

                    // Search up to 5 pages of members per list.
                    while foundItem == nil, pagesChecked < 5 {
                        guard let page = try? await self.fetchListMembersPage(
                            list: list, cursor: cursor,
                            account: account, appPassword: appPassword
                        ) else { break }
                        foundItem = page.members.first { $0.actor.did == targetDID }
                        cursor = page.cursor
                        pagesChecked += 1
                        if cursor == nil { break }
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
                if let result { results.append(result) }
            }
            return results
        }
    }

    // MARK: - Blob Upload

    /// Uploads binary data (image/video) to the PDS via `com.atproto.repo.uploadBlob`.
    func uploadBlob(data: Data, mimeType: String, account: AppAccount, appPassword: String?) async throws -> UploadBlobResponse {
        try await sessionService.performAuthenticatedRequest(account: account, appPassword: appPassword) { authSession in
            let url = authSession.pdsURL.appendingPathComponent("xrpc/com.atproto.repo.uploadBlob")
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("Bearer \(authSession.accessJWT)", forHTTPHeaderField: "Authorization")
            request.setValue(mimeType, forHTTPHeaderField: "Content-Type")
            request.httpBody = data
            let (responseData, _) = try await httpClient.data(for: request, source: "Blob Upload")
            return try JSONDecoder().decode(UploadBlobResponse.self, from: responseData)
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

    /// Internal response type for the `app.bsky.feed.searchPosts` endpoint.
    struct SearchPostsResponse: Decodable {
        let cursor: String?
        let hitsTotal: Int?
        let posts: [RichPost]
    }

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
}

// MARK: - Supporting Types

/// An image attachment for post creation (pre-uploaded blob + alt text).
struct PostImageAttachment {
    let blob: UploadedBlob
    let alt: String
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
