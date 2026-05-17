import Foundation

@MainActor
final class PreviewBlueskyClient: LiveBlueskyClient {
    private let previewActors = [
        BlueskyActor(did: "did:plc:1", handle: "alice.bsky.social", displayName: "Alice Chen"),
        BlueskyActor(did: "did:plc:2", handle: "moderator.bsky.social", displayName: "Moderator Desk"),
        BlueskyActor(did: "did:plc:3", handle: "safetylab.bsky.social", displayName: "Safety Lab"),
        BlueskyActor(did: "did:plc:4", handle: "bskynews.bsky.social", displayName: "Bluesky News"),
        BlueskyActor(did: "did:plc:5", handle: "curation.team", displayName: "Curation Team"),
        BlueskyActor(did: "did:plc:6", handle: "reports.ops", displayName: "Reports Ops"),
    ]

    override func restoreSessions(for _: [AppAccount]) async {}

    override func authenticate(handle: String, appPassword _: String, entrywayURL _: URL? = nil) async throws -> BlueskySession {
        BlueskySession(
            did: "did:plc:previewaccount",
            handle: handle,
            accessJWT: "preview-access",
            refreshJWT: nil,
            pdsURL: URL(string: "https://bsky.social")!
        )
    }

    override func fetchLists(for account: AppAccount, appPassword _: String?) async throws -> [BlueskyList] {
        try await Task.sleep(for: .milliseconds(150))

        let seed = abs(account.handle.hashValue)
        let regularBase = 2 + (seed % 4)
        let moderationBase = 1 + (seed % 3)

        return [
            BlueskyList(
                id: "\(account.handle)-mod-1",
                name: "Spam Watch",
                description: "Accounts frequently reported for spam patterns.",
                memberCount: 120 + moderationBase,
                kind: .moderation
            ),
            BlueskyList(
                id: "\(account.handle)-mod-2",
                name: "Reply Filters",
                description: "Aggressive reply actors tracked for moderation review.",
                memberCount: 42 + moderationBase,
                kind: .moderation
            ),
            BlueskyList(
                id: "\(account.handle)-list-1",
                name: "Trusted Sources",
                description: "Accounts curated for signal over noise.",
                memberCount: 65 + regularBase,
                kind: .regular
            ),
            BlueskyList(
                id: "\(account.handle)-list-2",
                name: "Community Core",
                description: "People to monitor for community health updates.",
                memberCount: 18 + regularBase,
                kind: .regular
            ),
            BlueskyList(
                id: "\(account.handle)-list-3",
                name: "New Reports",
                description: "Freshly observed accounts pending deeper review.",
                memberCount: 7 + regularBase,
                kind: .regular
            ),
        ]
    }

    override func fetchListMembers(
        list: BlueskyList,
        account: AppAccount,
        appPassword: String?
    ) async throws -> [BlueskyListMember] {
        var cursor: String?
        var allMembers: [BlueskyListMember] = []

        repeat {
            let page = try await fetchListMembersPage(
                list: list,
                cursor: cursor,
                account: account,
                appPassword: appPassword
            )
            allMembers.append(contentsOf: page.members)
            cursor = page.cursor
        } while cursor != nil

        return allMembers
    }

    override func fetchListMembersPage(
        list: BlueskyList,
        cursor: String?,
        account _: AppAccount,
        appPassword _: String?
    ) async throws -> PagedListMembers {
        try await Task.sleep(for: .milliseconds(120))

        let members = previewMembers(for: list)
        let pageSize = 3
        let startIndex = Int(cursor ?? "0") ?? 0
        let endIndex = min(startIndex + pageSize, members.count)
        let nextCursor = endIndex < members.count ? String(endIndex) : nil

        return PagedListMembers(
            members: Array(members[startIndex ..< endIndex]),
            cursor: nextCursor
        )
    }

