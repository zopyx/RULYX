import Combine
import Foundation
import UIKit
import UserNotifications

/// Manages Bluesky direct messaging conversations: loading, sending, event-driven
/// log processing, and push-driven incremental sync.
///
/// The store uses an event loop that responds to push notifications and
/// app-lifecycle signals. Polling is adaptive: 5 seconds while a chat view is
/// visible and 30 seconds otherwise. External actors trigger an immediate sync
/// via `signalSync()`.
@MainActor
final class ChatStore: ObservableObject {
    private struct ChatAccountContext: Equatable {
        let generation: UUID
        let accountID: AppAccount.ID
        let did: String?
    }

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
    /// Short user-visible status shown while switching chat accounts.
    @Published var statusMessage: String?

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
    /// Guards against rapid redundant syncs from push notifications.
    private var lastSyncDate: Date = .distantPast
    /// The current chat loading context. Any response from an older context is discarded.
    private var activeContext: ChatAccountContext?
    /// The stored account ID for the active chat context.
    private var activeAccountID: AppAccount.ID?
    /// The currently active account.
    private var activeAccount: AppAccount?
    /// The app password for the active account.
    private var activeAppPassword: String?
    /// The ID of the conversation currently visible in the UI (for incremental updates).
    private var visibleConversationID: String?
    /// The DID of the currently active account (used to compute unread increments).
    private(set) var currentAccountDID: String?
    /// The task responsible for dismissing transient status text.
    private var statusDismissTask: Task<Void, Never>?
    /// Tokens representing currently visible chat UI views (list or detail).
    /// When non-empty, the event-log poll runs at the fast interval.
    private var chatVisibleTokens: Set<String> = []
    /// Current polling interval. Defaults to 30s and switches to 5s while chat is visible.
    private var currentPollingInterval: UInt64 = 30_000_000_000

    // MARK: - Init

    init(chatService: ChatServicing) {
        self.chatService = chatService
    }

    // MARK: - Account

    /// Sets the active account and password. When the stored account changes, clears all
    /// chat state so the UI immediately shows loading / empty before fresh data arrives.
    func setAccount(_ account: AppAccount?, appPassword: String?) {
        let accountDidChange = activeAccountID != account?.id || currentAccountDID != account?.did

        activeAccountID = account?.id
        activeAccount = account
        activeAppPassword = appPassword
        currentAccountDID = account?.did

        if accountDidChange {
            activeContext = account.map { ChatAccountContext(generation: UUID(), accountID: $0.id, did: $0.did) }
            stopPolling()
            resetConversationState(isLoading: account != nil)
        } else if activeContext == nil, let account {
            activeContext = ChatAccountContext(generation: UUID(), accountID: account.id, did: account.did)
        }
    }

    /// Switches chat to `account` by discarding every cached conversation/message and
    /// rebuilding the visible conversation list from the chat service response.
    func rebuildConversations(for account: AppAccount?, appPassword: String?, clearCaches: Bool = false, showPrompts: Bool = false) async {
        AppLogger.persistence.info("Chat rebuild started for \(account?.handle ?? "none"); clearCaches=\(clearCaches, privacy: .private); showPrompts=\(showPrompts, privacy: .private)")
        activeAccountID = account?.id
        activeAccount = account
        activeAppPassword = appPassword
        currentAccountDID = account?.did
        let context = account.map { ChatAccountContext(generation: UUID(), accountID: $0.id, did: $0.did) }
        activeContext = context
        stopPolling()

        if clearCaches {
            chatService.clearCaches()
        }

        resetConversationState(isLoading: account != nil)

        if showPrompts, clearCaches {
            setStatusMessage("Caches Cleared", autoDismiss: false)
        }

        guard let account else {
            if !showPrompts {
                statusMessage = nil
            }
            return
        }

        if showPrompts {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard context.map(isCurrentContext) ?? false else { return }
            setStatusMessage("Reloading for \(account.handle)", autoDismiss: false)
        }

        await loadConvos()

        if showPrompts, context.map(isCurrentContext) ?? false {
            setStatusMessage("Reloading for \(account.handle)", autoDismiss: true)
        }
    }

    // MARK: - Conversations

