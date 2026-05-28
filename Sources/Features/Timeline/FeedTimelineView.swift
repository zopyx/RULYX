import SwiftUI

/// Main timeline feed view — renders the active account's following feed
/// (or a custom Bluesky feed) with inline threads, like/repost/reply/quote
/// actions, post interactions (mute, block, report, translate, share),
/// and a "new posts" banner.
struct FeedTimelineView: View {
    @ObservedObject var viewModel: FeedTimelineViewModel
    @Binding var navigationPath: NavigationPath
    @EnvironmentObject var accountStore: AccountStore
    @EnvironmentObject var blueskyClient: LiveBlueskyClient
    @EnvironmentObject var workspaceStore: ModerationWorkspaceStore
    @EnvironmentObject var mutedWordsStore: MutedWordsStore
    @EnvironmentObject var analyticsStore: AnalyticsStore
    @State private var imagePreview: ImagePreviewCollection?
    @State private var videoPreviewURL: URL?
    @State private var showLikesForURI: String?
    @State private var initialLoadTask: Task<Void, Never>?
    @State private var loadMoreTask: Task<Void, Never>?
    @State private var composeContext: ComposeContext?
    @State private var showFeedPicker = false
    @State private var showNewPostComposer = false
    @State private var muteWordEntry: RichFeedEntry?
    @State private var showMuteConfirmation = false
    @State private var postToDelete: RichFeedEntry?
    @State private var editPostEntry: RichFeedEntry?
    @State private var profileToShow: BlueskyActor?
    @State private var postToShare: RichFeedEntry?
    @EnvironmentObject private var localizationManager: LocalizationManager
    @EnvironmentObject private var internalListStore: InternalListStore
    @StateObject private var likerActions = PostLikerActionsManager()

    // MARK: - Body

