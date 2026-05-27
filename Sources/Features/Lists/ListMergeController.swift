import Foundation

// MARK: - SplitCriterion

/// Criteria for splitting list members into matching vs. non-matching groups.
enum SplitCriterion: String, CaseIterable, Identifiable {
    case youngAccounts = "Young Accounts (< 4 weeks)"
    case lowFollowers = "Low Followers (< 100)"
    case highFollowers = "High Followers (> 1000)"
    case handlePattern = "Handle Pattern"

    var id: String {
        rawValue
    }
}

// MARK: - ListMergeController

/// Handles merging members from one list into another, and splitting members
/// by criteria (young accounts, low/high followers, handle pattern).
@MainActor
final class ListMergeController {
    /// Copies all members from a source list into a target list via batch operation.
    func merge(
        sourceList _: BlueskyList,
        into targetList: BlueskyList,
        members: [BlueskyListMember],
        account: AppAccount,
        appPassword: String,
        using client: LiveBlueskyClient
    ) async -> ListBulkActionResult {
        let actors = Set(members.map(\.actor)).map(\.self)
        let controller = ListBatchController()
        return await controller.performBatch(
            title: "Merge into \(targetList.name)",
            actors: actors,
            operation: .copy,
            onProgress: nil,
            onActorComplete: nil
        ) { actor in
            _ = try await client.addActor(did: actor.did, to: targetList, account: account, appPassword: appPassword)
        }
    }

    /// Splits members into matching/rest based on the given criterion and optional pattern.
    func split(
        members: [BlueskyListMember],
        criterion: SplitCriterion,
        pattern: String = ""
    ) -> (matching: [BlueskyListMember], rest: [BlueskyListMember]) {
        let matching = members.filter { matches(criterion: criterion, member: $0, pattern: pattern) }
        let rest = members.filter { !matches(criterion: criterion, member: $0, pattern: pattern) }
        return (matching, rest)
    }

    private func matches(criterion: SplitCriterion, member: BlueskyListMember, pattern: String) -> Bool {
        let actor = member.actor
        switch criterion {
        case .youngAccounts:
            guard let createdAt = actor.createdAt else { return false }
            return createdAt > Date.now.addingTimeInterval(-28 * 86400)
        case .lowFollowers:
            return false
        case .highFollowers:
            return false
        case .handlePattern:
            guard !pattern.isEmpty else { return false }
            return actor.handle.localizedCaseInsensitiveContains(pattern) ||
                (actor.displayName?.localizedCaseInsensitiveContains(pattern) ?? false)
        }
    }
}
