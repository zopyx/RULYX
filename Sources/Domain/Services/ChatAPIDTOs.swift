import Foundation

// MARK: - List Convos

/// Response from `chat.bsky.convo.listConvos`.
struct ListConvosResponse: Decodable {
    /// Pagination cursor.
    let cursor: String?
    /// Array of conversation views.
    let convos: [ConvoViewDTO]
}

/// A conversation view returned by the Bluesky chat API.
struct ConvoViewDTO: Decodable {
    /// Conversation identifier.
    let id: String
    /// Revision token for optimistic concurrency.
    let rev: String
    /// Participants in the conversation.
    let members: [ChatMemberProfileDTO]
    /// The most recent message, if any.
    let lastMessage: LastMessageUnion?
    /// Whether the conversation is muted.
    let muted: Bool
    /// Conversation status string.
    let status: String?
    /// Number of unread messages.
    let unreadCount: Int
    /// Optional kind (direct vs. group).
    let kind: ConvoKindUnion?

    enum CodingKeys: String, CodingKey {
        case id, rev, members, lastMessage, muted, status, unreadCount, kind
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        rev = try container.decode(String.self, forKey: .rev)
        members = try container.decode([ChatMemberProfileDTO].self, forKey: .members)
        lastMessage = try container.decodeIfPresent(LastMessageUnion.self, forKey: .lastMessage)
        muted = try container.decode(Bool.self, forKey: .muted)
        status = try container.decodeIfPresent(String.self, forKey: .status)
        unreadCount = try container.decode(Int.self, forKey: .unreadCount)
        kind = try container.decodeIfPresent(ConvoKindUnion.self, forKey: .kind)
    }
}

/// Discriminated union for direct vs. group conversation kinds.
struct ConvoKindUnion: Decodable {
    let direct: DirectConvoDTO?
    let group: GroupConvoDTO?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let direct = try? container.decode(DirectConvoDTO.self) {
            self.direct = direct
            group = nil
        } else if let group = try? container.decode(GroupConvoDTO.self) {
            self.group = group
            direct = nil
        } else {
            direct = nil
            group = nil
        }
    }
}

/// A direct (1:1) conversation kind marker.
struct DirectConvoDTO: Decodable {}

/// A group conversation with name, member count, and lock status.
struct GroupConvoDTO: Decodable {
    /// Group display name.
    let name: String?
    /// Number of members in the group.
    let memberCount: Int?
    /// ISO 8601 creation date string.
    let createdAt: String?
    /// Lock status string (e.g. "unlocked").
    let lockStatus: String?
}

/// Profile information for a chat participant.
struct ChatMemberProfileDTO: Decodable {
    /// The member's DID.
    let did: String
    /// The member's handle (optional for deleted accounts).
    let handle: String?
    /// Display name if set.
    let displayName: String?
    /// Avatar URL string.
    let avatar: String?
}

/// Discriminated union for the last message in a conversation, which may be
/// a regular message, a deleted message, or a system message.
struct LastMessageUnion: Decodable {
    let message: MessageViewDTO?
    let deleted: DeletedMessageViewDTO?
    let system: SystemMessageViewDTO?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let msg = try? container.decode(MessageViewDTO.self), msg.id != nil {
            message = msg
            deleted = nil
            system = nil
        } else if let del = try? container.decode(DeletedMessageViewDTO.self), del.id != nil {
            deleted = del
            message = nil
            system = nil
        } else if let sys = try? container.decode(SystemMessageViewDTO.self), sys.id != nil {
            system = sys
            message = nil
            deleted = nil
        } else {
            message = nil
            deleted = nil
            system = nil
        }
    }
}

// MARK: - Get Messages

/// Response from `chat.bsky.convo.getMessages`.
struct GetMessagesResponse: Decodable {
    let cursor: String?
    let messages: [MessageUnionDTO]
    let relatedProfiles: [ChatMemberProfileDTO]?
}

