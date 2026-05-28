import Combine
import Foundation
import UIKit
import UserNotifications

/// Manages Bluesky direct messaging conversations: loading, sending, polling,
/// and push-driven incremental sync.
///
/// The store uses a polling loop (`startPolling` / `stopPolling`) to listen for
/// new events via the chat log endpoint. It also supports manual sync via `syncLog()`.
@MainActor
final class ChatStore: ObservableObject {
    /// All conversations, sorted by `lastMessageAt` descending.
    @Published private(set) var conversations: [ChatConversation] = []
    /// Messages keyed by conversation ID. Newest messages are at the end of each array.
    @Published private(set) var messages: [String: [ChatMessageKind]] = [:]
    /// `true` while the initial conversation list is loading.
    @Published private(set) var isLoadingConvos = false
    /// `true` while messages for a conversation are loading.
    @Published private(set) var isLoadingMessages = false
    /// `true` while older messages are being paginated.
    @Published private(set) var isLoadingMoreMessages = false
    /// `true` while a message is being sent.
    @Published private(set) var isSendingMessage = false
    /// Whether more paginated messages are available, keyed by conversation ID.
    @Published private(set) var hasMoreMessages: [String: Bool] = [:]
    /// The last conversation-level error that occurred.
    @Published var error: Error?
    /// The last message-level error that occurred.
    @Published var messageError: Error?

    /// The underlying chat service (network layer).
    private let chatService: ChatServicing
    /// Cursor for paginating the conversation list.
    private var convosCursor: String?
    /// Cursor for the chat event log (polling).
    private var logCursor: String?
    /// Cursors for paginating messages, keyed by conversation ID.
    private var messageCursors: [String: String] = [:]
    /// The polling task for real-time event delivery.
    private var pollingTask: Task<Void, Never>?
    /// The currently active account.
    private var activeAccount: AppAccount?
    /// The app password for the active account.
    private var activeAppPassword: String?
    /// The ID of the conversation currently visible in the UI (for incremental updates).
    private var visibleConversationID: String?
    /// The DID of the currently active account (used to compute unread increments).
    private(set) var currentAccountDID: String?

    // MARK: - Init

    init(chatService: ChatServicing) {
        self.chatService = chatService
    }

    // MARK: - Account

    /// Sets the active account and password. Clears all state and stops polling when account is `nil`.
    func setAccount(_ account: AppAccount?, appPassword: String?) {
        activeAccount = account
        activeAppPassword = appPassword
        currentAccountDID = account?.did
        if account == nil {
            stopPolling()
            conversations = []
            messages = [:]
        }
    }

    // MARK: - Conversations

    /// Loads the initial page of conversations.
    func loadConvos() async {
        guard let account = activeAccount else { return }
        isLoadingConvos = true
        error = nil
        do {
            let result = try await chatService.listConvos(account: account, appPassword: activeAppPassword, status: nil, cursor: nil)
            conversations = result.conversations.sorted { $0.lastMessageAt > $1.lastMessageAt }
            convosCursor = result.cursor
            isLoadingConvos = false
        } catch {
            guard !AppError.isCancellation(error) else { return }
            self.error = error
            isLoadingConvos = false
        }
    }

    /// Loads the next page of conversations using the stored cursor.
    func loadMoreConvos() async {
        guard let account = activeAccount, let cursor = convosCursor else { return }
        do {
            let result = try await chatService.listConvos(account: account, appPassword: activeAppPassword, status: nil, cursor: cursor)
            conversations = (conversations + result.conversations).sorted { $0.lastMessageAt > $1.lastMessageAt }
            convosCursor = result.cursor
        } catch {
            self.error = error
        }
    }

    // MARK: - Messages