    /// Loads the first page of conversations.
    func loadConvos() async {
        guard let account = activeAccount, let context = activeContext else { return }
        isLoadingConvos = true
        error = nil
        do {
            let result = try await chatService.listConvos(account: account, appPassword: activeAppPassword, status: nil, cursor: nil)
            guard isCurrentContext(context) else {
                return
            }
            conversations = result.conversations.sorted { $0.lastMessageAt > $1.lastMessageAt }
            convosCursor = result.cursor
            // Patch any conversations where the local message cache has a newer
            // message than the server's lastMessage (e.g., just-sent messages
            // that haven't propagated to the list endpoint yet).
            patchStaleLastMessages()
            isLoadingConvos = false
        } catch {
            guard isCurrentContext(context) else { return }
            guard !AppError.isCancellation(error) else {
                isLoadingConvos = false
                return
            }
            self.error = error
            isLoadingConvos = false
        }
    }

    /// Loads the next page of conversations using the stored cursor.
    func loadMoreConvos() async {
        guard let account = activeAccount, let context = activeContext, let cursor = convosCursor else { return }
        do {
            let result = try await chatService.listConvos(account: account, appPassword: activeAppPassword, status: nil, cursor: cursor)
            guard isCurrentContext(context) else { return }
            conversations = (conversations + result.conversations).sorted { $0.lastMessageAt > $1.lastMessageAt }
            convosCursor = result.cursor
        } catch {
            guard isCurrentContext(context) else { return }
            self.error = error
        }
    }

    // MARK: - Messages

    /// Loads messages for a conversation. Marks the conversation as read after loading.
    func loadMessages(convoId: String) async {
        guard let account = activeAccount, let context = activeContext else { return }
        isLoadingMessages = true
        messageError = nil
        do {
            let result = try await chatService.getMessages(convoId: convoId, cursor: nil, limit: 50, account: account, appPassword: activeAppPassword)
            guard isCurrentContext(context) else { return }
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
            guard isCurrentContext(context) else { return }
            AppLogger.persistence.error("Failed to load messages for \(convoId): \(error.localizedDescription, privacy: .private)")
            messageError = error
            isLoadingMessages = false
        }
    }

    /// Loads older (paginated) messages for a conversation. Deduplicates against existing messages.
    func loadMoreMessages(convoId: String) async {
        guard let account = activeAccount, let context = activeContext, let cursor = messageCursors[convoId], cursor != "" else { return }
        guard hasMoreMessages[convoId] != false else { return }
        isLoadingMoreMessages = true
        do {
            let result = try await chatService.getMessages(convoId: convoId, cursor: cursor, limit: 50, account: account, appPassword: activeAppPassword)
            guard isCurrentContext(context) else { return }
            messageCursors[convoId] = result.cursor
            hasMoreMessages[convoId] = result.cursor != nil
            let existing = messages[convoId] ?? []
            let existingSet = Set(existing.map { idForMessage($0) })
            let newMessages = result.messages.reversed().filter { !existingSet.contains(idForMessage($0)) }
            messages[convoId] = newMessages + existing
            isLoadingMoreMessages = false
        } catch {
            guard isCurrentContext(context) else { return }
            messageError = error
            isLoadingMoreMessages = false
        }
    }

    // MARK: - Send

