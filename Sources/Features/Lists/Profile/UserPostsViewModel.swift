import Combine
import Foundation

/// Manages a user's posts with search/filter, CSV/JSON export, optimistic interactions, and inline thread expansion.
///
/// Loads paginated feed data via `fetchRichFeed`, supports client-side text and date filtering,
/// optimistic like/repost toggles, inline thread caching/expansion, and provides `sortedFilteredPosts` for display.
@MainActor
final class UserPostsViewModel: ObservableObject {
    // MARK: - Properties

    /// All loaded posts, unsorted. Display via `sortedFilteredPosts`.
    @Published private(set) var posts: [RichFeedEntry] = []
    /// True while the initial load is in progress.
    @Published private(set) var isLoading = false
    /// True while loading the next page.
    @Published private(set) var isLoadingMore = false
    /// False when no more pages are available.
    @Published private(set) var hasMore = true
    /// User-facing error message.
    @Published var errorMessage: String?
    /// Filter text for client-side post body search.
    @Published var searchText = ""
    /// Inclusive start date for filtering posts.
    @Published var fromDate: Date?
    /// Inclusive end date for filtering posts.
    @Published var toDate: Date?

    /// Posts filtered by search text and date range, sorted newest-first.
    @Published private(set) var sortedFilteredPosts: [RichFeedEntry] = []

    // MARK: - Optimistic Interactions

    @Published private var optimisticLikes: [String: Bool] = [:]
    @Published private var optimisticReposts: [String: Bool] = [:]
    @Published private var optimisticLikeURIs: [String: String] = [:]
    @Published private var optimisticRepostURIs: [String: String] = [:]
    @Published private var optimisticLikeCounts: [String: Int] = [:]
    @Published private var optimisticRepostCounts: [String: Int] = [:]

    // MARK: - Scanning

    /// True while auto-scanning threads for replies from other users.
    @Published private(set) var isScanning = false
    /// Progress label shown during thread scanning.
    @Published private(set) var scanProgressLabel: String?

    // MARK: - Inline Threads

    @Published var expandedThreadURIs: Set<String> = []
    @Published var inlineThreads: [String: ThreadNode] = [:]

    // MARK: - Private Properties

    /// Cursor for paginating through the author feed.
    private var cursor: String?
    /// The DID of the profile whose posts are being viewed.
    private let did: String
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Init

