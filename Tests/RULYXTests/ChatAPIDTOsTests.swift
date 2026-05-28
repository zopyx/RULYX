@testable import RULYX
import XCTest

final class ChatAPIDTOsTests: XCTestCase {
    func testConvoViewDTODecoding() throws {
        let json = Data("""
        {"id":"cid1","rev":"r1","members":[{"did":"did:plc:a","handle":"a.bsky.social"}],"muted":false,"status":"accepted","unreadCount":3}
        """.utf8)
        let dto = try JSONDecoder().decode(ConvoViewDTO.self, from: json)
        XCTAssertEqual(dto.id, "cid1")
        XCTAssertEqual(dto.rev, "r1")
        XCTAssertEqual(dto.members.count, 1)
        XCTAssertEqual(dto.members[0].did, "did:plc:a")
        XCTAssertFalse(dto.muted)
        XCTAssertEqual(dto.status, "accepted")
        XCTAssertEqual(dto.unreadCount, 3)
        XCTAssertNil(dto.lastMessage)
        XCTAssertNil(dto.kind)
    }

    func testConvoViewDTOWithLastMessage() throws {
        let json = Data("""
        {"id":"cid1","rev":"r1","members":[],"muted":false,"lastMessage":{"$type":"chat.bsky.convo.defs#messageView","id":"msg1","rev":"mr1","text":"Hello","sender":{"did":"did:plc:s"},"sentAt":"2024-01-01T00:00:00Z"},"unreadCount":0}
        """.utf8)
        let dto = try JSONDecoder().decode(ConvoViewDTO.self, from: json)
        XCTAssertNotNil(dto.lastMessage)
        XCTAssertNotNil(dto.lastMessage?.message)
        XCTAssertNil(dto.lastMessage?.deleted)
        XCTAssertNil(dto.lastMessage?.system)
        XCTAssertEqual(dto.lastMessage?.message?.text, "Hello")
    }

    func testConvoViewDTOWithKindDirect() throws {
        let json = Data("""
        {"id":"cid1","rev":"r1","members":[],"muted":false,"kind":{},"unreadCount":0}
        """.utf8)
        let dto = try JSONDecoder().decode(ConvoViewDTO.self, from: json)
        XCTAssertNotNil(dto.kind?.direct)
        XCTAssertNil(dto.kind?.group)
    }

    func testGroupConvoDTODecoding() throws {
        let json = Data("""
        {"name":"Group","memberCount":5,"createdAt":"2024-01-01T00:00:00Z","lockStatus":"unlocked"}
        """.utf8)
        let dto = try JSONDecoder().decode(GroupConvoDTO.self, from: json)
        XCTAssertEqual(dto.name, "Group")
        XCTAssertEqual(dto.memberCount, 5)
        XCTAssertEqual(dto.lockStatus, "unlocked")
    }

    func testGetMessagesResponseDecoding() throws {
        let json = Data("""
        {"cursor":"c1","messages":[{"$type":"chat.bsky.convo.defs#messageView","id":"m1","rev":"r1","text":"Hi","sender":{"did":"did:plc:s"},"sentAt":"2024-01-01T00:00:00Z"}]}
        """.utf8)
        let response = try JSONDecoder().decode(GetMessagesResponse.self, from: json)
        XCTAssertEqual(response.cursor, "c1")
        XCTAssertEqual(response.messages.count, 1)
    }

    func testMessageUnionDTOMessage() throws {
        let json = Data("""
        {"$type":"chat.bsky.convo.defs#messageView","id":"m1","rev":"r1","text":"Hello world","sender":{"did":"did:plc:s"},"sentAt":"2024-01-01T00:00:00Z"}
        """.utf8)
        let union = try JSONDecoder().decode(MessageUnionDTO.self, from: json)
        XCTAssertNotNil(union.messageView)
        XCTAssertNil(union.deletedMessageView)
        XCTAssertNil(union.systemMessageView)
    }

    func testDeletedMessageViewDTODecoding() throws {
        let json = Data("""
        {"id":"dm1","rev":"dr1","sender":{"did":"did:plc:s"},"sentAt":"2024-01-01T00:00:00Z"}
        """.utf8)
        let dto = try JSONDecoder().decode(DeletedMessageViewDTO.self, from: json)
        XCTAssertEqual(dto.id, "dm1")
        XCTAssertEqual(dto.sender?.did, "did:plc:s")
    }

    func testSystemMessageViewDTODecoding() throws {
        let json = Data("""
        {"id":"sm1","rev":"sr1","sentAt":"2024-01-01T00:00:00Z"}
        """.utf8)
        let dto = try JSONDecoder().decode(SystemMessageViewDTO.self, from: json)
        XCTAssertEqual(dto.id, "sm1")
    }

    func testSystemMessageDataUnionMemberJoin() throws {
        let json = Data("""
        {"member":{"did":"did:plc:joined"},"type":"chat.bsky.convo.defs#memberJoin"}
        """.utf8)
        let data = try JSONDecoder().decode(SystemMessageDataUnion.self, from: json)
        XCTAssertEqual(data.member?.did, "did:plc:joined")
    }

