@testable import BlueskyModeration
import XCTest

@MainActor
final class BlueskyProfileServiceTests: XCTestCase {
    private var requestExecutor: MockRequestExecutor!
    private var sessionService: MockSessionService!
    private var service: BlueskyProfileService!

    override func setUp() {
        super.setUp()
        requestExecutor = MockRequestExecutor()
        sessionService = MockSessionService()
        service = BlueskyProfileService(requestExecutor: requestExecutor, sessionService: sessionService)
    }

    func testFetchProfileSuccess() async throws {
        sessionService.onAuthenticatedRequest = { _, _ in
            let json = """
            {"did": "did:plc:test", "handle": "test.bsky.social", "displayName": "Test", "followersCount": 100, "followsCount": 50, "postsCount": 25}
            """.data(using: .utf8)!
            return try JSONDecoder().decode(ProfileViewDetailed.self, from: json)
        }

        let profile = try await service.fetchProfile(did: "did:plc:test", account: makeAccount(), appPassword: "pass")
        XCTAssertEqual(profile.handle, "test.bsky.social")
        XCTAssertEqual(profile.followersCount, 100)
        XCTAssertEqual(profile.followsCount, 50)
    }

    func testFetchProfileWithViewerState() async throws {
        sessionService.onAuthenticatedRequest = { _, _ in
            let json = """
            {"did": "did:plc:test", "handle": "test.bsky.social", "viewer": {"muted": true, "blockedBy": false, "blocking": "at://block/1"}}
            """.data(using: .utf8)!
            return try JSONDecoder().decode(ProfileViewDetailed.self, from: json)
        }

        let profile = try await service.fetchProfile(did: "did:plc:test", account: makeAccount(), appPassword: "pass")
        XCTAssertNotNil(profile.viewerState)
        XCTAssertTrue(profile.viewerState?.muted ?? false)
    }

    func testFetchProfileWithLabels() async throws {
        sessionService.onAuthenticatedRequest = { _, _ in
            let json = """
            {"did": "did:plc:test", "handle": "test.bsky.social", "labels": [{"val": "spam"}, {"val": "bot"}]}
            """.data(using: .utf8)!
            return try JSONDecoder().decode(ProfileViewDetailed.self, from: json)
        }

        let profile = try await service.fetchProfile(did: "did:plc:test", account: makeAccount(), appPassword: "pass")
        XCTAssertEqual(profile.labels, ["spam", "bot"])
    }

    func testFetchProfileWithAssociated() async throws {
        sessionService.onAuthenticatedRequest = { _, _ in
            let json = """
            {"did": "did:plc:test", "handle": "test.bsky.social", "associated": {"lists": 3, "starterPacks": 1}}
            """.data(using: .utf8)!
            return try JSONDecoder().decode(ProfileViewDetailed.self, from: json)
        }

        let profile = try await service.fetchProfile(did: "did:plc:test", account: makeAccount(), appPassword: "pass")
        XCTAssertEqual(profile.listsCount, 3)
        XCTAssertEqual(profile.starterPacksCount, 1)
    }

    func testSearchActorsSuccess() async throws {
        sessionService.onAuthenticatedRequest = { _, _ in
            let json = """
            {"actors": [{"did": "did:plc:1", "handle": "alice.bsky.social"}, {"did": "did:plc:2", "handle": "bob.bsky.social"}]}
            """.data(using: .utf8)!
            return try JSONDecoder().decode(SearchActorsResponse.self, from: json)
        }

        let actors = try await service.searchActors(query: "alice", account: makeAccount(), appPassword: "pass")
        XCTAssertEqual(actors.count, 2)
        XCTAssertEqual(actors[0].handle, "alice.bsky.social")
    }

    func testSearchActorsEmptyQuery() async throws {
        let actors = try await service.searchActors(query: "   ", account: makeAccount(), appPassword: "pass")
        XCTAssertTrue(actors.isEmpty)
    }

    func testBlockActorSuccess() async throws {
        sessionService.onAuthenticatedRequest = { _, _ in
            let json = """
            {"uri": "at://block/1", "cid": "cid123"}
            """.data(using: .utf8)!
            return try JSONDecoder().decode(CreateRecordResponse.self, from: json)
        }

        try await service.blockActor(did: "did:plc:target", account: makeAccount(), appPassword: "pass")
    }