    override func searchActors(
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

    override func searchActorsPage(
        query: String,
        cursor: String?,
        account _: AppAccount,
        appPassword _: String?
    ) async throws -> PagedActorSearch {
        try await Task.sleep(for: .milliseconds(120))

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else {
            return PagedActorSearch(actors: [], cursor: nil)
        }

        let matches = previewActors.filter {
            $0.handle.lowercased().contains(trimmed) ||
                ($0.displayName?.lowercased().contains(trimmed) ?? false)
        }
        let pageSize = 3
        let startIndex = Int(cursor ?? "0") ?? 0
        let endIndex = min(startIndex + pageSize, matches.count)
        let nextCursor = endIndex < matches.count ? String(endIndex) : nil

        return PagedActorSearch(
            actors: Array(matches[startIndex ..< endIndex]),
            cursor: nextCursor
        )
    }

    override func addActor(
        did actorDID: String,
        to _: BlueskyList,
        account _: AppAccount,
        appPassword _: String?
    ) async throws -> String {
        try await Task.sleep(for: .milliseconds(100))
        return "at://\(actorDID)/app.bsky.graph.listitem/\(UUID().uuidString)"
    }

    override func removeMember(
        recordURI _: String,
        account _: AppAccount,
        appPassword _: String?
    ) async throws {
        try await Task.sleep(for: .milliseconds(100))
    }

    override func createList(name: String, description: String, kind: BlueskyList.Kind, account _: AppAccount, appPassword _: String?) async throws -> BlueskyList {
        try await Task.sleep(for: .milliseconds(100))
        let id = "at://did:plc:preview/app.bsky.graph.list/\(UUID().uuidString)"
        return BlueskyList(id: id, name: name, description: description, memberCount: 0, kind: kind)
    }

    override func deleteList(list _: BlueskyList, account _: AppAccount, appPassword _: String?) async throws {
        try await Task.sleep(for: .milliseconds(100))
    }

    override func updateListMetadata(
        list: BlueskyList,
        title: String,
        description: String,
        account _: AppAccount,
        appPassword _: String?
    ) async throws -> BlueskyList {
        try await Task.sleep(for: .milliseconds(120))

        return BlueskyList(
            id: list.id,
            name: title,
            description: description,
            memberCount: list.memberCount,
            kind: list.kind
        )
    }

    override func fetchFollowers(
        actor _: String,
        account _: AppAccount,
        appPassword _: String?
    ) async throws -> [BlueskyActor] {
        try await Task.sleep(for: .milliseconds(200))
        return previewActors
    }

    override func fetchFollowersPage(
        actor _: String,
        cursor: String?,
        account _: AppAccount,
        appPassword _: String?
    ) async throws -> PagedActorSearch {
        try await Task.sleep(for: .milliseconds(120))
        let pageSize = 3
        let startIndex = Int(cursor ?? "0") ?? 0
        let endIndex = min(startIndex + pageSize, previewActors.count)
        let nextCursor = endIndex < previewActors.count ? String(endIndex) : nil
        return PagedActorSearch(
            actors: Array(previewActors[startIndex ..< endIndex]),
            cursor: nextCursor
        )
    }

    override func fetchFollowing(
        actor _: String,
        account _: AppAccount,
        appPassword _: String?
    ) async throws -> [BlueskyActor] {
        try await Task.sleep(for: .milliseconds(200))
        return previewActors
    }

    override func fetchFollowingPage(
        actor _: String,
        cursor: String?,
        account _: AppAccount,
        appPassword _: String?
    ) async throws -> PagedActorSearch {
        try await Task.sleep(for: .milliseconds(120))
        let pageSize = 3
        let startIndex = Int(cursor ?? "0") ?? 0
        let endIndex = min(startIndex + pageSize, previewActors.count)
        let nextCursor = endIndex < previewActors.count ? String(endIndex) : nil
        return PagedActorSearch(
            actors: Array(previewActors[startIndex ..< endIndex]),
            cursor: nextCursor
        )
    }

    override func fetchProfile(
        did actorDID: String,
        account _: AppAccount,
        appPassword _: String?
    ) async throws -> BlueskyProfile {
        try await Task.sleep(for: .milliseconds(120))

        return BlueskyProfile(
            id: actorDID,
            did: actorDID,
            handle: "alice.bsky.social",
            displayName: "Alice Chen",
            description: "Community moderation and list curation.",
            websiteURL: URL(string: "https://example.com"),
            avatarURL: nil,
            bannerURL: nil,
            followersCount: 1200,
            followsCount: 340,
            postsCount: 89,
            listsCount: 3,
            starterPacksCount: 1,
            createdAt: .now.addingTimeInterval(-86400 * 200),
            labels: ["spam", "bot"],
            viewerState: BlueskyViewerState(
                muted: false,
                blockedBy: false,
                isBlocking: false,
                blockingRecordURI: nil,
                isFollowing: true,
                followingRecordURI: "at://did:plc:preview/app.bsky.graph.follow/1",
                followsYou: false,
                mutedByListName: nil,
                blockingByListName: nil
            )
        )
    }

    override func inspectProfile(
        query: String,
        account _: AppAccount,
        appPassword _: String?
    ) async throws -> ProfileInspection {
        try await Task.sleep(for: .milliseconds(150))

        return ProfileInspection(
            profile: BlueskyProfile(
                id: "did:plc:preview-inspect",
                did: "did:plc:preview-inspect",
                handle: query.isEmpty ? "example.bsky.social" : query,
                displayName: "Example Profile",
                description: "Preview inspector data modeled after a ClearSky-style lookup.",
                websiteURL: URL(string: "https://bsky.app"),
                avatarURL: nil,
                bannerURL: nil,
                followersCount: 5400,
                followsCount: 420,
                postsCount: 128,
                listsCount: 4,
                starterPacksCount: 2,
                createdAt: .now.addingTimeInterval(-86400 * 500),
                labels: ["bot", "spam"],
                viewerState: BlueskyViewerState(
                    muted: false,
                    blockedBy: false,
                    isBlocking: true,
                    blockingRecordURI: "at://did:plc:preview/app.bsky.graph.block/1",
                    isFollowing: true,
                    followingRecordURI: "at://did:plc:preview/app.bsky.graph.follow/1",
                    followsYou: false,
                    mutedByListName: nil,
                    blockingByListName: "Reply Filters"
                )
            ),
            listMemberships: [
                ProfileListMembership(
                    listURI: "at://did:plc:preview/app.bsky.graph.list/1",
                    name: "Reply Filters",
                    kind: .moderation,
                    memberCount: 42,
                    isMember: true,
                    listItemRecordURI: "at://did:plc:preview/app.bsky.graph.listitem/42"
                ),
                ProfileListMembership(
                    listURI: "at://did:plc:preview/app.bsky.graph.list/2",
                    name: "Trusted Sources",
                    kind: .regular,
                    memberCount: 67,
                    isMember: false,
                    listItemRecordURI: nil
                ),
            ],
            starterPackMemberships: [
                ProfileStarterPackMembership(
                    uri: "at://did:plc:preview/app.bsky.graph.starterpack/1",
                    name: "Safety Starter Pack",
                    memberCount: 25,
                    joinedAllTimeCount: 340,
                    isMember: true
                ),
            ]
        )
    }

    override func fetchList(
        uri: String,
        account: AppAccount,
        appPassword: String?
    ) async throws -> BlueskyList? {
        try await fetchLists(for: account, appPassword: appPassword).first { $0.id == uri }
    }

    override func fetchBlockedActors(
        account _: AppAccount,
        appPassword _: String?
    ) async throws -> ClearskyBlocklistResult {
        try await Task.sleep(for: .milliseconds(80))
        let actors = [
            BlueskyActor(did: "did:plc:blocked1", handle: "spam.bsky.social", displayName: "Spam Account"),
            BlueskyActor(did: "did:plc:blocked2", handle: "troll.bsky.social", displayName: "Troll Account"),
        ]
        return ClearskyBlocklistResult(actors: actors, totalCount: actors.count)
    }

    override func fetchBlockedByActors(
        account _: AppAccount,
        appPassword _: String?
    ) async throws -> ClearskyBlocklistResult {
        try await Task.sleep(for: .milliseconds(80))
        return ClearskyBlocklistResult(actors: [], totalCount: 0)
    }

    override func fetchBlockingCount(for _: AppAccount) async throws -> Int {
        2
    }

    override func fetchBlockedByCount(for _: AppAccount) async throws -> Int {
        0
    }

    override func blockActor(
        did _: String,
        account _: AppAccount,
        appPassword _: String?
    ) async throws {
        try await Task.sleep(for: .milliseconds(120))
    }

    override func unblockActor(
        recordURI _: String,
        account _: AppAccount,
        appPassword _: String?
    ) async throws {
        try await Task.sleep(for: .milliseconds(120))
    }

    override func muteActor(
        did _: String,
        account _: AppAccount,
        appPassword _: String?
    ) async throws {
        try await Task.sleep(for: .milliseconds(120))
    }

    override func followActor(
        did _: String,
        account _: AppAccount,
        appPassword _: String?
    ) async throws {
        try await Task.sleep(for: .milliseconds(120))
    }

    override func unfollowActor(
        recordURI _: String,
        account _: AppAccount,
        appPassword _: String?
    ) async throws {
        try await Task.sleep(for: .milliseconds(120))
    }

    override func unmuteActor(
        did _: String,
        account _: AppAccount,
        appPassword _: String?
    ) async throws {
        try await Task.sleep(for: .milliseconds(120))
    }

    override func searchPosts(q _: String, mentions _: String? = nil, sort _: String? = nil, cursor: String? = nil, limit _: Int = 25, account _: AppAccount, appPassword _: String?) async throws -> SearchPostsResponse {
        try await Task.sleep(for: .milliseconds(120))

        let previewEntries: [RichFeedEntry] = previewActors.enumerated().map { index, actor in
            RichFeedEntry(
                post: RichPost(
                    uri: "at://\(actor.did)/app.bsky.feed.post/\(UUID().uuidString)",
                    cid: "preview-cid-\(index)",
                    author: RichAuthor(did: actor.did, handle: actor.handle, displayName: actor.displayName, avatar: nil),
                    record: RichRecord(text: "Hey @user this is a mention! Check out this post \(index + 1)", createdAt: ISO8601DateFormatter().string(from: Date().addingTimeInterval(-Double(index) * 3600))),
                    embed: nil,
                    viewer: nil,
                    replyCount: Int.random(in: 0 ... 10),
                    repostCount: Int.random(in: 0 ... 5),
                    likeCount: Int.random(in: 0 ... 20),
                    indexedAt: ISO8601DateFormatter().string(from: Date().addingTimeInterval(-Double(index) * 3600))
                ),
                reply: nil
            )
        }

        let pageSize = 3
        let startIndex = Int(cursor ?? "0") ?? 0
        let endIndex = min(startIndex + pageSize, previewEntries.count)
        let nextCursor = endIndex < previewEntries.count ? String(endIndex) : nil

        return SearchPostsResponse(
            cursor: nextCursor,
            hitsTotal: previewEntries.count,
            posts: previewEntries[startIndex ..< endIndex].map(\.post)
        )
    }

    private func previewMembers(for list: BlueskyList) -> [BlueskyListMember] {
        let now = Date()
        return previewActors.enumerated().map { index, actor in
            BlueskyListMember(
                recordURI: "at://did:plc:preview/\(list.id)/app.bsky.graph.listitem/\(index + 1)",
                actor: actor,
                createdAt: now.addingTimeInterval(-Double(index) * 86400 * 7)
            )
        }
    }
}
