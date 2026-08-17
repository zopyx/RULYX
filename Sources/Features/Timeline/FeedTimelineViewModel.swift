import Foundation
import Observation

/// Manages the main timeline feed with polling, pagination, optimistic likes/reposts, inline thread expansion, and analytics.
///
/// State machine: `.initialLoading → .loadingMore → .loaded | .exhausted | .failed | .loadMoreFailed | .refreshing | .empty`
/// Supports periodic polling for new post count, optimistic interaction toggles, and account/feed switching.
@MainActor
@Observable
final class FeedTimelineViewModel: TimelineViewModelProtocol {
    // MARK: - Properties

    /// Store of muted words used to filter visible entries.
    let mutedWords: MutedWordsStore
    /// Store managing the active custom feed selection.
    let feedStore: FeedStore
    /// Store for recording engagement analytics.
    let analytics: AnalyticsStore
    /// All loaded timeline entries, unfiltered. Use `visibleEntries` for display.
    private(set) var entries: [RichFeedEntry] = []
    /// Current state of the timeline loading lifecycle.
    private(set) var state: TimelineState = .initialLoading
    /// Number of new posts discovered since the last refresh (via polling).
    var newPostCount = 0

    // MARK: - Init

    init(
        mutedWords: MutedWordsStore = MutedWordsStore(),
        feedStore: FeedStore = FeedStore(),
        analytics: AnalyticsStore = AnalyticsStore()
    ) {
        self.mutedWords = mutedWords
        self.feedStore = feedStore
        self.analytics = analytics
    }

    // MARK: - Computed Properties

    /// Entries with their post text checked against muted words; muted entries are excluded.
    var visibleEntries: [RichFeedEntry] {
        entries.filter { !mutedWords.contains($0.post.safeRecord.text ?? "") }
    }

    // MARK: - Private Properties

    /// Cursor for paginating through the timeline.
    private var cursor: String?
    /// Set of known post URIs, used to detect new posts during polling.
    private var knownURIs: Set<String> = []
    /// Whether the last refresh produced any posts; used for `newPostCount` calculation.
    private var lastRefreshHadPosts = false
    /// The running polling task.
    private var pollingTask: Task<Void, Never>?

    // MARK: - Polling

    /// Timestamp of the last user interaction (scroll, tap, etc.) for adaptive interval.
    private var lastInteractionTime = Date()
    /// Active polling interval that may adapt over time.
    private var currentPollingInterval: TimeInterval = 15

    /// Notifies the polling system that the user has interacted with the timeline.
    /// Resets the adaptive interval to the base rate.
    func userDidInteract() {
        lastInteractionTime = Date()
        currentPollingInterval = 15
    }

