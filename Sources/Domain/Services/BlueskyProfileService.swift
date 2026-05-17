import Foundation

@MainActor
final class BlueskyProfileService: ObservableObject, BlueskyProfileInspecting {
    private let requestExecutor: BlueskyRequestExecuting
    private let sessionService: BlueskySessionServicing

    init(requestExecutor: BlueskyRequestExecuting, sessionService: BlueskySessionServicing) {
        self.requestExecutor = requestExecutor
        self.sessionService = sessionService
    }

    func searchActors(
        query: String,
        account: AppAccount,
        appPassword: String?
    ) async throws -> [BlueskyActor] {
        let page = try await searchActorsPage(
            query: query,
            cursor: nil,
            account: account,
            appPassword: appPassword
        )
        return page.actors
    }

    func searchActorsPage(
        query: String,
        cursor: String?,
        account: AppAccount,
        appPassword: String?
    ) async throws -> PagedActorSearch {
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
                    avatarURL: URL(string: $0.avatar ?? "")
                )
            },
            cursor: response.cursor
        )
    }

    func fetchFollowers(
        actor actorDID: String,
        account: AppAccount,
        appPassword: String?
    ) async throws -> [BlueskyActor] {
        var all: [BlueskyActor] = []
        var cursor: String?
        var pageCount = 0
        let maxPages = 50
        repeat {
            let page = try await fetchFollowersPage(actor: actorDID, cursor: cursor, account: account, appPassword: appPassword)
            all.append(contentsOf: page.actors)
            cursor = page.cursor
            pageCount += 1
            if pageCount >= maxPages { break }
        } while cursor != nil
        return all
    }

    func fetchFollowersPage(
        actor actorDID: String,
        cursor: String?,
        account: AppAccount,
        appPassword: String?
    ) async throws -> PagedActorSearch {
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
                    createdAt: parseDate($0.createdAt)
                )
            },
            cursor: response.cursor
        )
    }

    func fetchProfile(
        did actorDID: String,
        account: AppAccount,
        appPassword: String?
    ) async throws -> BlueskyProfile {
        let response: ProfileViewDetailed = try await sessionService.performAuthenticatedRequest(
            account: account,
            appPassword: appPassword
        ) { authSession in
            try await requestExecutor.send(
                path: "app.bsky.actor.getProfile",
                method: "GET",
                queryItems: [
                    URLQueryItem(name: "actor", value: actorDID),
                ],
                accessToken: authSession.accessJWT,
                hostURL: authSession.pdsURL
            )
        }

        return BlueskyProfile(
            id: response.did,
            did: response.did,
            handle: response.handle,
            displayName: response.displayName,
            description: response.description,
            websiteURL: URL(string: response.website ?? ""),
            avatarURL: URL(string: response.avatar ?? ""),
            bannerURL: URL(string: response.banner ?? ""),
            followersCount: response.followersCount,
            followsCount: response.followsCount,
            postsCount: response.postsCount,

            listsCount: response.associated?.lists,
            starterPacksCount: response.associated?.starterPacks,
            createdAt: parseDate(response.createdAt),
            labels: response.labels?.map(\.val) ?? [],
            viewerState: mapViewerState(response.viewer)
        )
    }

    func inspectProfile(
        query: String,
        account: AppAccount,
        appPassword: String?
    ) async throws -> ProfileInspection {
        let actor = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !actor.isEmpty else {
            throw BlueskyAPIError.server("Enter a Bluesky handle or DID.")
        }

        let (profile, lists, starterPacks): (ProfileViewDetailed, ListsWithMembershipResponse, StarterPacksWithMembershipResponse) =
            try await sessionService.performAuthenticatedRequest(
                account: account,
                appPassword: appPassword
            ) { authSession in
                async let profileResponse: ProfileViewDetailed = requestExecutor.send(
                    path: "app.bsky.actor.getProfile",
                    method: "GET",
                    queryItems: [URLQueryItem(name: "actor", value: actor)],
                    accessToken: authSession.accessJWT,
                    hostURL: authSession.pdsURL
                )
                async let listMembershipResponse: ListsWithMembershipResponse = requestExecutor.send(
                    path: "app.bsky.graph.getListsWithMembership",
                    method: "GET",
                    queryItems: [
                        URLQueryItem(name: "actor", value: actor),
                        URLQueryItem(name: "limit", value: "100"),
                    ],
                    accessToken: authSession.accessJWT,
                    hostURL: authSession.pdsURL
                )
                async let starterPackMembershipResponse: StarterPacksWithMembershipResponse = requestExecutor.send(
                    path: "app.bsky.graph.getStarterPacksWithMembership",
                    method: "GET",
                    queryItems: [
                        URLQueryItem(name: "actor", value: actor),
                        URLQueryItem(name: "limit", value: "100"),
                    ],
                    accessToken: authSession.accessJWT,
                    hostURL: authSession.pdsURL
                )

                return try await (profileResponse, listMembershipResponse, starterPackMembershipResponse)
            }

        let mappedProfile = BlueskyProfile(
            id: profile.did,
            did: profile.did,
            handle: profile.handle,
            displayName: profile.displayName,
            description: profile.description,
            websiteURL: URL(string: profile.website ?? ""),
            avatarURL: URL(string: profile.avatar ?? ""),
            bannerURL: URL(string: profile.banner ?? ""),
            followersCount: profile.followersCount,
            followsCount: profile.followsCount,
            postsCount: profile.postsCount,
            listsCount: profile.associated?.lists,
            starterPacksCount: profile.associated?.starterPacks,
            createdAt: parseDate(profile.createdAt),
            labels: profile.labels?.map(\.val) ?? [],
            viewerState: mapViewerState(profile.viewer)
        )

        return ProfileInspection(
            profile: mappedProfile,
            listMemberships: lists.listsWithMembership.map {
                ProfileListMembership(
                    listURI: $0.list.uri,
                    name: $0.list.name,
                    kind: $0.list.purpose.kind,
                    memberCount: $0.list.listItemCount,
                    isMember: $0.listItem != nil,
                    listItemRecordURI: $0.listItem?.uri
                )
            },
            starterPackMemberships: starterPacks.starterPacksWithMembership.map {
                ProfileStarterPackMembership(
                    uri: $0.starterPack.uri,
                    name: $0.starterPack.name ?? $0.starterPack.uri,
                    memberCount: $0.starterPack.listItemCount,
                    joinedAllTimeCount: $0.starterPack.joinedAllTimeCount,
                    isMember: $0.listItem != nil
                )
            }
        )
    }

    func fetchFollowing(
        actor actorDID: String,
        account: AppAccount,
        appPassword: String?
    ) async throws -> [BlueskyActor] {
        var all: [BlueskyActor] = []
        var cursor: String?
        var pageCount = 0
        let maxPages = 50
        repeat {
            let page = try await fetchFollowingPage(actor: actorDID, cursor: cursor, account: account, appPassword: appPassword)
            all.append(contentsOf: page.actors)
            cursor = page.cursor
            pageCount += 1
            if pageCount >= maxPages { break }
        } while cursor != nil
        return all
    }

    func fetchFollowingPage(
        actor actorDID: String,
        cursor: String?,
        account: AppAccount,
        appPassword: String?
    ) async throws -> PagedActorSearch {
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
                BlueskyActor(did: $0.did, handle: $0.handle, displayName: $0.displayName, avatarURL: URL(string: $0.avatar ?? ""), createdAt: parseDate($0.createdAt))
            },
            cursor: response.cursor
        )
    }

    func blockActor(
        did actorDID: String,
        account: AppAccount,
        appPassword: String?
    ) async throws {
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

    func unblockActor(
        recordURI: String,
        account: AppAccount,
        appPassword: String?
    ) async throws {
        let record = try parseATURI(recordURI)
        let _: EmptyResponse = try await sessionService.performAuthenticatedRequest(
            account: account,
            appPassword: appPassword
        ) { authSession in
            let body = DeleteRecordRequest(
                repo: authSession.did,
                collection: record.collection,
                rkey: record.rkey
            )

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

    func followActor(
        did actorDID: String,
        account: AppAccount,
        appPassword: String?
    ) async throws {
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

    func unfollowActor(
        recordURI: String,
        account: AppAccount,
        appPassword: String?
    ) async throws {
        let record = try parseATURI(recordURI)
        let _: EmptyResponse = try await sessionService.performAuthenticatedRequest(
            account: account,
            appPassword: appPassword
        ) { authSession in
            let body = DeleteRecordRequest(
                repo: authSession.did,
                collection: record.collection,
                rkey: record.rkey
            )

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

    func muteActor(
        did actorDID: String,
        account: AppAccount,
        appPassword: String?
    ) async throws {
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

    func unmuteActor(
        did actorDID: String,
        account: AppAccount,
        appPassword: String?
    ) async throws {
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
}
