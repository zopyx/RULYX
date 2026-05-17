import Foundation

@MainActor
protocol BlueskyListServicing {
    func fetchLists(for account: AppAccount, appPassword: String?) async throws -> [BlueskyList]
    func fetchList(uri: String, account: AppAccount, appPassword: String?) async throws -> BlueskyList?
    func fetchListMembers(list: BlueskyList, account: AppAccount, appPassword: String?) async throws -> [BlueskyListMember]
    func fetchListMembersPage(list: BlueskyList, cursor: String?, account: AppAccount, appPassword: String?) async throws -> PagedListMembers
    func addActor(did actorDID: String, to list: BlueskyList, account: AppAccount, appPassword: String?) async throws -> String
    func removeMember(recordURI: String, account: AppAccount, appPassword: String?) async throws
    func updateListMetadata(list: BlueskyList, title: String, description: String, account: AppAccount, appPassword: String?) async throws -> BlueskyList
    func createList(name: String, description: String, kind: BlueskyList.Kind, account: AppAccount, appPassword: String?) async throws -> BlueskyList
    func deleteList(list: BlueskyList, account: AppAccount, appPassword: String?) async throws
}
