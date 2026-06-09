import Foundation

/// Manages a timeline of all posts by members of a given Bluesky list.
///
/// Prefer the server-provided list feed, then falls back to member author feeds
/// filtered to posts authored by the member being scanned.
@MainActor
final class ListTimelineViewModel: ObservableObject {
    let list: BlueskyList

    // MARK: - Published State

    @Published private(set) var posts: [RichFeedEntry] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var hasMore = true
    @Published var errorMessage: String?
    @Published private(set) var scanProgressLabel: String?

    // MARK: - Optimistic Interactions

    @Published private var optimisticLikes: [String: Bool] = [:]
    @Published private var optimisticReposts: [String: Bool] = [:]
    @Published private var optimisticLikeURIs: [String: String] = [:]
    @Published private var optimisticRepostURIs: [String: String] = [:]
    @Published private var optimisticLikeCounts: [String: Int] = [:]
    @Published private var optimisticRepostCounts: [String: Int] = [:]

    // MARK: - Inline Threads

    @Published var expandedThreadURIs: Set<String> = []
    @Published var inlineThreads: [String: ThreadNode] = [:]

    // MARK: - Private Properties

    private enum SourceMode {
        case appViewListFeed
        case memberOwnPosts
    }

    private var cursor: String?
    private var sourceMode = SourceMode.appViewListFeed
    private var members: [BlueskyListMember] = []
    private var memberCursors: [String: String] = [:]
    private var memberHasMore: Set<String> = []
    private var nextMemberIndex = 0
    private let initialMemberBatchSize = 20
    private let memberBatchSize = 10

    // MARK: - Init

    init(list: BlueskyList) {
        self.list = list
    }

    // MARK: - Loading

