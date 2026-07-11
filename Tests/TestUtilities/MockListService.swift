@testable import RULYX
import Foundation

/// Mock implementation of BlueskyListServicing for unit testing.
@MainActor
struct MockListService: BlueskyListServicing {
    var fetchListsHandler: @Sendable (AppAccount, String?) async throws -> [BlueskyList] = { _, _ in [] }
    var fetchActorListsHandler: @Sendable (String, AppAccount, String?) async throws -> [BlueskyList] = { _, _, _ in [] }
    var fetchListHandler: @Sendable (String, AppAccount, String?) async throws -> BlueskyList? = { _, _, _ in nil }
    var fetchListMembersHandler: @Sendable (BlueskyList, AppAccount, String?) async throws -> [BlueskyListMember] = { _, _, _ in [] }
    var fetchListMembersPageHandler: @Sendable (BlueskyList, String?, AppAccount, String?) async throws -> PagedListMembers = { _, _, _, _ in PagedListMembers(members: [], cursor: nil) }
    var fetchListDetailsHandler: @Sendable (String, AppAccount, String?) async throws -> (list: BlueskyList, creator: BlueskyActor) = { uri, _, _ in
        let list = BlueskyList(id: uri, name: "Test", description: "", memberCount: nil, kind: .moderation)
        let actor = BlueskyActor(did: "did:plc:creator", handle: "creator.bsky.social")
        return (list, actor)
    }
    var fetchSubscribedModerationListsHandler: @Sendable (AppAccount, String?) async throws -> [SubscribedListInfo] = { _, _ in [] }
    var isSubscribedToModerationListHandler: @Sendable (String, AppAccount, String?) async throws -> Bool = { _, _, _ in false }
    var subscribeToModerationListHandler: @Sendable (String, AppAccount, String?) async throws -> Void = { _, _, _ in }
    var unsubscribeFromModerationListHandler: @Sendable (String, AppAccount, String?) async throws -> Void = { _, _, _ in }
    var addActorHandler: @Sendable (String, BlueskyList, AppAccount, String?) async throws -> String = { did, _, _, _ in "at://record/\(did)/1" }
    var removeMemberHandler: @Sendable (String, AppAccount, String?) async throws -> Void = { _, _, _ in }
    var createListHandler: @Sendable (String, String, BlueskyList.Kind, AppAccount, String?) async throws -> BlueskyList = { name, desc, kind, _, _ in
        BlueskyList(id: "at://list/new", name: name, description: desc, memberCount: 0, kind: kind)
    }
    var deleteListHandler: @Sendable (BlueskyList, AppAccount, String?) async throws -> Void = { _, _, _ in }
    var updateListMetadataHandler: @Sendable (BlueskyList, String, String, AppAccount, String?) async throws -> BlueskyList = { list, title, desc, _, _ in
        BlueskyList(id: list.id, name: title, description: desc, memberCount: list.memberCount, kind: list.kind)
    }

    func fetchLists(for account: AppAccount, appPassword: String?) async throws -> [BlueskyList] {
        try await fetchListsHandler(account, appPassword)
    }

    func fetchActorLists(actor: String, account: AppAccount, appPassword: String?) async throws -> [BlueskyList] {
        try await fetchActorListsHandler(actor, account, appPassword)
    }

    func fetchList(uri: String, account: AppAccount, appPassword: String?) async throws -> BlueskyList? {
        try await fetchListHandler(uri, account, appPassword)
    }

    func fetchListMembers(list: BlueskyList, account: AppAccount, appPassword: String?) async throws -> [BlueskyListMember] {
        try await fetchListMembersHandler(list, account, appPassword)
    }

    func fetchListMembersPage(list: BlueskyList, cursor: String?, account: AppAccount, appPassword: String?) async throws -> PagedListMembers {
        try await fetchListMembersPageHandler(list, cursor, account, appPassword)
    }

    func fetchListDetails(uri: String, account: AppAccount, appPassword: String?) async throws -> (list: BlueskyList, creator: BlueskyActor) {
        try await fetchListDetailsHandler(uri, account, appPassword)
    }

    func fetchSubscribedModerationLists(account: AppAccount, appPassword: String?) async throws -> [SubscribedListInfo] {
        try await fetchSubscribedModerationListsHandler(account, appPassword)
    }

    func isSubscribedToModerationList(_ listURI: String, account: AppAccount, appPassword: String?) async throws -> Bool {
        try await isSubscribedToModerationListHandler(listURI, account, appPassword)
    }

    func subscribeToModerationList(_ listURI: String, account: AppAccount, appPassword: String?) async throws {
        try await subscribeToModerationListHandler(listURI, account, appPassword)
    }

    func unsubscribeFromModerationList(_ listURI: String, account: AppAccount, appPassword: String?) async throws {
        try await unsubscribeFromModerationListHandler(listURI, account, appPassword)
    }

    func addActor(did actorDID: String, to list: BlueskyList, account: AppAccount, appPassword: String?) async throws -> String {
        try await addActorHandler(actorDID, list, account, appPassword)
    }

    func removeMember(recordURI: String, account: AppAccount, appPassword: String?) async throws {
        try await removeMemberHandler(recordURI, account, appPassword)
    }

    func createList(name: String, description: String, kind: BlueskyList.Kind, account: AppAccount, appPassword: String?) async throws -> BlueskyList {
        try await createListHandler(name, description, kind, account, appPassword)
    }

    func deleteList(list: BlueskyList, account: AppAccount, appPassword: String?) async throws {
        try await deleteListHandler(list, account, appPassword)
    }

    func updateListMetadata(list: BlueskyList, title: String, description: String, account: AppAccount, appPassword: String?) async throws -> BlueskyList {
        try await updateListMetadataHandler(list, title, description, account, appPassword)
    }
}
