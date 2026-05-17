@testable import BlueskyModeration
import XCTest

@MainActor
final class ListDetailViewModelTests: XCTestCase {
    private var viewModel: ListDetailViewModel!

    override func setUp() {
        super.setUp()
        viewModel = ListDetailViewModel()
    }

    func testInitialState() {
        XCTAssertTrue(viewModel.members.isEmpty)
        XCTAssertTrue(viewModel.searchResults.isEmpty)
        XCTAssertNil(viewModel.comparisonReport)
        XCTAssertNil(viewModel.bulkActionResult)
    }

    func testLoadedMemberSummary() {
        XCTAssertFalse(viewModel.isLoadingMembers)
        XCTAssertEqual(viewModel.loadedMemberSummary, "0 members loaded.")
    }

    func testLoadedMemberSummaryWithMembers() {
        viewModel.members = [makeMember()]
        viewModel.hasMoreMembers = false
        XCTAssertEqual(viewModel.loadedMemberSummary, "1 member loaded.")
    }

    func testLoadedMemberSummaryPlural() {
        viewModel.members = [makeMember(), makeMember(did: "did:plc:2", handle: "b.bsky.social")]
        viewModel.hasMoreMembers = false
        XCTAssertEqual(viewModel.loadedMemberSummary, "2 members loaded.")
    }

    func testLoadedMemberSummaryWithHasMore() {
        viewModel.members = [makeMember()]
        viewModel.hasMoreMembers = true
        XCTAssertTrue(viewModel.loadedMemberSummary.contains("so far"))
    }

    func testToggleSearchSelection() {
        let actor = makeActor()
        XCTAssertFalse(viewModel.isSelectedForBulkAdd(actor))
        viewModel.toggleSearchSelection(for: actor)
        XCTAssertTrue(viewModel.isSelectedForBulkAdd(actor))
        viewModel.toggleSearchSelection(for: actor)
        XCTAssertFalse(viewModel.isSelectedForBulkAdd(actor))
    }

    func testToggleMemberSelection() {
        let member = makeMember()
        XCTAssertFalse(viewModel.isSelectedForBulkRemoval(member))
        viewModel.toggleMemberSelection(for: member)
        XCTAssertTrue(viewModel.isSelectedForBulkRemoval(member))
        viewModel.toggleMemberSelection(for: member)
        XCTAssertFalse(viewModel.isSelectedForBulkRemoval(member))
    }

    func testToggleComparisonSelection() {
        viewModel.toggleComparisonSelection(for: "did:plc:test")
        XCTAssertTrue(viewModel.selectedComparisonActorDIDs.contains("did:plc:test"))
        viewModel.toggleComparisonSelection(for: "did:plc:test")
        XCTAssertFalse(viewModel.selectedComparisonActorDIDs.contains("did:plc:test"))
    }

    func testSelectAllSearchResults() {
        viewModel.searchResults = [makeActor(did: "did:plc:1"), makeActor(did: "did:plc:2")]
        viewModel.selectAllSearchResults()
        XCTAssertEqual(viewModel.selectedSearchActorIDs.count, 2)
    }

    func testClearSearchSelection() {
        viewModel.searchResults = [makeActor(did: "did:plc:1")]
        viewModel.selectAllSearchResults()
        viewModel.clearSearchSelection()
        XCTAssertTrue(viewModel.selectedSearchActorIDs.isEmpty)
    }

    func testSelectAllFilteredMembers() {
        viewModel.filteredMembers = [makeMember(did: "did:plc:1"), makeMember(did: "did:plc:2")]
        viewModel.selectAllFilteredMembers()
        XCTAssertEqual(viewModel.selectedMemberIDs.count, 2)
    }

    func testClearMemberSelection() {
        viewModel.filteredMembers = [makeMember(did: "did:plc:1")]
        viewModel.selectAllFilteredMembers()
        viewModel.clearMemberSelection()
        XCTAssertTrue(viewModel.selectedMemberIDs.isEmpty)
    }