    /// Loads messages for a conversation. Marks the conversation as read after loading.
    func loadMessages(convoId: String) async {
        guard let account = activeAccount else { return }
        isLoadingMessages = true
        messageError = nil
        do {
            let result = try await chatService.getMessages(convoId: convoId, cursor: nil, limit: 50, account: account, appPassword: activeAppPassword)
            messages[convoId] = result.messages.reversed()
            messageCursors[convoId] = result.cursor
            hasMoreMessages[convoId] = result.cursor != nil
            isLoadingMessages = false
            // Mark the conversation as read using the last message ID.
            if let lastMessageKind = result.messages.last {
                let lastId: String = switch lastMessageKind {
                case let .message(msg): msg.id
                case let .deleted(d): d.id
                case let .system(s): s.id
                }
                try? await chatService.updateRead(convoId: convoId, messageId: lastId, account: account, appPassword: activeAppPassword)
            }
        } catch {
            AppLogger.persistence.error("Failed to load messages for \(convoId, privacy: .public): \(error.localizedDescription, privacy: .public)")
            messageError = error
            isLoadingMessages = false
        }
    }

    /// Loads older (paginated) messages for a conversation. Deduplicates against existing messages.
    func loadMoreMessages(convoId: String) async {
        guard let account = activeAccount, let cursor = messageCursors[convoId], cursor != "" else { return }
        guard hasMoreMessages[convoId] != false else { return }
        isLoadingMoreMessages = true
        do {
            let result = try await chatService.getMessages(convoId: convoId, cursor: cursor, limit: 50, account: account, appPassword: activeAppPassword)
            messageCursors[convoId] = result.cursor
            hasMoreMessages[convoId] = result.cursor != nil
            let existing = messages[convoId] ?? []
            let existingSet = Set(existing.map { idForMessage($0) })
            let newMessages = result.messages.reversed().filter { !existingSet.contains(idForMessage($0)) }
            messages[convoId] = newMessages + existing
            isLoadingMoreMessages = false
        } catch {
            messageError = error
            isLoadingMoreMessages = false
        }
    }

    // MARK: - Send

    /// Sends a text message to a conversation. Appends the new message to the local cache on success.
    func sendMessage(convoId: String, text: String) async {
        guard let account = activeAccount else { return }
        isSendingMessage = true
        do {
            let result = try await chatService.sendMessage(convoId: convoId, text: text, account: account, appPassword: activeAppPassword)
            let newMsg = ChatMessageKind.message(ChatMessage(
                id: result.id,
                rev: result.rev,
                text: result.text,
                senderDID: result.senderDID,
                sentAt: result.sentAt,
                reactions: []
            ))
            var current = messages[convoId] ?? []
            current.append(newMsg)
            messages[convoId] = current
            isSendingMessage = false
        } catch {
            self.error = error
            isSendingMessage = false
        }
    }

    // MARK: - Actions

    /// Marks a conversation as read. Updates the unread count to 0 locally.
    func markRead(convoId: String, messageId: String?) async {
        guard let account = activeAccount else { return }
        try? await chatService.updateRead(convoId: convoId, messageId: messageId, account: account, appPassword: activeAppPassword)
        if let idx = conversations.firstIndex(where: { $0.id == convoId }) {
            var updated = conversations[idx]
            updated = ChatConversation(
                id: updated.id,
                rev: updated.rev,
                members: updated.members,
                lastMessage: updated.lastMessage,
                muted: updated.muted,
                status: updated.status,
                unreadCount: 0,
                kind: updated.kind,
                groupInfo: updated.groupInfo
            )
            conversations[idx] = updated
        }
    }

    /// Mutes a conversation locally and on the server.
    func mute(convoId: String) async {
        guard let account = activeAccount else { return }
        try? await chatService.muteConvo(convoId: convoId, account: account, appPassword: activeAppPassword)
        if let idx = conversations.firstIndex(where: { $0.id == convoId }) {
            var updated = conversations[idx]
            updated = ChatConversation(
                id: updated.id,
                rev: updated.rev,
                members: updated.members,
                lastMessage: updated.lastMessage,
                muted: true,
                status: updated.status,
                unreadCount: updated.unreadCount,
                kind: updated.kind,
                groupInfo: updated.groupInfo
            )
            conversations[idx] = updated
        }
    }

