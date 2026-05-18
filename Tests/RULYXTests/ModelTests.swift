@testable import RULYX
import XCTest

final class AppAccountTests: XCTestCase {
    func testInitSetsDisplayNameToHandleWhenNil() {
        let account = AppAccount(handle: "user.bsky.social")
        XCTAssertEqual(account.displayName, "user.bsky.social")
    }

    func testInitSetsDisplayNameWhenProvided() {
        let account = AppAccount(handle: "user.bsky.social", displayName: "Alice")
        XCTAssertEqual(account.displayName, "Alice")
    }

    func testInitSetsDefaultID() {
        let a = AppAccount(handle: "a")
        let b = AppAccount(handle: "b")
        XCTAssertNotEqual(a.id, b.id)
    }

    func testCodableRoundTrip() throws {
        let original = AppAccount(
            handle: "test.bsky.social",
            displayName: "Test",
            did: "did:plc:test",
            avatarURL: URL(string: "https://example.com/avatar.jpg"),
            pdsURL: URL(string: "https://pds.example.com"),
            label: "work",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            lastUsedAt: Date(timeIntervalSince1970: 1_700_000_001)
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AppAccount.self, from: data)
        XCTAssertEqual(decoded.handle, original.handle)
        XCTAssertEqual(decoded.displayName, original.displayName)
        XCTAssertEqual(decoded.did, original.did)
        XCTAssertEqual(decoded.avatarURL, original.avatarURL)
        XCTAssertEqual(decoded.pdsURL, original.pdsURL)
        XCTAssertEqual(decoded.label, original.label)
        XCTAssertEqual(decoded.createdAt, original.createdAt)
        XCTAssertEqual(decoded.lastUsedAt, original.lastUsedAt)
    }

    func testHashable() {
        let id = UUID()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let a = AppAccount(id: id, handle: "user.bsky.social", createdAt: now, lastUsedAt: now)
        let b = AppAccount(id: id, handle: "user.bsky.social", createdAt: now, lastUsedAt: now)
        let c = AppAccount(handle: "other.bsky.social")
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }
}

final class BlueskyActorTests: XCTestCase {
    func testTitleReturnsDisplayNameWhenPresent() {
        let actor = BlueskyActor(did: "did:plc:test", handle: "user.bsky.social", displayName: "Alice")
        XCTAssertEqual(actor.title, "Alice")
    }

    func testTitleReturnsHandleWhenNoDisplayName() {
        let actor = BlueskyActor(did: "did:plc:test", handle: "user.bsky.social")
        XCTAssertEqual(actor.title, "user.bsky.social")
    }

    func testTitleReturnsHandleWhenDisplayNameIsEmpty() {
        let actor = BlueskyActor(did: "did:plc:test", handle: "user.bsky.social", displayName: "")
        XCTAssertEqual(actor.title, "user.bsky.social")
    }

    func testIsNewWhenCreatedRecently() {
        let actor = BlueskyActor(did: "did:plc:test", handle: "user.bsky.social", createdAt: Date().addingTimeInterval(-86400 * 2))
        XCTAssertTrue(actor.isNew)
    }

    func testIsNotNewWhenCreatedLongAgo() {
        let actor = BlueskyActor(did: "did:plc:test", handle: "user.bsky.social", createdAt: Date().addingTimeInterval(-86400 * 60))
        XCTAssertFalse(actor.isNew)
    }

    func testIsNotNewWhenCreatedAtNil() {
        let actor = BlueskyActor(did: "did:plc:test", handle: "user.bsky.social")
        XCTAssertFalse(actor.isNew)
    }

