import Foundation

enum ChatConversationKind: String {
    case direct
    case group
}

enum ChatConversationStatus: String {
    case request
    case accepted
}

enum ChatMessageKind {
    case message(ChatMessage)
    case deleted(ChatDeletedMessage)
    case system(ChatSystemMessage)
}

struct ChatConversation: Identifiable, Hashable {
    let id: String
    let rev: String
    let members: [ChatMemberProfile]
    let lastMessage: ChatMessageKind?
    let muted: Bool
    let status: ChatConversationStatus?
    let unreadCount: Int
    let kind: ChatConversationKind
    let groupInfo: ChatGroupInfo?

    var lastMessageAt: Date {
        guard let lastMessage else { return .distantPast }
        return switch lastMessage {
        case let .message(m): m.sentAt
        case let .deleted(d): d.sentAt
        case let .system(s): s.sentAt
        }
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: ChatConversation, rhs: ChatConversation) -> Bool {
        lhs.id == rhs.id && lhs.rev == rhs.rev
    }
}

struct ChatGroupInfo {
    let name: String
    let memberCount: Int
    let createdAt: Date
    let lockStatus: String
}

struct ChatMemberProfile: Identifiable {
    let did: String
    let handle: String
    let displayName: String?
    let avatarURL: URL?
    var id: String {
        did
    }
}

struct ChatMessage: Identifiable {
    let id: String
    let rev: String
    let text: String
    let senderDID: String
    let sentAt: Date
    let reactions: [ChatReaction]
}

struct ChatDeletedMessage: Identifiable {
    let id: String
    let rev: String
    let senderDID: String
    let sentAt: Date
}

struct ChatSystemMessage: Identifiable {
    let id: String
    let rev: String
    let sentAt: Date
    let data: ChatSystemMessageData
}

enum ChatSystemMessageData {
    case addMember(memberDID: String, addedByDID: String)
    case removeMember(memberDID: String, removedByDID: String)
    case memberJoin(memberDID: String)
    case memberLeave(memberDID: String)
    case lockConvo
    case unlockConvo
    case lockConvoPermanently
    case editGroup(oldName: String?, newName: String?)
    case unknown
}

struct ChatReaction {
    let value: String
    let senderDID: String
    let createdAt: Date
}

struct ChatMessageSendResult {
    let id: String
    let rev: String
    let text: String
    let senderDID: String
    let sentAt: Date
}

struct PagedMessages {
    let messages: [ChatMessageKind]
    let cursor: String?
}

struct PagedConvos {
    let conversations: [ChatConversation]
    let cursor: String?
}

struct ChatLogEvent {
    let rev: String
    let kind: ChatLogEventKind
}

enum ChatLogEventKind {
    case beginConvo(convoId: String)
    case acceptConvo(convoId: String)
    case leaveConvo(convoId: String)
    case muteConvo(convoId: String)
    case unmuteConvo(convoId: String)
    case createMessage(convoId: String, message: ChatMessage)
    case deleteMessage(convoId: String, message: ChatDeletedMessage)
    case addReaction(convoId: String, messageId: String, reaction: ChatReaction)
    case removeReaction(convoId: String, messageId: String, reaction: ChatReaction)
    case readConvo(convoId: String, messageId: String)
    case addMember(convoId: String, memberDID: String)
    case removeMember(convoId: String, memberDID: String)
}
