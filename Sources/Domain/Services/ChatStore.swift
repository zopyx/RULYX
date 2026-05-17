import Combine
import Foundation
import UIKit

@MainActor
final class ChatStore: ObservableObject {
    @Published private(set) var conversations: [ChatConversation] = []
    @Published private(set) var messages: [String: [ChatMessageKind]] = [:]
    @Published private(set) var isLoadingConvos = false
    @Published private(set) var isLoadingMessages = false
    @Published private(set) var isLoadingMoreMessages = false
    @Published private(set) var isSendingMessage = false
    @Published private(set) var hasMoreMessages: [String: Bool] = [:]
    @Published var error: Error?

    private let chatService: ChatServicing
    private var convosCursor: String?
    private var logCursor: String?
    private var messageCursors: [String: String] = [:]
    private var pollingTask: Task<Void, Never>?
    private var activeAccount: AppAccount?
    private var activeAppPassword: String?
    private var visibleConversationID: String?
    private(set) var currentAccountDID: String?

    init(chatService: ChatServicing) {
        self.chatService = chatService
    }

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
            self.error = error
            isLoadingConvos = false
        }
    }

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

    func loadMessages(convoId: String) async {
        guard let account = activeAccount else { return }
        isLoadingMessages = true
        error = nil
        do {
            let result = try await chatService.getMessages(convoId: convoId, cursor: nil, limit: 50, account: account, appPassword: activeAppPassword)
            messages[convoId] = result.messages.reversed()
            messageCursors[convoId] = result.cursor
            hasMoreMessages[convoId] = result.cursor != nil
            isLoadingMessages = false
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
            self.error = error
            isLoadingMessages = false
        }
    }

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
            self.error = error
            isLoadingMoreMessages = false
        }
    }

    // MARK: - Send

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

    func leave(convoId: String) async {
        guard let account = activeAccount else { return }
        try? await chatService.leaveConvo(convoId: convoId, account: account, appPassword: activeAppPassword)
        conversations.removeAll { $0.id == convoId }
        messages.removeValue(forKey: convoId)
    }

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

    private func refreshMessages(convoId: String) async {
        guard let account = activeAccount else { return }
        do {
            let result = try await chatService.getMessages(convoId: convoId, cursor: nil, limit: 50, account: account, appPassword: activeAppPassword)
            messages[convoId] = result.messages.reversed()
        } catch {
            if let urlError = error as? URLError, urlError.code == .cancelled { return }
        }
    }

    func setVisibleConversation(_ convoId: String?) {
        visibleConversationID = convoId
    }

    // MARK: - Push-Driven Incremental Sync

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
            try await Task.sleep(nanoseconds: 300_000_000)
            let result = try await chatService.listConvos(account: account, appPassword: activeAppPassword, status: nil, cursor: nil)
            conversations = result.conversations.sorted { $0.lastMessageAt > $1.lastMessageAt }
            convosCursor = result.cursor
            updateAppBadge()

            if let visibleID = visibleConversationID {
                await refreshMessages(convoId: visibleID)
            }
        } catch {
            if let urlError = error as? URLError, urlError.code == .cancelled { return }
            AppLogger.persistence.error("Chat syncLog failed: \(error.localizedDescription, privacy: .public)")
            self.error = error
        }
    }

    private func updateAppBadge() {
        let totalUnread = conversations.reduce(0) { $0 + $1.unreadCount }
        UIApplication.shared.applicationIconBadgeNumber = totalUnread
    }

    // MARK: - Polling

    func startPolling(interval: TimeInterval = 5) {
        stopPolling()
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.pollLog()
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }
        }
    }

    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    private func idForMessage(_ kind: ChatMessageKind) -> String {
        switch kind {
        case let .message(m): m.id
        case let .deleted(d): d.id
        case let .system(s): s.id
        }
    }

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

            if needsReload {
                try await Task.sleep(nanoseconds: 500_000_000)
                let result = try await chatService.listConvos(account: account, appPassword: activeAppPassword, status: nil, cursor: nil)
                conversations = result.conversations.sorted { $0.lastMessageAt > $1.lastMessageAt }
                convosCursor = result.cursor
            }

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

    private func applyIncomingMessage(_ message: ChatMessage, to convoId: String) {
        let incomingKind = ChatMessageKind.message(message)

        var currentMessages = messages[convoId] ?? []
        if !currentMessages.contains(where: { idForMessage($0) == message.id }) {
            currentMessages.append(incomingKind)
            messages[convoId] = currentMessages
        }

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
    }

    private func upsertConversation(_ conversation: ChatConversation) {
        if let index = conversations.firstIndex(where: { $0.id == conversation.id }) {
            conversations[index] = conversation
        } else {
            conversations.append(conversation)
        }
        conversations.sort { $0.lastMessageAt > $1.lastMessageAt }
    }
}
