import Foundation

@MainActor
protocol ChatServicing {
    func listConvos(account: AppAccount, appPassword: String?, status: String?, cursor: String?) async throws -> PagedConvos
    func getConvo(convoId: String, account: AppAccount, appPassword: String?) async throws -> ChatConversation
    func getConvoForMembers(members: [String], account: AppAccount, appPassword: String?) async throws -> ChatConversation
    func getMessages(convoId: String, cursor: String?, limit: Int, account: AppAccount, appPassword: String?) async throws -> PagedMessages
    func sendMessage(convoId: String, text: String, account: AppAccount, appPassword: String?) async throws -> ChatMessageSendResult
    func updateRead(convoId: String, messageId: String?, account: AppAccount, appPassword: String?) async throws
    func leaveConvo(convoId: String, account: AppAccount, appPassword: String?) async throws
    func muteConvo(convoId: String, account: AppAccount, appPassword: String?) async throws
    func unmuteConvo(convoId: String, account: AppAccount, appPassword: String?) async throws
    func getLog(cursor: String?, account: AppAccount, appPassword: String?) async throws -> (events: [ChatLogEvent], cursor: String?)
}