    init(did: String) {
        self.did = did

        $posts
            .combineLatest($searchText, $fromDate, $toDate)
            .map { posts, searchText, fromDate, toDate in
                var result = posts

                if !searchText.isEmpty {
                    let query = searchText.lowercased()
                    result = result.filter { entry in
                        entry.post.safeRecord.text?.lowercased().contains(query) ?? false
                    }
                }

                if let fromDate {
                    result = result.filter { entry in
                        guard let d = parseDate(entry.post.safeRecord.createdAt) else { return false }
                        return d >= fromDate
                    }
                }

                if let toDate {
                    result = result.filter { entry in
                        guard let d = parseDate(entry.post.safeRecord.createdAt) else { return false }
                        return d <= toDate
                    }
                }

                result.sort { a, b in
                    let dateA = parseDate(a.post.safeRecord.createdAt) ?? .distantPast
                    let dateB = parseDate(b.post.safeRecord.createdAt) ?? .distantPast
                    return dateA > dateB
                }

                return result
            }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] filtered in
                self?.sortedFilteredPosts = filtered
            }
            .store(in: &cancellables)
    }

    // MARK: - Public Methods

    /// Pull-to-refresh: resets pagination and reloads the first page, preserving cursor on failure.
    func refresh(account: AppAccount, appPassword: String, using client: LiveBlueskyClient) async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        let oldCursor = cursor
        let oldHasMore = hasMore
        cursor = nil
        hasMore = true
        defer { isLoading = false }
        do {
            guard !Task.isCancelled else { return }
            let response = try await client.fetchRichFeed(did: did, cursor: nil, account: account, appPassword: appPassword)
            posts = response.feed
            cursor = response.cursor
            hasMore = cursor != nil
            resetOptimisticState()
            await autoExpandThreads(account: account, appPassword: appPassword, using: client)
        } catch {
            guard !AppError.isCancellation(error) else { return }
            cursor = oldCursor
            hasMore = oldHasMore
            errorMessage = AppError.userMessage(from: error)
            AppLogger.moderation.error("Failed to refresh posts: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Loads the first page of posts, replacing any existing data.
    func loadPosts(account: AppAccount, appPassword: String, using client: LiveBlueskyClient) async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            guard !Task.isCancelled else { return }
            let response = try await client.fetchRichFeed(did: did, cursor: nil, account: account, appPassword: appPassword)
            posts = response.feed
            cursor = response.cursor
            hasMore = cursor != nil
        } catch {
            guard !AppError.isCancellation(error) else { return }
            errorMessage = AppError.userMessage(from: error)
            AppLogger.moderation.error("Failed to load posts: \(error.localizedDescription, privacy: .public)")
        }
        await autoExpandThreads(account: account, appPassword: appPassword, using: client)
    }

    /// Loads the next page of posts and appends to `posts`.
    func loadMorePosts(account: AppAccount, appPassword: String, using client: LiveBlueskyClient) async {
        guard !isLoadingMore, let cursor else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            guard !Task.isCancelled else { return }
            let response = try await client.fetchRichFeed(did: did, cursor: cursor, account: account, appPassword: appPassword)
            posts += response.feed
            self.cursor = response.cursor
            hasMore = response.cursor != nil
        } catch {
            guard !AppError.isCancellation(error) else { return }
            errorMessage = AppError.userMessage(from: error)
            AppLogger.moderation.error("Failed to load more posts: \(error.localizedDescription, privacy: .public)")
        }
        await autoExpandThreads(account: account, appPassword: appPassword, using: client)
    }

    // MARK: - Optimistic Interactions

    func toggleLike(uri: String, account: AppAccount, appPassword: String, using client: LiveBlueskyClient) async {
        guard let entry = posts.first(where: { $0.post.uri == uri }),
              let cid = entry.post.cid else { return }
        let wasLiked = effectiveIsLiked(uri: uri)
        let oldCount = effectiveLikeCount(uri: uri)
        optimisticLikes[uri] = !wasLiked
        optimisticLikeCounts[uri] = oldCount + (wasLiked ? -1 : 1)
        do {
            if wasLiked, let likeURI = effectiveMyLikeURI(uri: uri) {
                _ = try await client.deleteRecord(recordURI: likeURI, account: account, appPassword: appPassword)
                optimisticLikeURIs.removeValue(forKey: uri)
            } else {
                let response = try await client.createLike(uri: uri, cid: cid, account: account, appPassword: appPassword)
                optimisticLikeURIs[uri] = response.uri
            }
        } catch {
            optimisticLikes.removeValue(forKey: uri)
            optimisticLikeCounts.removeValue(forKey: uri)
            if wasLiked { optimisticLikeURIs[uri] = posts.first(where: { $0.post.uri == uri })?.post.myLikeURI }
            AppLogger.moderation.error("Like failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func toggleRepost(uri: String, account: AppAccount, appPassword: String, using client: LiveBlueskyClient) async {
        guard let entry = posts.first(where: { $0.post.uri == uri }),
              let cid = entry.post.cid else { return }
        let wasReposted = effectiveIsReposted(uri: uri)
        let oldCount = effectiveRepostCount(uri: uri)
        optimisticReposts[uri] = !wasReposted
        optimisticRepostCounts[uri] = oldCount + (wasReposted ? -1 : 1)
        do {
            if wasReposted, let repostURI = effectiveMyRepostURI(uri: uri) {
                _ = try await client.deleteRecord(recordURI: repostURI, account: account, appPassword: appPassword)
                optimisticRepostURIs.removeValue(forKey: uri)
            } else {
                let response = try await client.createRepost(uri: uri, cid: cid, account: account, appPassword: appPassword)
                optimisticRepostURIs[uri] = response.uri
            }
        } catch {
            optimisticReposts.removeValue(forKey: uri)
            optimisticRepostCounts.removeValue(forKey: uri)
            if wasReposted { optimisticRepostURIs[uri] = posts.first(where: { $0.post.uri == uri })?.post.myRepostURI }
            AppLogger.moderation.error("Repost failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func effectiveIsLiked(uri: String) -> Bool {
        optimisticLikes[uri] ?? posts.first(where: { $0.post.uri == uri })?.post.isLikedByMe ?? false
    }

    func effectiveIsReposted(uri: String) -> Bool {
        optimisticReposts[uri] ?? posts.first(where: { $0.post.uri == uri })?.post.isRepostedByMe ?? false
    }

    func effectiveMyLikeURI(uri: String) -> String? {
        optimisticLikeURIs[uri] ?? posts.first(where: { $0.post.uri == uri })?.post.myLikeURI
    }

    func effectiveMyRepostURI(uri: String) -> String? {
        optimisticRepostURIs[uri] ?? posts.first(where: { $0.post.uri == uri })?.post.myRepostURI
    }

    func effectiveLikeCount(uri: String) -> Int {
        if let count = optimisticLikeCounts[uri] { return count }
        return posts.first(where: { $0.post.uri == uri })?.post.likeCount ?? 0
    }

    func effectiveRepostCount(uri: String) -> Int {
        if let count = optimisticRepostCounts[uri] { return count }
        return posts.first(where: { $0.post.uri == uri })?.post.repostCount ?? 0
    }

    // MARK: - Inline Threads

    func toggleInlineThread(uri: String, account: AppAccount, appPassword: String, using client: LiveBlueskyClient) async {
        if expandedThreadURIs.contains(uri) {
            expandedThreadURIs.remove(uri)
            inlineThreads.removeValue(forKey: uri)
            return
        }
        if let cached = ThreadCacheService.shared.get(uri: uri) {
            inlineThreads[uri] = cached
            expandedThreadURIs.insert(uri)
            return
        }
        do {
            let response = try await client.fetchPostThread(uri: uri, account: account, appPassword: appPassword)
            ThreadCacheService.shared.set(uri: uri, thread: response.thread)
            inlineThreads[uri] = response.thread
            expandedThreadURIs.insert(uri)
        } catch {
            AppLogger.moderation.error("Failed to load thread for inline expansion: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// After loading posts, automatically expand threads for posts with replies,
    /// filtering to only show replies from users other than the profile author.
    func autoExpandThreads(account: AppAccount, appPassword: String, using client: LiveBlueskyClient) async {
        let replyPosts = posts.filter { ($0.post.replyCount ?? 0) > 0 }
        guard !replyPosts.isEmpty else { return }
        isScanning = true
        defer {
            isScanning = false
            scanProgressLabel = nil
        }

        let uris = replyPosts.map(\.post.uri)
        let total = uris.count
        var processed = 0

        for uri in uris {
            guard !Task.isCancelled else { return }
            // Skip already-expanded threads
            guard !expandedThreadURIs.contains(uri) else {
                processed += 1
                continue
            }

            processed += 1
            scanProgressLabel = loc("directreplies.scanning_progress")
                .replacingOccurrences(of: "{n}", with: "\(processed)")
                .replacingOccurrences(of: "{total}", with: "\(total)")

            do {
                let thread: ThreadNode
                if let cached = ThreadCacheService.shared.get(uri: uri) {
                    thread = cached
                } else {
                    let response = try await client.fetchPostThread(uri: uri, depth: 3, account: account, appPassword: appPassword)
                    ThreadCacheService.shared.set(uri: uri, thread: response.thread)
                    thread = response.thread
                }

                let filtered = filterOtherReplies(from: thread, myDID: did)
                if filtered.replies?.isEmpty == false {
                    inlineThreads[uri] = filtered
                    expandedThreadURIs.insert(uri)
                }
            } catch {
                AppLogger.moderation.error("Thread fetch failed for \(uri): \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Recursively filters a thread node to keep only replies from users other than `myDID`.
    private func filterOtherReplies(from node: ThreadNode, myDID: String) -> ThreadNode {
        let filteredReplies = node.replies?.compactMap { reply -> ThreadNode? in
            let authorDID = reply.post.author?.did
            guard authorDID != nil, authorDID != myDID else { return nil }
            let childFiltered = filterOtherReplies(from: reply, myDID: myDID)
            return ThreadNode(post: reply.post, parent: nil, replies: childFiltered.replies)
        }
        return ThreadNode(post: node.post, parent: nil, replies: filteredReplies)
    }

    // MARK: - Entry Management

    func removeEntry(uri: String) {
        posts.removeAll { $0.post.uri == uri }
    }

    func insertEntry(_ entry: RichFeedEntry, at index: Int) {
        posts.insert(entry, at: min(index, posts.count))
    }

    // MARK: - Export

    /// Exports the filtered/sorted posts as a CSV string with header row.
    func exportCSV() -> String {
        let header = "uri,author_did,author_handle,text,created_at,reply_count,repost_count,like_count"
        let rows = sortedFilteredPosts.map { entry -> String in
            let p = entry.post
            let author = p.safeAuthor
            let text = (p.safeRecord.text ?? "").replacingOccurrences(of: "\"", with: "\"\"")
            let fields = [
                p.uri,
                author.did ?? "",
                author.handle ?? "",
                "\"\(text)\"",
                p.safeRecord.createdAt ?? "",
                "\(p.replyCount ?? 0)",
                "\(p.repostCount ?? 0)",
                "\(p.likeCount ?? 0)",
            ]
            return fields.joined(separator: ",")
        }
        return ([header] + rows).joined(separator: "\n")
    }

    /// Exports the filtered/sorted posts as a pretty-printed JSON data object.
    func exportJSON() -> Data {
        let objects = sortedFilteredPosts.map { entry -> [String: Any] in
            let p = entry.post
            let author = p.safeAuthor
            return [
                "uri": p.uri,
                "author_did": author.did ?? "",
                "author_handle": author.handle ?? "",
                "author_display_name": author.displayName ?? "",
                "text": p.safeRecord.text ?? "",
                "created_at": p.safeRecord.createdAt ?? "",
                "reply_count": p.replyCount ?? 0,
                "repost_count": p.repostCount ?? 0,
                "like_count": p.likeCount ?? 0,
                "has_images": p.embed?.images?.isEmpty == false,
                "has_video": p.embed?.video != nil,
            ] as [String: Any]
        }
        return (try? JSONSerialization.data(withJSONObject: objects, options: [.prettyPrinted, .sortedKeys])) ?? Data()
    }

    // MARK: - Private

    private func resetOptimisticState() {
        optimisticLikes.removeAll()
        optimisticReposts.removeAll()
        optimisticLikeURIs.removeAll()
        optimisticRepostURIs.removeAll()
        optimisticLikeCounts.removeAll()
        optimisticRepostCounts.removeAll()
        expandedThreadURIs.removeAll()
        inlineThreads.removeAll()
        ThreadCacheService.shared.invalidateAll()
    }
}
