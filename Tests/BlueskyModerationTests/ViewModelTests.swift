@testable import BlueskyModeration
import XCTest

@MainActor
final class ViewModelTests: XCTestCase {
    override func setUp() {
        super.setUp()
        DashboardCache.clear(forKey: "")
        DashboardCache.clear(forKey: "did:plc:test")
        DashboardCache.clear(forKey: "test.bsky.social")
    }

    // MARK: - ListsViewModel

    func testListsViewModelInitialStateIsEmpty() {
        let viewModel = ListsViewModel()

        XCTAssertTrue(viewModel.listsByKind.isEmpty)
        XCTAssertNil(viewModel.activeProfile)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertFalse(viewModel.isFromCache)
        XCTAssertEqual(viewModel.blockingCount, 0)
        XCTAssertEqual(viewModel.blockedByCount, 0)
    }

    func testListsViewModelLoadWithNilAccountSetsNoError() async {
        let viewModel = ListsViewModel()
        let client = PreviewBlueskyClient()

        viewModel.addList(makeList(id: "at://pre-existing", name: "Pre-existing"))
        XCTAssertFalse(viewModel.listsByKind.isEmpty)

        await viewModel.load(for: nil, appPassword: nil, using: client)

        XCTAssertTrue(viewModel.listsByKind.isEmpty)
        XCTAssertNil(viewModel.activeProfile)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(viewModel.blockingCount, 0)
        XCTAssertEqual(viewModel.blockedByCount, 0)
        XCTAssertFalse(viewModel.isLoading)
    }

    func testListsViewModelAddListInsertsIntoCorrectKind() {
        let viewModel = ListsViewModel()
        let modList = BlueskyList(id: "at://list/mod-1", name: "Moderation List", description: "Mod items", memberCount: 10, kind: .moderation)
        let regList = BlueskyList(id: "at://list/reg-1", name: "Regular List", description: "Reg items", memberCount: 5, kind: .regular)

        viewModel.addList(modList)
        viewModel.addList(regList)

        XCTAssertEqual(viewModel.listsByKind[.moderation]?.count, 1)
        XCTAssertEqual(viewModel.listsByKind[.regular]?.count, 1)
        XCTAssertEqual(viewModel.listsByKind[.moderation]?.first?.name, "Moderation List")
        XCTAssertEqual(viewModel.listsByKind[.regular]?.first?.name, "Regular List")
    }

