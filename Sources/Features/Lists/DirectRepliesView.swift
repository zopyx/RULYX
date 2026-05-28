import SwiftUI

/// Scans the user's recent posts for direct replies (replies from other
/// accounts to the user's posts), surfacing them in a chronological list
/// for moderation review.
struct DirectRepliesView: View {
    let did: String
    let handle: String
    let displayName: String

    @StateObject private var viewModel: DirectRepliesViewModel
    @EnvironmentObject var accountStore: AccountStore
    @EnvironmentObject var blueskyClient: LiveBlueskyClient
    @EnvironmentObject private var internalListStore: InternalListStore
    @Environment(\.dismiss) private var dismiss
    @State private var selectedPostURI: String?
    @State private var imagePreview: ImagePreviewCollection?
    @State private var videoPreviewURL: URL?
    @State private var showLikesForURI: String?
    @State private var loadMoreTask: Task<Void, Never>?
    @State private var showProfileFor: BlueskyActor?
    @State private var searchAccount: AppAccount?
    @State private var hasAppeared = false
    @StateObject private var likerActions = PostLikerActionsManager()
    @State private var availableTargetLists: [BlueskyList] = []
    @State private var isFetchingLikers = false
    @State private var pendingLikerTargets: [PendingLikerTarget] = []
    @State private var showBlockLikersConfirmation = false
    @State private var blockError: String?
    @State private var batchOperationConfig: BatchOperationConfig?

    init(did: String, handle: String, displayName: String) {
        self.did = did
        self.handle = handle
        self.displayName = displayName
        _viewModel = StateObject(wrappedValue: DirectRepliesViewModel(did: did))
    }

    @EnvironmentObject private var localizationManager: LocalizationManager

    // MARK: - Body

