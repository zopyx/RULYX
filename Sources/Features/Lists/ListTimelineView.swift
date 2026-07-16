import SwiftUI

/// Timeline of recent posts from all members of a given Bluesky list.
///
/// Behaves like the main Timeline tab — full post interactions, inline threads,
/// swipe actions, context menus, compose — but scoped to list members' content,
/// sorted newest-first.
struct ListTimelineView: View {
    let list: BlueskyList

    @State private var viewModel: ListTimelineViewModel
    @EnvironmentObject var accountStore: AccountStore
    @EnvironmentObject var container: BlueskyServiceContainerWrapper
    @EnvironmentObject private var internalListStore: InternalListStore
    @EnvironmentObject private var localizationManager: LocalizationManager

    @State private var navigationPath = NavigationPath()
    @State private var selectedPostURI: String?
    @State private var shareFileURL: URL?
    @State private var imagePreview: ImagePreviewCollection?
    @State private var videoPreviewURL: URL?
    @State private var showLikesForURI: String?
    @State private var initialLoadTask: Task<Void, Never>?
    @State private var loadMoreTask: Task<Void, Never>?
    @State private var composeContext: ComposeContext?
    @State private var showNewPostComposer = false
    @State private var editPostEntry: RichFeedEntry?
    @State private var postToDelete: RichFeedEntry?
    @State private var postToShare: RichFeedEntry?
    @State private var profileToShow: BlueskyActor?
    @StateObject private var likerActions = PostLikerActionsManager()
    @State private var aiClassifications: [String: [String: Double]] = [:]

    init(list: BlueskyList) {
        self.list = list
        _viewModel = State(wrappedValue: ListTimelineViewModel(list: list))
    }

    // MARK: - Body

