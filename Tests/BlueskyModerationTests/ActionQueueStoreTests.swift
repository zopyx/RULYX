@testable import BlueskyModeration
import XCTest

@MainActor
final class ActionQueueStoreTests: XCTestCase {
    func testEnqueueAddsAction() {
        let store = ActionQueueStore()
        let action = QueuedAction(title: "Test", actors: [makeActor()], operation: .add) { _ in }
        XCTAssertTrue(store.actions.isEmpty)
        store.enqueue(action)
        XCTAssertEqual(store.actions.count, 1)
    }

    func testEnqueueSetsStatusToPendingInitially() {
        let action = QueuedAction(title: "Test", actors: [makeActor()], operation: .add) { _ in }
        XCTAssertEqual(action.status, .pending)
    }

    func testCancelRemovesAction() {
        let store = ActionQueueStore()
        let action = QueuedAction(title: "Test", actors: [makeActor()], operation: .add) { _ in }
        store.enqueue(action)
        store.cancel(action.id)
        XCTAssertTrue(store.actions.isEmpty)
    }

    func testCancelUnknownIDDoesNothing() {
        let store = ActionQueueStore()
        let action = QueuedAction(title: "Test", actors: [makeActor()], operation: .add) { _ in }
        store.enqueue(action)
        store.cancel(UUID())
        XCTAssertEqual(store.actions.count, 1)
    }

    func testRetryOnlyWorksOnCompletedActions() {
        let store = ActionQueueStore()
        let action = QueuedAction(title: "Test", actors: [makeActor()], operation: .add) { _ in }
        store.enqueue(action)
        store.retry(action.id)
        XCTAssertEqual(store.actions.count, 1)
    }

    func testRetryOnPendingDoesNothing() {
        let store = ActionQueueStore()
        let action = QueuedAction(title: "Test", actors: [makeActor()], operation: .add) { _ in }
        store.enqueue(action)
        let count = store.actions.count
        store.retry(action.id)
        XCTAssertEqual(store.actions.count, count)
    }

    func testQueuedActionHashable() {
        let id = UUID()
        let a1 = QueuedAction(id: id, title: "A", actors: [], operation: .add) { _ in }
        let a2 = QueuedAction(id: id, title: "B", actors: [], operation: .add) { _ in }
        XCTAssertEqual(a1, a2)
        XCTAssertEqual(a1.hashValue, a2.hashValue)
    }

    func testQueuedActionHashableDifferentIDs() {
        let a1 = QueuedAction(title: "A", actors: [], operation: .add) { _ in }
        let a2 = QueuedAction(title: "B", actors: [], operation: .add) { _ in }
        XCTAssertNotEqual(a1, a2)
    }

    func testEnqueueMultipleActions() {
        let store = ActionQueueStore()
        for i in 0 ..< 5 {
            store.enqueue(QueuedAction(title: "Action \(i)", actors: [makeActor()], operation: .add) { _ in })
        }
        XCTAssertEqual(store.actions.count, 5)
    }

    func testQueuedActionIdentifiable() {
        let action = QueuedAction(title: "Test", actors: [makeActor()], operation: .add) { _ in }
        XCTAssertEqual(action.id, action.id)
    }

    func testQueuedActionCreationTimestamp() {
        let before = Date.now
        let action = QueuedAction(title: "Test", actors: [], operation: .add) { _ in }
        let after = Date.now
        XCTAssertGreaterThanOrEqual(action.createdAt, before)
        XCTAssertLessThanOrEqual(action.createdAt, after)
    }

    func testQueuedActionStatuses() {
        XCTAssertEqual(QueuedActionStatus.pending, .pending)
        XCTAssertNotEqual(QueuedActionStatus.pending, QueuedActionStatus.running(1, 2, "h"))
        XCTAssertNotEqual(QueuedActionStatus.pending, QueuedActionStatus.completed(1, 0))
    }
}