    func testUpdateMemberFilter() {
        let alice = makeMember(did: "did:plc:alice", handle: "alice.bsky.social")
        let bob = makeMember(did: "did:plc:bob", handle: "bob.bsky.social")
        viewModel.members = [alice, bob]
        viewModel.updateMemberFilter("alice")
        XCTAssertEqual(viewModel.filteredMembers.count, 1)
        XCTAssertEqual(viewModel.filteredMembers[0].actor.handle, "alice.bsky.social")
    }

    func testUpdateMemberFilterEmpty() {
        viewModel.members = [makeMember()]
        viewModel.updateMemberFilter("")
        XCTAssertEqual(viewModel.filteredMembers.count, 1)
    }

    func testUpdateMemberFilterMatchesDisplayName() {
        let alice = makeMember(did: "did:plc:alice", handle: "alice.bsky.social")
        viewModel.members = [alice]
        viewModel.updateMemberFilter("alice")
        XCTAssertEqual(viewModel.filteredMembers.count, 1)
    }

    func testOnMembersChangedRemovesOrphanedSelections() {
        let m1 = makeMember(did: "did:plc:1", handle: "a.bsky.social")
        viewModel.members = [m1]
        viewModel.selectedMemberIDs.insert(m1.id)
        viewModel.selectedMemberIDs.insert("orphaned-id")
        viewModel.onMembersChanged()
        XCTAssertEqual(viewModel.selectedMemberIDs.count, 1)
    }

    func testExportRows() {
        viewModel.members = [makeMember(did: "did:plc:1", handle: "alice.bsky.social", recordURI: "at://item/1")]
        let rows = viewModel.exportRows()
        XCTAssertEqual(rows.count, 1)
        XCTAssertTrue(rows[0].contains("alice.bsky.social"))
    }

    func testExportDiffRowsWithoutComparison() {
        let rows = viewModel.exportDiffRows()
        XCTAssertTrue(rows.isEmpty)
    }

    func testComparisonMembersReturnsEmptyWithoutReport() {
        let members = viewModel.comparisonMembers(for: .overlap)
        XCTAssertTrue(members.isEmpty)
    }

    func testSelectedComparisonMembersReturnsEmptyWithoutReport() {
        let members = viewModel.selectedComparisonMembers()
        XCTAssertTrue(members.isEmpty)
    }

    func testClearComparison() {
        viewModel.comparisonReport = ListComparisonReport(otherList: makeList(), overlap: [], onlyInCurrent: [], onlyInOther: [])
        viewModel.selectedComparisonActorDIDs = ["did:plc:1"]
        viewModel.clearComparison()
        XCTAssertNil(viewModel.comparisonReport)
        XCTAssertTrue(viewModel.selectedComparisonActorDIDs.isEmpty)
    }

    func testDiscardImportPreview() {
        viewModel.importPreview = ImportPreview(sourceDescription: "Test", items: [])
        viewModel.discardImportPreview()
        XCTAssertNil(viewModel.importPreview)
    }

    func testSelectComparisonBucket() {
        let report = ListComparisonReport(
            otherList: makeList(),
            overlap: [makeMember(did: "did:plc:overlap", handle: "overlap.bsky.social")],
            onlyInCurrent: [makeMember(did: "did:plc:current", handle: "current.bsky.social")],
            onlyInOther: [makeMember(did: "did:plc:other", handle: "other.bsky.social")]
        )
        viewModel.comparisonReport = report
        viewModel.selectComparisonBucket(.overlap)
        XCTAssertEqual(viewModel.selectedComparisonActorDIDs, ["did:plc:overlap"])
    }

    func testClearComparisonSelection() {
        viewModel.selectedComparisonActorDIDs = ["did:plc:test"]
        viewModel.clearComparisonSelection()
        XCTAssertTrue(viewModel.selectedComparisonActorDIDs.isEmpty)
    }
}
