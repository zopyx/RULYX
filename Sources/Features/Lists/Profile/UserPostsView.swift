import SwiftUI

// MARK: - Retroactive conformances

extension String: @retroactive Identifiable {
    public var id: String {
        self
    }
}

extension URL: @retroactive Identifiable {
    public var id: String {
        absoluteString
    }
}

// MARK: - UserPostsView

/// Browse and search posts for a given user DID, with pagination,
/// date filtering, image/video preview, post liker actions, and
/// full timeline interaction features (like/repost/reply/quote,
/// inline thread expansion, context menus, swipe actions, compose).
struct UserPostsView: View {
    let did: String
    let displayName: String
    let searchAccount: AppAccount?

    @StateObject private var viewModel: UserPostsViewModel
    @EnvironmentObject var accountStore: AccountStore
    @EnvironmentObject var blueskyClient: LiveBlueskyClient
    @EnvironmentObject private var internalListStore: InternalListStore
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var localizationManager: LocalizationManager

    @State private var navigationPath = NavigationPath()
    @State private var selectedPostURI: String?
    @StateObject private var likerActions = PostLikerActionsManager()
    @State private var imagePreview: ImagePreviewCollection?
    @State private var videoPreviewURL: URL?
    @State private var showLikesForURI: String?
    @State private var showProfileFor: BlueskyActor?
    @State private var shareFileURL: URL?
    @State private var initialLoadTask: Task<Void, Never>?
    @State private var loadMoreTask: Task<Void, Never>?

    // Compose / interaction state
    @State private var composeContext: ComposeContext?
    @State private var showNewPostComposer = false
    @State private var editPostEntry: RichFeedEntry?
    @State private var postToDelete: RichFeedEntry?
    @State private var postToShare: RichFeedEntry?
    @State private var profileToShow: BlueskyActor?

    init(did: String, displayName: String, searchAccount: AppAccount? = nil) {
        self.did = did
        self.displayName = displayName
        self.searchAccount = searchAccount
        _viewModel = StateObject(wrappedValue: UserPostsViewModel(did: did))
    }

    // MARK: - Body