    func testSystemMessageDataUnionAddMember() throws {
        let json = Data("""
        {"member":{"did":"did:plc:added"},"addedBy":{"did":"did:plc:adder"},"type":"chat.bsky.convo.defs#addMember"}
        """.utf8)
        let data = try JSONDecoder().decode(SystemMessageDataUnion.self, from: json)
        XCTAssertEqual(data.member?.did, "did:plc:added")
        XCTAssertEqual(data.addedBy?.did, "did:plc:adder")
    }

    func testSystemMessageDataUnionEditGroup() throws {
        let json = Data("""
        {"oldName":"Old","newName":"New","type":"chat.bsky.convo.defs#editGroup"}
        """.utf8)
        let data = try JSONDecoder().decode(SystemMessageDataUnion.self, from: json)
        XCTAssertEqual(data.oldName, "Old")
        XCTAssertEqual(data.newName, "New")
    }

    func testListConvosResponseDecoding() throws {
        let json = Data("""
        {"cursor":"c1","convos":[{"id":"cid1","rev":"r1","members":[],"muted":false,"unreadCount":0}]}
        """.utf8)
        let response = try JSONDecoder().decode(ListConvosResponse.self, from: json)
        XCTAssertEqual(response.cursor, "c1")
        XCTAssertEqual(response.convos.count, 1)
    }

    func testSendMessageResponseDecoding() throws {
        let json = Data("""
        {"id":"m1","rev":"r1","text":"Hello","sender":{"did":"did:plc:s"},"sentAt":"2024-01-01T00:00:00Z"}
        """.utf8)
        let response = try JSONDecoder().decode(SendMessageResponse.self, from: json)
        XCTAssertEqual(response.id, "m1")
        XCTAssertEqual(response.text, "Hello")
        XCTAssertEqual(response.sender.did, "did:plc:s")
    }

    func testGetConvoResponseDecoding() throws {
        let json = Data("""
        {"convo":{"id":"cid1","rev":"r1","members":[],"muted":false,"unreadCount":0}}
        """.utf8)
        let response = try JSONDecoder().decode(GetConvoResponse.self, from: json)
        XCTAssertEqual(response.convo.id, "cid1")
    }

    func testMessageViewDTOWithReactions() throws {
        let json = Data("""
        {"id":"m1","rev":"r1","text":"Hi","sender":{"did":"did:plc:s"},"sentAt":"2024-01-01T00:00:00Z","reactions":[{"value":"👍","sender":{"did":"did:plc:s"},"createdAt":"2024-01-01T00:00:01Z"}]}
        """.utf8)
        let msg = try JSONDecoder().decode(MessageViewDTO.self, from: json)
        XCTAssertEqual(msg.reactions?.count, 1)
        XCTAssertEqual(msg.reactions?[0].value, "👍")
    }

    func testReactionViewDTODecoding() throws {
        let json = Data("""
        {"value":"❤️","sender":{"did":"did:plc:s"},"createdAt":"2024-01-01T00:00:00Z"}
        """.utf8)
        let reaction = try JSONDecoder().decode(ReactionViewDTO.self, from: json)
        XCTAssertEqual(reaction.value, "❤️")
        XCTAssertEqual(reaction.sender.did, "did:plc:s")
    }

    func testLogEventUnionDTOBeginConvo() throws {
        let json = Data("""
        {"$type":"chat.bsky.convo.defs#beginConvo","convoId":"cid1","rev":"r1"}
        """.utf8)
        let union = try JSONDecoder().decode(LogEventUnionDTO.self, from: json)
        XCTAssertNotNil(union.beginConvo)
        XCTAssertEqual(union.beginConvo?.convoId, "cid1")
    }

    func testLogAcceptConvoDTODecoding() throws {
        let json = Data("""
        {"convoId":"cid1","rev":"r1"}
        """.utf8)
        let dto = try JSONDecoder().decode(LogAcceptConvoDTO.self, from: json)
        XCTAssertEqual(dto.convoId, "cid1")
    }

    func testLogCreateMessageDTODecoding() throws {
        let json = Data("""
        {"convoId":"cid1","message":{"$type":"chat.bsky.convo.defs#messageView","id":"m1","rev":"r1","text":"Hi","sender":{"did":"did:plc:s"},"sentAt":"2024-01-01T00:00:00Z"},"rev":"r1"}
        """.utf8)
        let dto = try JSONDecoder().decode(LogCreateMessageDTO.self, from: json)
        XCTAssertEqual(dto.convoId, "cid1")
    }

    func testLogAddReactionDTODecoding() throws {
        let json = Data("""
        {"convoId":"cid1","message":{"$type":"chat.bsky.convo.defs#messageView","id":"m1","rev":"r1","text":"Hi","sender":{"did":"did:plc:s"},"sentAt":"2024-01-01T00:00:00Z"},"reaction":{"value":"❤️","sender":{"did":"did:plc:s"},"createdAt":"2024-01-01T00:00:00Z"},"rev":"r1"}
        """.utf8)
        let dto = try JSONDecoder().decode(LogAddReactionDTO.self, from: json)
        XCTAssertEqual(dto.reaction?.value, "❤️")
    }
}