    func testCodableRoundTrip() throws {
        let original = BlueskyActor(
            did: "did:plc:test",
            handle: "user.bsky.social",
            displayName: "User",
            avatarURL: URL(string: "https://example.com/avatar.jpg"),
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            blockedDate: Date(timeIntervalSince1970: 1_700_000_001),
            description: "A test user"
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(BlueskyActor.self, from: data)
        XCTAssertEqual(decoded.did, original.did)
        XCTAssertEqual(decoded.handle, original.handle)
        XCTAssertEqual(decoded.displayName, original.displayName)
        XCTAssertEqual(decoded.avatarURL, original.avatarURL)
        XCTAssertEqual(decoded.description, original.description)
    }

    func testIDDefaultsToDID() {
        let actor = BlueskyActor(did: "did:plc:test", handle: "h")
        XCTAssertEqual(actor.id, "did:plc:test")
    }
}

final class BlueskyListTests: XCTestCase {
    func testKindPurposeIdentifierModeration() {
        XCTAssertEqual(BlueskyList.Kind.moderation.purposeIdentifier, "app.bsky.graph.defs#modlist")
    }

    func testKindPurposeIdentifierRegular() {
        XCTAssertEqual(BlueskyList.Kind.regular.purposeIdentifier, "app.bsky.graph.defs#curatelist")
    }

    func testKindSymbolNames() {
        XCTAssertEqual(BlueskyList.Kind.moderation.symbolName, "shield.lefthalf.filled")
        XCTAssertEqual(BlueskyList.Kind.regular.symbolName, "person.3")
    }

    func testKindAllCases() {
        XCTAssertEqual(BlueskyList.Kind.allCases, [.moderation, .regular])
    }

    func testCodableRoundTrip() throws {
        let original = BlueskyList(id: "at://list/1", name: "Test List", description: "A test", memberCount: 10, kind: .moderation)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(BlueskyList.self, from: data)
        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.name, original.name)
        XCTAssertEqual(decoded.description, original.description)
        XCTAssertEqual(decoded.memberCount, 10)
        XCTAssertEqual(decoded.kind, .moderation)
    }

    func testDecodingFromJSON() throws {
        let json = """
        {"id": "at://list/1", "name": "Mod List", "description": "Desc", "memberCount": 5, "kind": "moderation"}
        """.data(using: .utf8)!
        let list = try JSONDecoder().decode(BlueskyList.self, from: json)
        XCTAssertEqual(list.name, "Mod List")
        XCTAssertEqual(list.kind, .moderation)
        XCTAssertEqual(list.memberCount, 5)
    }
}

final class BlueskyListMemberTests: XCTestCase {
    func testExtractsTimestampFromURI() {
        let actor = BlueskyActor(did: "did:plc:member", handle: "member.bsky.social")
        let uri = "at://did:plc:owner/app.bsky.graph.listitem/3j7s2k5h4t6a8"
        let member = BlueskyListMember(recordURI: uri, actor: actor)
        XCTAssertEqual(member.id, uri)
        XCTAssertEqual(member.actor.did, "did:plc:member")
    }
}

final class BlueskyProfileTests: XCTestCase {
    func testTitleReturnsDisplayNameWhenPresent() {
        let profile = BlueskyProfile(
            id: "did:plc:p", did: "did:plc:p", handle: "user.bsky.social",
            displayName: "Alice", description: nil, websiteURL: nil, avatarURL: nil,
            bannerURL: nil, followersCount: nil, followsCount: nil, postsCount: nil,
            listsCount: nil, starterPacksCount: nil, createdAt: nil,
            labels: [], viewerState: nil
        )
        XCTAssertEqual(profile.title, "Alice")
    }

    func testTitleReturnsHandleWhenNoDisplayName() {
        let profile = BlueskyProfile(
            id: "did:plc:p", did: "did:plc:p", handle: "user.bsky.social",
            displayName: nil, description: nil, websiteURL: nil, avatarURL: nil,
            bannerURL: nil, followersCount: nil, followsCount: nil, postsCount: nil,
            listsCount: nil, starterPacksCount: nil, createdAt: nil,
            labels: [], viewerState: nil
        )
        XCTAssertEqual(profile.title, "user.bsky.social")
    }

