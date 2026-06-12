import Foundation

/// Provides chat conversation operations for Bluesky's chat protocol.
/// Implementations handle listing conversations, fetching messages, sending messages,
/// managing read state, and conversation lifecycle (leave, mute, unmute).
@MainActor
protocol ChatServicing {
    /// Clears any in-memory caches used by the chat service.
    func clearCaches()

    // MARK: - Conversations

    /// Lists conversations with optional status filter and pagination.
    /// - Parameters:
    ///   - account: The account to authenticate with.
    ///   - appPassword: The app password for authentication, or `nil` to use the cached session.
    ///   - status: An optional conversation status filter (e.g. `"open"`, `"request"`).
    ///   - cursor: An optional cursor for paginating through conversations.
    /// - Returns: A `PagedConvos` containing conversations and an optional next cursor.
    func listConvos(account: AppAccount, appPassword: String?, status: String?, cursor: String?) async throws -> PagedConvos

    /// Fetches a single conversation by its ID.
    /// - Parameters:
    ///   - convoId: The ID of the conversation to fetch.
    ///   - account: The account to authenticate with.
    ///   - appPassword: The app password for authentication, or `nil` to use the cached session.
    /// - Returns: A `ChatConversation` with participant and message details.
    func getConvo(convoId: String, account: AppAccount, appPassword: String?) async throws -> ChatConversation

    /// Finds or creates a conversation for the specified member DIDs.
    /// - Parameters:
    ///   - members: An array of member DIDs to include in the conversation.
    ///   - account: The account to authenticate with.
    ///   - appPassword: The app password for authentication, or `nil` to use the cached session.
    /// - Returns: A `ChatConversation` containing the specified members.
    func getConvoForMembers(members: [String], account: AppAccount, appPassword: String?) async throws -> ChatConversation

    // MARK: - Messages

    /// Fetches messages in a conversation with cursor-based pagination.
    /// - Parameters:
    ///   - convoId: The conversation ID to fetch messages from.
    ///   - cursor: An optional cursor for paginating through messages.
    ///   - limit: The maximum number of messages to return per page.
    ///   - account: The account to authenticate with.
    ///   - appPassword: The app password for authentication, or `nil` to use the cached session.
    /// - Returns: A `PagedMessages` containing messages and an optional next cursor.
    func getMessages(convoId: String, cursor: String?, limit: Int, account: AppAccount, appPassword: String?) async throws -> PagedMessages

    /// Sends a text message to a conversation.
    /// - Parameters:
    ///   - convoId: The conversation ID to send the message to.
    ///   - text: The message text content.
    ///   - account: The account to authenticate with.
    ///   - appPassword: The app password for authentication, or `nil` to use the cached session.
    /// - Returns: A `ChatMessageSendResult` with the sent message details.
    func sendMessage(convoId: String, text: String, account: AppAccount, appPassword: String?) async throws -> ChatMessageSendResult

    /// Marks a conversation as read up to the specified message.
    /// - Parameters:
    ///   - convoId: The conversation ID to update.
    ///   - messageId: An optional message ID marking the last read message; if `nil`, marks all as read.
    ///   - account: The account to authenticate with.
    ///   - appPassword: The app password for authentication, or `nil` to use the cached session.
    func updateRead(convoId: String, messageId: String?, account: AppAccount, appPassword: String?) async throws

    // MARK: - Conversation Management

    /// Leaves a conversation (removes the current account from participants).
    /// - Parameters:
    ///   - convoId: The conversation ID to leave.
    ///   - account: The account to authenticate with.
    ///   - appPassword: The app password for authentication, or `nil` to use the cached session.
    func leaveConvo(convoId: String, account: AppAccount, appPassword: String?) async throws

    /// Mutes a conversation, suppressing push notifications.
    /// - Parameters:
    ///   - convoId: The conversation ID to mute.
    ///   - account: The account to authenticate with.
    ///   - appPassword: The app password for authentication, or `nil` to use the cached session.
    func muteConvo(convoId: String, account: AppAccount, appPassword: String?) async throws

    /// Unmutes a previously muted conversation, restoring push notifications.
    /// - Parameters:
    ///   - convoId: The conversation ID to unmute.
    ///   - account: The account to authenticate with.
    ///   - appPassword: The app password for authentication, or `nil` to use the cached session.
    func unmuteConvo(convoId: String, account: AppAccount, appPassword: String?) async throws

    // MARK: - Chat Requests

    /// Accepts an incoming conversation request.
    /// - Parameters:
    ///   - convoId: The ID of the conversation request to accept.
    ///   - account: The account to authenticate with.
    ///   - appPassword: The app password for authentication, or `nil` to use the cached session.
    func acceptConvo(convoId: String, account: AppAccount, appPassword: String?) async throws

