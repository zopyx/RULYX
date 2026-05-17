import Foundation

@MainActor
final class MockBlueskyListService: BlueskyListServicing {
    nonisolated static let previewActors = [
        BlueskyActor(did: "did:plc:1", handle: "alice.bsky.social", displayName: "Alice Chen"),
        BlueskyActor(did: "did:plc:2", handle: "moderator.bsky.social", displayName: "Moderator Desk"),
        BlueskyActor(did: "did:plc:3", handle: "safetylab.bsky.social", displayName: "Safety Lab"),
        BlueskyActor(did: "did:plc:4", handle: "bskynews.bsky.social", displayName: "Bluesky News"),
        BlueskyActor(did: "did:plc:5", handle: "curation.team", displayName: "Curation Team"),
        BlueskyActor(did: "did:plc:6", handle: "reports.ops", displayName: "Reports Ops"),
    ]

    func fetchLists(for account: AppAccount, appPassword _: String?) async throws -> [BlueskyList] {
        try await Task.sleep(for: .milliseconds(150))

        let seed = abs(account.handle.hashValue)
        let regularBase = 2 + (seed % 4)
        let moderationBase = 1 + (seed % 3)

        return [
            BlueskyList(id: "\(account.handle)-mod-1", name: "Spam Watch", description: "Accounts frequently reported for spam patterns.", memberCount: 120 + moderationBase, kind: .moderation),
            BlueskyList(id: "\(account.handle)-mod-2", name: "Reply Filters", description: "Aggressive reply actors tracked for moderation review.", memberCount: 42 + moderationBase, kind: .moderation),
            BlueskyList(id: "\(account.handle)-list-1", name: "Trusted Sources", description: "Accounts curated for signal over noise.", memberCount: 65 + regularBase, kind: .regular),
            BlueskyList(id: "\(account.handle)-list-2", name: "Community Core", description: "People to monitor for community health updates.", memberCount: 18 + regularBase, kind: .regular),
            BlueskyList(id: "\(account.handle)-list-3", name: "New Reports", description: "Freshly observed accounts pending deeper review.", memberCount: 7 + regularBase, kind: .regular),
        ]
    }

    func fetchList(uri: String, account: AppAccount, appPassword: String?) async throws -> BlueskyList? {
        try await fetchLists(for: account, appPassword: appPassword).first { $0.id == uri }
    }

    func fetchListMembers(list: BlueskyList, account: AppAccount, appPassword: String?) async throws -> [BlueskyListMember] {
        var cursor: String?
        var allMembers: [BlueskyListMember] = []

        repeat {
            let page = try await fetchListMembersPage(list: list, cursor: cursor, account: account, appPassword: appPassword)
            allMembers.append(contentsOf: page.members)
            cursor = page.cursor
        } while cursor != nil

        return allMembers
    }

    func fetchListMembersPage(list: BlueskyList, cursor: String?, account _: AppAccount, appPassword _: String?) async throws -> PagedListMembers {
        try await Task.sleep(for: .milliseconds(120))

        let members = previewMembers(for: list)
        let pageSize = 3
        let startIndex = Int(cursor ?? "0") ?? 0
        let endIndex = min(startIndex + pageSize, members.count)
        let nextCursor = endIndex < members.count ? String(endIndex) : nil

        return PagedListMembers(members: Array(members[startIndex ..< endIndex]), cursor: nextCursor)
    }

    func addActor(did actorDID: String, to _: BlueskyList, account _: AppAccount, appPassword _: String?) async throws -> String {
        try await Task.sleep(for: .milliseconds(100))
        return "at://\(actorDID)/app.bsky.graph.listitem/\(UUID().uuidString)"
    }

    func removeMember(recordURI _: String, account _: AppAccount, appPassword _: String?) async throws {
        try await Task.sleep(for: .milliseconds(100))
    }

    func createList(name: String, description: String, kind: BlueskyList.Kind, account _: AppAccount, appPassword _: String?) async throws -> BlueskyList {
        try await Task.sleep(for: .milliseconds(100))
        let id = "at://did:plc:preview/app.bsky.graph.list/\(UUID().uuidString)"
        return BlueskyList(id: id, name: name, description: description, memberCount: 0, kind: kind)
    }

    func deleteList(list _: BlueskyList, account _: AppAccount, appPassword _: String?) async throws {
        try await Task.sleep(for: .milliseconds(100))
    }

    func updateListMetadata(list: BlueskyList, title: String, description: String, account _: AppAccount, appPassword _: String?) async throws -> BlueskyList {
        try await Task.sleep(for: .milliseconds(120))
        return BlueskyList(id: list.id, name: title, description: description, memberCount: list.memberCount, kind: list.kind)
    }

    private func previewMembers(for list: BlueskyList) -> [BlueskyListMember] {
        let now = Date()
        return Self.previewActors.enumerated().map { index, actor in
            BlueskyListMember(
                recordURI: "at://did:plc:preview/\(list.id)/app.bsky.graph.listitem/\(index + 1)",
                actor: actor,
                createdAt: now.addingTimeInterval(-Double(index) * 86400 * 7)
            )
        }
    }
}
