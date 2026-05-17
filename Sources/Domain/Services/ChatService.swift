import Foundation

private let chatProxyHeader = "did:web:api.bsky.chat#bsky_chat"

@MainActor
final class ChatService: ChatServicing {
    private let sessionService: BlueskySessionServicing

    init(requestExecutor _: BlueskyRequestExecuting, sessionService: BlueskySessionServicing) {
        self.sessionService = sessionService
    }

    // MARK: - Conversations

    func listConvos(account: AppAccount, appPassword: String?, status: String? = nil, cursor: String? = nil) async throws -> PagedConvos {
        var queryItems = [URLQueryItem(name: "limit", value: "50")]
        if let cursor { queryItems.append(URLQueryItem(name: "cursor", value: cursor)) }
        if let status { queryItems.append(URLQueryItem(name: "status", value: status)) }

        let response: ListConvosResponse = try await chatRequest(
            path: "chat.bsky.convo.listConvos",
            method: "GET",
            queryItems: queryItems,
            account: account,
            appPassword: appPassword
        )

        return PagedConvos(
            conversations: response.convos.map { $0.toDomain() },
            cursor: response.cursor
        )
    }

    func getConvo(convoId: String, account: AppAccount, appPassword: String?) async throws -> ChatConversation {
        let response: GetConvoResponse = try await chatRequest(
            path: "chat.bsky.convo.getConvo",
            method: "GET",
            queryItems: [URLQueryItem(name: "convoId", value: convoId)],
            account: account,
            appPassword: appPassword
        )
        return response.convo.toDomain()
    }

    func getConvoForMembers(members: [String], account: AppAccount, appPassword: String?) async throws -> ChatConversation {
        let response: GetConvoResponse = try await chatRequest(
            path: "chat.bsky.convo.getConvoForMembers",
            method: "GET",
            queryItems: members.map { URLQueryItem(name: "members", value: $0) },
            account: account,
            appPassword: appPassword
        )
        return response.convo.toDomain()
    }

    // MARK: - Messages

    func getMessages(convoId: String, cursor: String? = nil, limit: Int = 50, account: AppAccount, appPassword: String?) async throws -> PagedMessages {
        var queryItems = [
            URLQueryItem(name: "convoId", value: convoId),
            URLQueryItem(name: "limit", value: "\(limit)"),
        ]
        if let cursor { queryItems.append(URLQueryItem(name: "cursor", value: cursor)) }

        let response: GetMessagesResponse = try await chatRequest(
            path: "chat.bsky.convo.getMessages",
            method: "GET",
            queryItems: queryItems,
            account: account,
            appPassword: appPassword
        )

        return PagedMessages(
            messages: response.messages.compactMap { $0.toDomain() },
            cursor: response.cursor
        )
    }

    func sendMessage(convoId: String, text: String, account: AppAccount, appPassword: String?) async throws -> ChatMessageSendResult {
        let body = SendMessageRequest(convoId: convoId, message: MessageInputDTO(text: text))
        let response: SendMessageResponse = try await chatRequest(
            path: "chat.bsky.convo.sendMessage",
            method: "POST",
            queryItems: [],
            body: body,
            account: account,
            appPassword: appPassword
        )

        return ChatMessageSendResult(
            id: response.id,
            rev: response.rev,
            text: response.text,
            senderDID: response.sender.did,
            sentAt: parseDate(response.sentAt) ?? .now
        )
    }

    // MARK: - Actions

    func updateRead(convoId: String, messageId: String?, account: AppAccount, appPassword: String?) async throws {
        let body = UpdateReadRequest(convoId: convoId, messageId: messageId)
        let _: UpdateReadResponse = try await chatRequest(
            path: "chat.bsky.convo.updateRead",
            method: "POST",
            queryItems: [],
            body: body,
            account: account,
            appPassword: appPassword
        )
    }

