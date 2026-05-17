@testable import BlueskyModeration
import XCTest

@MainActor
final class ListMembersControllerTests: XCTestCase {
    private var controller: ListMembersController!
    private var account: AppAccount!

    override func setUp() {
        super.setUp()
        controller = ListMembersController()
        account = makeAccount()
    }

    func testInitialState() {
        XCTAssertNil(controller.cursor)
        XCTAssertFalse(controller.hasMore)
    }

    func testReset() {
        controller.reset()
        XCTAssertNil(controller.cursor)
        XCTAssertFalse(controller.hasMore)
    }

    func testLoadMembersWithMockClient() async throws {
        let client = MockLiveBlueskyClient2()
        let list = makeList()
        client.pageResult = PagedListMembers(
            members: [
                makeMember(did: "did:plc:1", handle: "u1.bsky.social"),
                makeMember(did: "did:plc:2", handle: "u2.bsky.social"),
            ],
            cursor: "next"
        )

        let members = try await controller.loadMembers(
            for: list,
            account: account,
            appPassword: "pass",
            using: client
        )
        XCTAssertEqual(members.count, 2)
        XCTAssertEqual(controller.cursor, "next")
        XCTAssertTrue(controller.hasMore)
    }

    func testLoadMembersNoMorePages() async throws {
        let client = MockLiveBlueskyClient2()
        let list = makeList()
        client.pageResult = PagedListMembers(members: [makeMember()], cursor: nil)

        let members = try await controller.loadMembers(
            for: list,
            account: account,
            appPassword: "pass",
            using: client
        )
        XCTAssertEqual(members.count, 1)
        XCTAssertNil(controller.cursor)
        XCTAssertFalse(controller.hasMore)
    }

    func testLoadMoreMembersWithCursor() async throws {
        let client = MockLiveBlueskyClient2()
        let list = makeList()
        // First page returns a cursor so hasMore becomes true
        client.pageResult = PagedListMembers(members: [makeMember()], cursor: "next")

        _ = try await controller.loadMembers(
            for: list,
            account: account,
            appPassword: "pass",
            using: client
        )

        // Second page returns results with no cursor (last page)
        client.pageResult = PagedListMembers(
            members: [makeMember(did: "did:plc:more", handle: "more.bsky.social")],
            cursor: nil
        )

        let more = try await controller.loadMoreMembers(
            for: list,
            account: account,
            appPassword: "pass",
            using: client
        )
        XCTAssertEqual(more.count, 1)
    }

    func testLoadMoreMembersNoMore() async throws {
        let client = MockLiveBlueskyClient2()
        let list = makeList()
        client.pageResult = PagedListMembers(members: [makeMember()], cursor: nil)

        _ = try await controller.loadMembers(
            for: list,
            account: account,
            appPassword: "pass",
            using: client
        )

        let more = try await controller.loadMoreMembers(
            for: list,
            account: account,
            appPassword: "pass",
            using: client
        )
        XCTAssertTrue(more.isEmpty)
    }

    func testDeduplicatesMembers() async throws {
        let client = MockLiveBlueskyClient2()
        let list = makeList()
        client.pageResult = PagedListMembers(
            members: [
                makeMember(did: "did:plc:same", handle: "same.bsky.social", recordURI: "at://item/1"),
                makeMember(did: "did:plc:same", handle: "same.bsky.social", recordURI: "at://item/1"),
            ],
            cursor: nil
        )

        let members = try await controller.loadMembers(
            for: list,
            account: account,
            appPassword: "pass",
            using: client
        )
        XCTAssertEqual(members.count, 1)
    }
}

@MainActor
private final class MockLiveBlueskyClient2: LiveBlueskyClient {
    var pageResult: PagedListMembers?

    override func fetchListMembersPage(
        list _: BlueskyList,
        cursor _: String?,
        account _: AppAccount,
        appPassword _: String?
    ) async throws -> PagedListMembers {
        pageResult ?? PagedListMembers(members: [], cursor: nil)
    }
}