    /// Performs the initial list-feed load.
    func loadTimeline(account: AppAccount, appPassword: String, using client: LiveBlueskyClient) async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        cursor = nil
        sourceMode = .appViewListFeed
        resetFallbackPagination()
        defer {
            isLoading = false
            scanProgressLabel = nil
        }
        do {
            guard !Task.isCancelled else { return }
            scanProgressLabel = loc("list.timeline.fetching_posts")
            let response = try await client.fetchListFeed(listURI: list.id, cursor: nil, account: account, appPassword: appPassword)
            posts = response.feed
            cursor = response.cursor
            hasMore = response.cursor != nil
            if posts.isEmpty {
                await loadMemberOwnPostsFallback(account: account, appPassword: appPassword, using: client)
            }
        } catch {
            guard !AppError.isCancellation(error) else { return }
            AppLogger.moderation.error("Failed to load list timeline: \(error.localizedDescription, privacy: .public)")
            await loadMemberOwnPostsFallback(account: account, appPassword: appPassword, using: client)
        }
    }

    /// Loads the next page of the server-provided list feed.
    func loadMore(account: AppAccount, appPassword: String, using client: LiveBlueskyClient) async {
        guard !isLoadingMore, hasMore else { return }
        isLoadingMore = true
        scanProgressLabel = loc("list.timeline.loading_more")
        defer {
            isLoadingMore = false
            scanProgressLabel = nil
        }
        do {
            guard !Task.isCancelled else { return }
            switch sourceMode {
            case .appViewListFeed:
                guard let cursor else {
                    hasMore = false
                    return
                }
                let response = try await client.fetchListFeed(listURI: list.id, cursor: cursor, account: account, appPassword: appPassword)
                posts += response.feed
                self.cursor = response.cursor
                hasMore = response.cursor != nil
            case .memberOwnPosts:
                let newPosts = try await loadMoreMemberOwnPosts(account: account, appPassword: appPassword, using: client)
                posts = deduplicateAndSort(posts + newPosts)
                hasMore = nextMemberIndex < members.count || !memberHasMore.isEmpty
            }
        } catch {
            guard !AppError.isCancellation(error) else { return }
            errorMessage = AppError.userMessage(from: error)
            AppLogger.moderation.error("Failed to load more list timeline: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Pull-to-refresh: reloads everything from scratch.
    func refresh(account: AppAccount, appPassword: String, using client: LiveBlueskyClient) async {
        guard !isLoading else { return }
        resetOptimisticState()
        await loadTimeline(account: account, appPassword: appPassword, using: client)
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

    // MARK: - Entry Management

    func removeEntry(uri: String) {
        posts.removeAll { $0.post.uri == uri }
    }

    func insertEntry(_ entry: RichFeedEntry, at index: Int) {
        posts.insert(entry, at: min(index, posts.count))
    }

    // MARK: - Private Helpers

    private func loadMemberOwnPostsFallback(account: AppAccount, appPassword: String, using client: LiveBlueskyClient) async {
        sourceMode = .memberOwnPosts
        cursor = nil
        resetFallbackPagination()
        errorMessage = nil

        do {
            members = try await client.fetchListMembers(list: list, account: account, appPassword: appPassword)
            let firstBatch = Array(members.prefix(initialMemberBatchSize))
            nextMemberIndex = firstBatch.count
            scanProgressLabel = loc("list.timeline.fetching_posts")
            posts = try await deduplicateAndSort(fetchMemberOwnPosts(for: firstBatch, account: account, appPassword: appPassword, using: client))
            hasMore = nextMemberIndex < members.count || !memberHasMore.isEmpty
            while posts.isEmpty, hasMore, !Task.isCancelled {
                let morePosts = try await loadMoreMemberOwnPosts(account: account, appPassword: appPassword, using: client)
                posts = deduplicateAndSort(posts + morePosts)
                hasMore = nextMemberIndex < members.count || !memberHasMore.isEmpty
            }
        } catch {
            guard !AppError.isCancellation(error) else { return }
            errorMessage = AppError.userMessage(from: error)
            AppLogger.moderation.error("Failed to load fallback list timeline: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func loadMoreMemberOwnPosts(account: AppAccount, appPassword: String, using client: LiveBlueskyClient) async throws -> [RichFeedEntry] {
        let membersWithMore = members.filter { memberHasMore.contains($0.actor.did) }
        if !membersWithMore.isEmpty {
            return try await fetchMemberOwnPosts(for: Array(membersWithMore.prefix(memberBatchSize)), account: account, appPassword: appPassword, using: client)
        }

        guard nextMemberIndex < members.count else { return [] }
        let remaining = members[nextMemberIndex...]
        let batch = Array(remaining.prefix(memberBatchSize))
        nextMemberIndex += batch.count
        return try await fetchMemberOwnPosts(for: batch, account: account, appPassword: appPassword, using: client)
    }

    private func fetchMemberOwnPosts(
        for members: [BlueskyListMember],
        account: AppAccount,
        appPassword: String,
        using client: LiveBlueskyClient
    ) async throws -> [RichFeedEntry] {
        var result: [RichFeedEntry] = []
        for member in members {
            guard !Task.isCancelled else { return result }
            let did = member.actor.did
            let response = try await client.fetchRichFeed(did: did, cursor: memberCursors[did], account: account, appPassword: appPassword)
            result += response.feed.filter { entry in
                guard let authorDID = entry.post.author?.did else { return false }
                return authorDID == did
            }
            if let cursor = response.cursor {
                memberCursors[did] = cursor
                memberHasMore.insert(did)
            } else {
                memberCursors.removeValue(forKey: did)
                memberHasMore.remove(did)
            }
        }

        return result
    }

    private func deduplicateAndSort(_ entries: [RichFeedEntry]) -> [RichFeedEntry] {
        var seen = Set<String>()
        let deduped = entries.filter { seen.insert($0.post.uri).inserted }
        return deduped.sorted { first, second in
            let firstDate = parseDate(first.post.safeRecord.createdAt) ?? .distantPast
            let secondDate = parseDate(second.post.safeRecord.createdAt) ?? .distantPast
            return firstDate > secondDate
        }
    }

    private func resetFallbackPagination() {
        members.removeAll()
        memberCursors.removeAll()
        memberHasMore.removeAll()
        nextMemberIndex = 0
    }

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