    func leaveConvo(convoId: String, account: AppAccount, appPassword: String?) async throws {
        let body = LeaveConvoRequest(convoId: convoId)
        let _: LeaveConvoResponse = try await chatRequest(
            path: "chat.bsky.convo.leaveConvo",
            method: "POST",
            queryItems: [],
            body: body,
            account: account,
            appPassword: appPassword
        )
    }

    func muteConvo(convoId: String, account: AppAccount, appPassword: String?) async throws {
        let body = MuteConvoRequest(convoId: convoId)
        let _: MuteConvoResponse = try await chatRequest(
            path: "chat.bsky.convo.muteConvo",
            method: "POST",
            queryItems: [],
            body: body,
            account: account,
            appPassword: appPassword
        )
    }

    func unmuteConvo(convoId: String, account: AppAccount, appPassword: String?) async throws {
        let body = MuteConvoRequest(convoId: convoId)
        let _: MuteConvoResponse = try await chatRequest(
            path: "chat.bsky.convo.unmuteConvo",
            method: "POST",
            queryItems: [],
            body: body,
            account: account,
            appPassword: appPassword
        )
    }

    // MARK: - Log

    func getLog(cursor: String?, account: AppAccount, appPassword: String?) async throws -> (events: [ChatLogEvent], cursor: String?) {
        var queryItems: [URLQueryItem] = []
        if let cursor { queryItems.append(URLQueryItem(name: "cursor", value: cursor)) }

        let response: GetLogResponse = try await chatRequest(
            path: "chat.bsky.convo.getLog",
            method: "GET",
            queryItems: queryItems,
            account: account,
            appPassword: appPassword
        )

        let events = response.logs.compactMap { $0.toDomain() }
        return (events, response.cursor)
    }

    // MARK: - Chat HTTP Helper

    private func chatRequest<Response: Decodable>(
        path: String,
        method: String,
        queryItems: [URLQueryItem],
        account: AppAccount,
        appPassword: String?
    ) async throws -> Response {
        try await performChatRequest(path: path, method: method, queryItems: queryItems, body: String?.none, account: account, appPassword: appPassword)
    }

    private func chatRequest<Response: Decodable>(
        path: String,
        method: String,
        queryItems: [URLQueryItem],
        body: some Encodable,
        account: AppAccount,
        appPassword: String?
    ) async throws -> Response {
        try await performChatRequest(path: path, method: method, queryItems: queryItems, body: body, account: account, appPassword: appPassword)
    }

    private func performChatRequest<Response: Decodable>(
        path: String,
        method: String,
        queryItems: [URLQueryItem],
        body: (some Encodable)?,
        account: AppAccount,
        appPassword: String?
    ) async throws -> Response {
        try await sessionService.performAuthenticatedRequest(account: account, appPassword: appPassword) { authSession in
            guard var components = URLComponents(url: authSession.pdsURL.appendingPathComponent("xrpc/\(path)"), resolvingAgainstBaseURL: false) else {
                throw BlueskyAPIError.invalidURL
            }
            if !queryItems.isEmpty {
                components.queryItems = queryItems
            }
            guard let url = components.url else {
                throw BlueskyAPIError.invalidURL
            }

            var request = URLRequest(url: url)
            request.httpMethod = method
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue(UserAgentProvider.random, forHTTPHeaderField: "User-Agent")
            request.setValue("Bearer \(authSession.accessJWT)", forHTTPHeaderField: "Authorization")
            request.setValue(chatProxyHeader, forHTTPHeaderField: "atproto-proxy")

            if let body {
                request.httpBody = try JSONEncoder().encode(body)
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            }

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw BlueskyAPIError.invalidResponse
            }

            guard (200 ..< 300).contains(httpResponse.statusCode) else {
                if let errorPayload = try? JSONDecoder().decode(APIErrorPayload.self, from: data) {
                    let errorCode = errorPayload.error ?? ""
                    let isAuthError = httpResponse.statusCode == 401
                        || errorCode.lowercased().contains("token")
                        || errorCode.lowercased().contains("auth")
                        || errorCode.lowercased().contains("unauthorized")
                    if isAuthError {
                        throw BlueskyAPIError.unauthorized
                    }
                    throw BlueskyAPIError.server(errorPayload.message ?? errorCode)
                }
                throw BlueskyAPIError.invalidResponse
            }

            let decodedData = data.isEmpty ? Data("{}".utf8) : data
            return try JSONDecoder().decode(Response.self, from: decodedData)
        }
    }
}

