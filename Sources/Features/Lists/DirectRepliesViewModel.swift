import Foundation

@MainActor
final class DirectRepliesViewModel: ObservableObject {
    @Published private(set) var entries: [RichFeedEntry] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var hasMore = true
    @Published var errorMessage: String?

    private var cursor: String?
    private let did: String

    init(did: String) {
        self.did = did
    }

    func reset() {
        entries = []
        cursor = nil
        hasMore = true
        errorMessage = nil
    }

    func load(account: AppAccount, appPassword: String, using client: LiveBlueskyClient) async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            guard !Task.isCancelled else { return }
            entries = []
            cursor = nil
            hasMore = true
            try await accumulatePages(account: account, appPassword: appPassword, using: client)
        } catch {
            guard !AppError.isCancellation(error) else { return }
            cursor = nil
            hasMore = false
            errorMessage = AppError.userMessage(from: error)
            AppLogger.moderation.error("Failed to load direct replies: \(error.localizedDescription, privacy: .public)")
        }
    }

    func loadMore(account: AppAccount, appPassword: String, using client: LiveBlueskyClient) async {
        guard !isLoadingMore, let cursor else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            guard !Task.isCancelled else { return }
            try await accumulatePages(account: account, appPassword: appPassword, using: client)
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
        let oldCursor = cursor
        cursor = nil
        hasMore = true
        defer { isLoading = false }
        do {
            guard !Task.isCancelled else { return }
            entries = []
            try await accumulatePages(account: account, appPassword: appPassword, using: client)
        } catch {
            guard !AppError.isCancellation(error) else { return }
            cursor = oldCursor
            errorMessage = AppError.userMessage(from: error)
            AppLogger.moderation.error("Failed to refresh direct replies: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func accumulatePages(account: AppAccount, appPassword: String, using client: LiveBlueskyClient) async throws {
        var accumulatedCursor = cursor
        var pagesChecked = 0
        let maxPages = 10

        while pagesChecked < maxPages, !Task.isCancelled {
            let response = try await client.fetchRichFeed(
                did: did,
                cursor: accumulatedCursor,
                account: account,
                appPassword: appPassword
            )

            let newEntries = response.feed.filter { entry in
                guard let reply = entry.reply else { return false }
                let isReplyToMe = reply.root?.author?.did == did || reply.parent?.author?.did == did
                let isNotByMe = entry.post.author?.did != did
                return isReplyToMe && isNotByMe
            }

            entries += newEntries
            accumulatedCursor = response.cursor
            pagesChecked += 1

            if accumulatedCursor == nil {
                cursor = nil
                hasMore = false
                return
            }

            if !entries.isEmpty {
                cursor = accumulatedCursor
                hasMore = true
                return
            }
        }

        cursor = accumulatedCursor
        hasMore = cursor != nil
    }
}
