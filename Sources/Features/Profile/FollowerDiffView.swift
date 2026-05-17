import SwiftUI

struct FollowerDiffView: View {
    @EnvironmentObject private var accountStore: AccountStore
    @EnvironmentObject private var blueskyClient: LiveBlueskyClient
    @State private var followers: [BlueskyActor] = []
    @State private var previousFollowers: [BlueskyActor] = []
    @State private var isLoading = false
    @State private var statusMessage: String?

    private var newFollowers: [BlueskyActor] {
        let prev = Set(previousFollowers.map(\.did))
        return followers.filter { !prev.contains($0.did) }
    }

    private var unfollowed: [BlueskyActor] {
        let curr = Set(followers.map(\.did))
        return previousFollowers.filter { !curr.contains($0.did) }
    }

    var body: some View {
        List {
            if isLoading {
                Section {
                    SkeletonRow()
                    SkeletonRow()
                    SkeletonRow()
                }
            }

            if !newFollowers.isEmpty {
                Section {
                    ForEach(newFollowers) { actor in
                        Label(actor.handle, systemImage: "person.fill.badge.plus").foregroundStyle(.green)
                    }
                } header: {
                    Text(verbatim: loc("follower_diff.new").replacingOccurrences(of: "{count}", with: "\(newFollowers.count)"))
                }
            }

            if !unfollowed.isEmpty {
                Section {
                    ForEach(unfollowed) { actor in
                        Label(actor.handle, systemImage: "person.fill.badge.minus").foregroundStyle(.red)
                    }
                } header: {
                    Text(verbatim: loc("follower_diff.unfollowed").replacingOccurrences(of: "{count}", with: "\(unfollowed.count)"))
                }
            }

            if !isLoading, newFollowers.isEmpty, unfollowed.isEmpty, !followers.isEmpty {
                ContentUnavailableView(loc("follower_diff.no_changes"), systemImage: "person.3", description: Text(loc("follower_diff.no_changes_desc")))
            }

            if let statusMessage {
                Text(statusMessage).font(.caption).foregroundStyle(.secondary)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(loc("follower_diff.title"))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(loc("follower_diff.refresh")) { Task { await load() } }
                    .disabled(isLoading)
                    .accessibilityHint(loc("follower_diff.refresh.hint"))
            }
        }
        .task { await load() }
    }

    private func load() async {
        guard let account = accountStore.activeAccount,
              let appPassword = accountStore.appPassword(for: account) else { return }
        isLoading = true
        statusMessage = nil
        let did = account.did ?? account.handle

        let cacheKey = "followers_diff_\(did)"
        previousFollowers = RelationshipCache.load(forKey: cacheKey)

        do {
            followers = try await blueskyClient.fetchFollowers(actor: did, account: account, appPassword: appPassword)
            RelationshipCache.save(followers, forKey: cacheKey)
            statusMessage = previousFollowers.isEmpty ? loc("follower_diff.baseline") : nil
        } catch {
            if !previousFollowers.isEmpty { followers = previousFollowers }
            statusMessage = AppError.userMessage(from: error)
        }
        isLoading = false
    }
}

#Preview {
    NavigationStack { FollowerDiffView().environmentObject(AccountStore(preview: true)).environmentObject(PreviewBlueskyClient()) }
}
