import Foundation
import XCTest
@testable import RULYX

// MARK: - AutoBlockBackServiceTests

/// Tests for the automatic block-back service, covering target list loading,
/// actor addition dispatching, and the main performAutoBlockBack flow.
@MainActor
final class AutoBlockBackServiceTests: XCTestCase {
    private var mockClearsky: MockClearSkyService!
    private var mockProfile: MockProfileService!
    private var mockList: MockListService!
    private var mockSocial: MockSocialService!
    private var mockAccountStore: MockAccountStore!
    private var internalListStore: InternalListStore!
    private var service: AutoBlockBackService!

    override func setUp() {
        super.setUp()
        mockClearsky = MockClearSkyService()
        mockProfile = MockProfileService()
        mockList = MockListService()
        mockSocial = MockSocialService()
        mockAccountStore = MockAccountStore()
        internalListStore = InternalListStore(defaults: UserDefaults(suiteName: UUID().uuidString)!)
    }

    // MARK: - loadTargetLists

    func testLoadTargetLists_returnsEmpty_whenNoStoredIDs() async {
        service = makeService()

        let lists = await service.loadTargetLists(
            account: mockAccountStore.activeAccount!,
            appPassword: "pw",
            using: mockList
        )

        XCTAssertTrue(lists.isEmpty, "No target list IDs stored → empty result")
    }

    func testLoadTargetLists_returnsEmpty_whenStoredIDsDoNotMatch() async {
        // Store a non-matching ID
        UserDefaults.standard.set(try? JSONEncoder().encode(["does-not-exist"]), forKey: "autoBlockTargetListIDs")
        service = makeService()

        let lists = await service.loadTargetLists(
            account: mockAccountStore.activeAccount!,
            appPassword: "pw",
            using: mockList
        )

        XCTAssertTrue(lists.isEmpty, "Nonexistent list ID → empty result")
    }

    func testLoadTargetLists_matchesRemoteListByID() async {
        let listID = "at://did:plc:test/app.bsky.graph.list/abc"
        UserDefaults.standard.set(try? JSONEncoder().encode([listID]), forKey: "autoBlockTargetListIDs")

        let remoteList = BlueskyList(id: listID, name: "TestList", description: "Test", memberCount: 0, kind: .moderation, cid: nil)
        mockList.fetchListsHandler = { _, _ in [remoteList] }

        service = makeService()

        let lists = await service.loadTargetLists(
            account: mockAccountStore.activeAccount!,
            appPassword: "pw",
            using: mockList
        )

        XCTAssertEqual(lists.count, 1)
        XCTAssertEqual(lists.first?.id, listID)
        XCTAssertEqual(lists.first?.name, "TestList")
    }

    func testLoadTargetLists_includesInternalLists() async {
        let internalID = "internal:\(internalListStore.lists.first?.id.uuidString ?? "")"
        UserDefaults.standard.set(try? JSONEncoder().encode([internalID]), forKey: "autoBlockTargetListIDs")
        mockList.fetchListsHandler = { _, _ in [] }

        service = makeService()

        let lists = await service.loadTargetLists(
            account: mockAccountStore.activeAccount!,
            appPassword: "pw",
            using: mockList
        )

        XCTAssertEqual(lists.count, 1, "Should match internal list by composite ID")
        XCTAssertEqual(lists.first?.kind, .internal)
    }

    // MARK: - addActorToTargetList

    func testAddActorToTargetList_externalList_callsAddActor() async throws {
        let list = BlueskyList(id: "at://uri", name: "Mod", description: "", memberCount: nil, kind: .moderation, cid: nil)
        let addCalled = XCTestExpectation(description: "addActor called")
        mockList.addActorHandler = { _, _, _, _ in
            addCalled.fulfill()
            return "at://new-record"
        }

        service = makeService()

        try await service.addActorToTargetList(
            did: "did:plc:target",
            handle: "target.bsky.social",
            list: list,
            account: mockAccountStore.activeAccount!,
            appPassword: "pw",
            using: mockList
        )

        await fulfillment(of: [addCalled], timeout: 1)
    }

    func testAddActorToTargetList_internalList_addsToStore() async {
        let list = BlueskyList(id: "internal:\(internalListStore.lists[0].id.uuidString)", name: "Hostile", description: "", memberCount: nil, kind: .internal, cid: nil)

        service = makeService()

        try? await service.addActorToTargetList(
            did: "did:plc:target",
            handle: "target.bsky.social",
            list: list,
            account: mockAccountStore.activeAccount!,
            appPassword: "pw",
            using: mockList
        )

        let memberStatus = internalListStore.memberStatus(did: "did:plc:target")
        let isMember = memberStatus[internalListStore.lists[0].id] ?? false
        XCTAssertTrue(isMember, "Actor should be added to internal list store")
    }

    // MARK: - Helpers

    private func makeService() -> AutoBlockBackService {
        AutoBlockBackService(
            clearskyService: mockClearsky,
            profileService: mockProfile,
            listService: mockList,
            socialService: mockSocial,
            accountStore: mockAccountStore,
            internalListStore: internalListStore
        )
    }
}