    /// Sends a text message to a conversation with optimistic local insertion.
    /// The message appears immediately as pending; it's replaced with the server response on success.
    func sendMessage(convoId: String, text: String) async {
        guard let account = activeAccount, let context = activeContext, let senderDID = currentAccountDID else { return }
        let pendingId = "pending-\(UUID().uuidString)"
        let pendingMsg = ChatMessageKind.message(ChatMessage(
            id: pendingId,
            rev: "",
            text: text,
            senderDID: senderDID,
            sentAt: .now,
            reactions: []
        ))

        var current = messages[convoId] ?? []
        current.append(pendingMsg)
        messages[convoId] = current

        // Optimistically update the conversation's lastMessage so the list
        // preview shows the outgoing text immediately.
        if let idx = conversations.firstIndex(where: { $0.id == convoId }) {
            let existing = conversations[idx]
            conversations[idx] = ChatConversation(
                id: existing.id,
                rev: existing.rev,
                members: existing.members,
                lastMessage: pendingMsg,
                muted: existing.muted,
                status: existing.status,
                unreadCount: existing.unreadCount,
                kind: existing.kind,
                groupInfo: existing.groupInfo
            )
            conversations.sort { $0.lastMessageAt > $1.lastMessageAt }
        }

        isSendingMessage = true
        do {
            let result = try await chatService.sendMessage(convoId: convoId, text: text, account: account, appPassword: activeAppPassword)
            guard isCurrentContext(context) else { return }
            let confirmedMsg = ChatMessageKind.message(ChatMessage(
                id: result.id,
                rev: result.rev,
                text: result.text,
                senderDID: result.senderDID,
                sentAt: result.sentAt,
                reactions: []
            ))

            var updated = messages[convoId] ?? []
            if let pendingIndex = updated.firstIndex(where: { idForMessage($0) == pendingId }) {
                updated[pendingIndex] = confirmedMsg
            } else if !updated.contains(where: { idForMessage($0) == result.id }) {
                updated.append(confirmedMsg)
            }
            messages[convoId] = updated

            // Update the conversation's lastMessage and bump it to the top.
            if let idx = conversations.firstIndex(where: { $0.id == convoId }) {
                let existing = conversations[idx]
                conversations[idx] = ChatConversation(
                    id: existing.id,
                    rev: result.rev,
                    members: existing.members,
                    lastMessage: confirmedMsg,
                    muted: existing.muted,
                    status: existing.status,
                    unreadCount: existing.unreadCount,
                    kind: existing.kind,
                    groupInfo: existing.groupInfo
                )
                conversations.sort { $0.lastMessageAt > $1.lastMessageAt }
            }

            isSendingMessage = false
        } catch {
            guard isCurrentContext(context) else { return }
            var updated = messages[convoId] ?? []
            if let pendingIndex = updated.firstIndex(where: { idForMessage($0) == pendingId }) {
                if case var .message(m) = updated[pendingIndex] {
                    m = ChatMessage(id: pendingId, rev: "failed", text: m.text, senderDID: m.senderDID, sentAt: m.sentAt, reactions: m.reactions)
                    updated[pendingIndex] = .message(m)
                }
            }
            messages[convoId] = updated
            self.error = error
            isSendingMessage = false
        }
    }

    // MARK: - Actions

    /// Marks a conversation as read. Updates the unread count to 0 locally.
    func markRead(convoId: String, messageId: String?) async {
        guard let account = activeAccount, let context = activeContext else { return }
        try? await chatService.updateRead(convoId: convoId, messageId: messageId, account: account, appPassword: activeAppPassword)
        guard isCurrentContext(context) else { return }
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
        guard let account = activeAccount, let context = activeContext else { return }
        try? await chatService.muteConvo(convoId: convoId, account: account, appPassword: activeAppPassword)
        guard isCurrentContext(context) else { return }
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
        guard let account = activeAccount, let context = activeContext else { return }
        try? await chatService.unmuteConvo(convoId: convoId, account: account, appPassword: activeAppPassword)
        guard isCurrentContext(context) else { return }
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
        guard let account = activeAccount, let context = activeContext else { return }
        try? await chatService.leaveConvo(convoId: convoId, account: account, appPassword: activeAppPassword)
        guard isCurrentContext(context) else { return }
        conversations.removeAll { $0.id == convoId }
        messages.removeValue(forKey: convoId)
    }

    /// Removes a single message from the local cache by its ID. Used for retry of failed messages.
    func removeMessage(_ messageId: String, from convoId: String) {
        var current = messages[convoId] ?? []
        current.removeAll { idForMessage($0) == messageId }
        messages[convoId] = current
    }

    /// Retries sending a previously failed message.
    func resendFailedMessage(convoId: String, messageId: String, text: String) async {
        removeMessage(messageId, from: convoId)
        await sendMessage(convoId: convoId, text: text)
    }

