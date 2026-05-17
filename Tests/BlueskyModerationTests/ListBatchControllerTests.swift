@testable import BlueskyModeration
import XCTest

@MainActor
final class ListBatchControllerTests: XCTestCase {
    private var controller: ListBatchController!

    override func setUp() {
        super.setUp()
        controller = ListBatchController()
    }

    func testPerformBatchAllSucceed() async {
        let actors = [
            makeActor(did: "did:plc:1", handle: "a.bsky.social"),
            makeActor(did: "did:plc:2", handle: "b.bsky.social"),
            makeActor(did: "did:plc:3", handle: "c.bsky.social"),
        ]
        let result = await controller.performBatch(
            title: "Test",
            actors: actors,
            operation: .add,
            action: { _ in }
        )
        XCTAssertEqual(result.succeededActors.count, 3)
        XCTAssertEqual(result.failures.count, 0)
    }

    func testPerformBatchSomeFail() async {
        let actors = [
            makeActor(did: "did:plc:1", handle: "a.bsky.social"),
            makeActor(did: "did:plc:2", handle: "b.bsky.social"),
        ]
        var callCount = 0
        let result = await controller.performBatch(
            title: "Test",
            actors: actors,
            operation: .remove,
            action: { actor in
                callCount += 1
                if actor.did == "did:plc:2" {
                    throw BlueskyAPIError.server("Failed")
                }
            }
        )
        XCTAssertEqual(result.succeededActors.count, 1)
        XCTAssertEqual(result.failures.count, 1)
        XCTAssertEqual(result.failures[0].actor.did, "did:plc:2")
    }

    func testPerformBatchEmptyActors() async {
        let result = await controller.performBatch(
            title: "Empty",
            actors: [],
            operation: .add,
            action: { _ in }
        )
        XCTAssertEqual(result.succeededActors.count, 0)
        XCTAssertEqual(result.failures.count, 0)
    }

    func testPerformBatchReportsProgress() async {
        let actors = [
            makeActor(did: "did:plc:1", handle: "a.bsky.social"),
            makeActor(did: "did:plc:2", handle: "b.bsky.social"),
        ]
        var progressUpdates: [BatchProgress] = []
        let result = await controller.performBatch(
            title: "Test",
            actors: actors,
            operation: .block,
            onProgress: { progress in
                progressUpdates.append(progress)
            },
            action: { _ in }
        )
        XCTAssertGreaterThanOrEqual(progressUpdates.count, 1)
        if let last = progressUpdates.last {
            XCTAssertEqual(last.completedCount, actors.count)
            XCTAssertEqual(last.totalCount, actors.count)
        }
    }

    func testPerformBatchCallsOnStartAndComplete() async {
        let actors = [
            makeActor(did: "did:plc:1", handle: "a.bsky.social"),
            makeActor(did: "did:plc:2", handle: "b.bsky.social"),
        ]
        var completed: [BlueskyActor] = []
        _ = await controller.performBatch(
            title: "Test",
            actors: actors,
            operation: .add,
            onActorComplete: { actor in completed.append(actor) },
            action: { _ in }
        )
        XCTAssertEqual(completed.count, 2)
    }

    func testBatchResultSummaryText() {
        let result = ListBulkActionResult(
            operation: .add,
            succeededActors: [makeActor()],
            failures: []
        )
        XCTAssertEqual(result.summaryText, "1 account added.")
    }

    func testBatchResultSummaryTextWithFailures() {
        let result = ListBulkActionResult(
            operation: .add,
            succeededActors: [makeActor()],
            failures: [.init(actor: makeActor(), message: "Error")]
        )
        XCTAssertTrue(result.summaryText.contains("failed"))
    }

    func testBatchResultSummaryTextAllFailed() {
        let result = ListBulkActionResult(
            operation: .add,
            succeededActors: [],
            failures: [.init(actor: makeActor(), message: "Error")]
        )
        XCTAssertTrue(result.summaryText.contains("No accounts"))
    }

    func testBatchProgressFractionComplete() {
        let progress = BatchProgress(title: "Test", completedCount: 3, totalCount: 10, currentHandle: nil)
        XCTAssertEqual(progress.fractionComplete, 0.3, accuracy: 0.001)
    }

    func testBatchProgressFractionCompleteZeroTotal() {
        let progress = BatchProgress(title: "Test", completedCount: 0, totalCount: 0, currentHandle: nil)
        XCTAssertEqual(progress.fractionComplete, 0)
    }

    func testOperationTitles() {
        XCTAssertEqual(ListBulkActionResult.Operation.add.title, "Bulk Add")
        XCTAssertEqual(ListBulkActionResult.Operation.block.title, "Block Followers")
        XCTAssertEqual(ListBulkActionResult.Operation.remove.title, "Bulk Remove")
        XCTAssertEqual(ListBulkActionResult.Operation.import.title, "Import Handles")
        XCTAssertEqual(ListBulkActionResult.Operation.copy.title, "Copy Members")
        XCTAssertEqual(ListBulkActionResult.Operation.move.title, "Move Members")
    }

    func testOperationPastTenseVerbs() {
        XCTAssertEqual(ListBulkActionResult.Operation.add.pastTenseVerb, "added")
        XCTAssertEqual(ListBulkActionResult.Operation.remove.pastTenseVerb, "removed")
        XCTAssertEqual(ListBulkActionResult.Operation.block.pastTenseVerb, "blocked")
        XCTAssertEqual(ListBulkActionResult.Operation.copy.pastTenseVerb, "copied")
    }

    func testListBulkActionResultEquatable() {
        let result1 = ListBulkActionResult(operation: .add, succeededActors: [], failures: [])
        let result2 = ListBulkActionResult(operation: .add, succeededActors: [], failures: [])
        XCTAssertEqual(result1, result2)
    }

    func testListBulkActionResultFailureIdentifiable() {
        let failure = ListBulkActionResult.Failure(actor: makeActor(did: "did:test"), message: "err")
        XCTAssertEqual(failure.id, "did:test")
    }

    func testBatchProgressWithHandle() {
        let progress = BatchProgress(title: "Test", completedCount: 1, totalCount: 2, currentHandle: "user.bsky.social")
        XCTAssertEqual(progress.currentHandle, "user.bsky.social")
    }

    func testPerformBatchAllFail() async {
        let actors = [makeActor(did: "did:plc:f1", handle: "f1.bsky.social")]
        let result = await controller.performBatch(
            title: "Fail All",
            actors: actors,
            operation: .add,
            action: { _ in throw BlueskyAPIError.server("Always fails") }
        )
        XCTAssertEqual(result.succeededActors.count, 0)
        XCTAssertEqual(result.failures.count, 1)
    }
}
