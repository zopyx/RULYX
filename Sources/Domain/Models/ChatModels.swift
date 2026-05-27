import Foundation

/// Represents the kind of a chat conversation.
enum ChatConversationKind: String {
    /// A one-on-one direct message conversation.
    case direct
    /// A multi-participant group conversation.
    case group
}

/// Represents the current status of a chat conversation.
enum ChatConversationStatus: String {
    /// An incoming conversation request that has not yet been accepted.
    case request
    /// A conversation that has been accepted by the user.
    case accepted
}

/// Represents the different kinds of messages that can appear in a conversation timeline.
enum ChatMessageKind {
    /// A regular text message with full content.
    case message(ChatMessage)
    /// A message that has been deleted; only metadata remains.
    case deleted(ChatDeletedMessage)
    /// A system event message (e.g., member added, conversation locked).
    case system(ChatSystemMessage)
}

/// Represents a Bluesky chat conversation with full metadata.
struct ChatConversation: Identifiable, Hashable {
    // MARK: - Properties

    /// The unique identifier for this conversation.
    let id: String
    /// The revision token used for optimistic concurrency control.
    let rev: String
    /// The member profiles participating in this conversation.
    let members: [ChatMemberProfile]
    /// The most recent message in the conversation, if any.
    let lastMessage: ChatMessageKind?
    /// Whether the conversation is muted for the current user.
    let muted: Bool
    /// The status of the conversation (request or accepted).
    let status: ChatConversationStatus?
    /// The number of unread messages in this conversation.
    let unreadCount: Int
    /// Whether this is a direct or group conversation.
    let kind: ChatConversationKind
    /// Group-specific metadata, if this is a group conversation.
    let groupInfo: ChatGroupInfo?

    // MARK: - Computed Properties

    /// The timestamp of the most recent message, regardless of message kind.
    /// Returns `.distantPast` if there are no messages.
    var lastMessageAt: Date {
        guard let lastMessage else { return .distantPast }
        return switch lastMessage {
        case let .message(m): m.sentAt
        case let .deleted(d): d.sentAt
        case let .system(s): s.sentAt
        }
    }

    // MARK: - Hashable

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    // MARK: - Equatable

    /// Two conversations are equal if they share the same ID and revision token.
    static func == (lhs: ChatConversation, rhs: ChatConversation) -> Bool {
        lhs.id == rhs.id && lhs.rev == rhs.rev
    }
}

/// Metadata for a group conversation.
struct ChatGroupInfo {
    /// The display name of the group.
    let name: String
    /// The number of members in the group.
    let memberCount: Int
    /// The date the group was created.
    let createdAt: Date
    /// The lock status of the group (e.g., "locked", "unlocked").
    let lockStatus: String
}

/// Represents a participant in a chat conversation.
struct ChatMemberProfile: Identifiable {
    /// The DID of the chat member.
    let did: String
    /// The Bluesky handle of the member.
    let handle: String
    /// The display name of the member, if available.
    let displayName: String?
    /// The URL to the member's avatar image.
    let avatarURL: URL?
    /// The unique identifier, derived from the DID.
    var id: String {
        did
    }
}

/// Represents a regular text message in a chat conversation.
struct ChatMessage: Identifiable {
    /// The unique identifier for this message.
    let id: String
    /// The revision token for this message.
    let rev: String
    /// The text content of the message.
    let text: String
    /// The DID of the sender.
    let senderDID: String
    /// The timestamp when the message was sent.
    let sentAt: Date
    /// Reactions applied to this message.
    let reactions: [ChatReaction]
}

/// Represents a deleted message in a chat conversation.
/// Retains only the metadata; the text content is no longer available.
struct ChatDeletedMessage: Identifiable {
    /// The unique identifier for the deleted message.
    let id: String
    /// The revision token at the time of deletion.
    let rev: String
    /// The DID of the original sender.
    let senderDID: String
    /// The timestamp of the original message.
    let sentAt: Date
}

/// Represents a system event message in a chat conversation.
struct ChatSystemMessage: Identifiable {
    /// The unique identifier for this system message.
    let id: String
    /// The revision token for this system message.
    let rev: String
    /// The timestamp when the system event occurred.
    let sentAt: Date
    /// The structured data describing the system event.
    let data: ChatSystemMessageData
}

/// Represents the specific type of a system event in a chat conversation.
enum ChatSystemMessageData {
    /// A member was added by another member.
    case addMember(memberDID: String, addedByDID: String)
    /// A member was removed by another member.
    case removeMember(memberDID: String, removedByDID: String)
    /// A member joined the conversation voluntarily.
    case memberJoin(memberDID: String)
    /// A member left the conversation voluntarily.
    case memberLeave(memberDID: String)
    /// The conversation was locked (no new members can be added).
    case lockConvo
    /// The conversation was unlocked.
    case unlockConvo
    /// The conversation was permanently locked (irreversible).
    case lockConvoPermanently
    /// The group name was changed.
    case editGroup(oldName: String?, newName: String?)
    /// An unrecognized or unsupported system event type.
    case unknown
}

/// Represents a reaction (emoji) applied to a chat message.
struct ChatReaction {
    /// The reaction value (e.g., an emoji character).
    let value: String
    /// The DID of the user who sent the reaction.
    let senderDID: String
    /// The timestamp when the reaction was added.
    let createdAt: Date
}

/// The result returned after successfully sending a chat message.
struct ChatMessageSendResult {
    /// The unique identifier of the sent message.
    let id: String
    /// The revision token of the sent message.
    let rev: String
    /// The text content that was sent.
    let text: String
    /// The DID of the sender.
    let senderDID: String
    /// The timestamp when the message was sent.
    let sentAt: Date
}

/// A paginated response containing chat messages.
struct PagedMessages {
    /// The messages in this page.
    let messages: [ChatMessageKind]
    /// The cursor for fetching the next page, nil if this is the last page.
    let cursor: String?
}

/// A paginated response containing chat conversations.
struct PagedConvos {
    /// The conversations in this page.
    let conversations: [ChatConversation]
    /// The cursor for fetching the next page, nil if this is the last page.
    let cursor: String?
}

/// Represents a single event from the chat event log (used for real-time updates via websocket).
struct ChatLogEvent {
    /// The revision token for this event.
    let rev: String
    /// The type of event that occurred.
    let kind: ChatLogEventKind
}

/// Represents the different types of events that can appear in the chat event log.
enum ChatLogEventKind {
    /// A new conversation was initiated.
    case beginConvo(convoId: String)
    /// A conversation request was accepted.
    case acceptConvo(convoId: String)
    /// A user left a conversation.
    case leaveConvo(convoId: String)
    /// A conversation was muted.
    case muteConvo(convoId: String)
    /// A conversation was unmuted.
    case unmuteConvo(convoId: String)
    /// A new message was created in a conversation.
    case createMessage(convoId: String, message: ChatMessage)
    /// A message was deleted from a conversation.
    case deleteMessage(convoId: String, message: ChatDeletedMessage)
    /// A reaction was added to a message.
    case addReaction(convoId: String, messageId: String, reaction: ChatReaction)
    /// A reaction was removed from a message.
    case removeReaction(convoId: String, messageId: String, reaction: ChatReaction)
    /// A conversation was marked as read up to a specific message.
    case readConvo(convoId: String, messageId: String)
    /// A member was added to a conversation.
    case addMember(convoId: String, memberDID: String)
    /// A member was removed from a conversation.
    case removeMember(convoId: String, memberDID: String)
}