    /// Gets or creates a 1:1 conversation with a member by their DID.
    func getOrCreateConvo(memberDID: String) async -> ChatConversation? {
        guard let account = activeAccount, let context = activeContext else { return nil }
        do {
            let conversation = try await chatService.getConvoForMembers(members: [memberDID], account: account, appPassword: activeAppPassword)
            guard isCurrentContext(context) else { return nil }
            upsertConversation(conversation)
            return conversation
        } catch {
            guard isCurrentContext(context) else { return nil }
            self.error = error
            return nil
        }
    }

    /// Refreshes messages for a conversation (replaces the full message list).
    private func refreshMessages(convoId: String) async {
        guard let account = activeAccount, let context = activeContext else { return }
        do {
            let result = try await chatService.getMessages(convoId: convoId, cursor: nil, limit: 50, account: account, appPassword: activeAppPassword)
            guard isCurrentContext(context) else { return }
            messages[convoId] = result.messages.reversed()
        } catch {
            if let urlError = error as? URLError, urlError.code == .cancelled {
                return
            }
        }
    }

    /// Sets the currently visible conversation ID (used for incremental unread tracking).
    func setVisibleConversation(_ convoId: String?) {
        visibleConversationID = convoId
    }

    /// Triggers an immediate log sync. Called by `PushNotificationCoordinator`
    /// when a push notification arrives, or by lifecycle handlers when the app
    /// becomes active.
    ///
    /// Rapid calls are debounced: if less than one second has elapsed since the
    /// last completed sync, the call is skipped.
    func signalSync() {
        let now = Date()
        guard now.timeIntervalSince(lastSyncDate) >= 1.0 else { return }
        lastSyncDate = now
        Task { await processLog() }
    }

    // MARK: - Event-Driven Log Processing

    /// Fetches the latest event-log entries from the server and applies them
    /// as fine-grained local mutations. Falls back to a full conversation-list
    /// reload only when structural changes (convo added/removed) are detected.
    private func processLog() async {
        guard let account = activeAccount, let context = activeContext else { return }
        do {
            let (events, newCursor) = try await chatService.getLog(cursor: logCursor, account: account, appPassword: activeAppPassword)
            guard isCurrentContext(context) else { return }
            logCursor = newCursor

            let actions = parseEvents(events)
            try await applyActions(actions, context: context)

            updateAppBadge()
        } catch {
            guard isCurrentContext(context) else { return }
            if let urlError = error as? URLError, urlError.code == .cancelled {
                return
            }
            AppLogger.persistence.error("Chat processLog failed: \(error.localizedDescription, privacy: .private)")
            self.error = error
        }
    }

    /// Translates raw `ChatLogEvent` values into a list of `ChatLocalAction`
    /// mutations. Reactions, deletes, reads, and mutes are mapped to targeted
    /// actions; structural changes trigger a full conversation-list reload.
    private func parseEvents(_ events: [ChatLogEvent]) -> [ChatLocalAction] {
        var actions: [ChatLocalAction] = []
        for event in events {
            switch event.kind {
            case let .createMessage(convoId, message):
                actions.append(.appendMessage(convoId: convoId, message: message))
                if !conversations.contains(where: { $0.id == convoId }) {
                    actions.append(.reloadConvos)
                }
            case let .deleteMessage(convoId, deletedMessage):
                if messages[convoId] != nil {
                    actions.append(.deleteMessage(convoId: convoId, messageId: deletedMessage.id))
                }
            case let .addReaction(convoId, messageId, reaction):
                if messages[convoId] != nil {
                    actions.append(.addReaction(convoId: convoId, messageId: messageId, reaction: reaction))
                }
            case let .removeReaction(convoId, messageId, reaction):
                if messages[convoId] != nil {
                    actions.append(.removeReaction(convoId: convoId, messageId: messageId, reaction: reaction))
                }
            case .beginConvo, .acceptConvo, .leaveConvo, .addMember, .removeMember:
                actions.append(.reloadConvos)
            case let .muteConvo(convoId):
                actions.append(.updateMuted(convoId: convoId, muted: true))
            case let .unmuteConvo(convoId):
                actions.append(.updateMuted(convoId: convoId, muted: false))
            case let .readConvo(convoId, _):
                actions.append(.markRead(convoId: convoId))
            }
        }
        return actions
    }

