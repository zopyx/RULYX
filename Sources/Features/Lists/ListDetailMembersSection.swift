import SwiftUI

extension ListDetailView {
    // MARK: - ListMembersSection

    /// Section for filtering and browsing existing list members, with
    /// swipe-to-remove, pagination, and double-tap to follow/unfollow.
    struct ListMembersSection: View {
        @ObservedObject var viewModel: ListDetailViewModel
        @ObservedObject var batchState: ListBatchProgressState
        @Binding var memberSearchQuery: String
        let currentList: BlueskyList
        let account: AppAccount
        let appPassword: String
        let syncSnapshot: () -> Void

        @EnvironmentObject var accountStore: AccountStore
        @EnvironmentObject var container: BlueskyServiceContainerWrapper
        @EnvironmentObject var workspaceStore: ModerationWorkspaceStore
        @EnvironmentObject private var localizationManager: LocalizationManager

        // MARK: - Optimistic Follow State

        @State private var pendingFollowActions: Set<String> = []
        @State private var pendingUnfollowActions: Set<String> = []
        /// Follow record URIs captured from successful follow calls (needed for unfollow before next API reload).
        @State private var optimisticFollowRecordURIs: [String: String] = [:]
        /// Tracks last tap for manual double-tap detection (member recordURI + timestamp).
        @State private var lastTapMemberID: String?
        @State private var lastTapTime: Date?

        private func effectiveViewerState(for member: BlueskyListMember) -> BlueskyViewerState? {
            guard var state = member.viewerState else { return nil }
            if pendingFollowActions.contains(member.actor.did) {
                state = BlueskyViewerState(
                    muted: state.muted, blockedBy: state.blockedBy,
                    isBlocking: state.isBlocking, blockingRecordURI: state.blockingRecordURI,
                    isFollowing: true, followingRecordURI: optimisticFollowRecordURIs[member.actor.did] ?? state.followingRecordURI,
                    followsYou: state.followsYou,
                    mutedByListName: state.mutedByListName, blockingByListName: state.blockingByListName
                )
            }
            if pendingUnfollowActions.contains(member.actor.did) {
                state = BlueskyViewerState(
                    muted: state.muted, blockedBy: state.blockedBy,
                    isBlocking: state.isBlocking, blockingRecordURI: state.blockingRecordURI,
                    isFollowing: false, followingRecordURI: nil,
                    followsYou: state.followsYou,
                    mutedByListName: state.mutedByListName, blockingByListName: state.blockingByListName
                )
            }
            return state
        }

        // MARK: - Body

        var body: some View {
            findMembersSection
            membersSection
        }

        @FocusState private var memberFilterFocused: Bool

