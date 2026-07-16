import Foundation
import Observation

/// Manages a timeline of all posts by members of a given Bluesky list.
///
/// Prefer the server-provided list feed, then falls back to member author feeds
/// filtered to posts authored by the member being scanned.
@MainActor
@Observable
final class ListTimelineViewModel: TimelineViewModelProtocol {
    let list: BlueskyList

    // MARK: - Published State

    private(set) var entries: [RichFeedEntry] = []
    private(set) var state: TimelineState = .initialLoading
    var newPostCount = 0
    private(set) var scanProgressLabel: String?

    // MARK: - Optimistic Interactions

    private var optimisticLikes: [String: Bool] = [:]
    private var optimisticReposts: [String: Bool] = [:]
    private var optimisticLikeURIs: [String: String] = [:]
    private var optimisticRepostURIs: [String: String] = [:]
    private var optimisticLikeCounts: [String: Int] = [:]
    private var optimisticRepostCounts: [String: Int] = [:]

    // MARK: - Inline Threads

    var expandedThreadURIs: Set<String> = []
    var inlineThreads: [String: ThreadNode] = [:]

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

    func loadTimeline(account: AppAccount, appPassword: String, using client: LiveBlueskyClient) async {
        guard state == .initialLoading else { return }
        state = .initialLoading
        cursor = nil
        sourceMode = .appViewListFeed
        resetFallbackPagination()
        defer { scanProgressLabel = nil }
        do {
            guard !Task.isCancelled else { return }
            scanProgressLabel = loc("list.timeline.fetching_posts")
            let response = try await client.fetchListFeed(listURI: list.id, cursor: nil, account: account, appPassword: appPassword)
            entries = response.feed
            cursor = response.cursor
            state = entries.isEmpty ? .empty : (response.cursor == nil ? .exhausted : .loaded)
            if entries.isEmpty {
                await loadMemberOwnPostsFallback(account: account, appPassword: appPassword, using: client)
            }
        } catch {
            guard !AppError.isCancellation(error) else { return }
            state = .failed(AppError.userMessage(from: error))
            AppLogger.moderation.error("Failed to load list timeline: \(error.localizedDescription, privacy: .public)")
            await loadMemberOwnPostsFallback(account: account, appPassword: appPassword, using: client)
        }
    }

    func loadMore(account: AppAccount, appPassword: String, using client: LiveBlueskyClient) async {
        guard state != .loadingMore, state.hasMore else { return }
        state = .loadingMore
        scanProgressLabel = loc("list.timeline.loading_more")
        defer { scanProgressLabel = nil }
        do {
            guard !Task.isCancelled else { return }
            switch sourceMode {
            case .appViewListFeed:
                guard let cursor else {
                    state = .exhausted
                    return
                }
                let response = try await client.fetchListFeed(listURI: list.id, cursor: cursor, account: account, appPassword: appPassword)
                entries += response.feed
                self.cursor = response.cursor
                state = response.cursor == nil ? .exhausted : .loaded
            case .memberOwnPosts:
                let newPosts = try await loadMoreMemberOwnPosts(account: account, appPassword: appPassword, using: client)
                entries = deduplicateAndSort(entries + newPosts)
                let hasMorePosts = nextMemberIndex < members.count || !memberHasMore.isEmpty
                state = hasMorePosts ? .loaded : .exhausted
            }
        } catch {
            guard !AppError.isCancellation(error) else { return }
            state = .loadMoreFailed(AppError.userMessage(from: error))
            AppLogger.moderation.error("Failed to load more list timeline: \(error.localizedDescription, privacy: .public)")
        }
    }

    func refresh(account: AppAccount, appPassword: String, using client: LiveBlueskyClient) async {
        guard state != .initialLoading else { return }
        resetOptimisticState()
        state = .initialLoading
        await loadTimeline(account: account, appPassword: appPassword, using: client)
    }

    // MARK: - Polling

    func startPolling(account: AppAccount, appPassword: String, using client: LiveBlueskyClient, interval: TimeInterval = 15) {
        // Polling not yet implemented for list timelines — deferred to Phase 4.
    }