    /// Applies a list of `ChatLocalAction` values, performing a full conversation
    /// list reload if any action requires it. Refreshes messages for the visible
    /// conversation after all actions are applied.
    private func applyActions(_ actions: [ChatLocalAction], context: ChatAccountContext) async throws {
        var needsReload = false

        for action in actions {
            switch action {
            case let .appendMessage(convoId, message):
                applyIncomingMessage(message, to: convoId)
                if !conversations.contains(where: { $0.id == convoId }) {
                    needsReload = true
                }

            case let .deleteMessage(convoId, messageId):
                if messages[convoId] != nil {
                    applyDeleteMessage(messageId, in: convoId)
                }

            case let .addReaction(convoId, messageId, reaction):
                applyReaction(convoId: convoId, messageId: messageId, reaction: reaction)

            case let .removeReaction(convoId, messageId, reaction):
                applyRemoveReaction(convoId: convoId, messageId: messageId, reaction: reaction)

            case let .markRead(convoId):
                if let idx = conversations.firstIndex(where: { $0.id == convoId }) {
                    let existing = conversations[idx]
                    conversations[idx] = ChatConversation(
                        id: existing.id,
                        rev: existing.rev,
                        members: existing.members,
                        lastMessage: existing.lastMessage,
                        muted: existing.muted,
                        status: existing.status,
                        unreadCount: 0,
                        kind: existing.kind,
                        groupInfo: existing.groupInfo
                    )
                }

            case let .updateMuted(convoId, muted):
                if let idx = conversations.firstIndex(where: { $0.id == convoId }) {
                    let existing = conversations[idx]
                    conversations[idx] = ChatConversation(
                        id: existing.id,
                        rev: existing.rev,
                        members: existing.members,
                        lastMessage: existing.lastMessage,
                        muted: muted,
                        status: existing.status,
                        unreadCount: existing.unreadCount,
                        kind: existing.kind,
                        groupInfo: existing.groupInfo
                    )
                }

            case .reloadConvos:
                needsReload = true
            }
        }

        // Always reload the conversation list from the server when events were
        // processed. This ensures the list view is always in sync with the server,
        // even though targeted mutations give immediate responsiveness for the
        // message detail view.
        if needsReload || !actions.isEmpty {
            try await Task.sleep(nanoseconds: 500_000_000)
            guard isCurrentContext(context) else { return }
            guard let account = activeAccount else { return }
            let result = try await chatService.listConvos(account: account, appPassword: activeAppPassword, status: nil, cursor: nil)
            guard isCurrentContext(context) else { return }
            conversations = result.conversations.sorted { $0.lastMessageAt > $1.lastMessageAt }
            convosCursor = result.cursor
            patchStaleLastMessages()
        }

        // Refresh the visible conversation's messages if we're viewing one.
        if let visibleID = visibleConversationID {
            try? await Task.sleep(nanoseconds: 100_000_000)
            await refreshMessages(convoId: visibleID)
        }
    }

    /// Updates the app icon badge to the total unread count across all conversations.
    private func updateAppBadge() {
        let totalUnread = conversations.reduce(0) { $0 + $1.unreadCount }
        Task { try? await UNUserNotificationCenter.current().setBadgeCount(totalUnread) }
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

    /// Clears all per-account chat data.
    private func resetConversationState(isLoading: Bool) {
        statusDismissTask?.cancel()
        statusDismissTask = nil
        statusMessage = nil
        conversations = []
        messages = [:]
        convosCursor = nil
        logCursor = nil
        messageCursors = [:]
        hasMoreMessages = [:]
        visibleConversationID = nil
        error = nil
        messageError = nil
        isLoadingConvos = isLoading
        isLoadingMessages = false
        isLoadingMoreMessages = false
        isSendingMessage = false
    }

    /// Returns whether an async response still belongs to the current chat context.
    private func isCurrentContext(_ context: ChatAccountContext) -> Bool {
        activeContext == context
    }

    /// Patches any conversations where the local message cache has a newer
    /// message than what the server returned as `lastMessage`.
    ///
    /// This handles cases where a message has been sent or received and stored
    /// in `messages[convoId]` but the `listConvos` endpoint hasn't propagated
    /// the update yet.
    private func patchStaleLastMessages() {
        for (index, convo) in conversations.enumerated() {
            guard let msgs = messages[convo.id], let newest = msgs.last else { continue }
            let newestDate: Date = switch newest {
            case let .message(m): m.sentAt
            case let .deleted(d): d.sentAt
            case let .system(s): s.sentAt
            }
            guard newestDate > convo.lastMessageAt else { continue }
            conversations[index] = ChatConversation(
                id: convo.id,
                rev: convo.rev,
                members: convo.members,
                lastMessage: newest,
                muted: convo.muted,
                status: convo.status,
                unreadCount: convo.unreadCount,
                kind: convo.kind,
                groupInfo: convo.groupInfo
            )
        }
    }

    private func setStatusMessage(_ message: String, autoDismiss: Bool) {
        statusDismissTask?.cancel()
        statusMessage = message
        AppLogger.persistence.info("Chat status prompt: \(message, privacy: .private)")

        guard autoDismiss else { return }
        statusDismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            self?.statusMessage = nil
            self?.statusDismissTask = nil
        }
    }

