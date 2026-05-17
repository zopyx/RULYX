@testable import BlueskyModeration
import XCTest

@MainActor
final class ListDiffControllerTests: XCTestCase {
    private var controller: ListDiffController!

    override func setUp() async throws {
        try await super.setUp()
        controller = ListDiffController()
    }

    func testComparisonMembersForOverlapBucket() {
        let report = makeComparisonReport()
        let members = controller.comparisonMembers(for: .overlap, in: report)
        XCTAssertEqual(members.map(\.actor.handle), ["alice.bsky.social"])
    }

    func testComparisonMembersForOnlyInCurrentBucket() {
        let report = makeComparisonReport()
        let members = controller.comparisonMembers(for: .onlyInCurrent, in: report)
        XCTAssertEqual(members.map(\.actor.handle), ["bob.bsky.social"])
    }

    func testComparisonMembersForOnlyInOtherBucket() {
        let report = makeComparisonReport()
        let members = controller.comparisonMembers(for: .onlyInOther, in: report)
        XCTAssertEqual(members.map(\.actor.handle), ["carol.bsky.social"])
    }

    func testSelectedComparisonMembersFiltersByDID() {
        let report = makeComparisonReport()
        let selected = controller.selectedComparisonMembers(
            selectedDIDs: ["did:plc:alice", "did:plc:carol"],
            in: report
        )
        XCTAssertEqual(selected.map(\.actor.handle), ["alice.bsky.social", "carol.bsky.social"])
    }

    func testSelectComparisonBucketReturnsDIDsForBucket() {
        let report = makeComparisonReport()
        let dids = controller.selectComparisonBucket(.onlyInCurrent, in: report)
        XCTAssertEqual(dids, ["did:plc:bob"])
    }

    func testExportDiffRowsIncludesAllBuckets() {
        let report = makeComparisonReport()
        let rows = controller.exportDiffRows(from: report)
        XCTAssertEqual(rows.count, 3)
        XCTAssertTrue(rows[0].contains("Shared"))
        XCTAssertTrue(rows[0].contains("alice.bsky.social"))
        XCTAssertTrue(rows[1].contains("Only Here"))
        XCTAssertTrue(rows[1].contains("bob.bsky.social"))
        XCTAssertTrue(rows[2].contains("Only There"))
        XCTAssertTrue(rows[2].contains("carol.bsky.social"))
    }

    private func makeComparisonReport() -> ListComparisonReport {
        ListComparisonReport(
            otherList: BlueskyList(
                id: "at://other",
                name: "Other",
                description: "",
                memberCount: nil,
                kind: .regular
            ),
            overlap: [makeMember(did: "did:plc:alice", handle: "alice.bsky.social")],
            onlyInCurrent: [makeMember(did: "did:plc:bob", handle: "bob.bsky.social")],
            onlyInOther: [makeMember(did: "did:plc:carol", handle: "carol.bsky.social")]
        )
    }

    private func makeMember(did: String, handle: String) -> BlueskyListMember {
        BlueskyListMember(
            recordURI: "at://did:plc:owner/app.bsky.graph.listitem/\(did)",
            actor: BlueskyActor(did: did, handle: handle, displayName: nil, avatarURL: nil)
        )
    }
}
