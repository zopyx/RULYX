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
        // setVisibleConversation is a no-op when no account is set
        // but should not crash or produce errors.
        store.setVisibleConversation("convo-1")
        store.setVisibleConversation(nil)
        XCTAssertNil(store.error)
    }
}

// MARK: - Mock

@MainActor
private final class MockChatService: ChatServicing {
    func listConvos() async throws -> [ChatConversation] { [] }
    func getConvo(id: String) async throws -> ChatConversation? { nil }
    func getConvoForMembers(dids: [String]) async throws -> ChatConversation? { nil }
    func getMessages(convoId: String, cursor: String?) async throws -> (messages: [ChatMessageKind], cursor: String?) { ([], nil) }
    func sendMessage(convoId: String, text: String) async throws -> ChatMessageKind { fatalError() }
    func updateRead(convoId: String, messageId: String?) async throws {}
    func leaveConvo(convoId: String) async throws {}
    func muteConvo(convoId: String) async throws {}
    func unmuteConvo(convoId: String) async throws {}
    func getLog(cursor: String?) async throws -> (events: [ChatLogEvent], cursor: String?) { ([], nil) }
}