    func testProfileURL() {
        let profile = BlueskyProfile(
            id: "did:plc:p", did: "did:plc:p", handle: "user.bsky.social",
            displayName: nil, description: nil, websiteURL: nil, avatarURL: nil,
            bannerURL: nil, followersCount: nil, followsCount: nil, postsCount: nil,
            listsCount: nil, starterPacksCount: nil, createdAt: nil,
            labels: [], viewerState: nil
        )
        XCTAssertEqual(profile.profileURL?.absoluteString, "https://bsky.app/profile/user.bsky.social")
    }

    func testDecodingFromJSON() throws {
        let json = """
        {"id": "did:plc:p", "did": "did:plc:p", "handle": "user.bsky.social", "labels": ["bad-actor"]}
        """.data(using: .utf8)!
        let profile = try JSONDecoder().decode(BlueskyProfile.self, from: json)
        XCTAssertEqual(profile.handle, "user.bsky.social")
        XCTAssertEqual(profile.labels, ["bad-actor"])
        XCTAssertNil(profile.displayName)
    }

    func testViewerStateMutedNotBlocking() {
        let state = BlueskyViewerState(muted: true, blockedBy: false, isBlocking: false, blockingRecordURI: nil, isFollowing: true, followingRecordURI: "at://follow/1", followsYou: false, mutedByListName: nil, blockingByListName: nil)
        XCTAssertTrue(state.muted)
        XCTAssertFalse(state.isBlocking)
        XCTAssertTrue(state.isFollowing)
    }
}

final class ChatModelsTests: XCTestCase {
    func testConversationLastMessageFromMessage() {
        let msg = ChatMessage(id: "m1", rev: "r1", text: "Hello", senderDID: "did:plc:a", sentAt: Date(timeIntervalSince1970: 1_700_000_000), reactions: [])
        let convo = ChatConversation(id: "c1", rev: "r1", members: [], lastMessage: .message(msg), muted: false, status: .accepted, unreadCount: 0, kind: .direct, groupInfo: nil)
        XCTAssertEqual(convo.lastMessageAt, Date(timeIntervalSince1970: 1_700_000_000))
    }

    func testConversationLastMessageFromDeleted() {
        let d = ChatDeletedMessage(id: "m1", rev: "r1", senderDID: "did:plc:a", sentAt: Date(timeIntervalSince1970: 1_700_000_001))
        let convo = ChatConversation(id: "c1", rev: "r1", members: [], lastMessage: .deleted(d), muted: false, status: .accepted, unreadCount: 0, kind: .direct, groupInfo: nil)
        XCTAssertEqual(convo.lastMessageAt, Date(timeIntervalSince1970: 1_700_000_001))
    }

    func testConversationLastMessageFromSystem() {
        let s = ChatSystemMessage(id: "m1", rev: "r1", sentAt: Date(timeIntervalSince1970: 1_700_000_002), data: .memberJoin(memberDID: "did:plc:b"))
        let convo = ChatConversation(id: "c1", rev: "r1", members: [], lastMessage: .system(s), muted: false, status: .accepted, unreadCount: 0, kind: .direct, groupInfo: nil)
        XCTAssertEqual(convo.lastMessageAt, Date(timeIntervalSince1970: 1_700_000_002))
    }

    func testConversationLastMessageAtDistantPastWhenNil() {
        let convo = ChatConversation(id: "c1", rev: "r1", members: [], lastMessage: nil, muted: false, status: .accepted, unreadCount: 0, kind: .direct, groupInfo: nil)
        XCTAssertEqual(convo.lastMessageAt, .distantPast)
    }

