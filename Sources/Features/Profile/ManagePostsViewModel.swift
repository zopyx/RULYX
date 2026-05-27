import Foundation

/// Manages the full lifecycle of a user's posts — loading, filtering, bulk selection, and deletion.
///
/// Supports paginated loading via `fetchRichFeed`, text/date filtering, single delete,
/// multi-select bulk delete, and a "nuclear" delete-all-pages mode. All mutations are
/// optimistic (post removed from UI before network confirmation).
@MainActor
final class ManagePostsViewModel: ObservableObject {
    // MARK: - Properties

    /// All loaded posts, unsorted. Display via `sortedFilteredPosts`.
    @Published private(set) var posts: [RichFeedEntry] = []
    /// True while the initial load is in progress.
    @Published private(set) var isLoading = false
    /// True while loading the next page of posts.
    @Published private(set) var isLoadingMore = false
    /// False when the server has no more pages to return.
    @Published private(set) var hasMore = true
    /// True while a bulk-delete operation is executing.
    @Published private(set) var isDeleting = false
    /// Tracks (completed, total) during bulk deletion for progress UI.
    @Published private(set) var deleteProgress: (current: Int, total: Int)?
    /// Set on any network error; cleared on next load attempt.
    @Published var errorMessage: String?
    /// Filter text for client-side post body search.
    @Published var searchText = ""
    /// Inclusive start date for filtering posts.
    @Published var fromDate: Date?
    /// Inclusive end date for filtering posts.
    @Published var toDate: Date?
    /// Convenience date-range preset (overrides `fromDate`/`toDate` when set).
    @Published var relativeDateFilter: RelativeDateOption?
    /// True when multi-select mode is active.
    @Published var isSelecting = false
    /// Set of post URIs selected for bulk operations.
    @Published var selectedURIs: Set<String> = []
    /// Entry awaiting single-delete confirmation dialog.
    @Published var pendingDeleteEntry: RichFeedEntry?
    /// True when the bulk-delete confirmation sheet is presented.
    @Published var showBulkConfirm = false
    /// Escalation level for nuclear delete: 0→1→2→3→4→confirmed.
    @Published var nuclearDeleteLevel = 0

    /// Predefined relative date ranges for quick filtering.
    enum RelativeDateOption: String, CaseIterable {
        case today, last7, last30, lastYear, allTime

        var label: String {
            "profile.manage_posts.relative.\(rawValue)"
        }

        var dateFrom: Date? {
            let cal = Calendar.current
            switch self {
            case .today: return cal.startOfDay(for: Date())
            case .last7: return cal.date(byAdding: .day, value: -7, to: cal.startOfDay(for: Date()))
            case .last30: return cal.date(byAdding: .day, value: -30, to: cal.startOfDay(for: Date()))
            case .lastYear: return cal.date(byAdding: .year, value: -1, to: cal.startOfDay(for: Date()))
            case .allTime: return nil
            }
        }
    }

    // MARK: - Computed Properties

    /// Posts filtered by search text and date range, sorted newest-first.
    var sortedFilteredPosts: [RichFeedEntry] {
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

    /// Entries whose URIs are in `selectedURIs`.
    var selectedPosts: [RichFeedEntry] {
        posts.filter { selectedURIs.contains($0.post.uri) }
    }

    /// URIs of every loaded post.
    var allPostURIs: [String] {
        posts.map(\.post.uri)
    }

    // MARK: - Private Properties

    /// Cursor for paginating through the author feed.
    private var cursor: String?
    /// The DID of the profile whose posts are being managed.
    private let did: String

    // MARK: - Init

    init(did: String) {
        self.did = did
    }

    // MARK: - Public Methods

    /// Loads the first page of posts, replacing any existing data.
    /// - Guard: skips if `isLoading` is already true.
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
    }

    /// Loads the next page of posts and appends to `posts`.
    /// - Guard: requires a valid `cursor` and `isLoadingMore == false`.
    func loadMore(account: AppAccount, appPassword: String, using client: LiveBlueskyClient) async {
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
    }

