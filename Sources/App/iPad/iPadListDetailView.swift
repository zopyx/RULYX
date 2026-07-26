import SwiftUI

struct iPadListDetailView: View {
    let list: BlueskyList

    @EnvironmentObject private var accountStore: AccountStore
    @EnvironmentObject private var container: BlueskyServiceContainerWrapper
    @EnvironmentObject private var workspaceStore: ModerationWorkspaceStore
    @EnvironmentObject private var localizationManager: LocalizationManager
    @EnvironmentObject private var navState: iPadNavigationState

    @StateObject private var detailVM = ListDetailViewModel()

    @State private var searchQuery = ""
    @State private var showExport = false
    @State private var showMerge = false
    @State private var showAIScreen = false

    // Subscribe/unsubscribe state
    @State private var isSubscribedToModerationList = false
    @State private var subscribeError: String?
    @State private var isSubscribing = false

    // Optimistic follow state (double-tap)
    @State private var pendingFollowActions: Set<String> = []
    @State private var pendingUnfollowActions: Set<String> = []
    /// Follow record URIs captured from successful follow calls (needed for unfollow before next API reload).
    @State private var optimisticFollowRecordURIs: [String: String] = [:]
    /// Tracks last tap for manual double-tap detection (member recordURI + timestamp).
    @State private var lastTapMemberID: String?
    @State private var lastTapTime: Date?

    private var isOwnedList: Bool {
        guard let activeDID = accountStore.activeAccount?.did else { return false }
        return list.id.hasPrefix("at://\(activeDID)")
    }

    private var listTitleWithMemberCount: String {
        "\(list.name) (\(list.memberCount ?? detailVM.members.count))"
    }

    /// Returns the effective viewer state for a member, merging API data
    /// with any pending optimistic follow/unfollow action.
    private func effectiveViewerState(for member: BlueskyListMember) -> BlueskyViewerState? {
        guard var state = member.viewerState else { return nil }
        if pendingFollowActions.contains(member.actor.did) {
            state = BlueskyViewerState(
                muted: state.muted,
                blockedBy: state.blockedBy,
                isBlocking: state.isBlocking,
                blockingRecordURI: state.blockingRecordURI,
                isFollowing: true,
                followingRecordURI: optimisticFollowRecordURIs[member.actor.did] ?? state.followingRecordURI,
                followsYou: state.followsYou,
                mutedByListName: state.mutedByListName,
                blockingByListName: state.blockingByListName
            )
        }
        if pendingUnfollowActions.contains(member.actor.did) {
            state = BlueskyViewerState(
                muted: state.muted,
                blockedBy: state.blockedBy,
                isBlocking: state.isBlocking,
                blockingRecordURI: state.blockingRecordURI,
                isFollowing: false,
                followingRecordURI: nil,
                followsYou: state.followsYou,
                mutedByListName: state.mutedByListName,
                blockingByListName: state.blockingByListName
            )
        }
        return state
    }

