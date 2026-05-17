@testable import BlueskyModeration
import XCTest

@MainActor
final class ListsViewModelTests: XCTestCase {
    private var viewModel: ListsViewModel!
    private var client: MockListsClient!

    override func setUp() {
        super.setUp()
        viewModel = ListsViewModel()
        client = MockListsClient()
        DashboardCache.clear(forKey: "did:plc:test")
        DashboardCache.clear(forKey: "test.bsky.social")
    }

    func testLoadWithNilAccountClearsState() async {
        await viewModel.load(for: nil, appPassword: nil, using: client)
        XCTAssertTrue(viewModel.listsByKind.isEmpty)
        XCTAssertNil(viewModel.activeProfile)
        XCTAssertEqual(viewModel.blockingCount, 0)
        XCTAssertEqual(viewModel.blockedByCount, 0)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testLoadFetchesListsAndProfile() async {
        let account = makeAccount()
        await viewModel.load(for: account, appPassword: "pass", using: client)
        XCTAssertFalse(viewModel.listsByKind.isEmpty)
        XCTAssertNotNil(viewModel.activeProfile)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertFalse(viewModel.isLoading)
    }

    func testLoadHandlesListFetchError() async {
        client.shouldFailLists = true
        let account = makeAccount()
        await viewModel.load(for: account, appPassword: "pass", using: client)
        XCTAssertTrue(viewModel.listsByKind.isEmpty)
        XCTAssertNotNil(viewModel.errorMessage)
    }

    func testAddList() {
        viewModel.addList(makeList(name: "New List"))
        let all = viewModel.listsByKind.values.flatMap { $0 }
        XCTAssertTrue(all.contains(where: { $0.name == "New List" }))
    }

    func testUpdateList() {
        let list = makeList(id: "at://list/1", name: "Original", kind: .moderation)
        viewModel.addList(list)
        let updated = makeList(id: "at://list/1", name: "Updated", kind: .moderation)
        viewModel.updateList(updated)
        guard let found = viewModel.listsByKind[.moderation]?.first(where: { $0.id == "at://list/1" }) else {
            return XCTFail("List not found")
        }
        XCTAssertEqual(found.name, "Updated")
    }

    func testUpdateListNonExistentDoesNotCrash() {
        let list = makeList(id: "at://list/999", name: "Ghost")
        viewModel.updateList(list)
    }

    func testLoadFetchesBlockingCount() async {
        client.blockedActors = [
            makeActor(did: "did:plc:b1", handle: "b1.bsky.social"),
            makeActor(did: "did:plc:b2", handle: "b2.bsky.social"),
        ]
        let account = makeAccount()
        await viewModel.load(for: account, appPassword: "pass", using: client)
        XCTAssertEqual(viewModel.blockingCount, 2)
    }

    func testLoadHandlesBlockingFetchError() async {
        client.shouldFailBlocking = true
        let account = makeAccount()
        await viewModel.load(for: account, appPassword: "pass", using: client)
        XCTAssertEqual(viewModel.blockingCount, 0)
    }

    func testActiveProfilePopulatedOnLoad() async {
        let account = makeAccount()
        await viewModel.load(for: account, appPassword: "pass", using: client)
        XCTAssertNotNil(viewModel.activeProfile)
        XCTAssertEqual(viewModel.activeProfile?.handle, account.handle)
    }
}

@MainActor
private final class MockListsClient: LiveBlueskyClient {
    var shouldFailLists = false
    var shouldFailBlocking = false
    var blockedActors: [BlueskyActor] = []

    override func fetchLists(for account: AppAccount, appPassword _: String?) async throws -> [BlueskyList] {
        if shouldFailLists { throw BlueskyAPIError.server("Failed") }
        return [
            makeList(id: "\(account.handle)-mod-1", name: "Spam Watch", kind: .moderation),
            makeList(id: "\(account.handle)-list-1", name: "Trusted", kind: .regular),
        ]
    }

    override func fetchProfile(did actorDID: String, account: AppAccount, appPassword _: String?) async throws -> BlueskyProfile {
        makeProfile(did: actorDID, handle: account.handle)
    }

    override func fetchBlockingCount(for _: AppAccount) async throws -> Int {
        if shouldFailBlocking { throw BlueskyAPIError.server("Failed") }
        return blockedActors.count
    }

    override func fetchBlockedByCount(for _: AppAccount) async throws -> Int {
        return 0
    }
}