// MARK: - DTO to Domain Mapping

private extension ConvoViewDTO {
    func toDomain() -> ChatConversation {
        let memberProfiles = members.map { $0.toDomain() }
        let groupInfo: ChatGroupInfo? = if let group = kind?.group {
            ChatGroupInfo(
                name: group.name ?? "",
                memberCount: group.memberCount ?? 0,
                createdAt: parseDate(group.createdAt ?? "") ?? .now,
                lockStatus: group.lockStatus ?? "unlocked"
            )
        } else {
            nil
        }

        return ChatConversation(
            id: id,
            rev: rev,
            members: memberProfiles,
            lastMessage: lastMessage?.toDomain(),
            muted: muted,
            status: ChatConversationStatus(rawValue: status ?? ""),
            unreadCount: unreadCount,
            kind: kind?.group != nil ? .group : .direct,
            groupInfo: groupInfo
        )
    }
}

private extension LastMessageUnion {
    func toDomain() -> ChatMessageKind? {
        if let msg = message, let id = msg.id {
            return .message(ChatMessage(
                id: id,
                rev: msg.rev ?? "",
                text: msg.text ?? "",
                senderDID: msg.sender?.did ?? "",
                sentAt: parseDate(msg.sentAt ?? "") ?? .now,
                reactions: msg.reactions?.map { $0.toDomain() } ?? []
            ))
        }
        if let del = deleted, let id = del.id {
            return .deleted(ChatDeletedMessage(
                id: id,
                rev: del.rev ?? "",
                senderDID: del.sender?.did ?? "",
                sentAt: parseDate(del.sentAt ?? "") ?? .now
            ))
        }
        if let sys = system, let id = sys.id {
            return .system(ChatSystemMessage(
                id: id,
                rev: sys.rev ?? "",
                sentAt: parseDate(sys.sentAt ?? "") ?? .now,
                data: sys.data?.toDomain() ?? .unknown
            ))
        }
        return nil
    }
}

private extension ChatMemberProfileDTO {
    func toDomain() -> ChatMemberProfile {
        ChatMemberProfile(
            did: did,
            handle: handle ?? "",
            displayName: displayName,
            avatarURL: avatar.flatMap { URL(string: $0) }
        )
    }
}

private extension ReactionViewDTO {
    func toDomain() -> ChatReaction {
        ChatReaction(
            value: value,
            senderDID: sender.did,
            createdAt: parseDate(createdAt) ?? .now
        )
    }
}

private extension MessageUnionDTO {
    func toDomain() -> ChatMessageKind? {
        if let msg = messageView, let id = msg.id {
            return .message(ChatMessage(
                id: id,
                rev: msg.rev ?? "",
                text: msg.text ?? "",
                senderDID: msg.sender?.did ?? "",
                sentAt: parseDate(msg.sentAt ?? "") ?? .now,
                reactions: msg.reactions?.map { $0.toDomain() } ?? []
            ))
        }
        if let del = deletedMessageView, let id = del.id {
            return .deleted(ChatDeletedMessage(
                id: id,
                rev: del.rev ?? "",
                senderDID: del.sender?.did ?? "",
                sentAt: parseDate(del.sentAt ?? "") ?? .now
            ))
        }
        if let sys = systemMessageView, let id = sys.id {
            return .system(ChatSystemMessage(
                id: id,
                rev: sys.rev ?? "",
                sentAt: parseDate(sys.sentAt ?? "") ?? .now,
                data: sys.data?.toDomain() ?? .unknown
            ))
        }
        return nil
    }
}

