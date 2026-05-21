import Foundation

struct ClearskyBlocklistResult {
    let actors: [BlueskyActor]
    let totalCount: Int
}

@MainActor
class LiveBlueskyClient: ObservableObject, BlueskyAuthenticating, BlueskyListServicing, BlueskyProfileInspecting {
    private let baseURL: URL
    private let httpClient: HTTPClient
    private let session: URLSession
    private let requestExecutor: BlueskyRequestExecuting
    private let sessionService: BlueskySessionServicing
    private let clearskyHeartbeat: ClearskyHeartbeatService

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

    func clearCache() {
        session.configuration.urlCache?.removeAllCachedResponses()
        URLCache.shared.removeAllCachedResponses()
        sessionService.clearSessionCache()
    }

    // MARK: - Authentication & Session

    func authenticate(handle: String, appPassword: String, entrywayURL: URL? = nil) async throws -> BlueskySession {
        try await sessionService.authenticate(handle: handle, appPassword: appPassword, entrywayURL: entrywayURL)
    }

    func persistSession(_ authSession: BlueskySession, for account: AppAccount) async throws {
        try await sessionService.persistSession(authSession, for: account)
    }

    func deletePersistedSession(for account: AppAccount) throws {
        try sessionService.deletePersistedSession(for: account)
    }

    func restoreSessions(for accounts: [AppAccount]) async {
        await sessionService.restoreSessions(for: accounts)
    }

    // MARK: - List Operations

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

    func fetchList(uri: String, account: AppAccount, appPassword: String?) async throws -> BlueskyList? {
        let lists = try await fetchLists(for: account, appPassword: appPassword)
        return lists.first { $0.id == uri }
    }

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

    func searchActors(query: String, account: AppAccount, appPassword: String?) async throws -> [BlueskyActor] {
        let page = try await searchActorsPage(query: query, cursor: nil, account: account, appPassword: appPassword)
        return page.actors
    }

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

    func unblockActor(recordURI: String, account: AppAccount, appPassword: String?) async throws {
        try await removeMember(recordURI: recordURI, account: account, appPassword: appPassword)
    }

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

    func unfollowActor(recordURI: String, account: AppAccount, appPassword: String?) async throws {
        try await removeMember(recordURI: recordURI, account: account, appPassword: appPassword)
    }

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

    private static let bskyLabelerDID = "did:plc:ar7c4by46qjdydhdevvrndac"

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

    func reportAccount(did targetDID: String, reason: String?, account: AppAccount, appPassword: String?) async throws {
        try await reportAccount(
            did: targetDID,
            selectedReason: nil,
            reason: reason,
            account: account,
            appPassword: appPassword
        )
    }

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

    func reportList(_ list: BlueskyList, reason: String?, account: AppAccount, appPassword: String?) async throws {
        try await reportList(
            list,
            selectedReason: nil,
            reason: reason,
            account: account,
            appPassword: appPassword
        )
    }

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

    private func guardClearskyAvailable() throws {
        guard clearskyHeartbeat.isClearskyAvailable else {
            throw BlueskyAPIError.server("ClearSky is temporarily unavailable")
        }
    }

    func fetchBlockedActors(account: AppAccount, appPassword _: String?) async throws -> ClearskyBlocklistResult {
        try await fetchClearskyActors(account: account, endpoint: "blocklist")
    }

    func fetchBlockedByActors(account: AppAccount, appPassword _: String?) async throws -> ClearskyBlocklistResult {
        try await fetchClearskyActors(account: account, endpoint: "single-blocklist")
    }

    func fetchBlockingCount(for account: AppAccount) async throws -> Int {
        try await fetchClearskyActors(account: account, endpoint: "blocklist").totalCount
    }

    func fetchBlockedByCount(for account: AppAccount) async throws -> Int {
        try await fetchClearskyActors(account: account, endpoint: "single-blocklist").totalCount
    }

    func fetchUnblockedBlockersCount(for account: AppAccount) async throws -> Int {
        try guardClearskyAvailable()
        let actorDID = try await resolveAccountDID(account)

        async let blockedDIDs = fetchClearskyDIDs(actorDID: actorDID, endpoint: "blocklist")
        async let blockedByDIDs = fetchClearskyDIDs(actorDID: actorDID, endpoint: "single-blocklist")
        let (blocked, blockedBy) = try await (blockedDIDs, blockedByDIDs)

        return blockedBy.subtracting(blocked).count
    }