    var body: some View {
        Group {
            switch viewModel.state {
            case .initialLoading:
                skeletonContent
            case let .failed(msg):
                ContentUnavailableView(
                    loc("list.detail.alert_title"),
                    systemImage: "exclamationmark.bubble",
                    description: Text(msg)
                )
            case .empty:
                emptyStateContent
            default:
                listContent
            }
        }
        .pageTitle(loc("timeline.title"))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showNewPostComposer = true } label: {
                    Image(systemName: "square.and.pencil")
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
        .sheet(isPresented: $showFeedPicker) {
            FeedPickerView(feedStore: viewModel.feedStore)
        }
        .sheet(isPresented: $showNewPostComposer) {
            if let account = accountStore.activeAccount,
               let appPassword = accountStore.appPassword(for: account)
            {
                ComposePostView(
                    account: account,
                    appPassword: appPassword,
                    blueskyClient: blueskyClient,
                    onComplete: { refreshAfterAction() }
                )
                .environmentObject(accountStore)
                .environmentObject(blueskyClient)
            }
        }
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
                    onComplete: { refreshAfterAction() }
                )
                .presentationDetents([.medium, .large])
            } else {
                ComposePostView(
                    account: context.account,
                    appPassword: context.appPassword,
                    blueskyClient: blueskyClient,
                    onComplete: { refreshAfterAction() },
                    quote: (context.uri, context.cid)
                )
                .environmentObject(accountStore)
                .environmentObject(blueskyClient)
            }
        }
        .sheet(item: $editPostEntry) { entry in
            if let account = accountStore.activeAccount,
               let appPassword = accountStore.appPassword(for: account)
            {
                ComposePostView(
                    account: account,
                    appPassword: appPassword,
                    blueskyClient: blueskyClient,
                    onComplete: { refreshAfterAction() },
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
                    ToolbarItem(placement: .topBarTrailing) {
                        ToolbarCloseButton(action: { profileToShow = nil })
                    }
                }
                .environmentObject(accountStore)
                .environmentObject(blueskyClient)
                .environmentObject(workspaceStore)
                .environmentObject(mutedWordsStore)
                .environmentObject(analyticsStore)
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
        .task {
            await loadInitial()
            guard let account = accountStore.activeAccount,
                  let appPassword = accountStore.appPassword(for: account) else { return }
            viewModel.startPolling(account: account, appPassword: appPassword, using: blueskyClient)
        }
        .task {
            guard let account = accountStore.activeAccount,
                  let appPassword = accountStore.appPassword(for: account) else { return }
            await likerActions.loadAvailableTargetLists(using: blueskyClient, internalListStore: internalListStore, account: account, appPassword: appPassword)
        }
        .onDisappear {
            initialLoadTask?.cancel()
            loadMoreTask?.cancel()
            loadMoreTask = nil
            viewModel.stopPolling()
        }
        .onChange(of: viewModel.feedStore.customFeedURI) { _, _ in
            viewModel.prepareForFeedChange()
            Task { await refresh() }
        }
        .onChange(of: accountStore.activeAccount?.did) { _, _ in
            viewModel.stopPolling()
            Task {
                await loadInitial()
                guard let account = accountStore.activeAccount,
                      let appPassword = accountStore.appPassword(for: account) else { return }
                viewModel.startPolling(account: account, appPassword: appPassword, using: blueskyClient)
            }
        }
        .postLikerActions(manager: likerActions)
    }

    // MARK: - List content

    private var listContent: some View {
        List {
            ForEach(viewModel.visibleEntries, id: \.post.uri) { entry in
                postRowView(for: entry)
            }
            if viewModel.state.hasMore {
                Color.clear
                    .frame(height: 1)
                    .listRowSeparator(.hidden)
                    .onAppear {
                        Task { await loadMore() }
                    }
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
            if viewModel.state == .exhausted {
                Text(loc: "timeline.end")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
                    .listRowSeparator(.hidden)
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
        .overlay(alignment: .top) {
            if viewModel.newPostCount > 0 {
                newPostsBanner
            }
        }
    }

    // MARK: - Post row

    private func postRowView(for entry: RichFeedEntry) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            PostRowView(
                entry: entry,
                style: .full,
                callbacks: PostRowCallbacks(
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
                        likerActions.handleAddAllLikersToList(postURI: entry.post.uri, list: list, using: blueskyClient, fetchAccount: fetchAccount, fetchPassword: fetchPassword, activeAccount: activeAccount, activePassword: activePassword, internalListStore: internalListStore)
                    },
                    onClassify: { likerActions.postToClassify = entry },
                    isLiked: viewModel.effectiveIsLiked(uri: entry.post.uri),
                    isReposted: viewModel.effectiveIsReposted(uri: entry.post.uri),
                    overrideLikeCount: viewModel.effectiveLikeCount(uri: entry.post.uri),
                    overrideRepostCount: viewModel.effectiveRepostCount(uri: entry.post.uri),
                    availableLikerTargetLists: likerActions.availableTargetLists
                )
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
                if let word = muteWord(from: entry) {
                    Divider()
                    Button {
                        viewModel.mutedWords.add(word)
                    } label: {
                        Label(loc("timeline.mute_word").replacingOccurrences(of: "{word}", with: word), systemImage: "textformat.subscript")
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

    private var emptyStateContent: some View {
        let isCustomFeed = viewModel.feedStore.isUsingCustomFeed
        return ContentUnavailableView {
            Label(isCustomFeed ? loc("timeline.empty_custom") : loc("timeline.empty"), systemImage: "bubble.left.and.bubble.right")
        } description: {
            Text(verbatim: isCustomFeed ? loc("timeline.empty_custom_desc") : loc("timeline.empty_desc"))
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

    private func refreshAfterAction() {
        Task { await refresh() }
    }

    private func loadInitial() async {
        guard let account = accountStore.activeAccount,
              let appPassword = accountStore.appPassword(for: account) else { return }
        initialLoadTask?.cancel()
        let task = Task {
            await viewModel.loadTimeline(account: account, appPassword: appPassword, using: blueskyClient)
        }
        initialLoadTask = task
        await task.value
    }

    private func loadMore() async {
        guard let account = accountStore.activeAccount,
              let appPassword = accountStore.appPassword(for: account) else { return }
        guard loadMoreTask == nil else { return }
        let task = Task {
            await viewModel.loadMore(account: account, appPassword: appPassword, using: blueskyClient)
        }
        loadMoreTask = task
        defer { loadMoreTask = nil }
        await task.value
    }

    private func isOwnPost(_ entry: RichFeedEntry) -> Bool {
        guard let activeDID = accountStore.activeAccount?.did else { return false }
        return entry.post.author?.did == activeDID
    }

    private func deletePost(_ entry: RichFeedEntry) async {
        guard let account = accountStore.activeAccount,
              let appPassword = accountStore.appPassword(for: account) else { return }
        let entryURI = entry.post.uri
        let removedIndex = viewModel.entries.firstIndex(where: { $0.post.uri == entryURI })
        viewModel.removeEntry(uri: entryURI)
        postToDelete = nil
        do {
            _ = try await blueskyClient.deleteRecord(recordURI: entryURI, account: account, appPassword: appPassword)
        } catch {
            if let removedIndex {
                viewModel.insertEntry(entry, at: removedIndex)
            }
            AppLogger.moderation.error("Failed to delete post: \(error.localizedDescription, privacy: .public)")
        }
        await refresh()
    }

    private func openProfile(_ handle: String) {
        guard let entry = viewModel.visibleEntries.first(where: { $0.post.author?.handle == handle || $0.post.author?.did == handle }),
              let author = entry.post.author else { return }
        profileToShow = BlueskyActor(did: author.did ?? handle, handle: author.handle ?? handle, displayName: author.displayName)
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

    private func muteWord(from entry: RichFeedEntry) -> String? {
        guard let text = entry.post.safeRecord.text, !text.isEmpty else { return nil }
        let words = text
            .components(separatedBy: .whitespacesAndNewlines)
            .map { $0.trimmingCharacters(in: .punctuationCharacters) }
            .filter { $0.count > 3 && !$0.hasPrefix("@") && !$0.hasPrefix("http") && !$0.hasPrefix("at://") }
        for word in words {
            if !viewModel.mutedWords.contains(word) {
                return word
            }
        }
        return words.first
    }

    private func translateText(_ text: String) {
        guard let encoded = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://translate.google.com/?text=\(encoded)") else { return }
        UIApplication.shared.open(url)
    }

    private func refresh() async {
        guard let account = accountStore.activeAccount,
              let appPassword = accountStore.appPassword(for: account) else { return }
        await viewModel.refresh(account: account, appPassword: appPassword, using: blueskyClient)
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

    private func shareURL(for entry: RichFeedEntry) -> URL? {
        let uri = entry.post.uri
        guard let did = entry.post.author?.did else { return nil }
        let rkey = uri.split(separator: "/").last.map(String.init) ?? ""
        return URL(string: "https://bsky.app/profile/\(did)/post/\(rkey)")
    }
}

private struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context _: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_: UIActivityViewController, context _: Context) {}
}

private struct InlineReplyRow: View {
    let node: ThreadNode
    var onNavigateToThread: (() -> Void)?

    var body: some View {
        let author = node.post.author ?? RichAuthor(did: "", handle: "unknown", displayName: nil, avatar: nil)
        let record = node.post.record ?? RichRecord(text: "", createdAt: "")

        Button {
            onNavigateToThread?()
        } label: {
            HStack(alignment: .top, spacing: 8) {
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 2)
                    .frame(maxHeight: .infinity)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        if let avatarURL = author.avatar.flatMap(URL.init) {
                            AsyncImage(url: avatarURL) { image in
                                image.resizable().scaledToFill()
                            } placeholder: {
                                Circle().fill(Color.skyPrimary.opacity(0.16))
                            }
                            .frame(width: 20, height: 20)
                            .clipShape(Circle())
                        }
                        Text(author.displayName ?? author.handle ?? "")
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                        if let handle = author.handle {
                            Text("@\(handle)")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                        Spacer()
                        if node.post.likeCount.map({ $0 > 0 }) ?? false {
                            HStack(spacing: 2) {
                                Image(systemName: "heart")
                                    .font(.caption2)
                                Text("\(node.post.likeCount ?? 0)")
                                    .font(.caption2)
                            }
                            .foregroundStyle(.tertiary)
                        }
                    }
                    if let text = record.text, !text.isEmpty {
                        Text(text)
                            .font(.subheadline)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .padding(.vertical, 4)
    }
}

#Preview {
    FeedTimelineView(viewModel: FeedTimelineViewModel(), navigationPath: .constant(NavigationPath()))
        .environmentObject(AccountStore(preview: true))
        .environmentObject(PreviewBlueskyClient())
}