    /// Pull-to-refresh: resets pagination and reloads the first page.
    /// Preserves old cursor on failure so the user can retry.
    func refresh(account: AppAccount, appPassword: String, using client: LiveBlueskyClient) async {
        guard !isLoading else { return }
        let oldCursor = cursor
        let oldHasMore = hasMore
        cursor = nil
        hasMore = true
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
            cursor = oldCursor
            hasMore = oldHasMore
            errorMessage = AppError.userMessage(from: error)
            AppLogger.moderation.error("Failed to refresh posts: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Deletes a single post by URI. Optimistic removal with rollback on failure.
    /// - Parameter entry: The entry to delete (used for rollback).
    func deletePost(_ entry: RichFeedEntry, account: AppAccount, appPassword: String, using client: LiveBlueskyClient) async {
        let uri = entry.post.uri
        posts.removeAll { $0.post.uri == uri }
        selectedURIs.remove(uri)
        pendingDeleteEntry = nil

        do {
            _ = try await client.deleteRecord(recordURI: uri, account: account, appPassword: appPassword)
        } catch {
            // Rollback: re-insert the entry if it was removed
            if !posts.contains(where: { $0.post.uri == uri }) {
                posts.append(entry)
            }
            AppLogger.moderation.error("Failed to delete post: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Deletes all posts whose URIs are in `selectedURIs`. Updates progress via `deleteProgress`.
    func deleteSelectedPosts(account: AppAccount, appPassword: String, using client: LiveBlueskyClient) async {
        let uris = selectedURIs
        guard !uris.isEmpty else { return }
        isDeleting = true
        deleteProgress = (0, uris.count)
        defer {
            isDeleting = false
            deleteProgress = nil
        }

        for (index, uri) in uris.enumerated() {
            guard !Task.isCancelled else { return }
            posts.removeAll { $0.post.uri == uri }
            deleteProgress = (index + 1, uris.count)
            do {
                _ = try await client.deleteRecord(recordURI: uri, account: account, appPassword: appPassword)
            } catch {
                AppLogger.moderation.error("Failed to delete post \(uri): \(error.localizedDescription, privacy: .public)")
            }
        }

        selectedURIs = []
        showBulkConfirm = false
        isSelecting = false
    }

    /// "Nuclear" delete: enumerates ALL pages of the author feed and deletes every post.
    /// Shows a combined progress across the entire collection.
    func deleteAllPosts(account: AppAccount, appPassword: String, using client: LiveBlueskyClient) async {
        isDeleting = true
        deleteProgress = nil
        nuclearDeleteLevel = 0

        var allURIs: [String] = []
        var pageCursor: String?

        while !Task.isCancelled {
            do {
                let response = try await client.fetchRichFeed(did: did, cursor: pageCursor, account: account, appPassword: appPassword)
                allURIs += response.feed.map(\.post.uri)
                guard let next = response.cursor else { break }
                pageCursor = next
            } catch {
                guard !AppError.isCancellation(error) else { return }
                AppLogger.moderation.error("Failed to load page for nuclear delete: \(error.localizedDescription, privacy: .public)")
                break
            }
        }

        guard !allURIs.isEmpty else {
            isDeleting = false
            return
        }

        deleteProgress = (0, allURIs.count)

        for (index, uri) in allURIs.enumerated() {
            guard !Task.isCancelled else { return }
            posts.removeAll { $0.post.uri == uri }
            deleteProgress = (index + 1, allURIs.count)
            do {
                _ = try await client.deleteRecord(recordURI: uri, account: account, appPassword: appPassword)
            } catch {
                AppLogger.moderation.error("Failed to delete post \(uri): \(error.localizedDescription, privacy: .public)")
            }
        }

        selectedURIs = []
        isSelecting = false
        isDeleting = false
        deleteProgress = nil
    }

    // MARK: - Selection Helpers

    /// Selects all posts matching the current filter/search criteria.
    func selectAllFiltered() {
        selectedURIs = Set(sortedFilteredPosts.map(\.post.uri))
    }

    /// Clears the current selection.
    func deselectAll() {
        selectedURIs = []
    }

    /// Exits multi-select mode and clears the selection.
    func exitSelectMode() {
        isSelecting = false
        selectedURIs = []
    }
}