        private var findMembersSection: some View {
            Section {
                TextField(loc("list.members.filter_placeholder"), text: $memberSearchQuery)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityLabel(loc("list.members.filter.label"))
                    .focused($memberFilterFocused)

                if !viewModel.members.isEmpty {
                    Text(viewModel.loadedMemberSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if !memberSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(verbatim: loc("list.members.matching").replacingOccurrences(of: "{count}", with: "\(viewModel.filteredMembers.count)"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text(loc("list.members.find"))
            }
        }

        /// The paginated list of members. Double-tap a row to follow/unfollow.
        private var membersSection: some View {
            Section {
                if viewModel.isLoadingMembers, viewModel.members.isEmpty {
                    LoadingPanel(message: loc("list.members.loading"))
                } else if let errorMsg = viewModel.membersErrorMessage, viewModel.members.isEmpty {
                    ErrorRetryBanner(message: errorMsg) {
                        Task {
                            await viewModel.loadMembers(
                                for: currentList, account: account,
                                appPassword: appPassword, using: container.liveClient
                            )
                        }
                    }
                } else if viewModel.members.isEmpty {
                    EmptyStatePanel(title: loc("list.members.no_members"), message: loc("list.members.no_members_desc"))
                } else if viewModel.filteredMembers.isEmpty {
                    EmptyStatePanel(title: loc("list.members.no_matches"), message: loc("list.members.no_matches_desc"))
                } else {
                    ForEach(viewModel.filteredMembers) { member in
                        NavigationLink {
                            BlueskyProfileView(member: member, list: currentList)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(alignment: .center, spacing: 8) {
                                    BlueskyActorRow(actor: member.actor)
                                    Spacer(minLength: 0)
                                    if let createdAt = member.createdAt {
                                        Text(relativeTimeString(from: createdAt))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                memberFollowBadges(member: member)
                                    .padding(.leading, 46)
                            }
                        }
                        .simultaneousGesture(
                            TapGesture().onEnded {
                                let now = Date()
                                let memberID = member.id
                                if lastTapMemberID == memberID, let last = lastTapTime, now.timeIntervalSince(last) < 0.35 {
                                    // Double-tap on same member → toggle follow
                                    lastTapMemberID = nil
                                    lastTapTime = nil
                                    Task { await toggleFollow(member: member) }
                                } else {
                                    lastTapMemberID = memberID
                                    lastTapTime = now
                                }
                            }
                        )
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                Task {
                                    await viewModel.remove(
                                        member: member, account: account,
                                        appPassword: appPassword, using: container.liveClient
                                    )
                                    syncSnapshot()
                                }
                            } label: {
                                Label { Text(loc("actions.remove")) } icon: { Image(systemName: "person.crop.circle.badge.minus") }
                            }
                            .disabled(viewModel.isRemoving(member) || batchState.isPerformingBulkAction)
                            .accessibilityHint(loc("list.members.remove.hint"))
                        }
                    }

                    if viewModel.isLoadingMoreMembers {
                        HStack {
                            ProgressView()
                            Text(loc("list.members.loading_more")).foregroundStyle(.secondary)
                        }
                    } else if viewModel.hasMoreMembers {
                        Button(loc("list.members.load_more_button")) {
                            Task {
                                await viewModel.loadMoreMembersIfNeeded(
                                    currentMember: viewModel.filteredMembers.last,
                                    list: currentList, account: account,
                                    appPassword: appPassword, using: container.liveClient
                                )
                            }
                        }
                        .accessibilityLabel(loc("list.members.load_more.label"))
                        .accessibilityHint(loc("list.members.load_more.hint"))
                    }
                }
            } header: {
                Text(loc("list.members.title"))
            }
        }

        // MARK: - Follow / Unfollow via Double-Tap

        private func toggleFollow(member: BlueskyListMember) async {
            guard let activeAccount = accountStore.activeAccount,
                  let appPassword = accountStore.appPassword(for: activeAccount)
            else { return }

            let did = member.actor.did
            let isCurrentlyFollowing = pendingFollowActions.contains(did)
                || (member.viewerState?.isFollowing == true && !pendingUnfollowActions.contains(did))

            if isCurrentlyFollowing {
                pendingUnfollowActions.insert(did)
                pendingFollowActions.remove(did)
                guard let recordURI = optimisticFollowRecordURIs[did] ?? member.viewerState?.followingRecordURI else {
                    pendingUnfollowActions.remove(did)
                    return
                }
                do {
                    try await container.social.unfollowActor(recordURI: recordURI, account: activeAccount, appPassword: appPassword)
                    optimisticFollowRecordURIs.removeValue(forKey: did)
                } catch {
                    pendingUnfollowActions.remove(did)
                }
            } else {
                pendingFollowActions.insert(did)
                pendingUnfollowActions.remove(did)
                do {
                    let recordURI = try await container.social.followActor(did: did, account: activeAccount, appPassword: appPassword)
                    optimisticFollowRecordURIs[did] = recordURI
                } catch {
                    pendingFollowActions.remove(did)
                }
            }
        }

        // MARK: - Follow Badges

        @ViewBuilder
        private func memberFollowBadges(member: BlueskyListMember) -> some View {
            if let state = effectiveViewerState(for: member) {
                HStack(spacing: 3) {
                    if state.isFollowing {
                        Text(loc("profile.badge.following"))
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(Color.infoBlue)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.infoBlue.opacity(0.12), in: Capsule())
                    }
                    if state.followsYou {
                        Text(loc("profile.badge.follows_me"))
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(Color.successGreen)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.successGreen.opacity(0.12), in: Capsule())
                    }
                }
            }
        }
    }
}
