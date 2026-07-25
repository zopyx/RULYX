import Combine
import Foundation
import Observation

/// Searches Bluesky posts and users with three tabs: Top, Newest, and Users.
///
/// Manages separate loading/pagination state per tab, search history
/// persisted in UserDefaults (up to 10 recent queries), and concurrent
/// search via `searchAll()`.
@MainActor
@Observable
final class CustomSearchViewModel {
    // MARK: - Types

    /// The three search result tabs.
    enum Tab: String, CaseIterable {
        case top = "Top"
        case newest = "Newest"
        case users = "Users"
    }

    // MARK: - Properties

    /// The search query text.
    var query = ""
    /// Top-rated search results.
    private(set) var topEntries: [RichFeedEntry] = []
    /// Newest search results.
    private(set) var newestEntries: [RichFeedEntry] = []
    /// Actor (user) search results.
    private(set) var users: [BlueskyActor] = []
    /// True while loading the Top tab.
    private(set) var isLoadingTop = false
    /// True while loading the Newest tab.
    private(set) var isLoadingNewest = false
    /// True while loading more Top results.
    private(set) var isLoadingMoreTop = false
    /// True while loading more Newest results.
    private(set) var isLoadingMoreNewest = false
    /// True while loading Users tab.
    private(set) var isLoadingUsers = false
    /// False when no more Top pages are available.
    private(set) var hasMoreTop = true
    /// False when no more Newest pages are available.
    private(set) var hasMoreNewest = true
    /// User-facing error message.
    var errorMessage: String?

    // MARK: - Private Properties

    /// Cursor for Top tab pagination.
    private var topCursor: String?
    /// Cursor for Newest tab pagination.
    private var newestCursor: String?
    /// Protected store for search history (queries may contain handles/DIDs).
    private let searchHistoryStore = ProtectedDataStore(
        name: "custom-search-history",
        legacyKey: "custom_search_history",
        defaults: .standard
    )
    /// Maximum number of history entries.
    private let maxHistory = 10

    /// Recent search queries, newest first.
    private(set) var searchHistory: [String] = []

    // MARK: - Init

    init() {
        loadHistory()
    }

    // MARK: - Public Methods

    /// Resets all search results and cursors.
    func reset() {
        topEntries = []
        newestEntries = []
        users = []
        topCursor = nil
        newestCursor = nil
        hasMoreTop = true
        hasMoreNewest = true
        errorMessage = nil
    }

