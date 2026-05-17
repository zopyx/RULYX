@testable import BlueskyModeration
import XCTest

@MainActor
final class ProfileInspectorViewModelTests: XCTestCase {
    func testSearchIgnoresStaleResponses() async {
        let viewModel = ProfileInspectorViewModel()
        var client = MockLiveBlueskyClient()
        client.searchHandler = { query in
            if query == "al" {
                try await Task.sleep(nanoseconds: 200_000_000)
                return [BlueskyActor(did: "did:plc:old", handle: "al-old.bsky.social")]
            }

            try await Task.sleep(nanoseconds: 50_000_000)
            return [BlueskyActor(did: "did:plc:new", handle: "ali-new.bsky.social")]
        }

        let account = AppAccount(handle: "moderator.bsky.social")

        viewModel.query = "al"
        async let firstSearch: Void = viewModel.search(
            account: account,
            appPassword: "password",
            using: client
        )

        try? await Task.sleep(nanoseconds: 20_000_000)

        viewModel.query = "ali"
        async let secondSearch: Void = viewModel.search(
            account: account,
            appPassword: "password",
            using: client
        )

        _ = await (firstSearch, secondSearch)

        XCTAssertEqual(viewModel.searchResults.map(\.handle), ["ali-new.bsky.social"])
        XCTAssertFalse(viewModel.isSearching)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testInspectSetsInspectionResult() async {
        let viewModel = ProfileInspectorViewModel()
        var client = MockLiveBlueskyClient()
        client.inspectHandler = { _ in
            ProfileInspection(
                profile: BlueskyProfile(
                    id: "did:plc:test",
                    did: "did:plc:test",
                    handle: "test.bsky.social",
                    displayName: "Test User",
                    description: "Inspection test",
                    websiteURL: nil, avatarURL: nil, bannerURL: nil,
                    followersCount: 100, followsCount: 50, postsCount: 10,
                    listsCount: 2, starterPacksCount: 1,
                    createdAt: nil, labels: ["spam"],
                    viewerState: nil
                ),
                listMemberships: [],
                starterPackMemberships: []
            )
        }

        viewModel.query = "test.bsky.social"
        await viewModel.inspect(
            account: AppAccount(handle: "mod.bsky.social"),
            appPassword: "password",
            using: client
        )

        XCTAssertNotNil(viewModel.inspection)
        XCTAssertEqual(viewModel.inspection?.profile.handle, "test.bsky.social")
        XCTAssertEqual(viewModel.inspection?.profile.labels, ["spam"])
        XCTAssertEqual(viewModel.inspection?.profile.followersCount, 100)
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testInspectHandlesNilAccount() async {
        let viewModel = ProfileInspectorViewModel()
        let client = MockLiveBlueskyClient()

        viewModel.query = "test.bsky.social"
        await viewModel.inspect(
            account: nil,
            appPassword: "password",
            using: client
        )

        XCTAssertNil(viewModel.inspection)
        XCTAssertEqual(viewModel.errorMessage, "Select an active account first.")
    }

    func testInspectHandlesNilPassword() async {
        let viewModel = ProfileInspectorViewModel()
        let client = MockLiveBlueskyClient()

        viewModel.query = "test.bsky.social"
        await viewModel.inspect(
            account: AppAccount(handle: "mod.bsky.social"),
            appPassword: nil,
            using: client
        )

        XCTAssertNil(viewModel.inspection)
        XCTAssertNotNil(viewModel.errorMessage)
    }

    func testSearchIgnoresCancellationErrors() async {
        let viewModel = ProfileInspectorViewModel()
        var client = MockLiveBlueskyClient()
        client.searchHandler = { _ in
            throw CancellationError()
        }

        viewModel.query = "al"
        await viewModel.search(
            account: AppAccount(handle: "moderator.bsky.social"),
            appPassword: "password",
            using: client
        )

        XCTAssertTrue(viewModel.searchResults.isEmpty)
        XCTAssertFalse(viewModel.isSearching)
        XCTAssertNil(viewModel.errorMessage)
    }
}

@MainActor
private struct MockLiveBlueskyClient: BlueskyProfileInspecting {
    var searchHandler: @Sendable (String) async throws -> [BlueskyActor] = { _ in [] }
    var inspectHandler: @Sendable (String) async throws -> ProfileInspection = { query in
        ProfileInspection(
            profile: BlueskyProfile(
                id: "did:plc:\(query)",
                did: "did:plc:\(query)",
                handle: "\(query).bsky.social",
                displayName: nil,
                description: nil,
                websiteURL: nil,
                avatarURL: nil,
                bannerURL: nil,
                followersCount: nil,
                followsCount: nil,
                postsCount: nil,
                listsCount: nil,
                starterPacksCount: nil,
                createdAt: nil,
                labels: [],
                viewerState: nil
            ),
            listMemberships: [],
            starterPackMemberships: []
        )
    }

    func searchActors(
        query: String,
        account _: AppAccount,
        appPassword _: String?
    ) async throws -> [BlueskyActor] {
        try await searchHandler(query)
    }

    func searchActorsPage(
        query: String,
        cursor _: String?,
        account _: AppAccount,
        appPassword _: String?
    ) async throws -> PagedActorSearch {
        let actors = try await searchHandler(query)
        return PagedActorSearch(actors: actors, cursor: nil)
    }

    func fetchProfile(
        did _: String,
        account _: AppAccount,
        appPassword _: String?
    ) async throws -> BlueskyProfile {
        throw BlueskyAPIError.server("Not implemented")
    }

    func inspectProfile(
        query: String,
        account _: AppAccount,
        appPassword _: String?
    ) async throws -> ProfileInspection {
        try await inspectHandler(query)
    }

    func blockActor(did _: String, account _: AppAccount, appPassword _: String?) async throws {}
    func unblockActor(recordURI _: String, account _: AppAccount, appPassword _: String?) async throws {}
    func muteActor(did _: String, account _: AppAccount, appPassword _: String?) async throws {}
    func unmuteActor(did _: String, account _: AppAccount, appPassword _: String?) async throws {}
    func fetchFollowers(actor _: String, account _: AppAccount, appPassword _: String?) async throws -> [BlueskyActor] {
        []
    }

    func fetchFollowersPage(actor _: String, cursor _: String?, account _: AppAccount, appPassword _: String?) async throws -> PagedActorSearch {
        PagedActorSearch(actors: [], cursor: nil)
    }

    func fetchFollowing(actor _: String, account _: AppAccount, appPassword _: String?) async throws -> [BlueskyActor] {
        []
    }

    func fetchFollowingPage(actor _: String, cursor _: String?, account _: AppAccount, appPassword _: String?) async throws -> PagedActorSearch {
        PagedActorSearch(actors: [], cursor: nil)
    }
}