    /// Lists incoming conversation requests (unaccepted conversations).
    /// - Parameters:
    ///   - cursor: An optional cursor for paginating through requests.
    ///   - account: The account to authenticate with.
    ///   - appPassword: The app password for authentication, or `nil` to use the cached session.
    /// - Returns: A `PagedConvos` containing request conversations and an optional next cursor.
    func listConvoRequests(cursor: String?, account: AppAccount, appPassword: String?) async throws -> PagedConvos

    /// Checks whether a conversation can be started with the specified members.
    /// - Parameters:
    ///   - members: An array of member DIDs to check availability for.
    ///   - account: The account to authenticate with.
    ///   - appPassword: The app password for authentication, or `nil` to use the cached session.
    /// - Returns: `true` if a conversation can be started, `false` otherwise.
    func getConvoAvailability(members: [String], account: AppAccount, appPassword: String?) async throws -> Bool

    /// Deletes a message for the current user only (removes it from their view).
    /// - Parameters:
    ///   - convoId: The conversation ID containing the message.
    ///   - messageId: The ID of the message to delete.
    ///   - account: The account to authenticate with.
    ///   - appPassword: The app password for authentication, or `nil` to use the cached session.
    func deleteMessageForSelf(convoId: String, messageId: String, account: AppAccount, appPassword: String?) async throws

    // MARK: - Group Management

    /// Fetches detailed member information for a group conversation.
    /// - Parameters:
    ///   - convoId: The conversation ID to fetch members for.
    ///   - account: The account to authenticate with.
    ///   - appPassword: The app password for authentication, or `nil` to use the cached session.
    /// - Returns: An array of `ChatMemberProfile` for all members.
    func getConvoMembers(convoId: String, account: AppAccount, appPassword: String?) async throws -> [ChatMemberProfile]

    /// Adds members to a group conversation.
    /// - Parameters:
    ///   - convoId: The conversation ID to add members to.
    ///   - memberDIDs: An array of member DIDs to add.
    ///   - account: The account to authenticate with.
    ///   - appPassword: The app password for authentication, or `nil` to use the cached session.
    func addMembers(convoId: String, memberDIDs: [String], account: AppAccount, appPassword: String?) async throws

    /// Removes members from a group conversation.
    /// - Parameters:
    ///   - convoId: The conversation ID to remove members from.
    ///   - memberDIDs: An array of member DIDs to remove.
    ///   - account: The account to authenticate with.
    ///   - appPassword: The app password for authentication, or `nil` to use the cached session.
    func removeMembers(convoId: String, memberDIDs: [String], account: AppAccount, appPassword: String?) async throws

    /// Edits a group conversation's metadata (e.g., name).
    /// - Parameters:
    ///   - convoId: The conversation ID to edit.
    ///   - name: The new name for the group, or `nil` to keep the current name.
    ///   - account: The account to authenticate with.
    ///   - appPassword: The app password for authentication, or `nil` to use the cached session.
    func editGroup(convoId: String, name: String?, account: AppAccount, appPassword: String?) async throws

    /// Locks a group conversation (prevents new members from being added).
    /// - Parameters:
    ///   - convoId: The conversation ID to lock.
    ///   - account: The account to authenticate with.
    ///   - appPassword: The app password for authentication, or `nil` to use the cached session.
    func lockConvo(convoId: String, account: AppAccount, appPassword: String?) async throws

    /// Unlocks a previously locked group conversation.
    /// - Parameters:
    ///   - convoId: The conversation ID to unlock.
    ///   - account: The account to authenticate with.
    ///   - appPassword: The app password for authentication, or `nil` to use the cached session.
    func unlockConvo(convoId: String, account: AppAccount, appPassword: String?) async throws

    // MARK: - Reactions

    /// Adds an emoji reaction to a message.
    /// - Parameters:
    ///   - convoId: The conversation ID containing the message.
    ///   - messageId: The ID of the message to react to.
    ///   - value: The emoji reaction value (e.g., "👍").
    ///   - account: The account to authenticate with.
    ///   - appPassword: The app password for authentication, or `nil` to use the cached session.
    func addReaction(convoId: String, messageId: String, value: String, account: AppAccount, appPassword: String?) async throws

    /// Removes an emoji reaction from a message.
    /// - Parameters:
    ///   - convoId: The conversation ID containing the message.
    ///   - messageId: The ID of the message to remove the reaction from.
    ///   - value: The emoji reaction value to remove (e.g., "👍").
    ///   - account: The account to authenticate with.
    ///   - appPassword: The app password for authentication, or `nil` to use the cached session.
    func removeReaction(convoId: String, messageId: String, value: String, account: AppAccount, appPassword: String?) async throws

    // MARK: - Log

    /// Fetches the chat event log with cursor-based pagination.
    /// - Parameters:
    ///   - cursor: An optional cursor for paginating through log events.
    ///   - account: The account to authenticate with.
    ///   - appPassword: The app password for authentication, or `nil` to use the cached session.
    /// - Returns: A tuple containing an array of `ChatLogEvent` and an optional next cursor.
    func getLog(cursor: String?, account: AppAccount, appPassword: String?) async throws -> (events: [ChatLogEvent], cursor: String?)
}