    var body: some View {
        NavigationStack(path: $navigationPath) {
            Group {
                if viewModel.isLoading, viewModel.posts.isEmpty {
                    LoadingPanel(message: loc("profile.posts.loading"))
                } else if let error = viewModel.errorMessage, viewModel.posts.isEmpty {
                    if error.localizedCaseInsensitiveContains("blocked") {
                        ContentUnavailableView(
                            loc("profile.blocked.title"),
                            systemImage: "hand.raised.slash.fill",
                            description: Text(loc: "profile.blocked.posts_desc")
                        )
                    } else {
                        ContentUnavailableView(
                            loc("list.detail.alert_title"),
                            systemImage: "exclamationmark.bubble",
                            description: Text(error)
                        )
                    }
                } else if viewModel.posts.isEmpty {
                    ContentUnavailableView(
                        loc("profile.posts.empty"),
                        systemImage: "bubble.left",
                        description: Text(loc: "profile.posts.empty_desc")
                    )
                } else {
                    listContent
                }
            }
            .pageTitle(loc("profile.posts.title_by").replacingOccurrences(of: "{name}", with: displayName))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if !viewModel.posts.isEmpty {
                        exportMenu
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    ToolbarCloseButton()
                }
            }
            .overlay(alignment: .bottomTrailing) {
                composeFAB
            }
            .modifier(MediaSheetsModifier(
                selectedPostURI: $selectedPostURI,
                shareFileURL: $shareFileURL,
                imagePreview: $imagePreview,
                videoPreviewURL: $videoPreviewURL,
                showLikesForURI: $showLikesForURI,
                accountStore: accountStore,
                blueskyClient: blueskyClient,
                searchAccount: searchAccount
            ))
            .modifier(ComposeSheetsModifier(
                composeContext: $composeContext,
                showNewPostComposer: $showNewPostComposer,
                editPostEntry: $editPostEntry,
                profileToShow: $profileToShow,
                postToShare: $postToShare,
                postToDelete: $postToDelete,
                accountStore: accountStore,
                blueskyClient: blueskyClient,
                refresh: refresh
            ))
            .navigationDestination(for: TimelineRoute.self) { route in
                switch route {
                case let .thread(postURI):
                    ThreadView(postURI: postURI, searchAccount: searchAccount)
                }
            }
            .navigationDestination(item: $showProfileFor) { actor in
                BlueskyProfileView(
                    member: BlueskyListMember(recordURI: "userposts:\(actor.did)", actor: actor),
                    list: nil
                )
                .environmentObject(accountStore)
                .environmentObject(blueskyClient)
            }
            .task {
                await loadInitial()
            }
            .onDisappear {
                initialLoadTask?.cancel()
                loadMoreTask?.cancel()
            }
            .task {
                guard let account = accountStore.activeAccount,
                      let appPassword = accountStore.appPassword(for: account) else { return }
                await likerActions.loadAvailableTargetLists(using: blueskyClient, internalListStore: internalListStore, account: account, appPassword: appPassword)
            }
            .postLikerActions(manager: likerActions)
        }
    }

    /// Main list with search bar, date filter, and paginated post rows.
    private var listContent: some View {
        List {
            searchSection

            if viewModel.isScanning, let label = viewModel.scanProgressLabel {
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

            ForEach(viewModel.sortedFilteredPosts, id: \.post.uri) { entry in
                postRowView(for: entry)
                    .postInfiniteScroll(
                        entry: entry,
                        entries: viewModel.sortedFilteredPosts,
                        hasMore: viewModel.hasMore,
                        isLoadingMore: viewModel.isLoadingMore,
                        loadMore: { await loadMore() }
                    )
            }
            if viewModel.isLoadingMore {
                HStack {
                    Spacer()
                    ProgressView()
                        .scaleEffect(0.8)
                    Spacer()
                }
                .listRowSeparator(.hidden)
            }
            if !viewModel.hasMore, !viewModel.posts.isEmpty {
                Text(loc("profile.posts.end"))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
                    .listRowSeparator(.hidden)
            }
            if !viewModel.searchText.isEmpty, viewModel.sortedFilteredPosts.isEmpty {
                Text(loc("profile.posts.no_matches"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .refreshable {
            await refresh()
        }
    }

    @ViewBuilder
    private var composeFAB: some View {
        if !viewModel.posts.isEmpty {
            Button {
                showNewPostComposer = true
            } label: {
                Image(systemName: "square.and.pencil")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(Circle().fill(Color.skyPrimary))
                    .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
            }
            .accessibilityLabel(loc("timeline.new_post"))
            .padding(.trailing, 16)
            .padding(.bottom, 16)
            .transition(.scale.combined(with: .opacity))
        }
    }

    // MARK: - Post row

    private func postRowView(for entry: RichFeedEntry) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            PostRowView(
                entry: entry,
                style: .full,
                callbacks: postRowCallbacks(for: entry)
            )
            .contextMenu {
                if let text = entry.post.safeRecord.text {
                    Button { UIPasteboard.general.string = text } label: {
                        Label(loc("post.copy"), systemImage: "doc.on.doc")
                    }
                }
                Button { postToShare = entry } label: {
                    Label(loc("post.share"), systemImage: "square.and.arrow.up")
                }
                Divider()
                if let handle = entry.post.author?.handle {
                    Button {
                        Task { await muteUser(handle: handle, did: entry.post.author?.did) }
                    } label: {
                        Label(String(format: loc("post.mute_user"), "@\(handle)"), systemImage: "eye.slash")
                    }
                    Button {
                        Task { await blockUser(handle: handle, did: entry.post.author?.did) }
                    } label: {
                        Label(String(format: loc("post.block_user"), "@\(handle)"), systemImage: "hand.raised")
                    }
                }
                Divider()
                if !isOwnPost(entry) {
                    Button { likerActions.postToReport = entry } label: {
                        Label(loc("post.report"), systemImage: "exclamationmark.bubble")
                    }
                }
                if let text = entry.post.safeRecord.text {
                    Button { translateText(text) } label: {
                        Label(loc("post.translate"), systemImage: "globe")
                    }
                }
            }

            inlineThreadSection(for: entry)
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                handleLike(entry)
            } label: {
                Image(systemName: viewModel.effectiveIsLiked(uri: entry.post.uri) ? "heart.slash" : "heart")
            }
            .tint(viewModel.effectiveIsLiked(uri: entry.post.uri) ? .gray : .pink)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button {
                handleReply(entry)
            } label: {
                Image(systemName: "arrowshape.turn.up.left")
            }
            .tint(.blue)
        }
    }

    private func postRowCallbacks(for entry: RichFeedEntry) -> PostRowCallbacks {
        let authorCB = makeAuthorCallbacks(author: entry.post.author, accountStore: accountStore, blueskyClient: blueskyClient, internalListStore: internalListStore)
        return PostRowCallbacks(
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
                likerActions.handleBlockAllLikers(postURI: entry.post.uri, using: blueskyClient, fetchAccount: account, fetchPassword: appPassword)
            },
            onAddAllLikersToList: { list in
                guard let fetchAccount = accountStore.activeAccount,
                      let fetchPassword = accountStore.appPassword(for: fetchAccount),
                      let activeAccount = accountStore.activeAccount,
                      let activePassword = accountStore.appPassword(for: activeAccount) else { return }
                likerActions.handleAddAllLikersToList(
                    postURI: entry.post.uri, list: list, using: blueskyClient,
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
    }

    @ViewBuilder
    private func inlineThreadSection(for entry: RichFeedEntry) -> some View {
        let uri = entry.post.uri
        let replyCount = entry.post.replyCount ?? 0
        if replyCount > 0 {
            if viewModel.expandedThreadURIs.contains(uri), let thread = viewModel.inlineThreads[uri] {
                VStack(spacing: 0) {
                    ForEach(Array((thread.replies ?? []).prefix(3).enumerated()), id: \.offset) { _, reply in
                        InlineReplyRow(node: reply, onNavigateToThread: {
                            navigationPath.append(TimelineRoute.thread(postURI: reply.post.uri ?? uri))
                        })
                        .padding(.leading, 16)
                    }
                    if (thread.replies?.count ?? 0) > 3 {
                        Button {
                            navigationPath.append(TimelineRoute.thread(postURI: uri))
                        } label: {
                            HStack {
                                Text(loc("timeline.view_all_replies"))
                                    .font(.caption.weight(.medium))
                                Spacer()
                                Text("+\((thread.replies?.count ?? 0) - 3)")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else {
                Button {
                    Task {
                        guard let account = accountStore.activeAccount,
                              let appPassword = accountStore.appPassword(for: account) else { return }
                        await viewModel.toggleInlineThread(uri: uri, account: account, appPassword: appPassword, using: blueskyClient)
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "bubble.left")
                            .font(.caption)
                        Text(loc("timeline.show_replies").replacingOccurrences(of: "{n}", with: "\(replyCount)"))
                            .font(.caption.weight(.medium))
                        Spacer()
                        Image(systemName: "chevron.down")
                            .font(.caption2)
                    }
                    .foregroundStyle(Color.skyPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.skyPrimary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// Search text field and date filter toggle button.
    private var searchSection: some View {
        Section {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.tertiary)
                    .font(.subheadline)
                TextField(loc("profile.posts.search"), text: $viewModel.searchText)
                    .textFieldStyle(.plain)
                    .font(.subheadline)
                if !viewModel.searchText.isEmpty {
                    Button {
                        viewModel.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
                dateFilterButton
            }
            .padding(.vertical, 4)

            if viewModel.fromDate != nil || viewModel.toDate != nil {
                dateFilterPickers
            }
        }
    }

    /// Toggle for activating/deactivating the date range filter.
    private var dateFilterButton: some View {
        let isActive = viewModel.fromDate != nil || viewModel.toDate != nil
        return Button {
            if isActive {
                viewModel.fromDate = nil
                viewModel.toDate = nil
            } else {
                viewModel.fromDate = Calendar.current.date(byAdding: .month, value: -1, to: Date())
                viewModel.toDate = Date()
            }
        } label: {
            Image(systemName: isActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(width: 36, height: 36)
        }
    }

    /// From/to date pickers for filtering posts by date range.
    private var dateFilterPickers: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(loc("profile.posts.from_date"))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                DatePicker(
                    "",
                    selection: Binding(
                        get: { viewModel.fromDate ?? Date() },
                        set: { viewModel.fromDate = $0 }
                    ),
                    in: ...Date(),
                    displayedComponents: .date
                )
                .labelsHidden()
                .datePickerStyle(.compact)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(loc("profile.posts.to_date"))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                DatePicker(
                    "",
                    selection: Binding(
                        get: { viewModel.toDate ?? Date() },
                        set: { viewModel.toDate = $0 }
                    ),
                    in: ...Date(),
                    displayedComponents: .date
                )
                .labelsHidden()
                .datePickerStyle(.compact)
            }
        }
        .padding(.bottom, 6)
    }

    /// Export menu with CSV and JSON options.
    private var exportMenu: some View {
        Menu {
            Button {
                let csv = viewModel.exportCSV()
                let url = FileManager.default.temporaryDirectory.appendingPathComponent("posts.csv")
                try? csv.write(to: url, atomically: true, encoding: .utf8)
                shareFileURL = url
            } label: {
                Label { Text(loc("profile.export.csv")) } icon: { Image(systemName: "arrow.down.doc") }
            }
            Button {
                let json = viewModel.exportJSON()
                let url = FileManager.default.temporaryDirectory.appendingPathComponent("posts.json")
                try? json.write(to: url, options: .atomic)
                shareFileURL = url
            } label: {
                Label { Text(loc("profile.export.json")) } icon: { Image(systemName: "arrow.down.doc") }
            }
        } label: {
            Image(systemName: "arrow.down.doc")
        }
    }

    // MARK: - Actions

    private func handleReply(_ entry: RichFeedEntry) {
        guard let account = accountStore.activeAccount,
              let appPassword = accountStore.appPassword(for: account),
              let cid = entry.post.cid else { return }
        let uri = entry.post.uri
        composeContext = ComposeContext(
            account: account,
            appPassword: appPassword,
            isReply: true,
            parentURI: uri,
            parentCID: cid,
            rootURI: uri,
            rootCID: cid
        )
    }

    private func handleLike(_ entry: RichFeedEntry) {
        guard let account = accountStore.activeAccount,
              let appPassword = accountStore.appPassword(for: account) else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        Task {
            await viewModel.toggleLike(uri: entry.post.uri, account: account, appPassword: appPassword, using: blueskyClient)
        }
    }

    private func handleRepost(_ entry: RichFeedEntry) {
        guard let account = accountStore.activeAccount,
              let appPassword = accountStore.appPassword(for: account) else { return }
        Task {
            await viewModel.toggleRepost(uri: entry.post.uri, account: account, appPassword: appPassword, using: blueskyClient)
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

    /// Loads the first page of posts, cancelling any existing load task.
    private func loadInitial() async {
        guard let account = searchAccount ?? accountStore.activeAccount,
              let appPassword = accountStore.appPassword(for: account) else { return }
        initialLoadTask?.cancel()
        let task = Task {
            await viewModel.loadPosts(account: account, appPassword: appPassword, using: blueskyClient)
        }
        initialLoadTask = task
        await task.value
    }

    /// Loads the next page of posts, guarding against duplicate calls.
    private func loadMore() async {
        guard let account = searchAccount ?? accountStore.activeAccount,
              let appPassword = accountStore.appPassword(for: account) else { return }
        guard loadMoreTask == nil else { return }
        let task = Task {
            await viewModel.loadMorePosts(account: account, appPassword: appPassword, using: blueskyClient)
        }
        loadMoreTask = task
        await task.value
        loadMoreTask = nil
    }

    /// Pull-to-refresh that resets and reloads all posts.
    private func refresh() async {
        guard let account = searchAccount ?? accountStore.activeAccount,
              let appPassword = accountStore.appPassword(for: account) else { return }
        await viewModel.refresh(account: account, appPassword: appPassword, using: blueskyClient)
    }

    private func isOwnPost(_ entry: RichFeedEntry) -> Bool {
        guard let activeDID = accountStore.activeAccount?.did else { return false }
        return entry.post.author?.did == activeDID
    }

    private func openProfile(_ handle: String) {
        guard let entry = viewModel.sortedFilteredPosts.first(where: { $0.post.author?.handle == handle || $0.post.author?.did == handle }),
              let author = entry.post.author else { return }
        profileToShow = BlueskyActor(did: author.did ?? handle, handle: author.handle ?? handle, displayName: author.displayName)
    }

    private func muteUser(handle: String, did: String?) async {
        guard let account = accountStore.activeAccount,
              let appPassword = accountStore.appPassword(for: account),
              let did else { return }
        do {
            try await blueskyClient.muteActor(did: did, account: account, appPassword: appPassword)
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
            try await blueskyClient.blockActor(did: did, account: account, appPassword: appPassword)
            AppLogger.moderation.info("Blocked @\(handle, privacy: .public)")
        } catch {
            AppLogger.moderation.error("Failed to block @\(handle, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Opens Google Translate in the browser with the selected text.
    private func translateText(_ text: String) {
        guard let encoded = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://translate.google.com/?text=\(encoded)") else { return }
        UIApplication.shared.open(url)
    }
}

// MARK: - MediaSheetsModifier

struct MediaSheetsModifier: ViewModifier {
    @Binding var selectedPostURI: String?
    @Binding var shareFileURL: URL?
    @Binding var imagePreview: ImagePreviewCollection?
    @Binding var videoPreviewURL: URL?
    @Binding var showLikesForURI: String?

    let accountStore: AccountStore
    let blueskyClient: LiveBlueskyClient
    let searchAccount: AppAccount?

    func body(content: Content) -> some View {
        content
            .sheet(item: $selectedPostURI) { uri in
                NavigationStack {
                    ThreadView(postURI: uri, searchAccount: searchAccount)
                        .environmentObject(accountStore)
                        .environmentObject(blueskyClient)
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
                    .environmentObject(blueskyClient)
            }
    }
}

// MARK: - ComposeSheetsModifier

struct ComposeSheetsModifier: ViewModifier {
    @Binding var composeContext: ComposeContext?
    @Binding var showNewPostComposer: Bool
    @Binding var editPostEntry: RichFeedEntry?
    @Binding var profileToShow: BlueskyActor?
    @Binding var postToShare: RichFeedEntry?
    @Binding var postToDelete: RichFeedEntry?

    let accountStore: AccountStore
    let blueskyClient: LiveBlueskyClient
    let refresh: () async -> Void

    @EnvironmentObject private var internalListStore: InternalListStore

    func body(content: Content) -> some View {
        content
            .sheet(item: $composeContext) { context in
                if context.isReply {
                    ReplyComposerView(
                        account: context.account,
                        appPassword: context.appPassword,
                        blueskyClient: blueskyClient,
                        parentURI: context.parentURI,
                        parentCID: context.parentCID,
                        rootURI: context.rootURI,
                        rootCID: context.rootCID,
                        onComplete: { Task { await refresh() } }
                    )
                    .presentationDetents([.medium, .large])
                } else {
                    ComposePostView(
                        account: context.account,
                        appPassword: context.appPassword,
                        blueskyClient: blueskyClient,
                        onComplete: { Task { await refresh() } },
                        quote: (context.uri, context.cid)
                    )
                    .environmentObject(accountStore)
                    .environmentObject(blueskyClient)
                }
            }
            .sheet(isPresented: $showNewPostComposer) {
                if let account = accountStore.activeAccount, let appPassword = accountStore.appPassword(for: account) {
                    ComposePostView(
                        account: account,
                        appPassword: appPassword,
                        blueskyClient: blueskyClient,
                        onComplete: { Task { await refresh() } }
                    )
                    .environmentObject(accountStore)
                    .environmentObject(blueskyClient)
                }
            }
            .sheet(item: $editPostEntry) { entry in
                if let account = accountStore.activeAccount, let appPassword = accountStore.appPassword(for: account) {
                    ComposePostView(
                        account: account,
                        appPassword: appPassword,
                        blueskyClient: blueskyClient,
                        onComplete: { Task { await refresh() } },
                        editPost: entry
                    )
                    .environmentObject(accountStore)
                    .environmentObject(blueskyClient)
                }
            }
            .sheet(item: $profileToShow) { actor in
                NavigationStack {
                    BlueskyProfileView(
                        member: BlueskyListMember(
                            recordURI: "profile:\(actor.did)",
                            actor: actor
                        ),
                        list: nil
                    )
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button(loc("actions.done")) { profileToShow = nil }
                        }
                    }
                    .environmentObject(accountStore)
                    .environmentObject(blueskyClient)
                }
            }
            .sheet(item: $postToShare) { entry in
                if let url = shareURL(for: entry) {
                    ShareSheet(activityItems: [url])
                }
            }
            .confirmationDialog(
                loc("post.delete.confirm"),
                isPresented: .init(get: { postToDelete != nil }, set: { if !$0 { postToDelete = nil } }),
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
    }

    private func deletePost(_ entry: RichFeedEntry) async {
        guard let account = accountStore.activeAccount,
              let appPassword = accountStore.appPassword(for: account) else { return }
        let entryURI = entry.post.uri
        postToDelete = nil
        do {
            _ = try await blueskyClient.deleteRecord(recordURI: entryURI, account: account, appPassword: appPassword)
        } catch {
            AppLogger.moderation.error("Failed to delete post from sheets: \(error.localizedDescription, privacy: .public)")
        }
        await refresh()
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