    /// Unmutes a conversation locally and on the server.
    func unmute(convoId: String) async {
        guard let account = activeAccount else { return }
        try? await chatService.unmuteConvo(convoId: convoId, account: account, appPassword: activeAppPassword)
        if let idx = conversations.firstIndex(where: { $0.id == convoId }) {
            var updated = conversations[idx]
            updated = ChatConversation(
                id: updated.id,
                rev: updated.rev,
                members: updated.members,
                lastMessage: updated.lastMessage,
                muted: false,
                status: updated.status,
                unreadCount: updated.unreadCount,
                kind: updated.kind,
                groupInfo: updated.groupInfo
            )
            conversations[idx] = updated
        }
    }

    /// Leaves a conversation. Removes it from the local cache.
    func leave(convoId: String) async {
        guard let account = activeAccount else { return }
        try? await chatService.leaveConvo(convoId: convoId, account: account, appPassword: activeAppPassword)
        conversations.removeAll { $0.id == convoId }
        messages.removeValue(forKey: convoId)
    }

    /// Gets or creates a 1:1 conversation with a member by their DID.
    func getOrCreateConvo(memberDID: String) async -> ChatConversation? {
        guard let account = activeAccount else { return nil }
        do {
            let conversation = try await chatService.getConvoForMembers(members: [memberDID], account: account, appPassword: activeAppPassword)
            upsertConversation(conversation)
            return conversation
        } catch {
            self.error = error
            return nil
        }
    }

    /// Refreshes messages for a conversation (replaces the full message list).
    private func refreshMessages(convoId: String) async {
        guard let account = activeAccount else { return }
        do {
            let result = try await chatService.getMessages(convoId: convoId, cursor: nil, limit: 50, account: account, appPassword: activeAppPassword)
            messages[convoId] = result.messages.reversed()
        } catch {
            if let urlError = error as? URLError, urlError.code == .cancelled { return }
        }
    }

    /// Sets the currently visible conversation ID (used for incremental unread tracking).
    func setVisibleConversation(_ convoId: String?) {
        visibleConversationID = convoId
    }

    // MARK: - Push-Driven Incremental Sync

    /// Performs a one-shot sync of the chat event log. Updates conversations and messages.
    /// Called from push notification handling or app foreground.
    func syncLog() async {
        guard let account = activeAccount else { return }
        do {
            let (events, newCursor) = try await chatService.getLog(cursor: logCursor, account: account, appPassword: activeAppPassword)
            logCursor = newCursor
            for event in events {
                switch event.kind {
                case let .createMessage(convoId, message):
                    applyIncomingMessage(message, to: convoId)
                default:
                    break
                }
            }
            // Brief delay then reload conversation list to pick up any reordering.
            try await Task.sleep(nanoseconds: 300_000_000)
            let result = try await chatService.listConvos(account: account, appPassword: activeAppPassword, status: nil, cursor: nil)
            conversations = result.conversations.sorted { $0.lastMessageAt > $1.lastMessageAt }
            convosCursor = result.cursor
            updateAppBadge()

            // Refresh the visible conversation's messages if we're viewing one.
            if let visibleID = visibleConversationID {
                await refreshMessages(convoId: visibleID)
            }
        } catch {
            if let urlError = error as? URLError, urlError.code == .cancelled { return }
            AppLogger.persistence.error("Chat syncLog failed: \(error.localizedDescription, privacy: .public)")
            self.error = error
        }
    }

    /// Updates the app icon badge to the total unread count across all conversations.
    private func updateAppBadge() {
        let totalUnread = conversations.reduce(0) { $0 + $1.unreadCount }
        Task { try? await UNUserNotificationCenter.current().setBadgeCount(totalUnread) }
    }

    // MARK: - Polling

