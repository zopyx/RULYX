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
/// date filtering, image/video preview, and post liker actions.
struct UserPostsView: View {
    let did: String
    let displayName: String
    let searchAccount: AppAccount?

    @StateObject private var viewModel: UserPostsViewModel
    @EnvironmentObject var accountStore: AccountStore
    @EnvironmentObject var blueskyClient: LiveBlueskyClient
    @EnvironmentObject private var internalListStore: InternalListStore
    @Environment(\.dismiss) private var dismiss
    @State private var selectedPostURI: String?
    @StateObject private var likerActions = PostLikerActionsManager()
    @State private var imagePreview: ImagePreviewCollection?
    @State private var videoPreviewURL: URL?
    @State private var showLikesForURI: String?
    @State private var showProfileFor: BlueskyActor?
    @State private var shareFileURL: URL?
    @State private var initialLoadTask: Task<Void, Never>?
    @State private var loadMoreTask: Task<Void, Never>?

    init(did: String, displayName: String, searchAccount: AppAccount? = nil) {
        self.did = did
        self.displayName = displayName
        self.searchAccount = searchAccount
        _viewModel = StateObject(wrappedValue: UserPostsViewModel(did: did))
    }

    @EnvironmentObject private var localizationManager: LocalizationManager

    // MARK: - Body

    var body: some View {
        NavigationStack {
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
            .navigationTitle(loc("profile.posts.title_by").replacingOccurrences(of: "{name}", with: displayName))
            .toolbarTitleDisplayMode(.inline)
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

            ForEach(viewModel.sortedFilteredPosts, id: \.post.uri) { entry in
                PostRowView(
                    entry: entry,
                    style: .compact,
                    callbacks: PostRowCallbacks(
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
                        onOpenProfile: { handle in
                            showProfileFor = BlueskyActor(
                                did: handle,
                                handle: handle,
                                displayName: nil,
                                avatarURL: nil
                            )
                        },
                        onShowLikes: { showLikesForURI = entry.post.uri },
                        onCopy: { UIPasteboard.general.string = entry.post.safeRecord.text },
                        onTranslate: { translateText(entry.post.safeRecord.text ?? "") },
                        onReportPost: {
                            guard let activeDID = accountStore.activeAccount?.did else { return }
                            guard entry.post.author?.did != activeDID else { return }
                            likerActions.postToReport = entry
                        },
                        onBlockAllLikers: {
                            let fetchAccount = searchAccount ?? accountStore.activeAccount
                            guard let fetchAccount, let fetchPassword = accountStore.appPassword(for: fetchAccount) else { return }
                            likerActions.handleBlockAllLikers(postURI: entry.post.uri, using: blueskyClient, fetchAccount: fetchAccount, fetchPassword: fetchPassword)
                        },
                        onAddAllLikersToList: { list in
                            let fetchAccount = searchAccount ?? accountStore.activeAccount
                            guard let fetchAccount, let fetchPassword = accountStore.appPassword(for: fetchAccount),
                                  let activeAccount = accountStore.activeAccount,
                                  let activePassword = accountStore.appPassword(for: activeAccount) else { return }
                            likerActions.handleAddAllLikersToList(postURI: entry.post.uri, list: list, using: blueskyClient, fetchAccount: fetchAccount, fetchPassword: fetchPassword, activeAccount: activeAccount, activePassword: activePassword, internalListStore: internalListStore)
                        },
                        onClassify: { likerActions.postToClassify = entry },
                        availableLikerTargetLists: likerActions.availableTargetLists
                    )
                )
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
                Text(loc: "profile.posts.end")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
                    .listRowSeparator(.hidden)
            }
            if !viewModel.searchText.isEmpty, viewModel.sortedFilteredPosts.isEmpty {
                Text(loc: "profile.posts.no_matches")
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

    /// Search text field and date filter toggle button.
    private var searchSection: some View {
        Section {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.tertiary)
                    .font(.subheadline)
                TextField("profile.posts.search", text: $viewModel.searchText)
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
                Text(loc: "profile.posts.from_date")
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
                Text(loc: "profile.posts.to_date")
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
                Label { Text(loc: "profile.export.csv") } icon: { Image(systemName: "arrow.down.doc") }
            }
            Button {
                let json = viewModel.exportJSON()
                let url = FileManager.default.temporaryDirectory.appendingPathComponent("posts.json")
                try? json.write(to: url, options: .atomic)
                shareFileURL = url
            } label: {
                Label { Text(loc: "profile.export.json") } icon: { Image(systemName: "arrow.down.doc") }
            }
        } label: {
            Image(systemName: "arrow.down.doc")
        }
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

    /// Opens Google Translate in the browser with the selected text.
    private func translateText(_ text: String) {
        guard let encoded = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://translate.google.com/?text=\(encoded)") else { return }
        UIApplication.shared.open(url)
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

// MARK: - ImagePreviewView

/// Full-screen image viewer with pinch-to-zoom, pan, and double-tap to reset.
private struct ImagePreviewView: View {
    let url: URL
    let onDismiss: () -> Void

    @State private var scale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastScale: CGFloat = 1
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        Color.black
            .ignoresSafeArea()
            .overlay {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .scaledToFit()
                        .scaleEffect(scale)
                        .offset(offset)
                        .gesture(
                            MagnificationGesture()
                                .onChanged { value in
                                    scale = max(1, lastScale * value)
                                }
                                .onEnded { _ in
                                    lastScale = scale
                                }
                        )
                        .simultaneousGesture(
                            DragGesture()
                                .onChanged { value in
                                    if scale > 1 {
                                        offset = CGSize(
                                            width: lastOffset.width + value.translation.width,
                                            height: lastOffset.height + value.translation.height
                                        )
                                    }
                                }
                                .onEnded { _ in
                                    lastOffset = offset
                                }
                        )
                        .onTapGesture(count: 2) {
                            withAnimation {
                                if scale > 1 {
                                    scale = 1
                                    offset = .zero
                                    lastScale = 1
                                    lastOffset = .zero
                                } else {
                                    scale = 2.5
                                    lastScale = 2.5
                                }
                            }
                        }
                } placeholder: {
                    ProgressView()
                        .tint(.white)
                }
            }
            .overlay(alignment: .topTrailing) {
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title)
                        .foregroundStyle(.white.opacity(0.8))
                        .padding()
                }
            }
            .onTapGesture {
                if scale <= 1 {
                    onDismiss()
                }
            }
    }
}
