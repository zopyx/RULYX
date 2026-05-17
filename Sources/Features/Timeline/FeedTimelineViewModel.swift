import Foundation

@MainActor
final class FeedTimelineViewModel: ObservableObject {
    let mutedWords: MutedWordsStore
    let feedStore: FeedStore
    let analytics: AnalyticsStore
    @Published private(set) var entries: [RichFeedEntry] = []
    @Published private(set) var state: TimelineState = .initialLoading
    @Published var newPostCount = 0

    init(
        mutedWords: MutedWordsStore = MutedWordsStore(),
        feedStore: FeedStore = FeedStore(),
        analytics: AnalyticsStore = AnalyticsStore()
    ) {
        self.mutedWords = mutedWords
        self.feedStore = feedStore
        self.analytics = analytics
    }

    var visibleEntries: [RichFeedEntry] {
        entries.filter { !mutedWords.contains($0.post.safeRecord.text ?? "") }
    }

    private var cursor: String?
    private var knownURIs: Set<String> = []
    private var lastRefreshHadPosts = false
    private var pollingTask: Task<Void, Never>?

    func startPolling(account: AppAccount, appPassword: String, using client: LiveBlueskyClient, interval: TimeInterval = 15) {
        stopPolling()
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                guard let self, !Task.isCancelled else { return }
                await checkForNewPosts(account: account, appPassword: appPassword, using: client)
            }
        }
    }

    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    private func checkForNewPosts(account: AppAccount, appPassword: String, using client: LiveBlueskyClient) async {
        guard !knownURIs.isEmpty, state != .initialLoading else { return }
        do {
            let response = try await fetchFeed(account: account, appPassword: appPassword, cursor: nil, limit: 5, using: client)
            let newURIs = Set(response.feed.map(\.post.uri)).subtracting(knownURIs)
            guard !newURIs.isEmpty else { return }
            knownURIs.formUnion(newURIs)
            newPostCount += newURIs.count
        } catch {
            if AppError.isCancellation(error) { return }
            AppLogger.moderation.debug("Polling check failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func fetchFeed(account: AppAccount, appPassword: String, cursor: String?, limit: Int = 50, using client: LiveBlueskyClient) async throws -> RichFeedResponse {
        if let feedURI = feedStore.customFeedURI, feedStore.isUsingCustomFeed {
            return try await client.fetchFeed(feedURI: feedURI, cursor: cursor, limit: limit, account: account, appPassword: appPassword)
        }
        return try await client.fetchTimeline(cursor: cursor, limit: limit, account: account, appPassword: appPassword)
    }

    func loadTimeline(account: AppAccount, appPassword: String, using client: LiveBlueskyClient) async {
        guard state == .initialLoading else { return }
        do {
            guard !Task.isCancelled else { return }
            let response = try await fetchFeed(account: account, appPassword: appPassword, cursor: nil, using: client)
            entries = response.feed
            knownURIs = Set(entries.map(\.post.uri))
            cursor = response.cursor
            state = entries.isEmpty ? .empty : (cursor == nil ? .exhausted : .loaded)
        } catch {
            guard !AppError.isCancellation(error) else { return }
            state = .failed(AppError.userMessage(from: error))
            AppLogger.moderation.error("Failed to load timeline: \(error.localizedDescription, privacy: .public)")
        }
    }

    func refresh(account: AppAccount, appPassword: String, using client: LiveBlueskyClient) async {
        guard state != .refreshing, state != .loadingMore else { return }
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

    func removeEntry(uri: String) {
        entries.removeAll { $0.post.uri == uri }
    }

    func insertEntry(_ entry: RichFeedEntry, at index: Int) {
        entries.insert(entry, at: min(index, entries.count))
    }

    func prepareForAccountChange() {
        entries = []
        cursor = nil
        knownURIs = []
        lastRefreshHadPosts = false
        newPostCount = 0
        state = .initialLoading
    }

    func prepareForFeedChange() {
        entries = []
        cursor = nil
        knownURIs = []
        lastRefreshHadPosts = false
        newPostCount = 0
        state = .initialLoading
    }

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
        } catch {
            guard !AppError.isCancellation(error) else { return }
            state = .loadMoreFailed(AppError.userMessage(from: error))
            AppLogger.moderation.error("Failed to load more timeline: \(error.localizedDescription, privacy: .public)")
        }
    }

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
