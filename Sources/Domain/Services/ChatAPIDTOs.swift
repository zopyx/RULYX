import Foundation

// MARK: - List Convos

struct ListConvosResponse: Decodable {
    let cursor: String?
    let convos: [ConvoViewDTO]
}

struct ConvoViewDTO: Decodable {
    let id: String
    let rev: String
    let members: [ChatMemberProfileDTO]
    let lastMessage: LastMessageUnion?
    let muted: Bool
    let status: String?
    let unreadCount: Int
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

struct DirectConvoDTO: Decodable {}

struct GroupConvoDTO: Decodable {
    let name: String?
    let memberCount: Int?
    let createdAt: String?
    let lockStatus: String?
}

struct ChatMemberProfileDTO: Decodable {
    let did: String
    let handle: String?
    let displayName: String?
    let avatar: String?
}

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

struct GetMessagesResponse: Decodable {
    let cursor: String?
    let messages: [MessageUnionDTO]
    let relatedProfiles: [ChatMemberProfileDTO]?
}

struct MessageUnionDTO: Decodable {
    let messageView: MessageViewDTO?
    let deletedMessageView: DeletedMessageViewDTO?
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

struct MessageViewDTO: Decodable {
    let id: String?
    let rev: String?
    let text: String?
    let sender: MessageViewSenderDTO?
    let sentAt: String?
    let reactions: [ReactionViewDTO]?
}

struct DeletedMessageViewDTO: Decodable {
    let id: String?
    let rev: String?
    let sender: MessageViewSenderDTO?
    let sentAt: String?
}

struct SystemMessageViewDTO: Decodable {
    let id: String?
    let rev: String?
    let sentAt: String?
    let data: SystemMessageDataUnion?
}

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

struct UpdateReadRequest: Encodable {
    let convoId: String
    let messageId: String?
}

struct UpdateReadResponse: Decodable {
    let convo: ConvoViewDTO
}

// MARK: - Leave Convo

struct LeaveConvoRequest: Encodable {
    let convoId: String
}

struct LeaveConvoResponse: Decodable {
    let convoId: String
    let rev: String
}

// MARK: - Mute/Unmute

struct MuteConvoRequest: Encodable {
    let convoId: String
}

struct MuteConvoResponse: Decodable {
    let convo: ConvoViewDTO
}

// MARK: - Get Log

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

struct GetConvoForMembersRequest: Encodable {
    let members: [String]
}

struct GetConvoResponse: Decodable {
    let convo: ConvoViewDTO
}