    func testConversationEqualityByIDAndRev() {
        let a = ChatConversation(id: "c1", rev: "r1", members: [], lastMessage: nil, muted: false, status: .accepted, unreadCount: 0, kind: .direct, groupInfo: nil)
        let b = ChatConversation(id: "c1", rev: "r1", members: [], lastMessage: nil, muted: false, status: .accepted, unreadCount: 0, kind: .direct, groupInfo: nil)
        let c = ChatConversation(id: "c1", rev: "r2", members: [], lastMessage: nil, muted: false, status: .accepted, unreadCount: 0, kind: .direct, groupInfo: nil)
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

    func testMemberProfileIDMatchesDID() {
        let m = ChatMemberProfile(did: "did:plc:a", handle: "a.bsky.social", displayName: nil, avatarURL: nil)
        XCTAssertEqual(m.id, "did:plc:a")
    }
}

final class ProfileMembershipModelsTests: XCTestCase {
    func testProfileListMembershipIDIsListURI() {
        let m = ProfileListMembership(listURI: "at://list/1", name: "L1", kind: .moderation, memberCount: nil, isMember: true, listItemRecordURI: nil)
        XCTAssertEqual(m.id, "at://list/1")
    }

    func testProfileStarterPackMembershipIDIsURI() {
        let m = ProfileStarterPackMembership(uri: "at://pack/1", name: "P1", memberCount: nil, joinedAllTimeCount: nil, isMember: true)
        XCTAssertEqual(m.id, "at://pack/1")
    }
}

final class PushNotificationRouteTests: XCTestCase {
    func testInitWithConvoID() {
        let userInfo: [AnyHashable: Any] = ["convoId": "cid123"]
        let route = PushNotificationRoute(userInfo: userInfo)
        XCTAssertNotNil(route)
        XCTAssertEqual(route?.conversationID, "cid123")
        XCTAssertNil(route?.memberDID)
    }

    func testInitWithMemberDID() {
        let userInfo: [AnyHashable: Any] = ["did": "did:plc:target"]
        let route = PushNotificationRoute(userInfo: userInfo)
        XCTAssertNotNil(route)
        XCTAssertNil(route?.conversationID)
        XCTAssertEqual(route?.memberDID, "did:plc:target")
    }

    func testInitWithNestedChatDict() {
        let userInfo: [AnyHashable: Any] = ["chat": ["convoId": "nested-cid"]]
        let route = PushNotificationRoute(userInfo: userInfo)
        XCTAssertNotNil(route)
        XCTAssertEqual(route?.conversationID, "nested-cid")
    }

    func testInitWithNestedDataDict() {
        let userInfo: [AnyHashable: Any] = ["data": ["convoId": "data-cid"]]
        let route = PushNotificationRoute(userInfo: userInfo)
        XCTAssertNotNil(route)
        XCTAssertEqual(route?.conversationID, "data-cid")
    }

    func testInitReturnsNilWhenNoRelevantKeys() {
        let userInfo: [AnyHashable: Any] = ["unrelated": "value"]
        let route = PushNotificationRoute(userInfo: userInfo)
        XCTAssertNil(route)
    }

    func testInitIgnoresEmptyStringValues() {
        let userInfo: [AnyHashable: Any] = ["convoId": ""]
        let route = PushNotificationRoute(userInfo: userInfo)
        XCTAssertNil(route)
    }

    func testInitWithMultipleKeysPrefersConvoId() {
        let userInfo: [AnyHashable: Any] = ["convoId": "cid", "did": "did:plc:d"]
        let route = PushNotificationRoute(userInfo: userInfo)
        XCTAssertEqual(route?.conversationID, "cid")
        XCTAssertEqual(route?.memberDID, "did:plc:d")
    }

    func testInitWithAlternateKeys() {
        let userInfo: [AnyHashable: Any] = ["conversationId": "alt-cid", "actorDid": "did:plc:alt"]
        let route = PushNotificationRoute(userInfo: userInfo)
        XCTAssertEqual(route?.conversationID, "alt-cid")
        XCTAssertEqual(route?.memberDID, "did:plc:alt")
    }
}
