@testable import BlueskyModeration
import XCTest

final class RelationshipCacheTests: XCTestCase {
    private let testKey = "test_relationship_cache"

    override func tearDown() {
        RelationshipCache.save([], forKey: testKey)
        super.tearDown()
    }

    func testSaveAndLoad() {
        let actors = [
            BlueskyActor(did: "did:plc:1", handle: "alice.bsky.social", displayName: "Alice"),
            BlueskyActor(did: "did:plc:2", handle: "bob.bsky.social", displayName: "Bob"),
        ]
        RelationshipCache.save(actors, forKey: testKey)
        let loaded = RelationshipCache.load(forKey: testKey)
        XCTAssertEqual(loaded.count, 2)
        XCTAssertEqual(loaded[0].handle, "alice.bsky.social")
    }

    func testLoadEmptyKeyReturnsEmpty() {
        let loaded = RelationshipCache.load(forKey: "nonexistent_key")
        XCTAssertTrue(loaded.isEmpty)
    }

    func testOverwriteCache() {
        let first = [BlueskyActor(did: "did:plc:1", handle: "first.bsky.social")]
        RelationshipCache.save(first, forKey: testKey)

        let second = [BlueskyActor(did: "did:plc:2", handle: "second.bsky.social")]
        RelationshipCache.save(second, forKey: testKey)

        let loaded = RelationshipCache.load(forKey: testKey)
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].handle, "second.bsky.social")
    }

    func testEmptyArrayOverwrites() {
        let actors = [BlueskyActor(did: "did:plc:1", handle: "test.bsky.social")]
        RelationshipCache.save(actors, forKey: testKey)
        RelationshipCache.save([], forKey: testKey)
        let loaded = RelationshipCache.load(forKey: testKey)
        XCTAssertTrue(loaded.isEmpty)
    }

    func testMultipleKeysIndependent() {
        let key1 = "\(testKey)_1"
        let key2 = "\(testKey)_2"
        RelationshipCache.save([BlueskyActor(did: "did:plc:a", handle: "a.bsky.social")], forKey: key1)
        RelationshipCache.save([BlueskyActor(did: "did:plc:b", handle: "b.bsky.social")], forKey: key2)
        XCTAssertEqual(RelationshipCache.load(forKey: key1).count, 1)
        XCTAssertEqual(RelationshipCache.load(forKey: key2).count, 1)
        RelationshipCache.save([], forKey: key1)
        RelationshipCache.save([], forKey: key2)
    }

    func testCachePersistsActorProperties() {
        let date = Date.now.addingTimeInterval(-86400 * 30)
        let actors = [BlueskyActor(did: "did:plc:test", handle: "test.bsky.social", displayName: "Test User", avatarURL: URL(string: "https://example.com/avatar.png"), createdAt: date)]
        RelationshipCache.save(actors, forKey: testKey)
        let loaded = RelationshipCache.load(forKey: testKey)
        XCTAssertEqual(loaded[0].displayName, "Test User")
        XCTAssertEqual(loaded[0].avatarURL?.absoluteString, "https://example.com/avatar.png")
        XCTAssertEqual(loaded[0].createdAt, date)
    }
}