    func testUnblockActorSuccess() async throws {
        sessionService.onAuthenticatedRequest = { _, _ in
            EmptyResponse()
        }

        try await service.unblockActor(recordURI: "at://did:plc:owner/app.bsky.graph.block/rkey123", account: makeAccount(), appPassword: "pass")
    }

    func testMuteActorSuccess() async throws {
        sessionService.onAuthenticatedRequest = { _, _ in
            EmptyResponse()
        }

        try await service.muteActor(did: "did:plc:target", account: makeAccount(), appPassword: "pass")
    }

    func testUnmuteActorSuccess() async throws {
        sessionService.onAuthenticatedRequest = { _, _ in
            EmptyResponse()
        }

        try await service.unmuteActor(did: "did:plc:target", account: makeAccount(), appPassword: "pass")
    }

    func testFetchFollowersSuccess() async throws {
        var pageCount = 0
        sessionService.onAuthenticatedRequest = { _, _ in
            pageCount += 1
            let actors = [["did": "did:plc:f\(pageCount)", "handle": "f\(pageCount).bsky.social"]]
            let json = pageCount <= 2
                ? try JSONSerialization.data(withJSONObject: ["cursor": "page\(pageCount)", "followers": actors])
                : try JSONSerialization.data(withJSONObject: ["followers": actors])
            return try JSONDecoder().decode(GetFollowersResponse.self, from: json)
        }

        let followers = try await service.fetchFollowers(actor: "did:plc:target", account: makeAccount(), appPassword: "pass")
        XCTAssertEqual(followers.count, 3)
    }

    func testFetchFollowingSuccess() async throws {
        var pageCount = 0
        sessionService.onAuthenticatedRequest = { _, _ in
            pageCount += 1
            let actors = [["did": "did:plc:f\(pageCount)", "handle": "f\(pageCount).bsky.social"]]
            let json = pageCount <= 1
                ? try JSONSerialization.data(withJSONObject: ["cursor": "page\(pageCount)", "follows": actors])
                : try JSONSerialization.data(withJSONObject: ["follows": actors])
            return try JSONDecoder().decode(GetFollowsResponse.self, from: json)
        }

        let following = try await service.fetchFollowing(actor: "did:plc:target", account: makeAccount(), appPassword: "pass")
        XCTAssertEqual(following.count, 2)
    }

    func testInspectProfileSuccess() {
        sessionService.onAuthenticatedRequest = { _, _ in
            let profile = try JSONDecoder().decode(ProfileViewDetailed.self, from: """
            {"did": "did:plc:test", "handle": "test.bsky.social", "displayName": "Test"}
            """.data(using: .utf8)!)
            let lists = try JSONDecoder().decode(ListsWithMembershipResponse.self, from: """
            {"listsWithMembership": [{"list": {"uri": "at://list/1", "name": "List", "purpose": "app.bsky.graph.defs#curatelist"}, "listItem": null}]}
            """.data(using: .utf8)!)
            let starterPacks = try JSONDecoder().decode(StarterPacksWithMembershipResponse.self, from: """
            {"starterPacksWithMembership": []}
            """.data(using: .utf8)!)
            return (profile, lists, starterPacks)
        }

        sessionService.onAuthenticatedRequest = { _, _ in
            throw BlueskyAPIError.invalidResponse
        }
    }

    func testSearchActorsPageSuccess() async throws {
        sessionService.onAuthenticatedRequest = { _, _ in
            let json = """
            {"cursor": "next", "actors": [{"did": "did:plc:1", "handle": "alice.bsky.social"}]}
            """.data(using: .utf8)!
            return try JSONDecoder().decode(SearchActorsResponse.self, from: json)
        }

        let page = try await service.searchActorsPage(query: "alice", cursor: nil, account: makeAccount(), appPassword: "pass")
        XCTAssertEqual(page.actors.count, 1)
        XCTAssertEqual(page.cursor, "next")
    }

    func testSearchActorsPageEmptyQuery() async throws {
        let page = try await service.searchActorsPage(query: "   ", cursor: nil, account: makeAccount(), appPassword: "pass")
        XCTAssertTrue(page.actors.isEmpty)
        XCTAssertNil(page.cursor)
    }
}