    /// Searches posts sorted by "top" (engagement).
    func searchTop(account: AppAccount, appPassword: String, using client: LiveBlueskyClient) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard !isLoadingTop else { return }
        isLoadingTop = true
        errorMessage = nil
        defer { isLoadingTop = false }
        do {
            let response = try await client.searchPosts(q: trimmed, sort: "top", cursor: nil, limit: 50, account: account, appPassword: appPassword)
            topEntries = response.posts.map { RichFeedEntry(post: $0, reply: nil) }
            topCursor = response.cursor
            hasMoreTop = topCursor != nil
            saveQuery(trimmed)
        } catch {
            guard !AppError.isCancellation(error) else { return }
            topCursor = nil
            hasMoreTop = false
            errorMessage = AppError.userMessage(from: error)
        }
    }

    /// Searches posts sorted by "latest" (newest first).
    func searchNewest(account: AppAccount, appPassword: String, using client: LiveBlueskyClient) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard !isLoadingNewest else { return }
        isLoadingNewest = true
        errorMessage = nil
        defer { isLoadingNewest = false }
        do {
            let response = try await client.searchPosts(q: trimmed, sort: "latest", cursor: nil, limit: 50, account: account, appPassword: appPassword)
            newestEntries = response.posts.map { RichFeedEntry(post: $0, reply: nil) }
            newestCursor = response.cursor
            hasMoreNewest = newestCursor != nil
        } catch {
            guard !AppError.isCancellation(error) else { return }
            newestCursor = nil
            hasMoreNewest = false
            errorMessage = AppError.userMessage(from: error)
        }
    }

    /// Loads the next page of Top results.
    func loadMoreTop(account: AppAccount, appPassword: String, using client: LiveBlueskyClient) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let topCursor else { return }
        guard !isLoadingMoreTop else { return }
        isLoadingMoreTop = true
        defer { isLoadingMoreTop = false }
        do {
            let response = try await client.searchPosts(q: trimmed, sort: "top", cursor: topCursor, limit: 50, account: account, appPassword: appPassword)
            topEntries += response.posts.map { RichFeedEntry(post: $0, reply: nil) }
            self.topCursor = response.cursor
            hasMoreTop = response.cursor != nil
        } catch {
            guard !AppError.isCancellation(error) else { return }
            errorMessage = AppError.userMessage(from: error)
        }
    }

    /// Loads the next page of Newest results.
    func loadMoreNewest(account: AppAccount, appPassword: String, using client: LiveBlueskyClient) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let newestCursor else { return }
        guard !isLoadingMoreNewest else { return }
        isLoadingMoreNewest = true
        defer { isLoadingMoreNewest = false }
        do {
            let response = try await client.searchPosts(q: trimmed, sort: "latest", cursor: newestCursor, limit: 50, account: account, appPassword: appPassword)
            newestEntries += response.posts.map { RichFeedEntry(post: $0, reply: nil) }
            self.newestCursor = response.cursor
            hasMoreNewest = response.cursor != nil
        } catch {
            guard !AppError.isCancellation(error) else { return }
            errorMessage = AppError.userMessage(from: error)
        }
    }

    /// Searches for actors (users) matching the query.
    func searchUsers(account: AppAccount, appPassword: String, using client: LiveBlueskyClient) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard !isLoadingUsers else { return }
        isLoadingUsers = true
        errorMessage = nil
        defer { isLoadingUsers = false }
        do {
            users = try await client.searchActorsFull(query: trimmed, account: account, appPassword: appPassword)
        } catch {
            guard !AppError.isCancellation(error) else { return }
            users = []
            errorMessage = AppError.userMessage(from: error)
        }
    }

    /// Runs all three searches (Top, Newest, Users) concurrently in a single task group.
    func searchAll(account: AppAccount, appPassword: String, using client: LiveBlueskyClient) async {
        reset()
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.searchTop(account: account, appPassword: appPassword, using: client) }
            group.addTask { await self.searchNewest(account: account, appPassword: appPassword, using: client) }
            group.addTask { await self.searchUsers(account: account, appPassword: appPassword, using: client) }
        }
    }

    /// Removes a single item from search history.
    func deleteHistoryItem(_ item: String) {
        searchHistory.removeAll { $0 == item }
        saveHistory()
    }

    /// Clears all search history.
    func clearHistory() {
        searchHistory.removeAll()
        saveHistory()
    }

    // MARK: - Private Helpers

    /// Saves a query to the top of the history list, capped at `maxHistory`.
    private func saveQuery(_ q: String) {
        searchHistory.removeAll { $0 == q }
        searchHistory.insert(q, at: 0)
        if searchHistory.count > maxHistory {
            searchHistory = Array(searchHistory.prefix(maxHistory))
        }
        saveHistory()
    }

    /// Loads search history from protected storage.
    /// Falls back to legacy UserDefaults key on first migration.
    private func loadHistory() {
        if let data = searchHistoryStore.data(),
           let history = try? JSONDecoder().decode([String].self, from: data)
        {
            searchHistory = history
        } else {
            searchHistory = UserDefaults.standard.stringArray(forKey: "custom_search_history") ?? []
        }
    }

    /// Persists search history to protected storage.
    private func saveHistory() {
        if let data = try? JSONEncoder().encode(searchHistory) {
            searchHistoryStore.set(data)
        }
    }
}
