import Foundation

/// Manages a timeline of all posts by members of a given Bluesky list.
///
/// Loads list members, then fetches each member's recent posts via `getAuthorFeed`,
/// merges them into a single chronologically-sorted feed, and supports
/// optimistic like/repost toggles, inline thread expansion, and pagination.
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

    private var members: [BlueskyListMember] = []
    /// Tracks the next cursor per member DID for paginating their author feed.
    private var memberCursors: [String: String] = [:]
    /// Member DIDs that still have more pages available.
    private var memberHasMore: Set<String> = []
    /// Index of the next member to fetch an initial page from (during loadMore).
    private var nextMemberIndex = 0
    /// Maximum number of members to process.
    private let maxMembers = 100
    /// Batch size for concurrent member feed fetches.
    private let batchSize = 5

    // MARK: - Init

    init(list: BlueskyList) {
        self.list = list
    }

    // MARK: - Loading

    /// Performs the initial load: fetches list members, then their recent posts.
    func loadTimeline(account: AppAccount, appPassword: String, using client: LiveBlueskyClient) async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer {
            isLoading = false
            scanProgressLabel = nil
        }
        do {
            guard !Task.isCancelled else { return }
            members = try await client.fetchListMembers(list: list, account: account, appPassword: appPassword)
            members = Array(members.prefix(maxMembers))
            memberCursors.removeAll()
            memberHasMore.removeAll()
            nextMemberIndex = 0

            // Load first 20 members' posts
            let initialCount = min(20, members.count)
            let firstBatch = Array(members.prefix(initialCount))
            nextMemberIndex = initialCount

            scanProgressLabel = loc("list.timeline.fetching_posts")
            let allPosts = try await fetchAuthorPages(for: firstBatch, account: account, appPassword: appPassword, using: client)
            posts = deduplicateAndSort(allPosts)
            hasMore = nextMemberIndex < members.count || !memberHasMore.isEmpty
        } catch {
            guard !AppError.isCancellation(error) else { return }
            errorMessage = AppError.userMessage(from: error)
            AppLogger.moderation.error("Failed to load list timeline: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Loads the next batch: either next pages from members with remaining cursors,
    /// or first pages from the next batch of un-fetched members.
    func loadMore(account: AppAccount, appPassword: String, using client: LiveBlueskyClient) async {
        guard !isLoadingMore, hasMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            guard !Task.isCancelled else { return }

            var newPosts: [RichFeedEntry] = []

            // Phase 1: fetch next pages from members with remaining cursors
            let membersWithMore = members.filter { memberHasMore.contains($0.actor.did ?? "") }
            if !membersWithMore.isEmpty {
                scanProgressLabel = loc("list.timeline.loading_more")
                let batch = Array(membersWithMore.prefix(batchSize))
                newPosts = try await fetchNextPages(for: batch, account: account, appPassword: appPassword, using: client)
            }

            // Phase 2: fetch first pages from the next batch of members
            if newPosts.isEmpty, nextMemberIndex < members.count {
                let remaining = members[nextMemberIndex...]
                let nextBatch = Array(remaining.prefix(10))
                nextMemberIndex += nextBatch.count

                scanProgressLabel = loc("list.timeline.fetching_posts")
                newPosts = try await fetchAuthorPages(for: nextBatch, account: account, appPassword: appPassword, using: client)
            }

            guard !newPosts.isEmpty else {
                hasMore = false
                return
            }
            posts = deduplicateAndSort(posts + newPosts)
            hasMore = nextMemberIndex < members.count || !memberHasMore.isEmpty
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

    /// Fetches the first page of each member's author feed sequentially.
    private func fetchAuthorPages(
        for members: [BlueskyListMember],
        account: AppAccount,
        appPassword: String,
        using client: LiveBlueskyClient
    ) async throws -> [RichFeedEntry] {
        var allPosts: [RichFeedEntry] = []
        let total = members.count
        var processed = 0

        for member in members {
            guard !Task.isCancelled else { return allPosts }
            let did = member.actor.did
            processed += 1

            scanProgressLabel = loc("list.timeline.fetching_posts")
                .replacingOccurrences(of: "{n}", with: "\(processed)")
                .replacingOccurrences(of: "{total}", with: "\(total)")

            do {
                let response = try await client.fetchRichFeed(did: did, cursor: nil, account: account, appPassword: appPassword)
                allPosts += response.feed
                if let cursor = response.cursor {
                    memberCursors[did] = cursor
                    memberHasMore.insert(did)
                }
            } catch {
                AppLogger.moderation.error("Failed to fetch posts for \(member.actor.handle ?? did): \(error.localizedDescription, privacy: .public)")
            }
        }
        return allPosts
    }

    /// Fetches the next page of posts for members with remaining cursors, sequentially.
    private func fetchNextPages(
        for batch: [BlueskyListMember],
        account: AppAccount,
        appPassword: String,
        using client: LiveBlueskyClient
    ) async throws -> [RichFeedEntry] {
        var allPosts: [RichFeedEntry] = []

        for member in batch {
            guard !Task.isCancelled else { return allPosts }
            let did = member.actor.did
            guard let cursor = memberCursors[did] else { continue }

            do {
                let response = try await client.fetchRichFeed(did: did, cursor: cursor, account: account, appPassword: appPassword)
                allPosts += response.feed
                if let nextCursor = response.cursor {
                    memberCursors[did] = nextCursor
                } else {
                    memberHasMore.remove(did)
                }
            } catch {
                AppLogger.moderation.error("Failed to fetch more posts for \(member.actor.handle ?? did): \(error.localizedDescription, privacy: .public)")
            }
        }
        return allPosts
    }

    private func deduplicateAndSort(_ entries: [RichFeedEntry]) -> [RichFeedEntry] {
        var seen = Set<String>()
        let deduped = entries.filter { seen.insert($0.post.uri).inserted }
        return deduped.sorted { a, b in
            let dateA = parseDate(a.post.safeRecord.createdAt) ?? .distantPast
            let dateB = parseDate(b.post.safeRecord.createdAt) ?? .distantPast
            return dateA > dateB
        }
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
