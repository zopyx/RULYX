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

    func listConvos(account: AppAccount, appPassword: String?, status: String?, cursor: String?) async throws -> PagedConvos {
        PagedConvos(conversations: [], cursor: nil)
    }

    func getConvo(convoId: String, account: AppAccount, appPassword: String?) async throws -> ChatConversation {
        throw NSError(domain: "mock", code: -1)
    }

    func getConvoForMembers(members: [String], account: AppAccount, appPassword: String?) async throws -> ChatConversation {
        throw NSError(domain: "mock", code: -1)
    }

    func getMessages(convoId: String, cursor: String?, limit: Int, account: AppAccount, appPassword: String?) async throws -> PagedMessages {
        PagedMessages(messages: [], cursor: nil)
    }

    func sendMessage(convoId: String, text: String, account: AppAccount, appPassword: String?) async throws -> ChatMessageSendResult {
        fatalError("not tested")
    }

    func updateRead(convoId: String, messageId: String?, account: AppAccount, appPassword: String?) async throws {}

    func leaveConvo(convoId: String, account: AppAccount, appPassword: String?) async throws {}
    func muteConvo(convoId: String, account: AppAccount, appPassword: String?) async throws {}
    func unmuteConvo(convoId: String, account: AppAccount, appPassword: String?) async throws {}

    func getLog(cursor: String?, account: AppAccount, appPassword: String?) async throws -> (events: [ChatLogEvent], cursor: String?) {
        ([], nil)
    }
}