    /// Starts a background polling task that checks for new posts at an adaptive interval.
    ///
    /// Base interval is 15 seconds (reduced from 8s for battery efficiency).
    /// After 120 seconds without user interaction, backs off to 30 seconds.
    func startPolling(account: AppAccount, appPassword: String, using client: LiveBlueskyClient, interval: TimeInterval = 15) {
        stopPolling()
        currentPollingInterval = interval
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, !Task.isCancelled else { return }
                try? await Task.sleep(nanoseconds: UInt64(currentPollingInterval * 1_000_000_000))
                guard !Task.isCancelled else { return }
                // Adaptive back-off: if no interaction for 2 minutes, go to 30s
                let elapsed = Date().timeIntervalSince(lastInteractionTime)
                if elapsed > 120, currentPollingInterval < 30 {
                    currentPollingInterval = 30
                } else if elapsed <= 120, currentPollingInterval > 15 {
                    currentPollingInterval = 15
                }
                await checkForNewPosts(account: account, appPassword: appPassword, using: client)
            }
        }
    }

    /// Cancels the active polling task.
    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    /// Checks for posts newer than the currently known URIs.
    /// Increments `newPostCount` for each new URI discovered.
    private func checkForNewPosts(account: AppAccount, appPassword: String, using client: LiveBlueskyClient) async {
        guard !knownURIs.isEmpty, state != .initialLoading else { return }
        do {
            let response = try await fetchFeed(account: account, appPassword: appPassword, cursor: nil, limit: 10, using: client)
            let newURIs = Set(response.feed.map(\.post.uri)).subtracting(knownURIs)
            guard !newURIs.isEmpty else { return }
            knownURIs.formUnion(newURIs)
            newPostCount += newURIs.count
        } catch {
            if AppError.isCancellation(error) {
                return
            }
            AppLogger.moderation.debug("Polling check failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Optimistic Interactions / Inline Threads

    /// Stores optimistic like state per post URI.
    private var optimisticLikes: [String: Bool] = [:]
    /// Stores optimistic repost state per post URI.
    private var optimisticReposts: [String: Bool] = [:]
    /// Stores the record URI for a like that was created optimistically.
    private var optimisticLikeURIs: [String: String] = [:]
    /// Stores the record URI for a repost that was created optimistically.
    private var optimisticRepostURIs: [String: String] = [:]
    /// Stores optimistic like counts per post URI.
    private var optimisticLikeCounts: [String: Int] = [:]
    /// Stores optimistic repost counts per post URI.
    private var optimisticRepostCounts: [String: Int] = [:]
    /// Set of post URIs with their inline thread expanded.
    var expandedThreadURIs: Set<String> = []
    /// Cached inline thread nodes for expanded posts.
    var inlineThreads: [String: ThreadNode] = [:]

    /// Toggles the inline thread expansion for a post URI.
    /// Uses `ThreadCacheService` to cache fetched threads.
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

    /// Returns the effective like state, preferring optimistic value over server data.
    func effectiveIsLiked(uri: String) -> Bool {
        optimisticLikes[uri] ?? entries.first(where: { $0.post.uri == uri })?.post.isLikedByMe ?? false
    }

    /// Returns the effective repost state, preferring optimistic value over server data.
    func effectiveIsReposted(uri: String) -> Bool {
        optimisticReposts[uri] ?? entries.first(where: { $0.post.uri == uri })?.post.isRepostedByMe ?? false
    }

    /// Returns the effective like record URI, preferring optimistic value over server data.
    func effectiveMyLikeURI(uri: String) -> String? {
        optimisticLikeURIs[uri] ?? entries.first(where: { $0.post.uri == uri })?.post.myLikeURI
    }

    /// Returns the effective like count, preferring optimistic value over server data.
    func effectiveLikeCount(uri: String) -> Int {
        if let count = optimisticLikeCounts[uri] {
            return count
        }
        return entries.first(where: { $0.post.uri == uri })?.post.likeCount ?? 0
    }

    /// Returns the effective repost count, preferring optimistic value over server data.
    func effectiveRepostCount(uri: String) -> Int {
        if let count = optimisticRepostCounts[uri] {
            return count
        }
        return entries.first(where: { $0.post.uri == uri })?.post.repostCount ?? 0
    }

    /// Optimistically toggles the like state. Rolls back on server failure.
    func toggleLike(uri: String, account: AppAccount, appPassword: String, using client: LiveBlueskyClient) async {
        guard let cid = entries.first(where: { $0.post.uri == uri })?.post.cid else { return }
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

    /// Optimistically toggles the repost state. Rolls back on server failure.
    func toggleRepost(uri: String, account: AppAccount, appPassword: String, using client: LiveBlueskyClient) async {
        guard let cid = entries.first(where: { $0.post.uri == uri })?.post.cid else { return }
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

    /// Returns the effective repost record URI, preferring optimistic value over server data.
    func effectiveMyRepostURI(uri: String) -> String? {
        optimisticRepostURIs[uri] ?? entries.first(where: { $0.post.uri == uri })?.post.myRepostURI
    }

    // MARK: - Feed Loading

    /// Fetches feed data from either the custom feed or the main timeline.
    private func fetchFeed(account: AppAccount, appPassword: String, cursor: String?, limit: Int = 50, using client: LiveBlueskyClient) async throws -> RichFeedResponse {
        if let feedURI = feedStore.customFeedURI, feedStore.isUsingCustomFeed {
            return try await client.fetchFeed(feedURI: feedURI, cursor: cursor, limit: limit, account: account, appPassword: appPassword)
        }
        return try await client.fetchTimeline(cursor: cursor, limit: limit, account: account, appPassword: appPassword)
    }

    /// Performs the initial timeline load. Only fires when `state == .initialLoading`.
    func loadTimeline(account: AppAccount, appPassword: String, using client: LiveBlueskyClient) async {
        guard state == .initialLoading else { return }
        do {
            guard !Task.isCancelled else { return }
            let response = try await fetchFeed(account: account, appPassword: appPassword, cursor: nil, using: client)
            entries = response.feed
            knownURIs = Set(entries.map(\.post.uri))
            cursor = response.cursor
            state = entries.isEmpty ? .empty : (cursor == nil ? .exhausted : .loaded)
            Task(priority: .utility) { await prefetchImages(for: response.feed) }
        } catch {
            guard !AppError.isCancellation(error) else { return }
            state = .failed(AppError.userMessage(from: error))
            AppLogger.moderation.error("Failed to load timeline: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Pull-to-refresh: resets optimistic state, reloads the first page of the timeline.
    func refresh(account: AppAccount, appPassword: String, using client: LiveBlueskyClient) async {
        guard state != .refreshing, state != .loadingMore else { return }
        optimisticLikes.removeAll()
        optimisticReposts.removeAll()
        optimisticLikeURIs.removeAll()
        optimisticRepostURIs.removeAll()
        optimisticLikeCounts.removeAll()
        optimisticRepostCounts.removeAll()
        expandedThreadURIs.removeAll()
        inlineThreads.removeAll()
        ThreadCacheService.shared.invalidateAll()
        let previousState = state
        state = .refreshing
        let oldKnown = knownURIs
        let oldCursor = cursor
        cursor = nil
        do {
            guard !Task.isCancelled else { return }
            let response = try await fetchFeed(account: account, appPassword: appPassword, cursor: nil, using: client)
            entries = response.feed
            knownURIs = Set(entries.map(\.post.uri))
            cursor = response.cursor
            recordAnalytics()
            Task(priority: .utility) { await prefetchImages(for: response.feed) }
            if lastRefreshHadPosts {
                newPostCount = knownURIs.subtracting(oldKnown).count
            }
            lastRefreshHadPosts = true
            state = entries.isEmpty ? .empty : (cursor == nil ? .exhausted : .loaded)
        } catch {
            guard !AppError.isCancellation(error) else { return }
            cursor = oldCursor
            state = (previousState == .initialLoading) ? .failed(AppError.userMessage(from: error)) : previousState
            AppLogger.moderation.error("Failed to refresh timeline: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Removes an entry from the timeline by URI (e.g. after deletion).
    func removeEntry(uri: String) {
        entries.removeAll { $0.post.uri == uri }
    }

    /// Inserts an entry at the given index (used for optimistic post creation).
    func insertEntry(_ entry: RichFeedEntry, at index: Int) {
        entries.insert(entry, at: min(index, entries.count))
    }

    /// Resets all state for an account switch (clears data, cache, optimistics).
    func prepareForAccountChange() {
        entries = []
        cursor = nil
        knownURIs = []
        lastRefreshHadPosts = false
        newPostCount = 0
        state = .initialLoading
        optimisticLikes.removeAll()
        optimisticReposts.removeAll()
        optimisticLikeURIs.removeAll()
        optimisticRepostURIs.removeAll()
        optimisticLikeCounts.removeAll()
        optimisticRepostCounts.removeAll()
        expandedThreadURIs.removeAll()
        inlineThreads.removeAll()
    }

    /// Resets all state for a feed switch (same as account change but for feed change).
    func prepareForFeedChange() {
        entries = []
        cursor = nil
        knownURIs = []
        lastRefreshHadPosts = false
        newPostCount = 0
        state = .initialLoading
        optimisticLikes.removeAll()
        optimisticReposts.removeAll()
        optimisticLikeURIs.removeAll()
        optimisticRepostURIs.removeAll()
        optimisticLikeCounts.removeAll()
        optimisticRepostCounts.removeAll()
        expandedThreadURIs.removeAll()
        inlineThreads.removeAll()
    }

    /// Loads the next page of timeline entries.
    func loadMore(account: AppAccount, appPassword: String, using client: LiveBlueskyClient) async {
        guard let cursor, state.hasMore else { return }
        state = .loadingMore
        do {
            guard !Task.isCancelled else { return }
            let response = try await fetchFeed(account: account, appPassword: appPassword, cursor: cursor, using: client)
            entries += response.feed
            knownURIs.formUnion(response.feed.map(\.post.uri))
            self.cursor = response.cursor
            state = response.cursor == nil ? .exhausted : .loaded
            Task(priority: .utility) { await prefetchImages(for: response.feed) }
        } catch {
            guard !AppError.isCancellation(error) else { return }
            state = .loadMoreFailed(AppError.userMessage(from: error))
            AppLogger.moderation.error("Failed to load more timeline: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Prefetch (T07)

    /// Warm ThumbnailPipeline for images in the given entries at low priority
    /// so they are ready before the row scrolls into view.
    private func prefetchImages(for entries: [RichFeedEntry]) async {
        let urls: [URL] = entries.flatMap { entry in
            entry.post.embed?.images?.compactMap { $0.thumb.flatMap(URL.init) } ?? []
        }
        guard !urls.isEmpty else { return }
        await withTaskGroup(of: Void.self) { group in
            for url in urls.prefix(20) {
                group.addTask(priority: .utility) {
                    _ = try? await ThumbnailPipeline.shared.image(for: url, maxPixelSize: 360, scale: 2, ttl: 86400)
                }
            }
        }
    }

    // MARK: - Private Helpers

    /// Records engagement analytics (likes, reposts, replies) for every loaded entry.
    private func recordAnalytics() {
        for entry in entries {
            let post = entry.post
            analytics.record(
                postURI: post.uri,
                likeCount: post.likeCount ?? 0,
                repostCount: post.repostCount ?? 0,
                replyCount: post.replyCount ?? 0
            )
        }
    }
}
