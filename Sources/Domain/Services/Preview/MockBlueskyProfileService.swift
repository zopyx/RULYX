import Foundation

@MainActor
final class MockBlueskyProfileService: BlueskyProfileInspecting {
    func searchActors(query: String, account: AppAccount, appPassword: String?) async throws -> [BlueskyActor] {
        let page = try await searchActorsPage(query: query, cursor: nil, account: account, appPassword: appPassword)
        return page.actors
    }

    func searchActorsPage(query: String, cursor: String?, account _: AppAccount, appPassword _: String?) async throws -> PagedActorSearch {
        try await Task.sleep(for: .milliseconds(120))

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else {
            return PagedActorSearch(actors: [], cursor: nil)
        }

        let matches = MockBlueskyListService.previewActors.filter {
            $0.handle.lowercased().contains(trimmed) ||
                ($0.displayName?.lowercased().contains(trimmed) ?? false)
        }
        let pageSize = 3
        let startIndex = Int(cursor ?? "0") ?? 0
        let endIndex = min(startIndex + pageSize, matches.count)
        let nextCursor = endIndex < matches.count ? String(endIndex) : nil

        return PagedActorSearch(actors: Array(matches[startIndex ..< endIndex]), cursor: nextCursor)
    }

    func fetchProfile(did actorDID: String, account _: AppAccount, appPassword _: String?) async throws -> BlueskyProfile {
        try await Task.sleep(for: .milliseconds(120))

        return BlueskyProfile(
            id: actorDID, did: actorDID, handle: "alice.bsky.social",
            displayName: "Alice Chen", description: "Community moderation and list curation.",
            websiteURL: URL(string: "https://example.com"), avatarURL: nil, bannerURL: nil,
            followersCount: 1200, followsCount: 340, postsCount: 89,
            listsCount: 3, starterPacksCount: 1,
            createdAt: .now.addingTimeInterval(-86400 * 200),
            labels: ["spam", "bot"],
            viewerState: BlueskyViewerState(muted: false, blockedBy: false, isBlocking: false, blockingRecordURI: nil, isFollowing: true, followingRecordURI: "at://did:plc:preview/app.bsky.graph.follow/1", followsYou: false, mutedByListName: nil, blockingByListName: nil)
        )
    }

    func inspectProfile(query: String, account _: AppAccount, appPassword _: String?) async throws -> ProfileInspection {
        try await Task.sleep(for: .milliseconds(150))

        return ProfileInspection(
            profile: BlueskyProfile(
                id: "did:plc:preview-inspect", did: "did:plc:preview-inspect",
                handle: query.isEmpty ? "example.bsky.social" : query,
                displayName: "Example Profile", description: "Preview inspector data modeled after a ClearSky-style lookup.",
                websiteURL: URL(string: "https://bsky.app"), avatarURL: nil, bannerURL: nil,
                followersCount: 5400, followsCount: 420, postsCount: 128,
                listsCount: 4, starterPacksCount: 2,
                createdAt: .now.addingTimeInterval(-86400 * 500),
                labels: ["bot", "spam"],
                // swiftlint:disable:next line_length
                viewerState: BlueskyViewerState(muted: false, blockedBy: false, isBlocking: true, blockingRecordURI: "at://did:plc:preview/app.bsky.graph.block/1", isFollowing: true, followingRecordURI: "at://did:plc:preview/app.bsky.graph.follow/1", followsYou: false, mutedByListName: nil, blockingByListName: "Reply Filters")
            ),
            listMemberships: [
                ProfileListMembership(listURI: "at://did:plc:preview/app.bsky.graph.list/1", name: "Reply Filters", kind: .moderation, memberCount: 42, isMember: true, listItemRecordURI: "at://did:plc:preview/app.bsky.graph.listitem/42"),
                ProfileListMembership(listURI: "at://did:plc:preview/app.bsky.graph.list/2", name: "Trusted Sources", kind: .regular, memberCount: 67, isMember: false, listItemRecordURI: nil),
            ],
            starterPackMemberships: [
                ProfileStarterPackMembership(uri: "at://did:plc:preview/app.bsky.graph.starterpack/1", name: "Safety Starter Pack", memberCount: 25, joinedAllTimeCount: 340, isMember: true),
            ]
        )
    }

    func fetchFollowers(actor _: String, account _: AppAccount, appPassword _: String?) async throws -> [BlueskyActor] {
        try await Task.sleep(for: .milliseconds(200))
        return MockBlueskyListService.previewActors
    }

    func fetchFollowersPage(actor _: String, cursor: String?, account _: AppAccount, appPassword _: String?) async throws -> PagedActorSearch {
        try await Task.sleep(for: .milliseconds(120))
        let actors = MockBlueskyListService.previewActors
        let pageSize = 3
        let startIndex = Int(cursor ?? "0") ?? 0
        let endIndex = min(startIndex + pageSize, actors.count)
        let nextCursor = endIndex < actors.count ? String(endIndex) : nil
        return PagedActorSearch(actors: Array(actors[startIndex ..< endIndex]), cursor: nextCursor)
    }

    func fetchFollowing(actor _: String, account _: AppAccount, appPassword _: String?) async throws -> [BlueskyActor] {
        try await Task.sleep(for: .milliseconds(200))
        return MockBlueskyListService.previewActors
    }

    func fetchFollowingPage(actor _: String, cursor: String?, account _: AppAccount, appPassword _: String?) async throws -> PagedActorSearch {
        try await Task.sleep(for: .milliseconds(120))
        let actors = MockBlueskyListService.previewActors
        let pageSize = 3
        let startIndex = Int(cursor ?? "0") ?? 0
        let endIndex = min(startIndex + pageSize, actors.count)
        let nextCursor = endIndex < actors.count ? String(endIndex) : nil
        return PagedActorSearch(actors: Array(actors[startIndex ..< endIndex]), cursor: nextCursor)
    }

    func blockActor(did _: String, account _: AppAccount, appPassword _: String?) async throws {
        try await Task.sleep(for: .milliseconds(120))
    }

    func unblockActor(recordURI _: String, account _: AppAccount, appPassword _: String?) async throws {
        try await Task.sleep(for: .milliseconds(120))
    }

    func muteActor(did _: String, account _: AppAccount, appPassword _: String?) async throws {
        try await Task.sleep(for: .milliseconds(120))
    }

    func followActor(did _: String, account _: AppAccount, appPassword _: String?) async throws {
        try await Task.sleep(for: .milliseconds(120))
    }

    func unfollowActor(recordURI _: String, account _: AppAccount, appPassword _: String?) async throws {
        try await Task.sleep(for: .milliseconds(120))
    }

    func unmuteActor(did _: String, account _: AppAccount, appPassword _: String?) async throws {
        try await Task.sleep(for: .milliseconds(120))
    }
}
