import Foundation

/// A fine-grained local mutation to apply in response to a chat event-log entry.
///
/// Each case represents a single atomic state change. Actions are collected
/// during event parsing and then applied together, minimising the need for
/// expensive full conversation-list reloads.
enum ChatLocalAction {
    /// Append an incoming message to the local message cache for a conversation.
    case appendMessage(convoId: String, message: ChatMessage)

    /// Remove a deleted message from the local message cache.
    case deleteMessage(convoId: String, messageId: String)

    /// Add a reaction to a message in the local cache.
    case addReaction(convoId: String, messageId: String, reaction: ChatReaction)

    /// Remove a reaction from a message in the local cache.
    case removeReaction(convoId: String, messageId: String, reaction: ChatReaction)

    /// Mark a conversation as read locally (unread count → 0).
    case markRead(convoId: String)

    /// Update the muted state of a conversation locally.
    case updateMuted(convoId: String, muted: Bool)

    /// Reload the full conversation list from the server.
    /// Used when structural changes (add/remove/member changes) occur.
    case reloadConvos
}
