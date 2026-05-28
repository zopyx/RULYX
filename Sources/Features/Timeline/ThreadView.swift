import SwiftUI

/// Displays a single post thread with ancestors (reversed), the root post,
/// and threaded replies with depth-based indentation and connection lines.
struct ThreadView: View {
    let postURI: String

    @StateObject private var viewModel = ThreadViewModel()
    @EnvironmentObject var accountStore: AccountStore
    @EnvironmentObject var blueskyClient: LiveBlueskyClient
    @State private var imagePreview: ImagePreviewCollection?
    @State private var videoPreviewURL: URL?
    @State private var showLikesForURI: String?
    @State private var composeContext: ComposeContext?
    @StateObject private var likerActions = PostLikerActionsManager()

    // MARK: - Computed properties

    private var mentionURLHandler: OpenURLAction {
        OpenURLAction { url in
            if url.scheme == "mention", let handle = url.host {
                openProfile(handle)
                return .handled
            }
            return .systemAction
        }
    }

    @EnvironmentObject private var localizationManager: LocalizationManager
    @EnvironmentObject private var internalListStore: InternalListStore

    // MARK: - Body

    var body: some View {
        Group {
            if viewModel.isLoading {
                LoadingPanel(message: loc("profile.posts.loading"))
            } else if let error = viewModel.errorMessage {
                ContentUnavailableView(
                    loc("list.detail.alert_title"),
                    systemImage: "exclamationmark.bubble",
                    description: Text(error)
                )
            } else if let thread = viewModel.thread {
                let ancestors = collectAncestors(from: thread)
                let hasAncestors = !ancestors.isEmpty
                let reversedAncestors = Array(ancestors.reversed())
                List {
                    threadPostSection(thread.post)

                    if hasAncestors {
                        Section {
                            ForEach(Array(reversedAncestors.enumerated()), id: \.offset) { index, ancestor in
                                ancestorRow(ancestor, isFirst: index == 0, isLast: index == ancestors.count - 1)
                            }
                        } header: {
                            Text(loc: "profile.posts.replying_to")
                        }
                    }

                    if let replies = thread.replies, !replies.isEmpty {
                        Section {
                            ForEach(Array(replies.enumerated()), id: \.offset) { index, reply in
                                replyThreadRow(reply, depth: 0, isLast: index == replies.count - 1)
                            }
                        } header: {
                            Text(loc: "profile.posts.replies")
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .pageTitle(loc("profile.posts.thread"))
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
        .sheet(item: $composeContext) { context in
            if context.isReply {
                ComposePostView(
                    account: context.account,
                    appPassword: context.appPassword,
                    blueskyClient: blueskyClient,
                    onComplete: { reloadThread() },
                    replyTo: (context.parentURI, context.parentCID, context.rootURI, context.rootCID)
                )
                .environmentObject(accountStore)
                .environmentObject(blueskyClient)
            } else {
                ComposePostView(
                    account: context.account,
                    appPassword: context.appPassword,
                    blueskyClient: blueskyClient,
                    onComplete: { reloadThread() },
                    quote: (context.uri, context.cid)
                )
                .environmentObject(accountStore)
                .environmentObject(blueskyClient)
            }
        }
        .task {
            guard let account = accountStore.activeAccount,
                  let appPassword = accountStore.appPassword(for: account)
            else {
                viewModel.handleMissingCredentials()
                return
            }
            await viewModel.loadThread(uri: postURI, account: account, appPassword: appPassword, using: blueskyClient)
        }
        .task {
            guard let account = accountStore.activeAccount,
                  let appPassword = accountStore.appPassword(for: account) else { return }
            await likerActions.loadAvailableTargetLists(using: blueskyClient, internalListStore: internalListStore, account: account, appPassword: appPassword)
        }
        .postLikerActions(manager: likerActions)
    }

    private func collectAncestors(from node: ThreadNode) -> [ThreadNode] {
        var ancestors: [ThreadNode] = []
        var current = node
        while let parent = current.parent {
            ancestors.insert(parent, at: 0)
            current = parent
        }
        return ancestors
    }

    private func reloadThread() {
        guard let account = accountStore.activeAccount,
              let appPassword = accountStore.appPassword(for: account) else { return }
        Task {
            await viewModel.loadThread(uri: postURI, account: account, appPassword: appPassword, using: blueskyClient)
        }
    }

    private func extractHandle(from uri: String) -> String {
        uri.dropFirst("at://".count).split(separator: "/").first.map(String.init) ?? uri
    }

    // MARK: - Shared Helpers

    private func threadAuthor(_ node: ThreadPostNode) -> RichAuthor {
        node.author ?? RichAuthor(did: "", handle: "unknown", displayName: nil, avatar: nil)
    }

    private func threadRecord(_ node: ThreadPostNode) -> RichRecord {
        node.record ?? RichRecord(text: "", createdAt: "")
    }

    private func threadCallbacks(for post: ThreadPostNode) -> PostRowCallbacks {
        PostRowCallbacks(
            onReply: { composeContext = makeReplyContext(uri: post.uri, cid: post.cid) },
            onLike: { performLike(uri: post.uri, cid: post.cid) },
            onShowLikes: { if let uri = post.uri { showLikesForURI = uri } },
            onRepost: { performRepost(uri: post.uri, cid: post.cid) },
            onQuote: { composeContext = makeQuoteContext(uri: post.uri, cid: post.cid) },
            onCopy: { UIPasteboard.general.string = post.record?.text },
            onTranslate: { translateText(post.record?.text ?? "") },
            onReportPost: {
                guard let activeDID = accountStore.activeAccount?.did else { return }
                guard post.author?.did != activeDID else { return }
                if post.uri != nil {
                    likerActions.postToReport = RichFeedEntry(threadPost: post)
                }
            },
            onBlockAllLikers: {
                guard let account = accountStore.activeAccount,
                      let appPassword = accountStore.appPassword(for: account),
                      let uri = post.uri else { return }
                likerActions.handleBlockAllLikers(postURI: uri, using: blueskyClient, fetchAccount: account, fetchPassword: appPassword)
            },
            onAddAllLikersToList: { list in
                guard let account = accountStore.activeAccount,
                      let appPassword = accountStore.appPassword(for: account),
                      let uri = post.uri else { return }
                likerActions.handleAddAllLikersToList(postURI: uri, list: list, using: blueskyClient, fetchAccount: account, fetchPassword: appPassword, activeAccount: account, activePassword: appPassword, internalListStore: internalListStore)
            },
            onClassify: {
                likerActions.postToClassify = RichFeedEntry(threadPost: post)
            },
            isLiked: post.isLikedByMe,
            isReposted: post.isRepostedByMe,
            availableLikerTargetLists: likerActions.availableTargetLists
        )
    }

    // MARK: - Ancestor Row

    @ViewBuilder
    private func ancestorRow(_ node: ThreadNode, isFirst: Bool = false, isLast: Bool = false) -> some View {
        let author = threadAuthor(node.post)
        let record = threadRecord(node.post)

        HStack(spacing: 8) {
            VStack(spacing: 0) {
                if isFirst {
                    Rectangle()
                        .fill(Color.gray.opacity(0.25))
                        .frame(width: 2, height: 8)
                }
                Rectangle()
                    .fill(Color.gray.opacity(0.25))
                    .frame(width: 2)
                    .frame(maxHeight: .infinity)
                if isLast {
                    Rectangle()
                        .fill(Color.gray.opacity(0.25))
                        .frame(width: 2, height: 8)
                }
            }
            .frame(width: 2)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    if let avatar = author.avatar.flatMap(URL.init) {
                        AsyncImage(url: avatar) { image in
                            image.resizable().scaledToFill()
                        } placeholder: {
                            Circle().fill(Color.skyPrimary.opacity(0.16))
                        }
                        .frame(width: 28, height: 28)
                        .clipShape(Circle())
                    } else {
                        Circle()
                            .fill(Color.skyPrimary.opacity(0.16))
                            .frame(width: 28, height: 28)
                            .overlay {
                                Text((author.displayName ?? author.handle ?? "?").prefix(1).uppercased())
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(Color.skyPrimary)
                            }
                    }
                    Text(author.displayName ?? author.handle ?? "")
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                    if let handle = author.handle {
                        Text("@\(handle)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    if let created = record.createdAt, let date = parseDate(created) {
                        Text(relativeTimeString(from: date))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    postMenu(for: record.text)
                }
                if let text = record.text, !text.isEmpty {
                    PostTextContent(
                        text: text,
                        onOpenProfile: { handle in openProfile(handle) },
                        font: .subheadline,
                        lineLimit: 3,
                        foregroundStyle: .secondary
                    )
                }
                if let embed = node.post.embed {
                    PostEmbedView(
                        embed: embed,
                        onTapImage: { index in
                            let allImages = embed.images ?? []
                            let urls = allImages.compactMap { $0.fullsize.flatMap(URL.init) }
                            guard index < urls.count else { return }
                            imagePreview = ImagePreviewCollection(urls: urls, initialIndex: index)
                        },
                        onPlayVideo: {
                            if let playlist = embed.video?.playlist, let url = URL(string: playlist) {
                                videoPreviewURL = url
                            }
                        }
                    )
                }
            }
        }
        .padding(.vertical, 4)
        .listRowSeparator(.hidden)
    }

    // MARK: - Thread Post

    private func threadPostSection(_ post: ThreadPostNode) -> some View {
        let author = threadAuthor(post)
        let record = threadRecord(post)
        let callbacks = threadCallbacks(for: post)

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if let avatar = author.avatar.flatMap(URL.init) {
                    AsyncImage(url: avatar) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Circle().fill(Color.skyPrimary.opacity(0.16))
                    }
                    .frame(width: 40, height: 40)
                    .clipShape(Circle())
                } else {
                    Circle()
                        .fill(Color.skyPrimary.opacity(0.16))
                        .frame(width: 40, height: 40)
                        .overlay {
                            Text((author.displayName ?? author.handle ?? "?").prefix(1).uppercased())
                                .font(.title3.weight(.bold))
                                .foregroundStyle(Color.skyPrimary)
                        }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(author.displayName ?? author.handle ?? "")
                        .font(.subheadline.weight(.semibold))
                    if let handle = author.handle {
                        Text("@\(handle)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if let created = record.createdAt, let date = parseDate(created) {
                    Text(relativeTimeString(from: date))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            if let text = record.text, !text.isEmpty {
                PostTextContent(
                    text: text,
                    onOpenProfile: { handle in openProfile(handle) }
                )
            }
            if let embed = post.embed {
                PostEmbedView(
                    embed: embed,
                    onTapImage: { index in
                        let allImages = embed.images ?? []
                        let urls = allImages.compactMap { $0.fullsize.flatMap(URL.init) }
                        guard index < urls.count else { return }
                        imagePreview = ImagePreviewCollection(urls: urls, initialIndex: index)
                    },
                    onPlayVideo: {
                        if let playlist = embed.video?.playlist, let url = URL(string: playlist) {
                            videoPreviewURL = url
                        }
                    }
                )
            }
            PostActionBar(
                replyCount: post.replyCount,
                repostCount: post.repostCount,
                likeCount: post.likeCount,
                isLiked: post.isLikedByMe,
                isReposted: post.isRepostedByMe,
                callbacks: callbacks
            )
        }
        .padding(.vertical, 8)
    }

    // MARK: - Reply Row

    private func threadLineColor(for depth: Int) -> Color {
        let opacity = max(0.08, 0.3 - Double(depth) * 0.06)
        return Color.gray.opacity(opacity)
    }

    private func replyThreadRow(_ reply: ThreadNode, depth: Int, isLast: Bool) -> AnyView {
        let author = threadAuthor(reply.post)
        let record = threadRecord(reply.post)
        let callbacks = threadCallbacks(for: reply.post)

        let content = HStack(spacing: 6) {
            VStack(spacing: 0) {
                Rectangle()
                    .fill(threadLineColor(for: depth))
                    .frame(width: 2)
                    .frame(maxHeight: .infinity)
                if !isLast {
                    Rectangle()
                        .fill(threadLineColor(for: depth))
                        .frame(width: 2, height: 8)
                }
            }
            .frame(width: 2)
            .padding(.leading, CGFloat(depth) * 16)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    if let avatar = author.avatar.flatMap(URL.init) {
                        AsyncImage(url: avatar) { image in
                            image.resizable().scaledToFill()
                        } placeholder: {
                            Circle().fill(Color.skyPrimary.opacity(0.16))
                        }
                        .frame(width: 28, height: 28)
                        .clipShape(Circle())
                    } else {
                        Circle()
                            .fill(Color.skyPrimary.opacity(0.16))
                            .frame(width: 28, height: 28)
                            .overlay {
                                Text((author.handle ?? "?").prefix(1).uppercased())
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(Color.skyPrimary)
                            }
                    }
                    Text(author.displayName ?? author.handle ?? "")
                        .font(.caption.weight(.semibold))
                    if let handle = author.handle {
                        Text("@\(handle)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let created = record.createdAt, let date = parseDate(created) {
                        Text(relativeTimeString(from: date))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                if let text = record.text, !text.isEmpty {
                    PostTextContent(
                        text: text,
                        onOpenProfile: { handle in openProfile(handle) },
                        font: .subheadline,
                        lineLimit: 10
                    )
                }
                if let embed = reply.post.embed {
                    PostEmbedView(
                        embed: embed,
                        onTapImage: { index in
                            let allImages = embed.images ?? []
                            let urls = allImages.compactMap { $0.fullsize.flatMap(URL.init) }
                            guard index < urls.count else { return }
                            imagePreview = ImagePreviewCollection(urls: urls, initialIndex: index)
                        },
                        onPlayVideo: {
                            if let playlist = embed.video?.playlist, let url = URL(string: playlist) {
                                videoPreviewURL = url
                            }
                        }
                    )
                }
                PostActionBar(
                    replyCount: reply.post.replyCount,
                    repostCount: reply.post.repostCount,
                    likeCount: reply.post.likeCount,
                    isLiked: reply.post.isLikedByMe,
                    isReposted: reply.post.isRepostedByMe,
                    callbacks: callbacks
                )
                if let replies = reply.replies, !replies.isEmpty {
                    ForEach(Array(replies.enumerated()), id: \.offset) { index, child in
                        replyThreadRow(child, depth: depth + 1, isLast: index == replies.count - 1)
                    }
                }
            }
        }
        .listRowSeparator(.hidden)
        return AnyView(content)
    }

    // MARK: - Actions

    private func makeReplyContext(uri: String?, cid: String?) -> ComposeContext? {
        guard let uri, let cid,
              let account = accountStore.activeAccount,
              let appPassword = accountStore.appPassword(for: account) else { return nil }
        let rootURI = findRootURI()
        let rootCID = findRootCID()
        return ComposeContext(
            account: account,
            appPassword: appPassword,
            isReply: true,
            parentURI: uri,
            parentCID: cid,
            rootURI: rootURI,
            rootCID: rootCID
        )
    }

    private func makeQuoteContext(uri: String?, cid: String?) -> ComposeContext? {
        guard let uri, let cid,
              let account = accountStore.activeAccount,
              let appPassword = accountStore.appPassword(for: account) else { return nil }
        return ComposeContext(
            account: account,
            appPassword: appPassword,
            isReply: false,
            uri: uri,
            cid: cid
        )
    }

    private func findRootURI() -> String {
        guard let thread = viewModel.thread else { return postURI }
        var current = thread
        while let parent = current.parent {
            current = parent
        }
        return current.post.uri ?? postURI
    }

    private func findRootCID() -> String {
        guard let thread = viewModel.thread else { return "" }
        var current = thread
        while let parent = current.parent {
            current = parent
        }
        return current.post.cid ?? ""
    }

    private func performLike(uri: String?, cid: String?) {
        guard let uri, let cid,
              let account = accountStore.activeAccount,
              let appPassword = accountStore.appPassword(for: account) else { return }
        let threadPost = findPost(byURI: uri)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        Task {
            do {
                if let threadPost, threadPost.isLikedByMe, let likeURI = threadPost.myLikeURI {
                    _ = try await blueskyClient.deleteRecord(recordURI: likeURI, account: account, appPassword: appPassword)
                } else {
                    _ = try await blueskyClient.createLike(uri: uri, cid: cid, account: account, appPassword: appPassword)
                }
                reloadThread()
            } catch {
                AppLogger.moderation.error("Like failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func performRepost(uri: String?, cid: String?) {
        guard let uri, let cid,
              let account = accountStore.activeAccount,
              let appPassword = accountStore.appPassword(for: account) else { return }
        let threadPost = findPost(byURI: uri)
        Task {
            do {
                if let threadPost, threadPost.isRepostedByMe, let repostURI = threadPost.myRepostURI {
                    _ = try await blueskyClient.deleteRecord(recordURI: repostURI, account: account, appPassword: appPassword)
                } else {
                    _ = try await blueskyClient.createRepost(uri: uri, cid: cid, account: account, appPassword: appPassword)
                }
                reloadThread()
            } catch {
                AppLogger.moderation.error("Repost failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func findPost(byURI uri: String) -> ThreadPostNode? {
        if viewModel.thread?.post.uri == uri { return viewModel.thread?.post }
        return findPostInReplies(viewModel.thread?.replies, uri: uri)
    }

    private func findPostInReplies(_ replies: [ThreadNode]?, uri: String) -> ThreadPostNode? {
        guard let replies else { return nil }
        for reply in replies {
            if reply.post.uri == uri { return reply.post }
            if let found = findPostInReplies(reply.replies, uri: uri) { return found }
        }
        return nil
    }

    private func postMenu(for text: String?) -> some View {
        Menu {
            Button {
                UIPasteboard.general.string = text
            } label: {
                Label("post.copy", systemImage: "doc.on.doc")
            }
            Button {
                translateText(text ?? "")
            } label: {
                Label("post.translate", systemImage: "globe")
            }
        } label: {
            Image(systemName: "gearshape")
                .font(.body.weight(.medium))
                .foregroundStyle(.tertiary)
                .padding(.leading, 4)
        }
    }

    private func openProfile(_ handle: String) {
        guard let url = URL(string: "https://bsky.app/profile/\(handle)") else { return }
        UIApplication.shared.open(url)
    }

    private func translateText(_ text: String) {
        guard let encoded = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://translate.google.com/?text=\(encoded)") else { return }
        UIApplication.shared.open(url)
    }
}

/// Manages loading and state for a single post thread view.
///
/// Fetches the full thread via `fetchPostThread` and exposes `thread`, `isLoading`, and `errorMessage`.
@MainActor
final class ThreadViewModel: ObservableObject {
    // MARK: - Properties

    /// The loaded thread node containing the post and its replies.
    @Published private(set) var thread: ThreadNode?
    /// True while the thread is loading. Starts as `true`.
    @Published private(set) var isLoading = true
    /// User-facing error message.
    @Published var errorMessage: String?

    // MARK: - Public Methods

    /// Handles the case where credentials are missing, showing a localized error.
    func handleMissingCredentials() {
        errorMessage = loc("list.detail.missing_creds")
        isLoading = false
    }

    /// Loads the post thread for the given URI.
    func loadThread(uri: String, account: AppAccount, appPassword: String, using client: LiveBlueskyClient) async {
        isLoading = true
        errorMessage = nil
        do {
            let response = try await client.fetchPostThread(uri: uri, account: account, appPassword: appPassword)
            thread = response.thread
        } catch {
            errorMessage = AppError.userMessage(from: error)
            AppLogger.moderation.error("Failed to load thread: \(error.localizedDescription, privacy: .public)")
        }
        isLoading = false
    }
}
