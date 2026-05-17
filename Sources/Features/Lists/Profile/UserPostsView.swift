import SwiftUI

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

struct UserPostsView: View {
    let did: String
    let displayName: String

    @StateObject private var viewModel: UserPostsViewModel
    @EnvironmentObject var accountStore: AccountStore
    @EnvironmentObject var blueskyClient: LiveBlueskyClient
    @Environment(\.dismiss) private var dismiss
    @State private var selectedPostURI: String?
    @State private var imagePreview: ImagePreviewCollection?
    @State private var videoPreviewURL: URL?
    @State private var showLikesForURI: String?
    @State private var shareFileURL: URL?
    @State private var initialLoadTask: Task<Void, Never>?
    @State private var loadMoreTask: Task<Void, Never>?

    init(did: String, displayName: String) {
        self.did = did
        self.displayName = displayName
        _viewModel = StateObject(wrappedValue: UserPostsViewModel(did: did))
    }

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
                            description: Text(verbatim: loc("profile.blocked.posts_desc"))
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
                        description: Text(verbatim: loc("profile.posts.empty_desc"))
                    )
                } else {
                    listContent
                }
            }
            .navigationTitle(loc("profile.posts.title_by").replacingOccurrences(of: "{name}", with: displayName))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(loc("actions.close")) { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if !viewModel.posts.isEmpty {
                        exportMenu
                    }
                }
            }
            .sheet(item: $selectedPostURI) { uri in
                ThreadView(postURI: uri)
                    .environmentObject(accountStore)
                    .environmentObject(blueskyClient)
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
            .task {
                await loadInitial()
            }
            .onDisappear {
                initialLoadTask?.cancel()
                loadMoreTask?.cancel()
            }
        }
    }

    private var listContent: some View {
        List {
            searchSection

            ForEach(viewModel.sortedFilteredPosts, id: \.post.uri) { entry in
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
                    onShowLikes: { showLikesForURI = entry.post.uri }
                )
                .onAppear {
                    if entry.post.uri == viewModel.sortedFilteredPosts.last?.post.uri {
                        Task { await loadMore() }
                    }
                }
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
                Text(verbatim: loc("profile.posts.end"))
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

    private var exportMenu: some View {
        Menu {
            Button {
                let csv = viewModel.exportCSV()
                let url = FileManager.default.temporaryDirectory.appendingPathComponent("posts.csv")
                try? csv.write(to: url, atomically: true, encoding: .utf8)
                shareFileURL = url
            } label: {
                Label { Text(verbatim: loc("profile.export.csv")) } icon: { Image(systemName: "arrow.down.doc") }
            }
            Button {
                let json = viewModel.exportJSON()
                let url = FileManager.default.temporaryDirectory.appendingPathComponent("posts.json")
                try? json.write(to: url, options: .atomic)
                shareFileURL = url
            } label: {
                Label { Text(verbatim: loc("profile.export.json")) } icon: { Image(systemName: "arrow.down.doc") }
            }
        } label: {
            Image(systemName: "arrow.down.doc")
        }
    }

    private func loadInitial() async {
        guard let account = accountStore.activeAccount,
              let appPassword = accountStore.appPassword(for: account) else { return }
        initialLoadTask?.cancel()
        let task = Task {
            await viewModel.loadPosts(account: account, appPassword: appPassword, using: blueskyClient)
        }
        initialLoadTask = task
        await task.value
    }

    private func loadMore() async {
        guard let account = accountStore.activeAccount,
              let appPassword = accountStore.appPassword(for: account) else { return }
        guard loadMoreTask == nil else { return }
        let task = Task {
            await viewModel.loadMorePosts(account: account, appPassword: appPassword, using: blueskyClient)
        }
        loadMoreTask = task
        await task.value
        loadMoreTask = nil
    }

    private func refresh() async {
        guard let account = accountStore.activeAccount,
              let appPassword = accountStore.appPassword(for: account) else { return }
        await viewModel.refresh(account: account, appPassword: appPassword, using: blueskyClient)
    }
}

private struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context _: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_: UIActivityViewController, context _: Context) {}
}

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