    /// Starts a polling loop that checks the chat event log at the given interval.
    func startPolling(interval: TimeInterval = 5) {
        stopPolling()
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.pollLog()
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }
        }
    }

    /// Stops the polling loop.
    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    // MARK: - Private Helpers

    /// Extracts the stable message ID from a `ChatMessageKind`.
    private func idForMessage(_ kind: ChatMessageKind) -> String {
        switch kind {
        case let .message(m): m.id
        case let .deleted(d): d.id
        case let .system(s): s.id
        }
    }

    /// Polls the chat event log and applies incremental updates.
    /// Rebuilds the conversation list if structural changes are detected.
    private func pollLog() async {
        guard let account = activeAccount else { return }
        do {
            let (events, newCursor) = try await chatService.getLog(cursor: logCursor, account: account, appPassword: activeAppPassword)
            logCursor = newCursor

            var needsReload = false
            for event in events {
                switch event.kind {
                case let .createMessage(convoId, message):
                    applyIncomingMessage(message, to: convoId)
                    if !conversations.contains(where: { $0.id == convoId }) {
                        needsReload = true
                    }
                case .beginConvo, .acceptConvo, .leaveConvo, .muteConvo, .unmuteConvo:
                    needsReload = true
                case let .addReaction(convoId, _, _), let .removeReaction(convoId, _, _):
                    if messages[convoId] != nil {
                        needsReload = true
                    }
                case let .deleteMessage(convoId, _):
                    if messages[convoId] != nil {
                        needsReload = true
                    }
                case .readConvo, .addMember, .removeMember:
                    needsReload = true
                }
            }

            // Reload the full conversation list if structural changes occurred.
            if needsReload {
                try await Task.sleep(nanoseconds: 500_000_000)
                let result = try await chatService.listConvos(account: account, appPassword: activeAppPassword, status: nil, cursor: nil)
                conversations = result.conversations.sorted { $0.lastMessageAt > $1.lastMessageAt }
                convosCursor = result.cursor
            }

            // Refresh the visible conversation's messages if we're viewing one.
            if let visibleID = visibleConversationID {
                try? await Task.sleep(nanoseconds: 100_000_000)
                await refreshMessages(convoId: visibleID)
            }
        } catch {
            if let urlError = error as? URLError, urlError.code == .cancelled { return }
            AppLogger.persistence.error("Chat pollLog failed: \(error.localizedDescription, privacy: .public)")
            self.error = error
        }
    }

    /// Applies an incoming message to the local cache and updates the conversation's last message.
    /// Increments the unread count if the message is from someone else and the conversation is not visible.
    /// Posts a local notification when a new message arrives from another user.
    private func applyIncomingMessage(_ message: ChatMessage, to convoId: String) {
        let incomingKind = ChatMessageKind.message(message)

        // Append to message list if not a duplicate.
        var currentMessages = messages[convoId] ?? []
        if !currentMessages.contains(where: { idForMessage($0) == message.id }) {
            currentMessages.append(incomingKind)
            messages[convoId] = currentMessages
        }

        // Update the conversation's last message and unread count.
        guard let index = conversations.firstIndex(where: { $0.id == convoId }) else { return }

        let existing = conversations[index]
        let shouldIncrementUnread = visibleConversationID != convoId && message.senderDID != currentAccountDID
        let updated = ChatConversation(
            id: existing.id,
            rev: message.rev,
            members: existing.members,
            lastMessage: incomingKind,
            muted: existing.muted,
            status: existing.status,
            unreadCount: shouldIncrementUnread ? existing.unreadCount + 1 : 0,
            kind: existing.kind,
            groupInfo: existing.groupInfo
        )
        conversations[index] = updated
        conversations.sort { $0.lastMessageAt > $1.lastMessageAt }

        if shouldIncrementUnread, !existing.muted {
            postLocalNotification(for: message, in: existing)
        }
    }

    /// Posts a local notification for an incoming chat message from another user.
    private func postLocalNotification(for message: ChatMessage, in conversation: ChatConversation) {
        let senderName = conversation.members
            .first { $0.did == message.senderDID }
            .flatMap { $0.displayName ?? $0.handle } ?? message.senderDID

        let content = UNMutableNotificationContent()
        content.title = senderName
        content.body = message.text
        content.sound = .default
        content.threadIdentifier = conversation.id

        let request = UNNotificationRequest(
            identifier: "chat_\(message.id)",
            content: content,
            trigger: nil
        )

        Task {
            try? await UNUserNotificationCenter.current().add(request)
        }
    }

    /// Inserts or replaces a conversation in the local list, then re-sorts by `lastMessageAt`.
    private func upsertConversation(_ conversation: ChatConversation) {
        if let index = conversations.firstIndex(where: { $0.id == conversation.id }) {
            conversations[index] = conversation
        } else {
            conversations.append(conversation)
        }
        conversations.sort { $0.lastMessageAt > $1.lastMessageAt }
    }
}
