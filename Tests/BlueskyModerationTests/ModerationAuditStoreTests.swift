@testable import BlueskyModeration
import XCTest

@MainActor
final class ModerationAuditStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "ModerationAuditTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        if let suiteName {
            defaults.removePersistentDomain(forName: suiteName)
        }
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testInitialState() {
        let store = ModerationAuditStore(defaults: defaults)
        XCTAssertTrue(store.operationLog.isEmpty)
    }

    func testPreviewPopulatesData() {
        let store = ModerationAuditStore(defaults: defaults, preview: true)
        XCTAssertEqual(store.operationLog.count, 1)
        XCTAssertEqual(store.operationLog[0].title, "Bulk Add")
    }

    func testRecordOperationInsertsAtFront() {
        let store = ModerationAuditStore(defaults: defaults)
        store.recordOperation(ModerationOperationLogEntry(title: "First", summary: "1 success", succeededHandles: ["a"], failedHandles: []))
        store.recordOperation(ModerationOperationLogEntry(title: "Second", summary: "2 successes", succeededHandles: ["b", "c"], failedHandles: []))
        XCTAssertEqual(store.operationLog.count, 2)
        XCTAssertEqual(store.operationLog[0].title, "Second")
        XCTAssertEqual(store.operationLog[1].title, "First")
    }

    func testRecordOperationLimitsTo25() {
        let store = ModerationAuditStore(defaults: defaults)
        for i in 0 ..< 30 {
            store.recordOperation(ModerationOperationLogEntry(title: "Op \(i)", summary: "", succeededHandles: ["h\(i)"], failedHandles: []))
        }
        XCTAssertEqual(store.operationLog.count, 25)
        XCTAssertEqual(store.operationLog[0].title, "Op 29")
        XCTAssertEqual(store.operationLog[24].title, "Op 5")
    }

    func testCaptureSnapshotCreatesSummary() {
        let store = ModerationAuditStore(defaults: defaults)
        let list = makeList(id: "at://list/1", name: "Test List")
        let members = [makeMember(did: "did:plc:alice", handle: "alice.bsky.social")]

        let summary = store.captureSnapshot(for: list, members: members)
        XCTAssertEqual(summary.listName, "Test List")
        // First snapshot has no previous to compare, so all members appear added
        XCTAssertEqual(summary.addedMembers.count, 1)
        XCTAssertTrue(summary.removedMembers.isEmpty)
    }

    func testCaptureSnapshotDetectsAddedMembers() {
        let store = ModerationAuditStore(defaults: defaults)
        let list = makeList(id: "at://list/add-test", name: "Add Test")

        let firstSummary = store.captureSnapshot(for: list, members: [makeMember(did: "did:plc:alice", handle: "alice.bsky.social")])
        XCTAssertEqual(firstSummary.snapshotID, firstSummary.snapshotID)

        let secondSummary = store.captureSnapshot(for: list, members: [
            makeMember(did: "did:plc:alice", handle: "alice.bsky.social"),
            makeMember(did: "did:plc:bob", handle: "bob.bsky.social"),
        ])
        XCTAssertTrue(secondSummary.hasChanges)
        XCTAssertEqual(secondSummary.addedMembers.count, 1)
        XCTAssertEqual(secondSummary.addedMembers[0].did, "did:plc:bob")
    }

    func testCaptureSnapshotDetectsRemovedMembers() {
        let store = ModerationAuditStore(defaults: defaults)
        let list = makeList(id: "at://list/remove-test", name: "Remove Test")

        _ = store.captureSnapshot(for: list, members: [
            makeMember(did: "did:plc:alice", handle: "alice.bsky.social"),
            makeMember(did: "did:plc:bob", handle: "bob.bsky.social"),
        ])
        let summary = store.captureSnapshot(for: list, members: [
            makeMember(did: "did:plc:alice", handle: "alice.bsky.social"),
        ])
        XCTAssertTrue(summary.hasChanges)
        XCTAssertEqual(summary.removedMembers.count, 1)
        XCTAssertEqual(summary.removedMembers[0].did, "did:plc:bob")
    }

    func testCaptureSnapshotDuplicateReturnsExisting() {
        let store = ModerationAuditStore(defaults: defaults)
        let list = makeList(id: "at://list/dup-test", name: "Dup Test")
        let members = [makeMember(did: "did:plc:alice", handle: "alice.bsky.social")]

        let first = store.captureSnapshot(for: list, members: members)
        let second = store.captureSnapshot(for: list, members: members)
        XCTAssertEqual(second.snapshotID, first.snapshotID)
        XCTAssertFalse(second.hasChanges)
    }

    func testSnapshotHistoryRetentionLimit() {
        let store = ModerationAuditStore(defaults: defaults)
        let list = makeList(id: "at://list/retention", name: "Retention")

        for i in 0 ..< 15 {
            let members = (0 ... i).map { idx in
                makeMember(did: "did:plc:\(i)-\(idx)", handle: "u\(i)-\(idx).bsky.social")
            }
            _ = store.captureSnapshot(for: list, members: members)
        }

        let history = store.snapshotHistory(for: list.id)
        XCTAssertEqual(history.count, 12)
    }

    func testCompareSnapshots() {
        let store = ModerationAuditStore(defaults: defaults)
        let list = makeList(id: "at://list/compare", name: "Compare")

        let first = store.captureSnapshot(for: list, members: [makeMember(did: "did:plc:a", handle: "a.bsky.social")])
        let second = store.captureSnapshot(for: list, members: [
            makeMember(did: "did:plc:a", handle: "a.bsky.social"),
            makeMember(did: "did:plc:b", handle: "b.bsky.social"),
        ])

        let comparison = store.compareSnapshots(listID: list.id, newerSnapshotID: second.snapshotID, olderSnapshotID: first.snapshotID)
        XCTAssertNotNil(comparison)
        XCTAssertEqual(comparison?.addedMembers.count, 1)
        XCTAssertEqual(comparison?.addedMembers[0].did, "did:plc:b")
    }

    func testCompareSnapshotsWithInvalidIDs() {
        let store = ModerationAuditStore(defaults: defaults)
        let result = store.compareSnapshots(listID: "nonexistent", newerSnapshotID: UUID(), olderSnapshotID: UUID())
        XCTAssertNil(result)
    }

    func testSnapshotHistoryEmpty() {
        let store = ModerationAuditStore(defaults: defaults)
        XCTAssertTrue(store.snapshotHistory(for: "nonexistent").isEmpty)
    }

    func testOperationLogPersistsAcrossInstances() {
        let store1 = ModerationAuditStore(defaults: defaults)
        store1.recordOperation(ModerationOperationLogEntry(title: "Persist Test", summary: "Test", succeededHandles: ["a"], failedHandles: []))

        let store2 = ModerationAuditStore(defaults: defaults)
        XCTAssertEqual(store2.operationLog.count, 1)
        XCTAssertEqual(store2.operationLog[0].title, "Persist Test")
    }
}