struct MessageUnionDTO: Decodable {
    /// A regular message view, if present.
    let messageView: MessageViewDTO?
    /// A deleted message view, if present.
    let deletedMessageView: DeletedMessageViewDTO?
    /// A system message view, if present.
    let systemMessageView: SystemMessageViewDTO?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let msg = try? container.decode(MessageViewDTO.self), msg.id != nil {
            messageView = msg
            deletedMessageView = nil
            systemMessageView = nil
        } else if let del = try? container.decode(DeletedMessageViewDTO.self), del.id != nil {
            deletedMessageView = del
            messageView = nil
            systemMessageView = nil
        } else if let sys = try? container.decode(SystemMessageViewDTO.self), sys.id != nil {
            systemMessageView = sys
            messageView = nil
            deletedMessageView = nil
        } else {
            messageView = nil
            deletedMessageView = nil
            systemMessageView = nil
        }
    }
}

/// A regular chat message view.
struct MessageViewDTO: Decodable {
    let id: String?
    let rev: String?
    let text: String?
    let sender: MessageViewSenderDTO?
    let sentAt: String?
    let reactions: [ReactionViewDTO]?
}

/// A deleted chat message view.
struct DeletedMessageViewDTO: Decodable {
    let id: String?
    let rev: String?
    let sender: MessageViewSenderDTO?
    let sentAt: String?
}

/// A system-generated message view (member join/leave, group rename, etc.).
struct SystemMessageViewDTO: Decodable {
    let id: String?
    let rev: String?
    let sentAt: String?
    let data: SystemMessageDataUnion?
}

/// System message payload containing member references, name changes, and type.
struct SystemMessageDataUnion: Decodable {
    let member: ReferredUserDTO?
    let addedBy: ReferredUserDTO?
    let removedBy: ReferredUserDTO?
    let oldName: String?
    let newName: String?
    let type: String?

    enum CodingKeys: String, CodingKey {
        case member, addedBy, removedBy, oldName, newName
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        member = try container.decodeIfPresent(ReferredUserDTO.self, forKey: .member)
        addedBy = try container.decodeIfPresent(ReferredUserDTO.self, forKey: .addedBy)
        removedBy = try container.decodeIfPresent(ReferredUserDTO.self, forKey: .removedBy)
        oldName = try container.decodeIfPresent(String.self, forKey: .oldName)
        newName = try container.decodeIfPresent(String.self, forKey: .newName)
        type = nil
    }
}

struct ReferredUserDTO: Decodable {
    let did: String
}

struct MessageViewSenderDTO: Decodable {
    let did: String
}

struct ReactionViewDTO: Decodable {
    let value: String
    let sender: ReactionViewSenderDTO
    let createdAt: String
}

struct ReactionViewSenderDTO: Decodable {
    let did: String
}

// MARK: - Send Message

/// Request body for `chat.bsky.convo.sendMessage`.
struct SendMessageRequest: Encodable {
    let convoId: String
    let message: MessageInputDTO
}

struct MessageInputDTO: Encodable {
    let text: String
}

struct SendMessageResponse: Decodable {
    let id: String
    let rev: String
    let text: String
    let sender: MessageViewSenderDTO
    let sentAt: String
}

// MARK: - Update Read

/// Request body for `chat.bsky.convo.updateRead`.
struct UpdateReadRequest: Encodable {
    let convoId: String
    let messageId: String?
}

struct UpdateReadResponse: Decodable {
    let convo: ConvoViewDTO
}

// MARK: - Leave Convo

/// Request body for `chat.bsky.convo.leaveConvo`.
struct LeaveConvoRequest: Encodable {
    let convoId: String
}

struct LeaveConvoResponse: Decodable {
    let convoId: String
    let rev: String
}

// MARK: - Mute/Unmute

/// Request body for `chat.bsky.convo.muteConvo` / `unmuteConvo`.
struct MuteConvoRequest: Encodable {
    let convoId: String
}

