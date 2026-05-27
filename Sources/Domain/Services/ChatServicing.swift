import Foundation

/// Provides chat conversation operations for Bluesky's chat protocol.
/// Implementations handle listing conversations, fetching messages, sending messages,
/// managing read state, and conversation lifecycle (leave, mute, unmute).
@MainActor
protocol ChatServicing {
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

    // MARK: - Log

    /// Fetches the chat event log with cursor-based pagination.
    /// - Parameters:
    ///   - cursor: An optional cursor for paginating through log events.
    ///   - account: The account to authenticate with.
    ///   - appPassword: The app password for authentication, or `nil` to use the cached session.
    /// - Returns: A tuple containing an array of `ChatLogEvent` and an optional next cursor.
    func getLog(cursor: String?, account: AppAccount, appPassword: String?) async throws -> (events: [ChatLogEvent], cursor: String?)
}
