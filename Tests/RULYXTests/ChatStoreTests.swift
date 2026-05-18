@testable import RULYX
import XCTest

@MainActor
final class ChatStoreTests: XCTestCase {
    private var store: ChatStore!
    private var service: MockChatService!
    private let account = AppAccount(handle: "test.bsky.social", did: "did:plc:test")

    override func setUp() {
        super.setUp()
        service = MockChatService()
        store = ChatStore(chatService: service)
        store.setAccount(account, appPassword: "password")
    }

    override func tearDown() {
        super.tearDown()
        store.stopPolling()
        store.setAccount(nil, appPassword: nil)
        service = nil
        store = nil
    }

    // MARK: - Account

    func testSetAccountNilClearsData() {
        store.setAccount(nil, appPassword: nil)
        XCTAssertNil(store.currentAccountDID)
        XCTAssertTrue(store.conversations.isEmpty)
        XCTAssertTrue(store.messages.isEmpty)
    }

    func testSetAccountSetsDID() {
        XCTAssertEqual(store.currentAccountDID, "did:plc:test")
    }

    // MARK: - Conversations

    func testLoadConvosPopulates() async {
        service.convosResult = .success(makePagedConvos(count: 2))
        await store.loadConvos()
        XCTAssertFalse(store.isLoadingConvos)
        XCTAssertEqual(store.conversations.count, 2)
        XCTAssertNil(store.error)
    }

    func testLoadConvosHandlesError() async {
        service.convosResult = .failure(BlueskyAPIError.server("Down"))
        await store.loadConvos()
        XCTAssertFalse(store.isLoadingConvos)
        XCTAssertNotNil(store.error)
    }

    func testLoadConvosNoAccount() async {
        store.setAccount(nil, appPassword: nil)
        await store.loadConvos()
        XCTAssertFalse(store.isLoadingConvos)
        XCTAssertTrue(store.conversations.isEmpty)
    }

    func testLoadMoreConvos() async {
        service.convosResult = .success(makePagedConvos(count: 2, cursor: "next"))
        await store.loadConvos()
        service.convosResult = .success(makePagedConvos(count: 1, cursor: nil))
        await store.loadMoreConvos()
        XCTAssertEqual(store.conversations.count, 3)
    }

    func testLoadMoreConvosNoCursorSkips() async {
        service.convosResult = .success(makePagedConvos(count: 1, cursor: nil))
        await store.loadConvos()
        await store.loadMoreConvos()
    }

    // MARK: - Messages

    func testLoadMessagesPopulates() async {
        service.messagesResult = .success(makePagedMessages(count: 2))
        await store.loadMessages(convoId: "c1")
        XCTAssertFalse(store.isLoadingMessages)
        XCTAssertEqual(store.messages["c1"]?.count, 2)
        XCTAssertNil(store.error)
    }

    func testLoadMessagesMarksRead() async {
        service.messagesResult = .success(makePagedMessages(count: 1))
        await store.loadMessages(convoId: "c1")
        XCTAssertTrue(service.didUpdateRead)
    }

    func testLoadMoreMessages() async {
        service.messagesResult = .success(makePagedMessages(count: 2, cursor: "next"))
        await store.loadMessages(convoId: "c1")
        let page2 = PagedMessages(
            messages: [
                ChatMessageKind.message(ChatMessage(
                    id: "m10", rev: "r10", text: "Older", senderDID: "did:plc:test",
                    sentAt: Date(), reactions: []
                )),
            ],
            cursor: nil
        )
        service.messagesResult = .success(page2)
        await store.loadMoreMessages(convoId: "c1")
        XCTAssertEqual(store.messages["c1"]?.count, 3)
    }

    func testSendMessageAppends() async {
        service.sendResult = .success(ChatMessageSendResult(id: "m3", rev: "r3", text: "Hello!", senderDID: "did:plc:test", sentAt: Date()))
        await store.sendMessage(convoId: "c1", text: "Hello!")
        XCTAssertFalse(store.isSendingMessage)
        XCTAssertEqual(store.messages["c1"]?.count, 1)
    }

    // MARK: - Actions

    func testMuteUpdatesLocal() async {
        let targetConvo = makeConvo(id: "c1", muted: false)
        service.convosResult = .success(PagedConvos(conversations: [targetConvo, makeConvo(id: "c2")], cursor: nil))
        await store.loadConvos()
        service.muteResult = .success(())
        await store.mute(convoId: "c1")
        XCTAssertTrue(store.conversations[0].muted)
    }

    func testUnmuteUpdatesLocal() async {
        let targetConvo = makeConvo(id: "c1", muted: false)
        service.convosResult = .success(PagedConvos(conversations: [targetConvo], cursor: nil))
        await store.loadConvos()
        let mutedConvo = ChatConversation(id: "c1", rev: "rev-c1", members: [], lastMessage: nil, muted: false, status: .accepted, unreadCount: 0, kind: .direct, groupInfo: nil)
        service.getConvoResult = .success(mutedConvo)
        let _ = await store.getOrCreateConvo(memberDID: "did:plc:m")
        service.unmuteResult = .success(())
        await store.unmute(convoId: "c1")
        let result = store.conversations.first { $0.id == "c1" }
        XCTAssertEqual(result?.muted, false)
    }