struct MuteConvoResponse: Decodable {
    let convo: ConvoViewDTO
}

// MARK: - Get Log

/// Response from `chat.bsky.convo.getLog`.
struct GetLogResponse: Decodable {
    let cursor: String?
    let logs: [LogEventUnionDTO]
}

struct LogEventUnionDTO: Decodable {
    let beginConvo: LogBeginConvoDTO?
    let acceptConvo: LogAcceptConvoDTO?
    let leaveConvo: LogLeaveConvoDTO?
    let muteConvo: LogMuteConvoDTO?
    let unmuteConvo: LogUnmuteConvoDTO?
    let createMessage: LogCreateMessageDTO?
    let deleteMessage: LogDeleteMessageDTO?
    let addReaction: LogAddReactionDTO?
    let removeReaction: LogRemoveReactionDTO?
    let readConvo: LogReadConvoDTO?
    let addMember: LogAddMemberDTO?
    let removeMember: LogRemoveMemberDTO?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let v = try? container.decode(LogBeginConvoDTO.self), v.rev != nil { beginConvo = v
            acceptConvo = nil
            leaveConvo = nil
            muteConvo = nil
            unmuteConvo = nil
            createMessage = nil
            deleteMessage = nil
            addReaction = nil
            removeReaction = nil
            readConvo = nil
            addMember = nil
            removeMember = nil
        } else if let v = try? container.decode(LogAcceptConvoDTO.self), v.rev != nil { acceptConvo = v
            beginConvo = nil
            leaveConvo = nil
            muteConvo = nil
            unmuteConvo = nil
            createMessage = nil
            deleteMessage = nil
            addReaction = nil
            removeReaction = nil
            readConvo = nil
            addMember = nil
            removeMember = nil
        } else if let v = try? container.decode(LogLeaveConvoDTO.self), v.rev != nil { leaveConvo = v
            beginConvo = nil
            acceptConvo = nil
            muteConvo = nil
            unmuteConvo = nil
            createMessage = nil
            deleteMessage = nil
            addReaction = nil
            removeReaction = nil
            readConvo = nil
            addMember = nil
            removeMember = nil
        } else if let v = try? container.decode(LogMuteConvoDTO.self), v.rev != nil { muteConvo = v
            beginConvo = nil
            acceptConvo = nil
            leaveConvo = nil
            unmuteConvo = nil
            createMessage = nil
            deleteMessage = nil
            addReaction = nil
            removeReaction = nil
            readConvo = nil
            addMember = nil
            removeMember = nil
        } else if let v = try? container.decode(LogUnmuteConvoDTO.self), v.rev != nil { unmuteConvo = v
            beginConvo = nil
            acceptConvo = nil
            leaveConvo = nil
            muteConvo = nil
            createMessage = nil
            deleteMessage = nil
            addReaction = nil
            removeReaction = nil
            readConvo = nil
            addMember = nil
            removeMember = nil
        } else if let v = try? container.decode(LogCreateMessageDTO.self), v.rev != nil { createMessage = v
            beginConvo = nil
            acceptConvo = nil
            leaveConvo = nil
            muteConvo = nil
            unmuteConvo = nil
            deleteMessage = nil
            addReaction = nil
            removeReaction = nil
            readConvo = nil
            addMember = nil
            removeMember = nil
        } else if let v = try? container.decode(LogDeleteMessageDTO.self), v.rev != nil { deleteMessage = v
            beginConvo = nil
            acceptConvo = nil
            leaveConvo = nil
            muteConvo = nil
            unmuteConvo = nil
            createMessage = nil
            addReaction = nil
            removeReaction = nil
            readConvo = nil
            addMember = nil
            removeMember = nil
        } else if let v = try? container.decode(LogAddReactionDTO.self), v.rev != nil { addReaction = v
            beginConvo = nil
            acceptConvo = nil
            leaveConvo = nil
            muteConvo = nil
            unmuteConvo = nil
            createMessage = nil
            deleteMessage = nil
            removeReaction = nil
            readConvo = nil
            addMember = nil
            removeMember = nil
        } else if let v = try? container.decode(LogRemoveReactionDTO.self), v.rev != nil { removeReaction = v
            beginConvo = nil
            acceptConvo = nil
            leaveConvo = nil
            muteConvo = nil
            unmuteConvo = nil
            createMessage = nil
            deleteMessage = nil
            addReaction = nil
            readConvo = nil
            addMember = nil
            removeMember = nil
        } else if let v = try? container.decode(LogReadConvoDTO.self), v.rev != nil { readConvo = v
            beginConvo = nil
            acceptConvo = nil
            leaveConvo = nil
            muteConvo = nil
            unmuteConvo = nil
            createMessage = nil
            deleteMessage = nil
            addReaction = nil
            removeReaction = nil
            addMember = nil
            removeMember = nil
        } else if let v = try? container.decode(LogAddMemberDTO.self), v.rev != nil { addMember = v
            beginConvo = nil
            acceptConvo = nil
            leaveConvo = nil
            muteConvo = nil
            unmuteConvo = nil
            createMessage = nil
            deleteMessage = nil
            addReaction = nil
            removeReaction = nil
            readConvo = nil
            removeMember = nil
        } else if let v = try? container.decode(LogRemoveMemberDTO.self), v.rev != nil { removeMember = v
            beginConvo = nil
            acceptConvo = nil
            leaveConvo = nil
            muteConvo = nil
            unmuteConvo = nil
            createMessage = nil
            deleteMessage = nil
            addReaction = nil
            removeReaction = nil
            readConvo = nil
            addMember = nil
        } else { beginConvo = nil
            acceptConvo = nil
            leaveConvo = nil
            muteConvo = nil
            unmuteConvo = nil
            createMessage = nil
            deleteMessage = nil
            addReaction = nil
            removeReaction = nil
            readConvo = nil
            addMember = nil
            removeMember = nil
        }
    }
}

