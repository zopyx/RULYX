import Foundation

/// Searches for posts mentioning a specific user by searching for their handle with the `mentions` parameter.
///
/// Uses `searchPosts(q: "@handle", mentions: did)` to find posts that mention the given user,
/// supporting pagination via cursor and pull-to-refresh with cursor preservation.
@MainActor
final class MentionsSearchViewModel: ObservableObject {
    // MARK: - Properties

    /// Posts that mention the user, sorted newest-first.
    @Published private(set) var entries: [RichFeedEntry] = []
    /// True while the initial load is in progress.
    @Published private(set) var isLoading = false
    /// True while loading the next page.
    @Published private(set) var isLoadingMore = false
    /// False when no more search pages are available.
    @Published private(set) var hasMore = true
    /// User-facing error message.
    @Published var errorMessage: String?

    // MARK: - Private Properties

    /// Cursor for paginating through mention search results.
    private var cursor: String?
    /// The DID of the user whose mentions are being searched.
    private let did: String
    /// The handle of the user (used in the search query as `@handle`).
    private let handle: String

    // MARK: - Init

    init(did: String, handle: String) {
        self.did = did
        self.handle = handle
    }

    // MARK: - Public Methods

    /// Resets all state to initial values.
    func reset() {
        entries = []
        cursor = nil
        hasMore = true
        errorMessage = nil
    }

    /// Performs the initial mention search.
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

    /// Loads the next page of mention results.
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

    /// Pull-to-refresh: reloads the first page, preserving the cursor on failure.
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