    func testListsViewModelUpdateListModifiesExistingList() {
        let viewModel = ListsViewModel()
        let list = BlueskyList(id: "at://list/1", name: "Original", description: "Original description", memberCount: 10, kind: .moderation)
        viewModel.addList(list)

        let updated = BlueskyList(id: "at://list/1", name: "Updated", description: "Updated description", memberCount: 20, kind: .moderation)
        viewModel.updateList(updated)

        let found = viewModel.listsByKind[.moderation]?.first { $0.id == "at://list/1" }
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.name, "Updated")
        XCTAssertEqual(found?.description, "Updated description")
        XCTAssertEqual(found?.memberCount, 20)
    }

    func testListsViewModelUpdateListNonExistentDoesNotCrash() {
        let viewModel = ListsViewModel()
        let list = BlueskyList(id: "at://list/ghost", name: "Ghost", description: "", memberCount: 0, kind: .moderation)

        viewModel.updateList(list)

        XCTAssertTrue(viewModel.listsByKind.isEmpty)
    }

    // MARK: - ProfileInspectorViewModel

    func testProfileInspectorViewModelInitialStateIsEmpty() {
        let viewModel = ProfileInspectorViewModel()

        XCTAssertTrue(viewModel.query.isEmpty)
        XCTAssertTrue(viewModel.searchResults.isEmpty)
        XCTAssertNil(viewModel.inspection)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertFalse(viewModel.isSearching)
    }

    func testProfileInspectorViewModelSearchWithEmptyQueryDoesNotCrash() async {
        let viewModel = ProfileInspectorViewModel()
        let client = PreviewBlueskyClient()

        viewModel.query = ""
        await viewModel.search(account: AccountStore(preview: true).activeAccount, appPassword: "password", using: client)

        XCTAssertTrue(viewModel.searchResults.isEmpty)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertFalse(viewModel.isSearching)
    }

    func testProfileInspectorViewModelSearchWithShortQueryReturnsEmpty() async {
        let viewModel = ProfileInspectorViewModel()
        let client = PreviewBlueskyClient()

        viewModel.query = "a"
        await viewModel.search(account: AccountStore(preview: true).activeAccount, appPassword: "password", using: client)

        XCTAssertTrue(viewModel.searchResults.isEmpty)
        XCTAssertFalse(viewModel.isSearching)
    }

    func testProfileInspectorViewModelInspectSetsErrorWhenNoAccount() async {
        let viewModel = ProfileInspectorViewModel()
        let client = PreviewBlueskyClient()

        viewModel.query = "test.bsky.social"
        await viewModel.inspect(account: nil, appPassword: "password", using: client)

        XCTAssertNil(viewModel.inspection)
        XCTAssertEqual(viewModel.errorMessage, "Select an active account first.")
    }

    func testProfileInspectorViewModelInspectSetsErrorWhenQueryEmpty() async {
        let viewModel = ProfileInspectorViewModel()
        let client = PreviewBlueskyClient()

        viewModel.query = ""
        await viewModel.inspect(account: AccountStore(preview: true).activeAccount, appPassword: "password", using: client)

        XCTAssertNil(viewModel.inspection)
        XCTAssertEqual(viewModel.errorMessage, "Enter a Bluesky handle or DID.")
    }

    func testProfileInspectorViewModelSearchReturnsResultsWithValidQuery() async {
        let viewModel = ProfileInspectorViewModel()
        let client = PreviewBlueskyClient()

        viewModel.query = "alice"
        await viewModel.search(account: AccountStore(preview: true).activeAccount, appPassword: "password", using: client)

        XCTAssertFalse(viewModel.searchResults.isEmpty)
        XCTAssertTrue(viewModel.searchResults.contains(where: { $0.handle == "alice.bsky.social" }))
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertFalse(viewModel.isSearching)
    }

    // MARK: - ListDetailViewModel

    func testListDetailViewModelInitialState() {
        let viewModel = ListDetailViewModel()

        XCTAssertTrue(viewModel.members.isEmpty)
        XCTAssertTrue(viewModel.filteredMembers.isEmpty)
        XCTAssertTrue(viewModel.searchResults.isEmpty)
        XCTAssertNil(viewModel.comparisonReport)
        XCTAssertNil(viewModel.importPreview)
        XCTAssertFalse(viewModel.isLoadingMembers)
        XCTAssertFalse(viewModel.isLoadingMoreMembers)
        XCTAssertFalse(viewModel.hasMoreMembers)
        XCTAssertFalse(viewModel.batchProgressState.isPerformingBulkAction)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertNil(viewModel.membersErrorMessage)
        XCTAssertNil(viewModel.searchErrorMessage)
        XCTAssertNil(viewModel.bulkActionResult)
        XCTAssertTrue(viewModel.selectedMemberIDs.isEmpty)
        XCTAssertTrue(viewModel.selectedSearchActorIDs.isEmpty)
    }

    func testListDetailViewModelToggleSelection() {
        let viewModel = ListDetailViewModel()
        let did = "did:plc:test"

        XCTAssertFalse(viewModel.selectedComparisonActorDIDs.contains(did))

        viewModel.toggleComparisonSelection(for: did)
        XCTAssertTrue(viewModel.selectedComparisonActorDIDs.contains(did))

        viewModel.toggleComparisonSelection(for: did)
        XCTAssertFalse(viewModel.selectedComparisonActorDIDs.contains(did))
    }

    func testListMembersControllerCanBeCreated() {
        let controller = ListMembersController()
        XCTAssertNotNil(controller)
    }

    func testListDiffControllerCanBeCreated() {
        let controller = ListDiffController()
        XCTAssertNotNil(controller)
    }
}
