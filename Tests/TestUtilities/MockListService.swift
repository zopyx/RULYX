import Foundation
@testable import RULYX

/// Mock implementation of BlueskyListServicing for unit testing.
/// Uses class semantics so handlers can be overridden after VM construction.
@MainActor
final class MockListService: BlueskyListServicing {
    var fetchListsHandler: @Sendable (AppAccount, String?) async throws -> [BlueskyList] = { _, _ in [] }
    var fetchListHandler: @Sendable (String, AppAccount, String?) async throws -> BlueskyList? = { _, _, _ in nil }
    var fetchListMembersHandler: @Sendable (BlueskyList, AppAccount, String?) async throws -> [BlueskyListMember] = { _, _, _ in [] }
    var fetchListMembersPageHandler: @Sendable (BlueskyList, String?, AppAccount, String?) async throws -> PagedListMembers = { _, _, _, _ in PagedListMembers(members: [], cursor: nil) }
    var addActorHandler: @Sendable (String, BlueskyList, AppAccount, String?) async throws -> String = { did, _, _, _ in "at://record/\(did)/1" }
    var removeMemberHandler: @Sendable (String, AppAccount, String?) async throws -> Void = { _, _, _ in }
    var updateListMetadataHandler: @Sendable (BlueskyList, String, String, AppAccount, String?) async throws -> BlueskyList = { list, title, desc, _, _ in
        BlueskyList(id: list.id, name: title, description: desc, memberCount: list.memberCount, kind: list.kind)
    }

    var createListHandler: @Sendable (String, String, BlueskyList.Kind, AppAccount, String?) async throws -> BlueskyList = { name, desc, kind, _, _ in
        BlueskyList(id: "at://list/new", name: name, description: desc, memberCount: 0, kind: kind)
    }

    var deleteListHandler: @Sendable (BlueskyList, AppAccount, String?) async throws -> Void = { _, _, _ in }
    var reportListHandler: @Sendable (BlueskyList, String?, AppAccount, String?) async throws -> Void = { _, _, _, _ in }
    var reportListTypedHandler: @Sendable (BlueskyList, ModerationReportReasonType?, String?, AppAccount, String?) async throws -> Void = { _, _, _, _, _ in }

    func fetchLists(for account: AppAccount, appPassword: String?) async throws -> [BlueskyList] {
        try await fetchListsHandler(account, appPassword)
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

    func addActor(did actorDID: String, to list: BlueskyList, account: AppAccount, appPassword: String?) async throws -> String {
        try await addActorHandler(actorDID, list, account, appPassword)
    }

    func removeMember(recordURI: String, account: AppAccount, appPassword: String?) async throws {
        try await removeMemberHandler(recordURI, account, appPassword)
    }

    func updateListMetadata(list: BlueskyList, title: String, description: String, account: AppAccount, appPassword: String?) async throws -> BlueskyList {
        try await updateListMetadataHandler(list, title, description, account, appPassword)
    }

    func createList(name: String, description: String, kind: BlueskyList.Kind, account: AppAccount, appPassword: String?) async throws -> BlueskyList {
        try await createListHandler(name, description, kind, account, appPassword)
    }

    func deleteList(list: BlueskyList, account: AppAccount, appPassword: String?) async throws {
        try await deleteListHandler(list, account, appPassword)
    }

    func reportList(_ list: BlueskyList, reason: String?, account: AppAccount, appPassword: String?) async throws {
        try await reportListHandler(list, reason, account, appPassword)
    }

    func reportList(_ list: BlueskyList, selectedReason: ModerationReportReasonType?, reason: String?, account: AppAccount, appPassword: String?) async throws {
        try await reportListTypedHandler(list, selectedReason, reason, account, appPassword)
    }

    func fetchActorLists(actor _: String, account: AppAccount, appPassword: String?) async throws -> [BlueskyList] {
        try await fetchLists(for: account, appPassword: appPassword)
    }

    func fetchListDetails(uri: String, account: AppAccount, appPassword: String?) async throws -> (list: BlueskyList, creator: BlueskyActor) {
        guard let list = try await fetchList(uri: uri, account: account, appPassword: appPassword) else {
            throw BlueskyAPIError.invalidResponse
        }
        return (list, BlueskyActor(did: "did:plc:creator", handle: "creator.bsky.social"))
    }

    func fetchSubscribedModerationLists(account _: AppAccount, appPassword _: String?) async throws -> [SubscribedListInfo] {
        []
    }

    func isSubscribedToModerationList(_: String, account _: AppAccount, appPassword _: String?) async throws -> Bool {
        false
    }

    func subscribeToModerationList(_: String, account _: AppAccount, appPassword _: String?) async throws {}

    func unsubscribeFromModerationList(_: String, account _: AppAccount, appPassword _: String?) async throws {}
}
