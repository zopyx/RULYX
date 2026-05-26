import Foundation

@MainActor
final class DirectRepliesViewModel: ObservableObject {
    @Published private(set) var entries: [RichFeedEntry] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var hasMore = true
    @Published var errorMessage: String?
    @Published private(set) var progressLabel: String?

    private var feedCursor: String?
    private let did: String
    private let maxPosts = 100

    init(did: String) {
        self.did = did
    }

    func reset() {
        entries = []
        feedCursor = nil
        hasMore = true
        errorMessage = nil
    }

    func load(account: AppAccount, appPassword: String, using client: LiveBlueskyClient) async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        progressLabel = loc("directreplies.scanning_posts")
        defer {
            isLoading = false
            progressLabel = nil
        }
        do {
            guard !Task.isCancelled else { return }
            entries = []
            feedCursor = nil
            hasMore = true
            let myPosts = try await fetchMyPosts(account: account, appPassword: appPassword, using: client)
            let replies = try await fetchReplies(for: myPosts, account: account, appPassword: appPassword, using: client)
            entries = deduplicateAndSort(replies)
            hasMore = !myPosts.isEmpty
        } catch {
            guard !AppError.isCancellation(error) else { return }
            feedCursor = nil
            hasMore = false
            errorMessage = AppError.userMessage(from: error)
            AppLogger.moderation.error("Failed to load direct replies: \(error.localizedDescription, privacy: .public)")
        }
    }

    func loadMore(account: AppAccount, appPassword: String, using client: LiveBlueskyClient) async {
        guard !isLoadingMore, let feedCursor else { return }
        isLoadingMore = true
        progressLabel = loc("directreplies.scanning_posts")
        defer {
            isLoadingMore = false
            progressLabel = nil
        }
        do {
            guard !Task.isCancelled else { return }
            let morePosts = try await fetchMyPosts(account: account, appPassword: appPassword, using: client)
            let moreReplies = try await fetchReplies(for: morePosts, account: account, appPassword: appPassword, using: client)
            let existingURIs = Set(entries.map(\.post.uri))
            let newEntries = moreReplies.filter { !existingURIs.contains($0.post.uri) }
            entries = deduplicateAndSort(entries + newEntries)
            hasMore = !morePosts.isEmpty
        } catch {
            guard !AppError.isCancellation(error) else { return }
            errorMessage = AppError.userMessage(from: error)
            AppLogger.moderation.error("Failed to load more direct replies: \(error.localizedDescription, privacy: .public)")
        }
    }

    func refresh(account: AppAccount, appPassword: String, using client: LiveBlueskyClient) async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        let oldCursor = feedCursor
        feedCursor = nil
        hasMore = true
        progressLabel = loc("directreplies.scanning_posts")
        defer {
            isLoading = false
            progressLabel = nil
        }
        do {
            guard !Task.isCancelled else { return }
            entries = []
            let myPosts = try await fetchMyPosts(account: account, appPassword: appPassword, using: client)
            let replies = try await fetchReplies(for: myPosts, account: account, appPassword: appPassword, using: client)
            entries = deduplicateAndSort(replies)
            hasMore = !myPosts.isEmpty
        } catch {
            guard !AppError.isCancellation(error) else { return }
            feedCursor = oldCursor
            errorMessage = AppError.userMessage(from: error)
            AppLogger.moderation.error("Failed to refresh direct replies: \(error.localizedDescription, privacy: .public)")
        }
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

    // MARK: - Phase 1: Collect my posts

    private func fetchMyPosts(account: AppAccount, appPassword: String, using client: LiveBlueskyClient) async throws -> [RichFeedEntry] {
        var allPosts: [RichFeedEntry] = []
        var pagesChecked = 0

        while pagesChecked < 5, !Task.isCancelled, allPosts.count < maxPosts {
            progressLabel = loc("directreplies.fetching_page")
                .replacingOccurrences(of: "{n}", with: "\(pagesChecked + 1)")
            let response = try await client.fetchRichFeed(
                did: did,
                cursor: feedCursor,
                account: account,
                appPassword: appPassword
            )

            let myPosts = response.feed.filter { $0.post.author?.did == did }
            allPosts += myPosts
            feedCursor = response.cursor
            pagesChecked += 1

            guard let next = response.cursor, !next.isEmpty else {
                feedCursor = nil
                break
            }
            feedCursor = next
        }

        return Array(allPosts.prefix(maxPosts))
    }

    // MARK: - Phase 2: Fetch threads and extract replies

    private func fetchReplies(for myPosts: [RichFeedEntry], account: AppAccount, appPassword: String, using client: LiveBlueskyClient) async throws -> [RichFeedEntry] {
        let uris = myPosts.map(\.post.uri)
        var allReplies: [RichFeedEntry] = []
        let batchSize = 5

        for batchStart in stride(from: 0, to: uris.count, by: batchSize) {
            guard !Task.isCancelled else { return allReplies }
            let batchEnd = min(batchStart + batchSize, uris.count)
            let batch = Array(uris[batchStart ..< batchEnd])

            var batchResults: [RichFeedEntry] = []

            try await withThrowingTaskGroup(of: [RichFeedEntry].self) { group in
                for uri in batch {
                    group.addTask {
                        try await self.fetchRepliesForPost(uri: uri, account: account, appPassword: appPassword, using: client)
                    }
                }

                for try await result in group {
                    batchResults += result
                }
            }

            allReplies += batchResults

            let fetchedSoFar = min(batchEnd, uris.count)
            progressLabel = loc("directreplies.scanning_progress")
                .replacingOccurrences(of: "{n}", with: "\(fetchedSoFar)")
                .replacingOccurrences(of: "{total}", with: "\(uris.count)")
        }

        return allReplies
    }

    private func fetchRepliesForPost(uri: String, account: AppAccount, appPassword: String, using client: LiveBlueskyClient) async throws -> [RichFeedEntry] {
        let response: GetPostThreadResponse
        do {
            response = try await client.fetchPostThread(uri: uri, depth: 3, account: account, appPassword: appPassword)
        } catch {
            AppLogger.moderation.error("Thread fetch failed for \(uri): \(error.localizedDescription, privacy: .public)")
            return []
        }

        var results: [RichFeedEntry] = []
        collectReplies(from: response.thread, myDID: did, into: &results)
        return results
    }

    private func collectReplies(from node: ThreadNode, myDID: String, into results: inout [RichFeedEntry]) {
        guard let replies = node.replies else { return }
        for replyNode in replies {
            guard !Task.isCancelled else { return }
            let authorDID = replyNode.post.author?.did
            if authorDID != nil, authorDID != myDID {
                let entry = RichFeedEntry(threadPost: replyNode.post)
                results.append(entry)
            }
            collectReplies(from: replyNode, myDID: myDID, into: &results)
        }
    }
}
