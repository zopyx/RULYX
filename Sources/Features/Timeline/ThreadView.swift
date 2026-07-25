import Observation
import SwiftUI

/// Displays a single post thread with ancestors (reversed), the root post,
/// and threaded replies with depth-based indentation and connection lines.
struct ThreadView: View {
    let postURI: String
    let searchAccount: AppAccount?

    @StateObject private var viewModel = ThreadViewModel()

    init(postURI: String, searchAccount: AppAccount? = nil) {
        self.postURI = postURI
        self.searchAccount = searchAccount
    }

    @EnvironmentObject var accountStore: AccountStore
    @EnvironmentObject var container: BlueskyServiceContainerWrapper
    @State private var imagePreview: ImagePreviewCollection?
    @State private var videoPreviewURL: URL?
    @State private var showLikesForURI: String?
    @State private var composeContext: ComposeContext?
    @State private var profileToShow: BlueskyActor?
    @StateObject private var likerActions = PostLikerActionsManager()

    @EnvironmentObject private var localizationManager: LocalizationManager
    @EnvironmentObject private var internalListStore: InternalListStore

    // MARK: - Body

    var body: some View {
        Group {
            if viewModel.isLoading {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(0 ..< 4, id: \.self) { _ in
                            SkeletonRow()
                            Divider()
                        }
                    }
                }
            } else if let error = viewModel.errorMessage {
                ContentUnavailableView(
                    loc("list.detail.alert_title"),
                    systemImage: "exclamationmark.bubble",
                    description: Text(error)
                )
            } else if let thread = viewModel.thread {
                if thread.post.isBlocked {
                    ContentUnavailableView(
                        loc("thread.blocked.title"),
                        systemImage: "hand.raised.slash",
                        description: Text(loc: "thread.blocked.desc")
                    )
                } else if thread.post.isNotFound {
                    ContentUnavailableView(
                        loc("thread.not_found.title"),
                        systemImage: "trash.slash",
                        description: Text(loc: "thread.not_found.desc")
                    )
                } else {
                    let ancestors = collectAncestors(from: thread)
                    let hasAncestors = !ancestors.isEmpty
                    let reversedAncestors = Array(ancestors.reversed())
                    List {
                        PostRowView(
                            entry: RichFeedEntry(threadPost: thread.post),
                            style: .full,
                            callbacks: threadCallbacks(for: thread.post),
                            avatarSize: 40
                        )
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)

                        if hasAncestors {
                            Section {
                                ForEach(Array(reversedAncestors.enumerated()), id: \.offset) { index, ancestor in
                                    threadConnectorRow(
                                        node: ancestor,
                                        style: .ancestor(
                                            isFirst: index == 0,
                                            isLast: index == ancestors.count - 1
                                        )
                                    )
                                }
                            } header: {
                                Text(loc: "profile.posts.replying_to")
                            }
                        }

                        if let replies = thread.replies, !replies.isEmpty {
                            Section {
                                ForEach(Array(replies.enumerated()), id: \.offset) { index, reply in
                                    replyTreeNode(reply, depth: 0, isLast: index == replies.count - 1)
                                }
                            } header: {
                                Text(loc: "profile.posts.replies")
                            }
                        }
                    }
                    .listStyle(.plain)
                }
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
                .environmentObject(container.blueskyClient)
        }
        .sheet(item: $composeContext) { context in
            if context.isReply {
                ComposePostView(viewModel: ComposePostViewModel(
                    blueskyClient: container.blueskyClient,
                    account: context.account,
                    appPassword: context.appPassword,
                    onComplete: { reloadThread() },
                    replyTo: (context.parentURI, context.parentCID, context.rootURI, context.rootCID)
                ))
                .environmentObject(accountStore)
                .environmentObject(container.blueskyClient)
            } else {
                ComposePostView(viewModel: ComposePostViewModel(
                    blueskyClient: container.blueskyClient,
                    account: context.account,
                    appPassword: context.appPassword,
                    onComplete: { reloadThread() },
                    quote: (context.uri, context.cid)
                ))
                .environmentObject(accountStore)
                .environmentObject(container.blueskyClient)
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
            }
        }
        .task {
            guard let (account, appPassword) = readCredentials else {
                viewModel.handleMissingCredentials()
                return
            }
            await viewModel.loadThread(uri: postURI, account: account, appPassword: appPassword, using: container.blueskyClient)
        }
        .task {
            guard let account = accountStore.activeAccount,
                  let appPassword = accountStore.appPassword(for: account) else { return }
            await likerActions.loadAvailableTargetLists(using: container.blueskyClient, internalListStore: internalListStore, account: account, appPassword: appPassword)
        }
        .postLikerActions(manager: likerActions)
    }

    // MARK: - Helpers

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
        guard let (account, appPassword) = readCredentials else { return }
        Task {
            await viewModel.loadThread(uri: postURI, account: account, appPassword: appPassword, using: container.blueskyClient)
        }
    }

    private var readCredentials: (AppAccount, String)? {
        if let searchAccount, let password = accountStore.appPassword(for: searchAccount) {
            return (searchAccount, password)
        }
        guard let account = accountStore.activeAccount,
              let appPassword = accountStore.appPassword(for: account) else { return nil }
        return (account, appPassword)
    }

    private func extractHandle(from uri: String) -> String {
        uri.dropFirst("at://".count).split(separator: "/").first.map(String.init) ?? uri
    }

    // MARK: - Thread Row Components

    private enum ConnectorStyle {
        case ancestor(isFirst: Bool, isLast: Bool)
        case reply(depth: Int, isLast: Bool)
    }

    private func threadConnectorRow(node: ThreadNode, style: ConnectorStyle) -> some View {
        let depth: Int = {
            if case let .reply(d, _) = style {
                return d
            }
            return 0
        }()

        return HStack(spacing: 6) {
            connectorLine(style: style, depth: depth)
                .padding(.leading, CGFloat(depth) * 16)

            PostRowView(
                entry: RichFeedEntry(threadPost: node.post),
                style: .threadReply,
                callbacks: threadCallbacks(for: node.post),
                avatarSize: 28
            )
        }
        .padding(.vertical, 4)
        .listRowSeparator(.hidden)
    }

    @ViewBuilder
    private func connectorLine(style: ConnectorStyle, depth _: Int) -> some View {
        let color: Color = {
            if case let .reply(d, _) = style {
                let opacity = max(0.08, 0.3 - Double(d) * 0.06)
                return Color.gray.opacity(opacity)
            }
            return Color.gray.opacity(0.25)
        }()

        VStack(spacing: 0) {
            if case let .ancestor(isFirst, _) = style, isFirst {
                Rectangle()
                    .fill(color)
                    .frame(width: 2, height: 8)
            }
            Rectangle()
                .fill(color)
                .frame(width: 2)
                .frame(maxHeight: .infinity)
            if case let .ancestor(_, isLast) = style, isLast {
                Rectangle()
                    .fill(color)
                    .frame(width: 2, height: 8)
            }
            if case let .reply(_, isLast) = style, !isLast {
                Rectangle()
                    .fill(color)
                    .frame(width: 2, height: 8)
            }
        }
        .frame(width: 2)
    }

    private func replyTreeNode(_ node: ThreadNode, depth: Int, isLast: Bool) -> AnyView {
        AnyView(
            Group {
                threadConnectorRow(
                    node: node,
                    style: .reply(depth: depth, isLast: isLast)
                )

                if let replies = node.replies, !replies.isEmpty {
                    ForEach(Array(replies.enumerated()), id: \.offset) { index, child in
                        replyTreeNode(child, depth: depth + 1, isLast: index == replies.count - 1)
                    }
                }
            }
        )
    }

    // MARK: - Callbacks

    private func threadCallbacks(for post: ThreadPostNode) -> PostRowCallbacks {
        let authorCB = makeAuthorCallbacks(author: post.author, accountStore: accountStore, blueskyClient: container.blueskyClient, internalListStore: internalListStore)
        return PostRowCallbacks(
            onTapImage: { index in
                let allImages = post.embed?.images ?? []
                let urls = allImages.compactMap { $0.fullsize.flatMap(URL.init) }
                guard index < urls.count else { return }
                imagePreview = ImagePreviewCollection(urls: urls, initialIndex: index)
            },
            onPlayVideo: {
                if let playlist = post.embed?.video?.playlist, let url = URL(string: playlist) {
                    videoPreviewURL = url
                }
            },
            onOpenProfile: { handle in
                if let author = post.author {
                    profileToShow = BlueskyActor(
                        did: author.did ?? handle,
                        handle: author.handle ?? handle,
                        displayName: author.displayName
                    )
                }
            },
            onReply: { composeContext = makeReplyContext(uri: post.uri, cid: post.cid) },
            onLike: { performLike(uri: post.uri, cid: post.cid) },
            onShowLikes: {
                if let uri = post.uri {
                    showLikesForURI = uri
                }
            },
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
                likerActions.handleBlockAllLikers(postURI: uri, using: container.blueskyClient, fetchAccount: account, fetchPassword: appPassword, confirmBlockAccount: account, confirmBlockPassword: appPassword)
            },
            onAddAllLikersToList: { list in
                guard let account = accountStore.activeAccount,
                      let appPassword = accountStore.appPassword(for: account),
                      let uri = post.uri else { return }
                likerActions.handleAddAllLikersToList(postURI: uri, list: list, using: container.blueskyClient, fetchAccount: account, fetchPassword: appPassword, activeAccount: account, activePassword: appPassword, internalListStore: internalListStore)
            },
            onClassify: {
                likerActions.postToClassify = RichFeedEntry(threadPost: post)
            },
            onBlockAuthor: authorCB.onBlock,
            onAddAuthorToList: authorCB.onAddToList,
            isLiked: post.isLikedByMe,
            isReposted: post.isRepostedByMe,
            availableLikerTargetLists: likerActions.availableTargetLists
        )
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
                    _ = try await container.post.deleteRecord(recordURI: likeURI, account: account, appPassword: appPassword)
                } else {
                    _ = try await container.social.createLike(uri: uri, cid: cid, account: account, appPassword: appPassword)
                }
                reloadThread()
            } catch {
                AppLogger.moderation.error("Like failed: \(error.localizedDescription, privacy: .private)")
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
                    _ = try await container.post.deleteRecord(recordURI: repostURI, account: account, appPassword: appPassword)
                } else {
                    _ = try await container.social.createRepost(uri: uri, cid: cid, account: account, appPassword: appPassword)
                }
                reloadThread()
            } catch {
                AppLogger.moderation.error("Repost failed: \(error.localizedDescription, privacy: .private)")
            }
        }
    }

    private func findPost(byURI uri: String) -> ThreadPostNode? {
        if viewModel.thread?.post.uri == uri {
            return viewModel.thread?.post
        }
        return findPostInReplies(viewModel.thread?.replies, uri: uri)
    }

    private func findPostInReplies(_ replies: [ThreadNode]?, uri: String) -> ThreadPostNode? {
        guard let replies else { return nil }
        for reply in replies {
            if reply.post.uri == uri {
                return reply.post
            }
            if let found = findPostInReplies(reply.replies, uri: uri) {
                return found
            }
        }
        return nil
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
    /// The loaded thread node containing the post and its replies.
    private(set) var thread: ThreadNode?
    /// True while the thread is loading. Starts as `true`.
    private(set) var isLoading = true
    /// User-facing error message.
    var errorMessage: String?

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
            AppLogger.moderation.error("Failed to load thread: \(error.localizedDescription, privacy: .private)")
        }
        isLoading = false
    }
}
