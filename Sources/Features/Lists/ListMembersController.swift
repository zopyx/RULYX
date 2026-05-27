import Foundation

// MARK: - ListMembersController

/// Manages paginated fetching of list members with deduplication and cursor tracking.
@MainActor
final class ListMembersController {
    private(set) var cursor: String?
    private(set) var hasMore = false

    /// Loads the first page of members, resetting cursor state.
    func loadMembers(
        for list: BlueskyList,
        account: AppAccount,
        appPassword: String,
        using client: LiveBlueskyClient
    ) async throws -> [BlueskyListMember] {
        cursor = nil
        hasMore = false
        let page = try await client.fetchListMembersPage(
            list: list,
            cursor: nil,
            account: account,
            appPassword: appPassword
        )
        cursor = page.cursor
        hasMore = page.cursor != nil
        return deduplicatedMembers(page.members)
    }

    /// Loads the next page of members using the stored cursor.
    func loadMoreMembers(
        for list: BlueskyList,
        account: AppAccount,
        appPassword: String,
        using client: LiveBlueskyClient
    ) async throws -> [BlueskyListMember] {
        guard hasMore, let currentCursor = cursor else {
            return []
        }
        let page = try await client.fetchListMembersPage(
            list: list,
            cursor: currentCursor,
            account: account,
            appPassword: appPassword
        )
        cursor = page.cursor
        hasMore = page.cursor != nil
        return deduplicatedMembers(page.members)
    }

    /// Resets cursor and hasMore to initial state.
    func reset() {
        cursor = nil
        hasMore = false
    }

    /// Removes duplicate members by ID, keeping the first occurrence.
    private func deduplicatedMembers(_ members: [BlueskyListMember]) -> [BlueskyListMember] {
        var deduplicated: [BlueskyListMember] = []
        var seen: Set<String> = []

        for member in members where seen.insert(member.id).inserted {
            deduplicated.append(member)
        }

        return deduplicated
    }
}