    func testLeaveRemovesConversation() async {
        service.convosResult = .success(PagedConvos(conversations: [makeConvo(id: "c1"), makeConvo(id: "c2")], cursor: nil))
        await store.loadConvos()
        service.leaveResult = .success(())
        await store.leave(convoId: "c1")
        XCTAssertEqual(store.conversations.count, 1)
        XCTAssertEqual(store.conversations[0].id, "c2")
    }

    func testMarkReadResetsUnreadCount() async {
        let convos = [
            ChatConversation(id: "c1", rev: "rev-c1", members: [], lastMessage: nil, muted: false, status: .accepted, unreadCount: 5, kind: .direct, groupInfo: nil),
        ]
        service.convosResult = .success(PagedConvos(conversations: convos, cursor: nil))
        await store.loadConvos()
        await store.markRead(convoId: "c1", messageId: "m1")
        XCTAssertEqual(store.conversations[0].unreadCount, 0)
    }

    func testGetOrCreateConvoUpserts() async {
        let convo = makeConvo(id: "c1")
        service.getConvoResult = .success(convo)
        let result = await store.getOrCreateConvo(memberDID: "did:plc:member")
        XCTAssertNotNil(result)
        XCTAssertEqual(store.conversations.count, 1)
    }

    // MARK: - Helpers

    private func makePagedConvos(count: Int, cursor: String? = nil) -> PagedConvos {
        let convos = (0 ..< count).map { i in
            makeConvo(id: "c\(i)")
        }
        return PagedConvos(conversations: convos, cursor: cursor)
    }

    private func makeConvo(id: String, muted: Bool = false, unreadCount: Int = 0) -> ChatConversation {
        ChatConversation(
            id: id,
            rev: "rev-\(id)",
            members: [],
            lastMessage: nil,
            muted: muted,
            status: .accepted,
            unreadCount: unreadCount,
            kind: .direct,
            groupInfo: nil
        )
    }

    private func makePagedMessages(count: Int, cursor: String? = nil) -> PagedMessages {
        let msgs = (0 ..< count).map { i in
            ChatMessageKind.message(ChatMessage(
                id: "m\(i)",
                rev: "r\(i)",
                text: "Message \(i)",
                senderDID: "did:plc:test",
                sentAt: Date(),
                reactions: []
            ))
        }
        return PagedMessages(messages: msgs, cursor: cursor)
    }
}

@MainActor
private final class MockChatService: ChatServicing {
    var convosResult: Result<PagedConvos, Error>?
    var messagesResult: Result<PagedMessages, Error>?
    var sendResult: Result<ChatMessageSendResult, Error>?
    var getConvoResult: Result<ChatConversation, Error>?
    var muteResult: Result<Void, Error>?
    var unmuteResult: Result<Void, Error>?
    var leaveResult: Result<Void, Error>?
    var logResult: Result<([ChatLogEvent], String?), Error>?
    private(set) var didUpdateRead = false

    func listConvos(account _: AppAccount, appPassword _: String?, status _: String?, cursor _: String?) async throws -> PagedConvos {
        guard let result = convosResult else { throw BlueskyAPIError.server("No mock") }
        return try result.get()
    }

    func getConvo(convoId _: String, account _: AppAccount, appPassword _: String?) async throws -> ChatConversation {
        guard let result = getConvoResult else { throw BlueskyAPIError.server("No mock") }
        return try result.get()
    }

    func getConvoForMembers(members _: [String], account _: AppAccount, appPassword _: String?) async throws -> ChatConversation {
        guard let result = getConvoResult else { throw BlueskyAPIError.server("No mock") }
        return try result.get()
    }

    func getMessages(convoId _: String, cursor _: String?, limit _: Int, account _: AppAccount, appPassword _: String?) async throws -> PagedMessages {
        guard let result = messagesResult else { throw BlueskyAPIError.server("No mock") }
        return try result.get()
    }

    func sendMessage(convoId _: String, text _: String, account _: AppAccount, appPassword _: String?) async throws -> ChatMessageSendResult {
        guard let result = sendResult else { throw BlueskyAPIError.server("No mock") }
        return try result.get()
    }

    func updateRead(convoId _: String, messageId _: String?, account _: AppAccount, appPassword _: String?) async throws {
        didUpdateRead = true
        if let result = muteResult { try result.get() }
    }

    func leaveConvo(convoId _: String, account _: AppAccount, appPassword _: String?) async throws {
        if let result = leaveResult { try result.get() }
    }

    func muteConvo(convoId _: String, account _: AppAccount, appPassword _: String?) async throws {
        if let result = muteResult { try result.get() }
    }

    func unmuteConvo(convoId _: String, account _: AppAccount, appPassword _: String?) async throws {
        if let result = unmuteResult { try result.get() }
    }

    func getLog(cursor _: String?, account _: AppAccount, appPassword _: String?) async throws -> (events: [ChatLogEvent], cursor: String?) {
        guard let result = logResult else { throw BlueskyAPIError.server("No mock") }
        return try result.get()
    }
}
