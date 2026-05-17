import Foundation

@MainActor
final class MentionsSearchViewModel: ObservableObject {
    @Published private(set) var entries: [RichFeedEntry] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var hasMore = true
    @Published var errorMessage: String?

    private var cursor: String?
    private let did: String
    private let handle: String

    init(did: String, handle: String) {
        self.did = did
        self.handle = handle
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
            let response = try await client.searchPosts(
                q: "@\(handle)",
                mentions: did,
                sort: "latest",
                cursor: nil,
                limit: 50,
                account: account,
                appPassword: appPassword
            )
            entries = response.posts.map { RichFeedEntry(post: $0, reply: nil) }
            cursor = response.cursor
            hasMore = cursor != nil
        } catch {
            guard !AppError.isCancellation(error) else { return }
            cursor = nil
            hasMore = false
            errorMessage = AppError.userMessage(from: error)
            AppLogger.moderation.error("Failed to load mentions: \(error.localizedDescription, privacy: .public)")
        }
    }

    func loadMore(account: AppAccount, appPassword: String, using client: LiveBlueskyClient) async {
        guard !isLoadingMore, let cursor else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            guard !Task.isCancelled else { return }
            let response = try await client.searchPosts(
                q: "@\(handle)",
                mentions: did,
                sort: "latest",
                cursor: cursor,
                limit: 50,
                account: account,
                appPassword: appPassword
            )
            entries += response.posts.map { RichFeedEntry(post: $0, reply: nil) }
            self.cursor = response.cursor
            hasMore = response.cursor != nil
        } catch {
            guard !AppError.isCancellation(error) else { return }
            errorMessage = AppError.userMessage(from: error)
            AppLogger.moderation.error("Failed to load more mentions: \(error.localizedDescription, privacy: .public)")
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
            let response = try await client.searchPosts(
                q: "@\(handle)",
                mentions: did,
                sort: "latest",
                cursor: nil,
                limit: 50,
                account: account,
                appPassword: appPassword
            )
            entries = response.posts.map { RichFeedEntry(post: $0, reply: nil) }
            cursor = response.cursor
            hasMore = cursor != nil
        } catch {
            guard !AppError.isCancellation(error) else { return }
            cursor = oldCursor
            errorMessage = AppError.userMessage(from: error)
            AppLogger.moderation.error("Failed to refresh mentions: \(error.localizedDescription, privacy: .public)")
        }
    }
}
