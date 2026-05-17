import SwiftUI

struct ThreadView: View {
    let postURI: String

    @StateObject private var viewModel = ThreadViewModel()
    @EnvironmentObject var accountStore: AccountStore
    @EnvironmentObject var blueskyClient: LiveBlueskyClient
    @Environment(\.dismiss) private var dismiss
    @State private var imagePreview: ImagePreviewCollection?
    @State private var videoPreviewURL: URL?
    @State private var showLikesForURI: String?
    @State private var composeContext: ComposeContext?

    private var mentionURLHandler: OpenURLAction {
        OpenURLAction { url in
            if url.scheme == "mention", let handle = url.host {
                openProfile(handle)
                return .handled
            }
            return .systemAction
        }
    }

    var body: some View {
        NavigationStack {
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
                                Text(verbatim: loc("profile.posts.replying_to"))
                            }
                        }

                        if let replies = thread.replies, !replies.isEmpty {
                            Section {
                                ForEach(Array(replies.enumerated()), id: \.offset) { index, reply in
                                    replyThreadRow(reply, depth: 0, isLast: index == replies.count - 1)
                                }
                            } header: {
                                Text(verbatim: loc("profile.posts.replies"))
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle(loc("profile.posts.thread"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(loc("actions.close")) { dismiss() }
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
        }
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

    // MARK: - Ancestor Row

    @ViewBuilder
    private func ancestorRow(_ node: ThreadNode, isFirst: Bool = false, isLast: Bool = false) -> some View {
        let author = node.post.author ?? RichAuthor(did: "", handle: "unknown", displayName: nil, avatar: nil)
        let record = node.post.record ?? RichRecord(text: "", createdAt: "")

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
                    Text(mentionAttributedString(from: text))
                        .font(.subheadline)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                        .foregroundStyle(.secondary)
                        .environment(\.openURL, mentionURLHandler)
                }
                if let embed = node.post.embed {
                    postEmbed(embed, onPlayVideo: {
                        if let playlist = embed.video?.playlist, let url = URL(string: playlist) {
                            videoPreviewURL = url
                        }
                    }, onTapImage: { index in
                        let allImages = embed.images ?? []
                        let urls = allImages.compactMap { $0.fullsize.flatMap(URL.init) }
                        guard index < urls.count else { return }
                        imagePreview = ImagePreviewCollection(urls: urls, initialIndex: index)
                    })
                }
            }
        }
        .padding(.vertical, 4)
        .listRowSeparator(.hidden)
    }

    // MARK: - Thread Post

