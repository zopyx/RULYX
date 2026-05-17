import SwiftUI

struct FeedTimelineView: View {
    @ObservedObject var viewModel: FeedTimelineViewModel
    @EnvironmentObject var accountStore: AccountStore
    @EnvironmentObject var blueskyClient: LiveBlueskyClient
    @EnvironmentObject var workspaceStore: ModerationWorkspaceStore
    @EnvironmentObject var mutedWordsStore: MutedWordsStore
    @EnvironmentObject var analyticsStore: AnalyticsStore
    @State private var selectedPostURI: String?
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
    @State private var profileToShow: BlueskyActor?

    var body: some View {
        NavigationStack {
            Group {
                switch viewModel.state {
                case .initialLoading:
                    skeletonContent
                case .failed(let msg):
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
            .navigationTitle(loc("timeline.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showNewPostComposer = true } label: {
                        Image(systemName: "square.and.pencil")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { Task { await refresh() } } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .keyboardShortcut("r", modifiers: .command)
                }
            }
            .sheet(item: $selectedPostURI) { uri in
                ThreadView(postURI: uri)
                    .environmentObject(accountStore)
                    .environmentObject(blueskyClient)
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
                    ComposePostView(
                        account: context.account,
                        appPassword: context.appPassword,
                        blueskyClient: blueskyClient,
                        onComplete: { refreshAfterAction() },
                        replyTo: (context.parentURI, context.parentCID, context.rootURI, context.rootCID)
                    )
                    .environmentObject(accountStore)
                    .environmentObject(blueskyClient)
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
                            Button(loc("actions.close")) { profileToShow = nil }
                        }
                    }
                    .environmentObject(accountStore)
                    .environmentObject(blueskyClient)
                    .environmentObject(workspaceStore)
                    .environmentObject(mutedWordsStore)
                    .environmentObject(analyticsStore)
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
            } message: { post in
                Text(verbatim: loc("post.delete.message"))
            }
            .task {
                await loadInitial()
                guard let account = accountStore.activeAccount,
                      let appPassword = accountStore.appPassword(for: account) else { return }
                viewModel.startPolling(account: account, appPassword: appPassword, using: blueskyClient)
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
        }
    }

    private var listContent: some View {
        List {
            ForEach(viewModel.visibleEntries, id: \.post.uri) { entry in
                    PostRowView(
                        entry: entry,
                        onTapThread: {
                            selectedPostURI = entry.post.uri
                        },
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
                        onReply: { handleReply(entry) },
                        onLike: { handleLike(entry) },
                        onShowLikes: { showLikesForURI = entry.post.uri },
                        isLiked: entry.post.isLikedByMe,
                        isReposted: entry.post.isRepostedByMe,
                        onRepost: { handleRepost(entry) },
                        onQuote: { handleQuote(entry) },
                        onCopy: { UIPasteboard.general.string = entry.post.safeRecord.text },
                        onTranslate: { translateText(entry.post.safeRecord.text ?? "") },
                        onDeletePost: isOwnPost(entry) ? { postToDelete = entry } : nil,
                        onOpenProfile: { handle in openProfile(handle) }
                    )
                    .contextMenu {
                        if let word = muteWord(from: entry) {
                            Button {
                                viewModel.mutedWords.add(word)
                            } label: {
                                Label {
                                    Text(verbatim: loc("timeline.mute_word").replacingOccurrences(of: "{word}", with: word))
                                } icon: {
                                    Image(systemName: "eye.slash")
                                }
                            }
                        }
                    }
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
                Text(verbatim: loc("timeline.end"))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
                    .listRowSeparator(.hidden)
            }
            if case .loadMoreFailed(let msg) = viewModel.state {
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
              let appPassword = accountStore.appPassword(for: account),
              let cid = entry.post.cid else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        Task {
            do {
                if entry.post.isLikedByMe, let likeURI = entry.post.myLikeURI {
                    _ = try await blueskyClient.deleteRecord(recordURI: likeURI, account: account, appPassword: appPassword)
                } else {
                    _ = try await blueskyClient.createLike(uri: entry.post.uri, cid: cid, account: account, appPassword: appPassword)
                }
                await refresh()
            } catch {
                AppLogger.moderation.error("Like failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func handleRepost(_ entry: RichFeedEntry) {
        guard let account = accountStore.activeAccount,
              let appPassword = accountStore.appPassword(for: account),
              let cid = entry.post.cid else { return }
        Task {
            do {
                if entry.post.isRepostedByMe, let repostURI = entry.post.myRepostURI {
                    _ = try await blueskyClient.deleteRecord(recordURI: repostURI, account: account, appPassword: appPassword)
                } else {
                    _ = try await blueskyClient.createRepost(uri: entry.post.uri, cid: cid, account: account, appPassword: appPassword)
                }
                await refresh()
            } catch {
                AppLogger.moderation.error("Repost failed: \(error.localizedDescription, privacy: .public)")
            }
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
}

private struct ComposeContext: Identifiable {
    let id = UUID()
    let account: AppAccount
    let appPassword: String
    let isReply: Bool
    var parentURI: String = ""
    var parentCID: String = ""
    var rootURI: String = ""
    var rootCID: String = ""
    var uri: String = ""
    var cid: String = ""
}

#Preview {
    FeedTimelineView(viewModel: FeedTimelineViewModel())
        .environmentObject(AccountStore(preview: true))
        .environmentObject(PreviewBlueskyClient())
}