    var body: some View {
        VStack(spacing: 0) {
            listHeader
            Divider()
            if !isOwnedList {
                List {
                    ListDetailSubscribeSection(
                        currentList: list,
                        isSubscribed: $isSubscribedToModerationList,
                        subscribeError: $subscribeError,
                        isSubscribing: $isSubscribing,
                        account: accountStore.activeAccount!,
                        appPassword: accountStore.activeAccount.flatMap { accountStore.appPassword(for: $0) } ?? ""
                    )
                }
                .listStyle(.inset)
                .frame(height: 120)
                Divider()
            }
            memberList
        }
        .task(id: "\(list.id)|\(accountStore.activeAccountID?.uuidString ?? "none")") {
            guard let activeAccount = accountStore.activeAccount else { return }
            await detailVM.loadMembers(
                for: list,
                account: activeAccount,
                appPassword: accountStore.appPassword(for: activeAccount) ?? "",
                using: container.list
            )
        }
        .task(id: "\(list.id)|sub|\(accountStore.activeAccountID?.uuidString ?? "none")") {
            guard !isOwnedList,
                  let account = accountStore.activeAccount,
                  let appPassword = accountStore.activeAccount.flatMap({ accountStore.appPassword(for: $0) })
            else { return }
            do {
                isSubscribedToModerationList = try await container.list.isSubscribedToModerationList(
                    list.id,
                    account: account,
                    appPassword: appPassword
                )
            } catch {
                subscribeError = AppError.userMessage(from: error)
            }
        }
        .navigationTitle("")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if !detailVM.members.isEmpty {
                    Button { showAIScreen = true } label: {
                        Image(systemName: "brain")
                            .accessibilityLabel(loc("ai.screen.title"))
                    }
                }
                Button { showExport = true } label: {
                    Image(systemName: "square.and.arrow.up")
                        .accessibilityLabel(loc("lists.export"))
                }
                Button { showMerge = true } label: {
                    Image(systemName: "arrow.left.arrow.right")
                        .accessibilityLabel(loc("lists.merge"))
                }
            }
        }
        .sheet(isPresented: $showAIScreen) {
            AIBatchScreenView(actors: detailVM.members.map { member in
                ScreenableActor(
                    id: member.actor.did,
                    displayName: member.actor.displayName ?? member.actor.handle,
                    handle: member.actor.handle,
                    description: member.actor.description
                )
            })
            .environmentObject(localizationManager)
        }
    }

    private var listHeader: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: list.kind.symbolName)
                    .font(.title2)
                    .foregroundStyle(list.kind == .moderation ? Color.skyPrimary : .secondary)
                Text(listTitleWithMemberCount)
                    .font(.title2.weight(.semibold))
                Spacer()
                Text("\(list.memberCount ?? detailVM.members.count)")
                    .font(.title.weight(.bold))
                    .foregroundStyle(Color.skyPrimary)
                    + Text(" members")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !list.description.isEmpty {
                Text(list.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 12) {
                listActionButton(loc("lists.add_actor"), icon: "person.badge.plus") {
                    navState.selectedList = nil
                }
                listActionButton(loc("lists.remove"), icon: "person.fill.badge.minus") {
                    navState.selectedList = nil
                }
                listActionButton(loc("lists.import"), icon: "square.and.arrow.down") {
                    navState.selectedList = nil
                }
                listActionButton(loc("lists.export"), icon: "square.and.arrow.up") {
                    showExport = true
                }
            }
            .padding(.vertical, 4)
        }
        .padding([.horizontal, .top])
    }

    private func listActionButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.title3)
                    .frame(height: 20)
                Text(title)
                    .font(.caption2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(.fill.quaternary)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
    }

    @ViewBuilder
    private var memberList: some View {
        if detailVM.isLoadingMembers {
            VStack(spacing: 16) {
                ProgressView()
                Text(loc("lists.loading"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if detailVM.members.isEmpty {
            ContentUnavailableView(
                loc("lists.no_members"),
                systemImage: "person.2.slash",
                description: Text(loc("lists.no_members_desc"))
            )
        } else {
            List {
                ForEach(filteredMembers) { member in
                    memberRow(member)
                        .simultaneousGesture(
                            TapGesture().onEnded {
                                let now = Date()
                                let memberID = member.id
                                if lastTapMemberID == memberID, let last = lastTapTime, now.timeIntervalSince(last) < 0.35 {
                                    lastTapMemberID = nil
                                    lastTapTime = nil
                                    Task { await toggleFollow(member: member) }
                                } else {
                                    lastTapMemberID = memberID
                                    lastTapTime = now
                                }
                            }
                        )
                }
                if detailVM.hasMoreMembers {
                    HStack {
                        Spacer()
                        ProgressView()
                            .onAppear {
                                Task {
                                    await detailVM.loadMoreMembersIfNeeded(
                                        currentMember: detailVM.members.last,
                                        list: list,
                                        account: accountStore.activeAccount!,
                                        appPassword: accountStore.activeAccount.flatMap { accountStore.appPassword(for: $0) } ?? "",
                                        using: container.list
                                    )
                                }
                            }
                        Spacer()
                    }
                }
            }
            .listStyle(.inset)
            .searchable(text: $searchQuery, prompt: loc("lists.search_members"))
        }
    }

    private var filteredMembers: [BlueskyListMember] {
        if searchQuery.isEmpty {
            return detailVM.members
        }
        return detailVM.members.filter { member in
            member.actor.handle.localizedCaseInsensitiveContains(searchQuery)
                || (member.actor.displayName?.localizedCaseInsensitiveContains(searchQuery) ?? false)
        }
    }

    private func memberRow(_ member: BlueskyListMember) -> some View {
        Button {
            navState.selectedProfileDID = member.actor.did
        } label: {
            HStack(spacing: 12) {
                AsyncImage(url: member.actor.avatarURL) { phase in
                    switch phase {
                    case let .success(image):
                        image.resizable().scaledToFill()
                    default:
                        Image(systemName: "person.crop.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                }
                .frame(width: 40, height: 40)
                .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(member.actor.title)
                        .font(.body.weight(.medium))
                    Text("@\(member.actor.handle)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    // Dedicated row for follow-relationship badges below handle
                    memberFollowBadges(member: member)
                        .padding(.top, 2)
                }

                Spacer()

                if let createdAt = member.createdAt {
                    Text(createdAt, style: .date)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
        .padding(.vertical, 2)
        .contextMenu {
            Button(loc("context.open_in_new_window")) {
                let pasteboard = UIPasteboard.general
                pasteboard.string = member.actor.did
            }
            Button(loc("context.copy_handle")) {
                UIPasteboard.general.string = member.actor.handle
            }
            Divider()
            Button(loc("context.block_actor"), role: .destructive) {
                Task {
                    try? await container.social.blockActor(
                        did: member.actor.did,
                        account: accountStore.activeAccount!,
                        appPassword: accountStore.activeAccount.flatMap { accountStore.appPassword(for: $0) }
                    )
                }
            }
        }
    }

    // MARK: - Follow / Unfollow via Double-Tap

    /// Toggles follow state for a member with optimistic UI feedback.
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
                try await container.social.unfollowActor(
                    recordURI: recordURI,
                    account: activeAccount,
                    appPassword: appPassword
                )
                optimisticFollowRecordURIs.removeValue(forKey: did)
            } catch {
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
            } catch {
                pendingFollowActions.remove(did)
            }
        }
    }

    // MARK: - Follow Badges

    /// Compact follow-relationship badges for a list member.
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