    var body: some View {
        List {
            searchAccountSection

            if isFetchingLikers {
                HStack {
                    Spacer()
                    ProgressView(loc("post.block_likers.fetching"))
                    Spacer()
                }
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }

            if viewModel.isLoading, viewModel.entries.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        LoadingPanel(message: viewModel.progressLabel ?? loc("directreplies.loading"))
                        ProgressView()
                            .scaleEffect(0.8)
                    }
                    Spacer()
                }
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            } else if let error = viewModel.errorMessage, viewModel.entries.isEmpty {
                HStack {
                    Spacer()
                    ContentUnavailableView(
                        loc("list.detail.alert_title"),
                        systemImage: "exclamationmark.bubble",
                        description: Text(error)
                    )
                    Spacer()
                }
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            } else if viewModel.entries.isEmpty, !isFetchingLikers {
                HStack {
                    Spacer()
                    ContentUnavailableView(
                        loc("directreplies.empty"),
                        systemImage: "arrowshape.turn.up.left",
                        description: Text(loc: "directreplies.empty_desc")
                    )
                    Spacer()
                }
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            } else {
                ForEach(viewModel.entries, id: \.post.uri) { entry in
                    let entryCallbacks = PostRowCallbacks(
                        onTapImage: { index in
                            let allImages = entry.post.embed?.images ?? []
                            let urls = allImages.compactMap { $0.fullsize.flatMap(URL.init) }
                            guard index < urls.count else { return }
                            imagePreview = ImagePreviewCollection(urls: urls, initialIndex: index)
                        },
                        onPlayVideo: {
                            if let playlist = entry.post.embed?.video?.playlist, let url = URL(string: playlist) {
                                videoPreviewURL = url
                            }
                        },
                        onOpenProfile: { _ in
                            let author = entry.post.safeAuthor
                            showProfileFor = BlueskyActor(
                                did: author.did ?? "",
                                handle: author.handle ?? "",
                                displayName: author.displayName,
                                avatarURL: author.avatar.flatMap(URL.init)
                            )
                        },
                        onShowLikes: { showLikesForURI = entry.post.uri },
                        onReportPost: {
                            guard let activeDID = accountStore.activeAccount?.did else { return }
                            guard entry.post.author?.did != activeDID else { return }
                            likerActions.postToReport = entry
                        },
                        onBlockAllLikers: { handleBlockAllLikers(postURI: entry.post.uri) },
                        onAddAllLikersToList: { list in
                            handleAddAllLikersToList(postURI: entry.post.uri, list: list)
                        },
                        onClassify: { likerActions.postToClassify = entry },
                        availableLikerTargetLists: availableTargetLists
                    )
                    PostRowView(
                        entry: entry,
                        style: .full,
                        callbacks: entryCallbacks
                    )
                    .buttonStyle(.plain)
                    .postInfiniteScroll(
                        entry: entry,
                        entries: viewModel.entries,
                        hasMore: viewModel.hasMore,
                        isLoadingMore: viewModel.isLoadingMore,
                        loadMore: { await loadMore() }
                    )
                }
                if viewModel.isLoadingMore {
                    HStack {
                        Spacer()
                        VStack(spacing: 6) {
                            if let label = viewModel.progressLabel {
                                Text(label)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            ProgressView()
                                .scaleEffect(0.8)
                        }
                        Spacer()
                    }
                    .listRowSeparator(.hidden)
                }
                if !viewModel.hasMore, !viewModel.entries.isEmpty {
                    Text(loc: "directreplies.end")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity)
                        .listRowSeparator(.hidden)
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable {
            await refresh()
        }
        .pageTitle(Text(loc: "directreplies.title"))
        .sheet(item: $selectedPostURI) { uri in
            NavigationStack {
                ThreadView(postURI: uri)
                    .environmentObject(accountStore)
                    .environmentObject(blueskyClient)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            ToolbarCloseButton()
                        }
                    }
            }
        }
        .fullScreenCover(item: $imagePreview) { preview in
            ImageCarouselView(urls: preview.urls, initialIndex: preview.initialIndex) {
                imagePreview = nil
            }
        }
        .fullScreenCover(item: $videoPreviewURL) { url in
            VideoPlayerView(url: url) {
                videoPreviewURL = nil
            }
        }
        .sheet(item: $showLikesForURI) { uri in
            LikesListView(uri: uri)
                .environmentObject(accountStore)
                .environmentObject(blueskyClient)
        }
        .sheet(item: $batchOperationConfig) { config in
            BatchOperationProgressView(config: config)
                .environmentObject(accountStore)
                .environmentObject(blueskyClient)
        }
        .navigationDestination(item: $showProfileFor) { actor in
            BlueskyProfileView(
                member: BlueskyListMember(recordURI: "directreply:\(actor.did)", actor: actor),
                list: nil
            )
            .environmentObject(accountStore)
            .environmentObject(blueskyClient)
        }
        .alert(String.localized("post.block_likers.confirm_title", replacements: ["count": "\(pendingLikerTargets.count)"]), isPresented: $showBlockLikersConfirmation) {
            Button(loc("post.block_likers.confirm_block"), role: .destructive) {
                let targets = pendingLikerTargets
                showBlockLikersConfirmation = false
                blockLikers(targets)
            }
            Button(loc("actions.cancel"), role: .cancel) {
                resetPendingLikerTargets()
            }
        } message: {
            let handles = pendingLikerTargets.prefix(5).map { target in
                if let handle = target.handle, !handle.isEmpty {
                    return "@\(handle)"
                }
                return target.did
            }.joined(separator: "\n")
            let remainder = pendingLikerTargets.count > 5 ? "\n…and \(pendingLikerTargets.count - 5) more" : ""
            Text(verbatim: loc("post.block_likers.confirm_message").replacingOccurrences(of: "{count}", with: "\(pendingLikerTargets.count)") + "\n\n" + handles + remainder)
        }
        .alert(loc("list.detail.alert_title"), isPresented: .init(get: { blockError != nil }, set: { if !$0 { blockError = nil } })) {
            Button(loc("actions.ok")) { blockError = nil }
        } message: {
            if let error = blockError {
                Text(error)
            }
        }
        .task {
            if !hasAppeared {
                hasAppeared = true
                if let prefID = accountStore.preferredSearchAccountID,
                   let prefAccount = accountStore.accounts.first(where: { $0.id == prefID })
                {
                    searchAccount = prefAccount
                } else {
                    searchAccount = accountStore.activeAccount
                }
                await loadInitial()
                await loadAvailableTargetLists()
            }
        }
        .onChange(of: accountStore.activeAccount?.id) { _, _ in
            Task {
                await loadAvailableTargetLists()
            }
        }
        .onDisappear {
            loadMoreTask?.cancel()
        }
        .postLikerActions(manager: likerActions)
    }

    // MARK: - Section builders

    private var searchAccountSection: some View {
        Group {
            if let searchAccount {
                searchAccountRow(searchAccount)
            }
        }
        .listRowInsets(EdgeInsets(top: -4, leading: 0, bottom: 0, trailing: 0))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    private func searchAccountRow(_ account: AppAccount) -> some View {
        HStack(spacing: 14) {
            if let avatarURL = account.avatarURL {
                ThumbnailImageView(url: avatarURL, maxPixelSize: 64) {
                    avatarPlaceholder(for: account)
                }
                .scaledToFill()
                .frame(width: 32, height: 32)
                .clipShape(Circle())
            } else {
                avatarPlaceholder(for: account)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(loc: "directreplies.searching_as")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.primary)
                Text(account.displayName)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.skyPrimary.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.skyPrimary.opacity(0.12), lineWidth: 1)
        )
    }

    private func avatarPlaceholder(for account: AppAccount) -> some View {
        Circle()
            .fill(Color.skyPrimary.opacity(0.25))
            .frame(width: 32, height: 32)
            .overlay {
                Text(account.displayName.prefix(1).uppercased())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
            }
    }

    // MARK: - Actions

    private func handleBlockAllLikers(postURI: String) {
        Task {
            guard let targets = await fetchLikerTargets(for: postURI) else { return }
            pendingLikerTargets = targets
            showBlockLikersConfirmation = true
        }
    }

    private func handleAddAllLikersToList(postURI: String, list: BlueskyList) {
        if list.kind == .internal {
            Task {
                guard let targets = await fetchLikerTargets(for: postURI) else { return }
                for target in targets {
                    let stripped = list.id.replacingOccurrences(of: "internal:", with: "")
                    if let listID = UUID(uuidString: stripped) {
                        internalListStore.addMember(did: target.did, handle: target.handle ?? target.did, to: listID)
                    }
                }
            }
        } else {
            Task {
                guard let targets = await fetchLikerTargets(for: postURI) else { return }
                guard let account = accountStore.activeAccount,
                      let appPassword = accountStore.appPassword(for: account) else { return }
                addLikers(targets, to: list, account: account, appPassword: appPassword)
            }
        }
    }

    private func fetchLikerTargets(for postURI: String) async -> [PendingLikerTarget]? {
        guard let account = searchAccount,
              let appPassword = accountStore.appPassword(for: account) else { return nil }
        isFetchingLikers = true
        resetPendingLikerTargets()
        do {
            var allLikes: [LikeItem] = []
            var cursor: String?
            repeat {
                let response = try await blueskyClient.fetchLikes(uri: postURI, cursor: cursor, account: account, appPassword: appPassword)
                allLikes += response.likes
                cursor = response.cursor
            } while cursor != nil
            isFetchingLikers = false
            let targets = collectPendingLikerTargets(from: allLikes)
            if targets.isEmpty {
                blockError = loc("post.block_likers.no_likers")
                return nil
            }
            return targets
        } catch {
            isFetchingLikers = false
            blockError = AppError.userMessage(from: error)
            return nil
        }
    }

    private func blockLikers(_ targets: [PendingLikerTarget]) {
        guard let account = accountStore.activeAccount,
              let appPassword = accountStore.appPassword(for: account) else { return }
        guard !targets.isEmpty else { return }
        resetPendingLikerTargets()
        batchOperationConfig = BatchOperationConfig(
            targets: targets,
            mode: .block(account: account, appPassword: appPassword)
        )
    }

    private func addLikers(_ targets: [PendingLikerTarget], to list: BlueskyList, account: AppAccount, appPassword: String) {
        guard !targets.isEmpty else { return }
        batchOperationConfig = BatchOperationConfig(
            targets: targets,
            mode: .addToList(list: list, account: account, appPassword: appPassword)
        )
    }

    private func collectPendingLikerTargets(from likes: [LikeItem]) -> [PendingLikerTarget] {
        var seenDIDs = Set<String>()
        return likes.compactMap { like in
            guard let did = like.actor.did, !did.isEmpty else { return nil }
            guard seenDIDs.insert(did).inserted else { return nil }
            return PendingLikerTarget(
                did: did,
                handle: like.actor.handle
            )
        }
    }

    private func resetPendingLikerTargets() {
        pendingLikerTargets = []
        showBlockLikersConfirmation = false
    }

    // MARK: - Data loading

    private func loadAvailableTargetLists() async {
        guard let account = accountStore.activeAccount,
              let appPassword = accountStore.appPassword(for: account)
        else {
            availableTargetLists = []
            return
        }
        var lists: [BlueskyList] = []
        do {
            lists = try await blueskyClient.fetchLists(for: account, appPassword: appPassword)
                .sorted { lhs, rhs in
                    if lhs.kind != rhs.kind {
                        return lhs.kind.sortOrder < rhs.kind.sortOrder
                    }
                    return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                }
        } catch {
            availableTargetLists = []
            AppLogger.moderation.error("Failed to load available target lists: \(error.localizedDescription, privacy: .public)")
        }
        let internalLists = internalListStore.lists.map { internalList in
            BlueskyList(
                id: "internal:\(internalList.id.uuidString)",
                name: internalList.name,
                description: "Internal",
                memberCount: internalList.memberCount,
                kind: .internal,
                cid: nil
            )
        }
        lists.append(contentsOf: internalLists)
        availableTargetLists = lists.sorted { lhs, rhs in
            if lhs.kind != rhs.kind {
                return lhs.kind.sortOrder < rhs.kind.sortOrder
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    private func loadInitial() async {
        guard let account = searchAccount,
              let appPassword = accountStore.appPassword(for: account) else { return }
        await viewModel.load(account: account, appPassword: appPassword, using: blueskyClient)
    }

    private func loadMore() async {
        guard let account = searchAccount,
              let appPassword = accountStore.appPassword(for: account) else { return }
        guard loadMoreTask == nil else { return }
        let task = Task {
            await viewModel.loadMore(account: account, appPassword: appPassword, using: blueskyClient)
        }
        loadMoreTask = task
        await task.value
        loadMoreTask = nil
    }

    private func refresh() async {
        guard let account = searchAccount,
              let appPassword = accountStore.appPassword(for: account) else { return }
        await viewModel.refresh(account: account, appPassword: appPassword, using: blueskyClient)
    }
}