    func stopPolling() {}

    func userDidInteract() {}

    // MARK: - Optimistic Interactions

    func toggleLike(uri: String, account: AppAccount, appPassword: String, using client: LiveBlueskyClient) async {
        guard let entry = entries.first(where: { $0.post.uri == uri }),
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
            if wasLiked {
                optimisticLikeURIs[uri] = entries.first(where: { $0.post.uri == uri })?.post.myLikeURI
            }
            AppLogger.moderation.error("Like failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func toggleRepost(uri: String, account: AppAccount, appPassword: String, using client: LiveBlueskyClient) async {
        guard let entry = entries.first(where: { $0.post.uri == uri }),
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
            if wasReposted {
                optimisticRepostURIs[uri] = entries.first(where: { $0.post.uri == uri })?.post.myRepostURI
            }
            AppLogger.moderation.error("Repost failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func effectiveIsLiked(uri: String) -> Bool {
        optimisticLikes[uri] ?? entries.first(where: { $0.post.uri == uri })?.post.isLikedByMe ?? false
    }

    func effectiveIsReposted(uri: String) -> Bool {
        optimisticReposts[uri] ?? entries.first(where: { $0.post.uri == uri })?.post.isRepostedByMe ?? false
    }

    func effectiveMyLikeURI(uri: String) -> String? {
        optimisticLikeURIs[uri] ?? entries.first(where: { $0.post.uri == uri })?.post.myLikeURI
    }

    func effectiveMyRepostURI(uri: String) -> String? {
        optimisticRepostURIs[uri] ?? entries.first(where: { $0.post.uri == uri })?.post.myRepostURI
    }

    func effectiveLikeCount(uri: String) -> Int {
        if let count = optimisticLikeCounts[uri] {
            return count
        }
        return entries.first(where: { $0.post.uri == uri })?.post.likeCount ?? 0
    }

    func effectiveRepostCount(uri: String) -> Int {
        if let count = optimisticRepostCounts[uri] {
            return count
        }
        return entries.first(where: { $0.post.uri == uri })?.post.repostCount ?? 0
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
        entries.removeAll { $0.post.uri == uri }
    }

    func insertEntry(_ entry: RichFeedEntry, at index: Int) {
        entries.insert(entry, at: min(index, entries.count))
    }

    func prepareForAccountChange() {
        entries = []
        cursor = nil
        newPostCount = 0
        state = .initialLoading
        resetOptimisticState()
    }

    // MARK: - Private Helpers

    private func loadMemberOwnPostsFallback(account: AppAccount, appPassword: String, using client: LiveBlueskyClient) async {
        sourceMode = .memberOwnPosts
        cursor = nil
        resetFallbackPagination()

        do {
            members = try await client.fetchListMembers(list: list, account: account, appPassword: appPassword)
            let firstBatch = Array(members.prefix(initialMemberBatchSize))
            nextMemberIndex = firstBatch.count
            scanProgressLabel = loc("list.timeline.fetching_posts")
            entries = try await deduplicateAndSort(fetchMemberOwnPosts(for: firstBatch, account: account, appPassword: appPassword, using: client))
            let hasMorePosts = nextMemberIndex < members.count || !memberHasMore.isEmpty
            state = entries.isEmpty ? .empty : (hasMorePosts ? .loaded : .exhausted)
            while entries.isEmpty, hasMorePosts, !Task.isCancelled {
                let morePosts = try await loadMoreMemberOwnPosts(account: account, appPassword: appPassword, using: client)
                entries = deduplicateAndSort(entries + morePosts)
                let stillHasMore = nextMemberIndex < members.count || !memberHasMore.isEmpty
                state = entries.isEmpty ? .empty : (stillHasMore ? .loaded : .exhausted)
            }
        } catch {
            guard !AppError.isCancellation(error) else { return }
            if state != .failed("") { // Don't overwrite a specific error with fallback error
                state = .failed(AppError.userMessage(from: error))
            }
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