struct LogBeginConvoDTO: Decodable { let rev: String?
    let convoId: String?
}

struct LogAcceptConvoDTO: Decodable { let rev: String?
    let convoId: String?
}

struct LogLeaveConvoDTO: Decodable { let rev: String?
    let convoId: String?
}

struct LogMuteConvoDTO: Decodable { let rev: String?
    let convoId: String?
}

struct LogUnmuteConvoDTO: Decodable { let rev: String?
    let convoId: String?
}

struct LogReadConvoDTO: Decodable { let rev: String?
    let convoId: String?
    let message: LastMessageUnion?
}

struct LogCreateMessageDTO: Decodable {
    let rev: String?
    let convoId: String?
    let message: LastMessageUnion?
}

struct LogDeleteMessageDTO: Decodable {
    let rev: String?
    let convoId: String?
    let message: LastMessageUnion?
}

struct LogAddReactionDTO: Decodable {
    let rev: String?
    let convoId: String?
    let message: LastMessageUnion?
    let reaction: ReactionViewDTO?
}

struct LogRemoveReactionDTO: Decodable {
    let rev: String?
    let convoId: String?
    let message: LastMessageUnion?
    let reaction: ReactionViewDTO?
}

struct LogAddMemberDTO: Decodable {
    let rev: String?
    let convoId: String?
    let message: LastMessageUnion?
}

struct LogRemoveMemberDTO: Decodable {
    let rev: String?
    let convoId: String?
    let message: LastMessageUnion?
}

// MARK: - Get Convo For Members

/// Request body for `chat.bsky.convo.getConvoForMembers`.
struct GetConvoForMembersRequest: Encodable {
    let members: [String]
}

struct GetConvoResponse: Decodable {
    let convo: ConvoViewDTO
}
