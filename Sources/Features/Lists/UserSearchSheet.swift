import SwiftUI

// MARK: - UserSearchSheet

/// Search sheet for finding Bluesky users by handle or display name,
/// with results linking to profile views and follow badges + double-tap.
struct UserSearchSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var accountStore: AccountStore
    @EnvironmentObject private var container: BlueskyServiceContainerWrapper
    @EnvironmentObject private var localizationManager: LocalizationManager

    @State private var searchQuery = ""
    @State private var results: [BlueskyActor] = []
    @State private var isSearching = false
    @State private var profileActor: BlueskyActor?
    @FocusState private var searchFocused: Bool

    // MARK: - Optimistic Follow State

    @State private var pendingFollowActions: Set<String> = []
    @State private var pendingUnfollowActions: Set<String> = []
    /// Follow record URIs captured from successful follow calls (needed for unfollow before next API reload).
    @State private var optimisticFollowRecordURIs: [String: String] = [:]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField(loc("usersearch.placeholder"), text: $searchQuery)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($searchFocused)
                }

                if results.isEmpty, !searchQuery.isEmpty, !isSearching {
                    ContentUnavailableView(
                        loc("usersearch.no_results"),
                        systemImage: "magnifyingglass",
                        description: Text(loc: "usersearch.no_results_desc")
                    )
                }

                ForEach(results) { actor in
                    HStack(spacing: 8) {
                        Button {
                            profileActor = actor
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                BlueskyActorRow(actor: actor)
                                MemberFollowBadgesView(viewerState: effectiveViewerState(for: actor))
                                    .padding(.leading, 46)
                            }
                        }
                        .buttonStyle(.plain)

                        Button {
                            Task { await toggleFollow(actor: actor) }
                        } label: {
                            Image(systemName: isFollowing(actor) ? "person.badge.minus" : "person.badge.plus")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(loc(isFollowing(actor) ? "profile.following" : "lists.following"))
                    }
                }

                if isSearching {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                }
            }
            .listStyle(.insetGrouped)
            .pageTitle(loc("usersearch.title"))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    ToolbarCloseButton()
                }
            }
            .navigationDestination(item: $profileActor) { actor in
                BlueskyProfileView(
                    member: BlueskyListMember(recordURI: "search:\(actor.did)", actor: actor),
                    list: nil
                )
                .environmentObject(accountStore)
                .environmentObject(container.blueskyClient)
            }
        }
        .onChange(of: searchQuery) { _, query in
            Task { await performSearch(query) }
        }
        .task {
            try? await Task.sleep(for: .milliseconds(300))
            searchFocused = true
        }
    }

    /// Searches for actors using the Bluesky API, debounced via onChange.
    private func performSearch(_ query: String) async {
        guard let account = accountStore.activeAccount,
              let appPassword = accountStore.appPassword(for: account)
        else { return }

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            results = []
            isSearching = false
            return
        }

        isSearching = true
        do {
            results = try await container.blueskyClient.searchActorsFull(query: trimmed, account: account, appPassword: appPassword)
        } catch {
            results = []
        }
        isSearching = false
    }

    // MARK: - Follow / Unfollow via Double-Tap

    private func effectiveViewerState(for actor: BlueskyActor) -> BlueskyViewerState? {
        guard var state = actor.viewerState else { return nil }
        if pendingFollowActions.contains(actor.did) {
            state = state.withOptimisticFollow(following: true, recordURI: optimisticFollowRecordURIs[actor.did])
        }
        if pendingUnfollowActions.contains(actor.did) {
            state = state.withOptimisticFollow(following: false)
        }
        return state
    }

    private func isFollowing(_ actor: BlueskyActor) -> Bool {
        pendingFollowActions.contains(actor.did)
            || (actor.viewerState?.isFollowing == true && !pendingUnfollowActions.contains(actor.did))
    }

    private func toggleFollow(actor: BlueskyActor) async {
        guard let activeAccount = accountStore.activeAccount,
              let appPassword = accountStore.appPassword(for: activeAccount)
        else { return }

        let did = actor.did
        let isCurrentlyFollowing = isFollowing(actor)

        if isCurrentlyFollowing {
            pendingUnfollowActions.insert(did)
            pendingFollowActions.remove(did)

            guard let recordURI = optimisticFollowRecordURIs[did] ?? actor.viewerState?.followingRecordURI else {
                pendingUnfollowActions.remove(did)
                return
            }

            do {
                try await container.social.unfollowActor(
                    recordURI: recordURI,
                    account: activeAccount,
                    appPassword: appPassword
                )
                optimisticFollowRecordURIs.removeValue(forKey: did)
                // Optimistic: pendingUnfollowActions keeps the badge hidden.
                // On the next full reload, viewerState will reflect the change.
            } catch {
                // Revert optimistic update
                pendingUnfollowActions.remove(did)
            }
        } else {
            pendingFollowActions.insert(did)
            pendingUnfollowActions.remove(did)

            do {
                let recordURI = try await container.social.followActor(
                    did: did,
                    account: activeAccount,
                    appPassword: appPassword
                )
                optimisticFollowRecordURIs[did] = recordURI
                // Optimistic: pendingFollowActions keeps the badge visible.
            } catch {
                // Revert optimistic update
                pendingFollowActions.remove(did)
            }
        }
    }
}