    /// Polls the chat event log and applies incremental updates.
    /// Rebuilds the conversation list if structural changes are detected.
    /// Applies a message deletion to the local cache.
    private func applyDeleteMessage(_ messageId: String, in convoId: String) {
        guard var current = messages[convoId] else { return }
        current.removeAll { idForMessage($0) == messageId }
        messages[convoId] = current
    }

    /// Applies a reaction addition to a message in the local cache.
    private func applyReaction(convoId: String, messageId: String, reaction: ChatReaction) {
        guard var current = messages[convoId] else { return }
        for (index, kind) in current.enumerated() {
            guard case var .message(msg) = kind, msg.id == messageId else { continue }
            var updatedReactions = msg.reactions
            if !updatedReactions.contains(where: { $0.senderDID == reaction.senderDID && $0.value == reaction.value }) {
                updatedReactions.append(reaction)
            }
            msg = ChatMessage(id: msg.id, rev: msg.rev, text: msg.text, senderDID: msg.senderDID, sentAt: msg.sentAt, reactions: updatedReactions)
            current[index] = .message(msg)
            messages[convoId] = current
            return
        }
    }

    /// Applies a reaction removal from a message in the local cache.
    private func applyRemoveReaction(convoId: String, messageId: String, reaction: ChatReaction) {
        guard var current = messages[convoId] else { return }
        for (index, kind) in current.enumerated() {
            guard case var .message(msg) = kind, msg.id == messageId else { continue }
            msg = ChatMessage(
                id: msg.id, rev: msg.rev, text: msg.text, senderDID: msg.senderDID,
                sentAt: msg.sentAt,
                reactions: msg.reactions.filter { $0.senderDID != reaction.senderDID || $0.value != reaction.value }
            )
            current[index] = .message(msg)
            messages[convoId] = current
            return
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
        var updatedConversations = conversations
        updatedConversations[index] = updated
        updatedConversations.sort { $0.lastMessageAt > $1.lastMessageAt }
        conversations = updatedConversations

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

// MARK: - Polling

extension ChatStore {
    /// Starts a polling loop that checks the chat event log. Polling is adaptive:
    /// 5 seconds while a chat view (list or detail) is visible, 30 seconds otherwise.
    /// Push-driven `signalSync()` still triggers immediate processing.
    func startPolling() {
        stopPolling()
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.processLog()
                guard let self else { return }
                try? await Task.sleep(nanoseconds: currentPollingInterval)
            }
        }
    }

    /// Registers or unregisters a visible chat UI view (e.g., list or detail).
    /// When any chat view is visible, polling speeds up to 5 seconds.
    func setChatViewVisible(_ visible: Bool, token: String) {
        if visible {
            chatVisibleTokens.insert(token)
        } else {
            chatVisibleTokens.remove(token)
        }
        updatePollingInterval()
    }

    private func updatePollingInterval() {
        let newInterval: UInt64 = chatVisibleTokens.isEmpty ? 30_000_000_000 : 5_000_000_000
        guard newInterval != currentPollingInterval else { return }
        currentPollingInterval = newInterval
        // Restart the loop so the new interval takes effect immediately.
        if pollingTask != nil {
            startPolling()
        }
    }

    /// Stops the polling loop.
    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }
}