    private func threadPostSection(_ post: ThreadPostNode) -> some View {
        let author = post.author ?? RichAuthor(did: "", handle: "unknown", displayName: nil, avatar: nil)
        let record = post.record ?? RichRecord(text: "", createdAt: "")

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
                postMenu(for: record.text)
            }
            if let text = record.text, !text.isEmpty {
                Text(mentionAttributedString(from: text))
                    .font(.body)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .environment(\.openURL, mentionURLHandler)
            }
            if let embed = post.embed {
                postEmbed(embed, onPlayVideo: {
                    if let playlist = embed.video?.playlist, let url = URL(string: playlist) {
                        videoPreviewURL = url
                    }
                }, onTapImage: { index in
                    let allImages = embed.images ?? []
                    let urls = allImages.compactMap { $0.fullsize.flatMap(URL.init) }
                    guard index < urls.count else { return }
                    imagePreview = ImagePreviewCollection(urls: urls, initialIndex: index)
                })
            }
            postActionBar(
                replyCount: post.replyCount,
                repostCount: post.repostCount,
                likeCount: post.likeCount,
                onReply: { composeContext = makeReplyContext(uri: post.uri, cid: post.cid) },
                onRepost: { performRepost(uri: post.uri, cid: post.cid) },
                onLike: { performLike(uri: post.uri, cid: post.cid) },
                onQuote: { composeContext = makeQuoteContext(uri: post.uri, cid: post.cid) },
                onShowLikes: { if let uri = post.uri { showLikesForURI = uri } },
                isLiked: post.isLikedByMe, isReposted: post.isRepostedByMe
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
        let author = reply.post.author ?? RichAuthor(did: "", handle: "unknown", displayName: nil, avatar: nil)
        let record = reply.post.record ?? RichRecord(text: "", createdAt: "")

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
                    postMenu(for: record.text)
                }
                if let text = record.text, !text.isEmpty {
                    Text(mentionAttributedString(from: text))
                        .font(.subheadline)
                        .lineLimit(10)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .environment(\.openURL, mentionURLHandler)
                }
                if let embed = reply.post.embed {
                    postEmbed(embed, onPlayVideo: {
                        if let playlist = embed.video?.playlist, let url = URL(string: playlist) {
                            videoPreviewURL = url
                        }
                    }, onTapImage: { index in
                        let allImages = embed.images ?? []
                        let urls = allImages.compactMap { $0.fullsize.flatMap(URL.init) }
                        guard index < urls.count else { return }
                        imagePreview = ImagePreviewCollection(urls: urls, initialIndex: index)
                    })
                }
                postActionBar(
                    replyCount: reply.post.replyCount,
                    repostCount: reply.post.repostCount,
                    likeCount: reply.post.likeCount,
                    onReply: { composeContext = makeReplyContext(uri: reply.post.uri, cid: reply.post.cid) },
                    onRepost: { performRepost(uri: reply.post.uri, cid: reply.post.cid) },
                    onLike: { performLike(uri: reply.post.uri, cid: reply.post.cid) },
                    onQuote: { composeContext = makeQuoteContext(uri: reply.post.uri, cid: reply.post.cid) },
                    onShowLikes: { if let uri = reply.post.uri { showLikesForURI = uri } },
                    isLiked: reply.post.isLikedByMe, isReposted: reply.post.isRepostedByMe
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

    // MARK: - Embed

    private func postActionBar(replyCount: Int?, repostCount: Int?, likeCount: Int?, onReply: @escaping () -> Void, onRepost: @escaping () -> Void, onLike: @escaping () -> Void, onQuote: @escaping () -> Void, onShowLikes: @escaping () -> Void = {}, isLiked: Bool = false, isReposted: Bool = false) -> some View {
        HStack(spacing: 24) {
            Button(action: onReply) {
                HStack(spacing: 4) {
                    Image(systemName: "bubble.left")
                        .font(.body.weight(.medium))
                    if let count = replyCount {
                        Text("\(count)")
                            .font(.callout)
                    }
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tertiary)

            Button(action: onRepost) {
                HStack(spacing: 4) {
                    Image(systemName: isReposted ? "repeat.circle.fill" : "repeat")
                        .font(.body.weight(.medium))
                    if let count = repostCount {
                        Text("\(count)")
                            .font(.callout)
                    }
                }
                .foregroundStyle(isReposted ? Color.green : Color.gray.opacity(0.6))
            }
            .buttonStyle(.plain)

            HStack(spacing: 4) {
                Button(action: onLike) {
                    Image(systemName: isLiked ? "heart.fill" : "heart")
                        .font(.body.weight(.medium))
                        .foregroundStyle(isLiked ? Color.red : Color.gray.opacity(0.6))
                }
                if let count = likeCount {
                    Button(action: onShowLikes) {
                        Text("\(count)")
                            .font(.callout)
                    }
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tertiary)

            Button(action: onQuote) {
                HStack(spacing: 4) {
                    Image(systemName: "quote.bubble")
                        .font(.body.weight(.medium))
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tertiary)
        }
    }

    private func postMenu(for text: String?) -> some View {
        Menu {
            Button {
                UIPasteboard.general.string = text
            } label: {
                Label(loc("post.copy"), systemImage: "doc.on.doc")
            }
            Button {
                translateText(text ?? "")
            } label: {
                Label(loc("post.translate"), systemImage: "globe")
            }
        } label: {
            Image(systemName: "ellipsis")
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

    @ViewBuilder
    private func postEmbed(_ embed: RichEmbed, onPlayVideo: @escaping () -> Void, onTapImage: @escaping (Int) -> Void) -> some View {
        if let video = embed.video {
            Button(action: onPlayVideo) {
                ZStack {
                    if let thumb = video.thumbnail, let url = URL(string: thumb) {
                        ThumbnailImageView(url: url, maxPixelSize: 720) {
                            Rectangle().fill(Color.skyPrimary.opacity(0.08))
                        }
                        .scaledToFill()
                    } else {
                        LinearGradient(
                            colors: [Color.skyPrimary.opacity(0.22), Color.skyPrimary.opacity(0.08)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        .overlay {
                            Image(systemName: "film.stack")
                                .font(.system(size: 34, weight: .medium))
                                .foregroundStyle(.white.opacity(0.92))
                        }
                    }

                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(.white)
                        .shadow(radius: 4)
                }
                .frame(height: 200)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
        }

        if let images = embed.images, !images.isEmpty {
            let cols = images.count == 1 ? 1 : 2
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: cols), spacing: 4) {
                ForEach(Array(images.prefix(4).enumerated()), id: \.offset) { index, item in
                    if let previewURL = item.fullsize.flatMap(URL.init) {
                        Button {
                            onTapImage(index)
                        } label: {
                            ThumbnailImageView(url: item.thumb.flatMap(URL.init) ?? previewURL, maxPixelSize: 512) {
                                Rectangle().fill(Color.skyPrimary.opacity(0.08))
                            }
                            .scaledToFill()
                            .frame(height: 120)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }

        if let external = embed.external, let uri = external.uri, let url = URL(string: uri) {
            if external.isTenorEmbed, let gifURL = external.preferredInlineMediaURL {
                InlineAnimatedMediaView(url: gifURL, allowsInteraction: true)
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.skyPrimary.opacity(0.12), lineWidth: 1)
                    }
            } else {
                Button {
                    UIApplication.shared.open(url)
                } label: {
                    HStack(spacing: 12) {
                        if let thumb = external.thumb, let thumbURL = URL(string: thumb) {
                            ThumbnailImageView(url: thumbURL, maxPixelSize: 512) {
                                RoundedRectangle(cornerRadius: 10).fill(Color.skyPrimary.opacity(0.08))
                            }
                            .scaledToFill()
                            .frame(width: 96, height: 96)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            if let title = external.title, !title.isEmpty {
                                Text(title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                    .lineLimit(2)
                            }
                            if let description = external.description, !description.isEmpty {
                                Text(description)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(3)
                            }
                            if let host = URL(string: uri)?.host, !host.isEmpty {
                                Label(host, systemImage: "link")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }

                        Spacer(minLength: 0)
                    }
                    .padding(10)
                    .background(Color.skyPrimary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.skyPrimary.opacity(0.12), lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)
            }
        }
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

@MainActor
final class ThreadViewModel: ObservableObject {
    @Published private(set) var thread: ThreadNode?
    @Published private(set) var isLoading = true
    @Published var errorMessage: String?

    func handleMissingCredentials() {
        errorMessage = loc("list.detail.missing_creds")
        isLoading = false
    }

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