private extension SystemMessageDataUnion {
    func toDomain() -> ChatSystemMessageData {
        if member != nil, addedBy != nil {
            return .addMember(memberDID: member?.did ?? "", addedByDID: addedBy?.did ?? "")
        }
        if member != nil, removedBy != nil {
            return .removeMember(memberDID: member?.did ?? "", removedByDID: removedBy?.did ?? "")
        }
        if member != nil {
            return .memberJoin(memberDID: member?.did ?? "")
        }
        if newName != nil {
            return .editGroup(oldName: oldName, newName: newName)
        }
        return .unknown
    }
}

private extension LogEventUnionDTO {
    func toDomain() -> ChatLogEvent? {
        if let v = beginConvo, let rev = v.rev, let convoId = v.convoId {
            return ChatLogEvent(rev: rev, kind: .beginConvo(convoId: convoId))
        }
        if let v = acceptConvo, let rev = v.rev, let convoId = v.convoId {
            return ChatLogEvent(rev: rev, kind: .acceptConvo(convoId: convoId))
        }
        if let v = leaveConvo, let rev = v.rev, let convoId = v.convoId {
            return ChatLogEvent(rev: rev, kind: .leaveConvo(convoId: convoId))
        }
        if let v = muteConvo, let rev = v.rev, let convoId = v.convoId {
            return ChatLogEvent(rev: rev, kind: .muteConvo(convoId: convoId))
        }
        if let v = unmuteConvo, let rev = v.rev, let convoId = v.convoId {
            return ChatLogEvent(rev: rev, kind: .unmuteConvo(convoId: convoId))
        }
        if let v = createMessage, let rev = v.rev, let convoId = v.convoId, let msg = v.message?.toDomain() {
            if case let .message(m) = msg {
                return ChatLogEvent(rev: rev, kind: .createMessage(convoId: convoId, message: m))
            }
        }
        if let v = deleteMessage, let rev = v.rev, let convoId = v.convoId, let msg = v.message?.toDomain() {
            if case let .deleted(d) = msg {
                return ChatLogEvent(rev: rev, kind: .deleteMessage(convoId: convoId, message: d))
            }
        }
        if let v = addReaction, let rev = v.rev, let convoId = v.convoId, let reaction = v.reaction?.toDomain(), let messageId = extractMessageID(v.message) {
            return ChatLogEvent(rev: rev, kind: .addReaction(convoId: convoId, messageId: messageId, reaction: reaction))
        }
        if let v = removeReaction, let rev = v.rev, let convoId = v.convoId, let reaction = v.reaction?.toDomain(), let messageId = extractMessageID(v.message) {
            return ChatLogEvent(rev: rev, kind: .removeReaction(convoId: convoId, messageId: messageId, reaction: reaction))
        }
        if let v = readConvo, let rev = v.rev, let convoId = v.convoId {
            return ChatLogEvent(rev: rev, kind: .readConvo(convoId: convoId, messageId: ""))
        }
        if let v = addMember, let rev = v.rev, let convoId = v.convoId, let msg = v.message?.toDomain() {
            if case let .system(s) = msg, case let .addMember(memberDID, _) = s.data {
                return ChatLogEvent(rev: rev, kind: .addMember(convoId: convoId, memberDID: memberDID))
            }
        }
        if let v = removeMember, let rev = v.rev, let convoId = v.convoId, let msg = v.message?.toDomain() {
            if case let .system(s) = msg, case let .removeMember(memberDID, _) = s.data {
                return ChatLogEvent(rev: rev, kind: .removeMember(convoId: convoId, memberDID: memberDID))
            }
        }
        return nil
    }
}

// MARK: - Helpers

private func parseDate(_ string: String) -> Date? {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = formatter.date(from: string) { return date }
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: string)
}

private func extractMessageID(_ union: LastMessageUnion?) -> String? {
    guard let kind = union?.toDomain() else { return nil }
    let id: String = switch kind {
    case let .message(m): m.id
    case let .deleted(d): d.id
    case let .system(s): s.id
    }
    return id
}
