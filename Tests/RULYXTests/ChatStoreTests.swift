@testable import RULYX
import XCTest

@MainActor
final class ChatStoreTests: XCTestCase {
    // MARK: - Initial State

    func testInitialStateIsEmpty() {
        let store = ChatStore(chatService: MockChatService())
        XCTAssertTrue(store.conversations.isEmpty)
        XCTAssertTrue(store.messages.isEmpty)
        XCTAssertFalse(store.isLoadingConvos)
        XCTAssertFalse(store.isLoadingMessages)
        XCTAssertFalse(store.isLoadingMoreMessages)
        XCTAssertFalse(store.isSendingMessage)
        XCTAssertNil(store.error)
        XCTAssertNil(store.messageError)
        XCTAssertNil(store.statusMessage)
    }

    // MARK: - Error Publish/Clear

    func testErrorIsPublishedAndCleared() {
        struct TestError: Error, Equatable { let message: String }
        let store = ChatStore(chatService: MockChatService())
        store.error = TestError(message: "boom")
        XCTAssertNotNil(store.error)
        store.error = nil
        XCTAssertNil(store.error)
    }

    // MARK: - Conversation Visibility

    func testSetVisibleConversation() {
        let store = ChatStore(chatService: MockChatService())
        store.setVisibleConversation("convo-1")
        store.setVisibleConversation(nil)
        XCTAssertNil(store.error)
    }
}

// MARK: - Mock

@MainActor
private final class MockChatService: ChatServicing {
    func clearCaches() {}

    func listConvos(account _: AppAccount, appPassword _: String?, status _: String?, cursor _: String?) async throws -> PagedConvos {
        PagedConvos(conversations: [], cursor: nil)
    }

    func getConvo(convoId _: String, account _: AppAccount, appPassword _: String?) async throws -> ChatConversation {
        throw NSError(domain: "mock", code: -1)
    }

    func getConvoForMembers(members _: [String], account _: AppAccount, appPassword _: String?) async throws -> ChatConversation {
        throw NSError(domain: "mock", code: -1)
    }

    func getMessages(convoId _: String, cursor _: String?, limit _: Int, account _: AppAccount, appPassword _: String?) async throws -> PagedMessages {
        PagedMessages(messages: [], cursor: nil)
    }

    func sendMessage(convoId _: String, text _: String, account _: AppAccount, appPassword _: String?) async throws -> ChatMessageSendResult {
        fatalError("not tested")
    }

    func updateRead(convoId _: String, messageId _: String?, account _: AppAccount, appPassword _: String?) async throws {}

    func leaveConvo(convoId _: String, account _: AppAccount, appPassword _: String?) async throws {}
    func muteConvo(convoId _: String, account _: AppAccount, appPassword _: String?) async throws {}
    func unmuteConvo(convoId _: String, account _: AppAccount, appPassword _: String?) async throws {}

    func getLog(cursor _: String?, account _: AppAccount, appPassword _: String?) async throws -> (events: [ChatLogEvent], cursor: String?) {
        ([], nil)
    }
}