    private func fetchClearskyDIDs(actorDID: String, endpoint: String) async throws -> Set<String> {
        var allDIDs = Set<String>()
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
                return Set()
            }
            guard let decoded = try? JSONDecoder().decode(ClearskyBlocklistResponse.self, from: data) else {
                return Set()
            }
            let entries = decoded.data.blocklist
            for entry in entries {
                allDIDs.insert(entry.did)
            }
            if entries.count < 100 { break }
            page += 1
        } while true
        return allDIDs
    }

    private func resolveAccountDID(_ account: AppAccount) async throws -> String {
        if let did = account.did { return did }
        return try await resolveHandleToDID(handle: account.handle)
    }

    private func fetchClearskyActors(account: AppAccount, endpoint: String) async throws -> ClearskyBlocklistResult {
        try guardClearskyAvailable()
        let actorDID = try await resolveAccountDID(account)

        var allDIDs = Set<String>()
        var blockedDates = [String: String]()
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
                return ClearskyBlocklistResult(actors: [], totalCount: 0)
            }
            guard let decoded = try? JSONDecoder().decode(ClearskyBlocklistResponse.self, from: data) else {
                return ClearskyBlocklistResult(actors: [], totalCount: 0)
            }
            let entries = decoded.data.blocklist
            for entry in entries {
                allDIDs.insert(entry.did)
                blockedDates[entry.did] = entry.blockedDate
            }
            if entries.count < 100 { break }
            page += 1
        } while true

        guard !allDIDs.isEmpty else {
            return ClearskyBlocklistResult(actors: [], totalCount: 0)
        }

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

    func fetchProfileBatch(identifiers: [String]) async throws -> [BlueskyActor] {
        try await Self.fetchProfileBatch(identifiers: identifiers, httpClient: httpClient)
    }

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

    func fetchPostThread(uri: String, account: AppAccount, appPassword: String?) async throws -> GetPostThreadResponse {
        try await sessionService.performAuthenticatedRequest(
            account: account,
            appPassword: appPassword
        ) { authSession in
            try await requestExecutor.send(
                path: "app.bsky.feed.getPostThread",
                method: "GET",
                queryItems: [URLQueryItem(name: "uri", value: uri)],
                accessToken: authSession.accessJWT,
                hostURL: authSession.pdsURL
            )
        }
    }

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
                if cursor == nil { throw error }
                break
            }
        } while cursor != nil
        if all.isEmpty, let lastError {
            throw lastError
        }
        return all
    }

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

    func inspectProfile(query: String, account: AppAccount, appPassword: String?) async throws -> ProfileInspection {
        let actor = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !actor.isEmpty else {
            throw BlueskyAPIError.server("Enter a Bluesky handle or DID.")
        }

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

        let listMemberships: [ProfileListMembership]
        if let lists {
            listMemberships = lists.listsWithMembership.map {
                ProfileListMembership(listURI: $0.list.uri, name: $0.list.name, kind: $0.list.purpose.kind, memberCount: $0.list.listItemCount, isMember: $0.listItem != nil, listItemRecordURI: $0.listItem?.uri)
            }
        } else {
            listMemberships = await fetchListMemberships(for: profile.did, account: account, appPassword: appPassword)
        }

        return ProfileInspection(
            profile: mappedProfile,
            listMemberships: listMemberships,
            starterPackMemberships: starterPacks?.starterPacksWithMembership.map {
                ProfileStarterPackMembership(uri: $0.starterPack.uri, name: $0.starterPack.name ?? $0.starterPack.uri, memberCount: $0.starterPack.listItemCount, joinedAllTimeCount: $0.starterPack.joinedAllTimeCount, isMember: $0.listItem != nil)
            } ?? []
        )
    }

    func fetchListMemberships(
        for targetDID: String,
        account: AppAccount,
        appPassword: String?
    ) async -> [ProfileListMembership] {
        guard let lists = try? await fetchLists(for: account, appPassword: appPassword) else {
            return []
        }

        return await withTaskGroup(of: ProfileListMembership?.self) { group in
            for list in lists {
                group.addTask {
                    var cursor: String?
                    var foundItem: BlueskyListMember?
                    var pagesChecked = 0

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

    func createPost(
        text: String,
        images: [PostImageAttachment]? = nil,
        video: PostVideoAttachment? = nil,
        replyTo: (parentURI: String, parentCID: String, rootURI: String, rootCID: String)? = nil,
        quote: (uri: String, cid: String)? = nil,
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

    struct SearchPostsResponse: Decodable {
        let cursor: String?
        let hitsTotal: Int?
        let posts: [RichPost]
    }

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

struct PostImageAttachment {
    let blob: UploadedBlob
    let alt: String
}

struct PostVideoAttachment {
    let blob: UploadedBlob
    let alt: String
    let aspectRatio: (width: Int, height: Int)?
}

private extension Array {
    func chunked(maxLength: Int) -> [[Element]] {
        stride(from: 0, to: count, by: maxLength).map {
            Array(self[$0 ..< Swift.min($0 + maxLength, count)])
        }
    }
}