    var body: some View {
        Group {
                if viewModel.state == .initialLoading {
                    skeletonContent
                } else if case let .failed(msg) = viewModel.state, viewModel.entries.isEmpty {
                    ContentUnavailableView(
                        loc("list.detail.alert_title"),
                        systemImage: "exclamationmark.bubble",
                        description: Text(msg)
                    )
                } else if viewModel.entries.isEmpty {
                    ContentUnavailableView(
                        loc("list.timeline.empty"),
                        systemImage: "bubble.left.and.bubble.right",
                        description: Text(loc: "list.timeline.empty_desc")
                    )
                } else {
                    listContent
                }
            }
            .pageTitle("\(loc("list.timeline.title")) — \(list.name)")
            .overlay(alignment: .bottomTrailing) {
                TimelineComposeFAB(isVisible: !viewModel.entries.isEmpty) {
                    showNewPostComposer = true
                }
            }
            .sheet(item: $selectedPostURI) { uri in
                NavigationStack {
                    ThreadView(postURI: uri)
                        .environmentObject(accountStore)
                        .environmentObject(container.blueskyClient)
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                ToolbarCloseButton()
                            }
                        }
                }
            }
            .sheet(item: $shareFileURL) { url in
                ShareSheet(activityItems: [url])
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
                    .environmentObject(container.blueskyClient)
            }
            .sheet(item: $composeContext) { context in
                if context.isReply {
                    ReplyComposerView(
                        account: context.account,
                        appPassword: context.appPassword,
                        blueskyClient: container.blueskyClient,
                        parentURI: context.parentURI,
                        parentCID: context.parentCID,
                        rootURI: context.rootURI,
                        rootCID: context.rootCID,
                        onComplete: { Task { await refresh() } }
                    )
                    .presentationDetents([.medium, .large])
                } else {
                    ComposePostView(viewModel: ComposePostViewModel(
                        blueskyClient: container.blueskyClient,
                        account: context.account,
                        appPassword: context.appPassword,
                        onComplete: { Task { await refresh() } },
                        quote: (context.uri, context.cid)
                    ))
                    .environmentObject(accountStore)
                    .environmentObject(container.blueskyClient)
                }
            }
            .sheet(isPresented: $showNewPostComposer) {
                if let account = accountStore.activeAccount, let appPassword = accountStore.appPassword(for: account) {
                    ComposePostView(viewModel: ComposePostViewModel(
                        blueskyClient: container.blueskyClient,
                        account: account,
                        appPassword: appPassword,
                        onComplete: { Task { await refresh() } }
                    ))
                    .environmentObject(accountStore)
                    .environmentObject(container.blueskyClient)
                }
            }
            .sheet(item: $editPostEntry) { entry in
                if let account = accountStore.activeAccount, let appPassword = accountStore.appPassword(for: account) {
                    ComposePostView(viewModel: ComposePostViewModel(
                        blueskyClient: container.blueskyClient,
                        account: account,
                        appPassword: appPassword,
                        onComplete: { Task { await refresh() } },
                        editPost: entry
                    ))
                    .environmentObject(accountStore)
                    .environmentObject(container.blueskyClient)
                }
            }
            .sheet(item: $profileToShow) { actor in
                NavigationStack {
                    BlueskyProfileView(
                        member: BlueskyListMember(recordURI: "listtimeline:\(actor.did)", actor: actor),
                        list: nil
                    )
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button(loc("actions.done")) { profileToShow = nil }
                        }
                    }
                    .environmentObject(accountStore)
                    .environmentObject(container.blueskyClient)
                }
            }
            .sheet(item: $postToShare) { entry in
                if let url = shareURL(for: entry) {
                    ShareSheet(activityItems: [url])
                }
            }
            .confirmationDialog(
                loc("post.delete.confirm"),
                isPresented: .init(get: { postToDelete != nil }, set: {
                    if !$0 {
                        postToDelete = nil
                    }
                }),
                titleVisibility: .visible,
                presenting: postToDelete
            ) { post in
                Button(loc("post.delete"), role: .destructive) {
                    Task { await deletePost(post) }
                }
                Button(loc("actions.cancel"), role: .cancel) {}
            } message: { _ in
                Text(loc: "post.delete.message")
            }
            .navigationDestination(for: TimelineRoute.self) { route in
                switch route {
                case let .thread(postURI):
                    ThreadView(postURI: postURI)
                }
            }
            .task {
                await loadInitial()
                guard let account = accountStore.activeAccount,
                      let appPassword = accountStore.appPassword(for: account) else { return }
                viewModel.startPolling(account: account, appPassword: appPassword, using: container.blueskyClient)
            }
            .onDisappear {
                initialLoadTask?.cancel()
                loadMoreTask?.cancel()
                viewModel.stopPolling()
            }
            .task {
                guard let account = accountStore.activeAccount,
                      let appPassword = accountStore.appPassword(for: account) else { return }
                await likerActions.loadAvailableTargetLists(using: container.blueskyClient, internalListStore: internalListStore, account: account, appPassword: appPassword)
            }
            .postLikerActions(manager: likerActions)
            .task(id: viewModel.entries.count) {
                await classifyVisiblePosts()
            }
    }

    // MARK: - List content

    private var listContent: some View {
        List {
            if viewModel.scanProgressLabel != nil, let label = viewModel.scanProgressLabel {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text(label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }

            ForEach(viewModel.entries, id: \.post.uri) { entry in
                postRowView(for: entry)
            }
            if viewModel.state == .loadingMore {
                HStack {
                    Spacer()
                    ProgressView()
                        .scaleEffect(0.8)
                    Spacer()
                }
                .listRowSeparator(.hidden)
            }
            if !viewModel.state.hasMore, !viewModel.entries.isEmpty {
                Text(loc("timeline.end"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .listRowSeparator(.hidden)
            }
            if !viewModel.entries.isEmpty, viewModel.state.hasMore {
                Color.clear
                    .frame(height: 1)
                    .listRowSeparator(.hidden)
                    .onAppear {
                        Task { await loadMore() }
                    }
            }
            if case let .loadMoreFailed(msg) = viewModel.state {
                VStack(spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                        Text(msg)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Button(loc("actions.retry")) {
                        Task { await loadMore() }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .refreshable {
            await refresh()
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 5)
                .onChanged { _ in viewModel.userDidInteract() }
        )
        .overlay(alignment: .top) {
            if viewModel.newPostCount > 0 {
                newPostsBanner
            }
        }
    }

    // MARK: - Post row

    private func postRowView(for entry: RichFeedEntry) -> some View {
        let authorCB = makeAuthorCallbacks(author: entry.post.author, accountStore: accountStore, blueskyClient: container.blueskyClient, internalListStore: internalListStore)
        let postCallbacks = PostRowCallbacks(
            onTapThread: { navigationPath.append(TimelineRoute.thread(postURI: entry.post.uri)) },
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
            onOpenProfile: { handle in openProfile(handle) },
            onReply: { handleReply(entry) },
            onLike: { handleLike(entry) },
            onShowLikes: { showLikesForURI = entry.post.uri },
            onRepost: { handleRepost(entry) },
            onQuote: { handleQuote(entry) },
            onCopy: { UIPasteboard.general.string = entry.post.safeRecord.text },
            onTranslate: { translateText(entry.post.safeRecord.text ?? "") },
            onDeletePost: isOwnPost(entry) ? { postToDelete = entry } : nil,
            onEditPost: isOwnPost(entry) ? { editPostEntry = entry } : nil,
            onReportPost: isOwnPost(entry) ? nil : { likerActions.postToReport = entry },
            onBlockAllLikers: {
                guard let account = accountStore.activeAccount,
                      let appPassword = accountStore.appPassword(for: account) else { return }
                likerActions.handleBlockAllLikers(postURI: entry.post.uri, using: container.blueskyClient, fetchAccount: account, fetchPassword: appPassword)
            },
            onAddAllLikersToList: { list in
                guard let fetchAccount = accountStore.activeAccount,
                      let fetchPassword = accountStore.appPassword(for: fetchAccount),
                      let activeAccount = accountStore.activeAccount,
                      let activePassword = accountStore.appPassword(for: activeAccount) else { return }
                likerActions.handleAddAllLikersToList(
                    postURI: entry.post.uri, list: list, using: container.blueskyClient,
                    fetchAccount: fetchAccount, fetchPassword: fetchPassword,
                    activeAccount: activeAccount, activePassword: activePassword,
                    internalListStore: internalListStore
                )
            },
            onClassify: { likerActions.postToClassify = entry },
            onBlockAuthor: authorCB.onBlock,
            onAddAuthorToList: authorCB.onAddToList,
            isLiked: viewModel.effectiveIsLiked(uri: entry.post.uri),
            isReposted: viewModel.effectiveIsReposted(uri: entry.post.uri),
            overrideLikeCount: viewModel.effectiveLikeCount(uri: entry.post.uri),
            overrideRepostCount: viewModel.effectiveRepostCount(uri: entry.post.uri),
            availableLikerTargetLists: likerActions.availableTargetLists
        )

        let context = TimelinePostRowContext(
            onCopyText: entry.post.safeRecord.text != nil ? { UIPasteboard.general.string = entry.post.safeRecord.text } : nil,
            onShare: { postToShare = entry },
            onMuteUser: entry.post.author?.handle != nil ? { Task { await muteUser(handle: entry.post.author!.handle!, did: entry.post.author?.did) } } : nil,
            onBlockUser: entry.post.author?.handle != nil ? { Task { await blockUser(handle: entry.post.author!.handle!, did: entry.post.author?.did) } } : nil,
            onReportPost: isOwnPost(entry) ? nil : { likerActions.postToReport = entry },
            onTranslate: entry.post.safeRecord.text != nil ? { translateText(entry.post.safeRecord.text ?? "") } : nil,
            onMuteWord: nil,
            muteWordLabel: nil,
            onToggleInlineThread: {
                guard let account = accountStore.activeAccount,
                      let appPassword = accountStore.appPassword(for: account) else { return }
                Task { await viewModel.toggleInlineThread(uri: entry.post.uri, account: account, appPassword: appPassword, using: container.blueskyClient) }
            }
        )

        return TimelinePostRow(
            entry: entry,
            callbacks: postCallbacks,
            context: context,
            viewModel: viewModel,
            navigationPath: $navigationPath,
            aiClassifications: aiClassifications,
            isOwnPost: isOwnPost(entry)
        )
    }

    // MARK: - State views

    private var skeletonContent: some View {
        List {
            ForEach(0 ..< 10) { _ in
                SkeletonRow()
                    .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
    }

    private var newPostsBanner: some View {
        Text(loc("timeline.new_posts").replacingOccurrences(of: "{n}", with: "\(viewModel.newPostCount)"))
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Capsule().fill(Color.skyPrimary))
            .padding(.top, 8)
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.3)) {
                    viewModel.newPostCount = 0
                }
                Task { await refresh() }
            }
            .transition(.move(edge: .top).combined(with: .opacity))
            .task {
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                withAnimation { viewModel.newPostCount = 0 }
            }
    }

    // MARK: - Actions

    private func handleReply(_ entry: RichFeedEntry) {
        guard let account = accountStore.activeAccount,
              let appPassword = accountStore.appPassword(for: account),
              let cid = entry.post.cid else { return }
        composeContext = ComposeContext(
            account: account,
            appPassword: appPassword,
            isReply: true,
            parentURI: entry.post.uri,
            parentCID: cid,
            rootURI: entry.post.uri,
            rootCID: cid
        )
    }

    private func handleLike(_ entry: RichFeedEntry) {
        guard let account = accountStore.activeAccount,
              let appPassword = accountStore.appPassword(for: account) else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        Task {
            await viewModel.toggleLike(uri: entry.post.uri, account: account, appPassword: appPassword, using: container.blueskyClient)
        }
    }

    private func handleRepost(_ entry: RichFeedEntry) {
        guard let account = accountStore.activeAccount,
              let appPassword = accountStore.appPassword(for: account) else { return }
        Task {
            await viewModel.toggleRepost(uri: entry.post.uri, account: account, appPassword: appPassword, using: container.blueskyClient)
        }
    }

    private func handleQuote(_ entry: RichFeedEntry) {
        guard let account = accountStore.activeAccount,
              let appPassword = accountStore.appPassword(for: account),
              let cid = entry.post.cid else { return }
        composeContext = ComposeContext(
            account: account,
            appPassword: appPassword,
            isReply: false,
            uri: entry.post.uri,
            cid: cid
        )
    }

    private func loadInitial() async {
        guard let account = accountStore.activeAccount,
              let appPassword = accountStore.appPassword(for: account) else { return }
        initialLoadTask?.cancel()
        let task = Task {
            await viewModel.loadTimeline(account: account, appPassword: appPassword, using: container.blueskyClient)
        }
        initialLoadTask = task
        await task.value
    }

    private func loadMore() async {
        guard let account = accountStore.activeAccount,
              let appPassword = accountStore.appPassword(for: account) else { return }
        guard loadMoreTask == nil else { return }
        let task = Task {
            await viewModel.loadMore(account: account, appPassword: appPassword, using: container.blueskyClient)
        }
        loadMoreTask = task
        await task.value
        loadMoreTask = nil
    }

    private func refresh() async {
        guard let account = accountStore.activeAccount,
              let appPassword = accountStore.appPassword(for: account) else { return }
        await viewModel.refresh(account: account, appPassword: appPassword, using: container.blueskyClient)
    }

    private func isOwnPost(_ entry: RichFeedEntry) -> Bool {
        guard let activeDID = accountStore.activeAccount?.did else { return false }
        return entry.post.author?.did == activeDID
    }

    private func deletePost(_ entry: RichFeedEntry) async {
        guard let account = accountStore.activeAccount,
              let appPassword = accountStore.appPassword(for: account) else { return }
        let entryURI = entry.post.uri
        postToDelete = nil
        do {
            _ = try await container.post.deleteRecord(recordURI: entryURI, account: account, appPassword: appPassword)
        } catch {
            AppLogger.moderation.error("Failed to delete post: \(error.localizedDescription, privacy: .public)")
        }
        await refresh()
    }

    private func openProfile(_ handle: String) {
        guard let entry = viewModel.entries.first(where: { $0.post.author?.handle == handle || $0.post.author?.did == handle }),
              let author = entry.post.author else { return }
        profileToShow = BlueskyActor(did: author.did ?? handle, handle: author.handle ?? handle, displayName: author.displayName)
    }

    private func muteUser(handle: String, did: String?) async {
        guard let account = accountStore.activeAccount,
              let appPassword = accountStore.appPassword(for: account),
              let did else { return }
        do {
            try await container.social.muteActor(did: did, account: account, appPassword: appPassword)
            AppLogger.moderation.info("Muted @\(handle, privacy: .public)")
        } catch {
            AppLogger.moderation.error("Failed to mute @\(handle, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    private func blockUser(handle: String, did: String?) async {
        guard let account = accountStore.activeAccount,
              let appPassword = accountStore.appPassword(for: account),
              let did else { return }
        do {
            try await container.social.blockActor(did: did, account: account, appPassword: appPassword)
            AppLogger.moderation.info("Blocked @\(handle, privacy: .public)")
        } catch {
            AppLogger.moderation.error("Failed to block @\(handle, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    private func translateText(_ text: String) {
        guard let encoded = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://translate.google.com/?text=\(encoded)") else { return }
        UIApplication.shared.open(url)
    }

    private func classifyVisiblePosts() async {
        let posts = viewModel.entries
        let uncached = posts.filter { aiClassifications[$0.post.uri] == nil }
        guard !uncached.isEmpty else { return }
        let engine = InferenceEngine()
        var newScores = aiClassifications
        for entry in uncached {
            guard let text = entry.post.safeRecord.text, !text.isEmpty else { continue }
            let scores = engine.classify(text: text)
            newScores[entry.post.uri] = scores
        }
        aiClassifications = newScores
    }

    private func shareURL(for entry: RichFeedEntry) -> URL? {
        let uri = entry.post.uri
        guard let did = entry.post.author?.did else { return nil }
        let rkey = uri.split(separator: "/").last.map(String.init) ?? ""
        return URL(string: "https://bsky.app/profile/\(did)/post/\(rkey)")
    }
}

// MARK: - ShareSheet

private struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context _: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_: UIActivityViewController, context _: Context) {}
}
