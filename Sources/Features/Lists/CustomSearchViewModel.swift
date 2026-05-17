import Combine
import Foundation

@MainActor
final class CustomSearchViewModel: ObservableObject {
    enum Tab: String, CaseIterable {
        case top = "Top"
        case newest = "Newest"
        case users = "Users"
    }

    @Published var query = ""
    @Published private(set) var topEntries: [RichFeedEntry] = []
    @Published private(set) var newestEntries: [RichFeedEntry] = []
    @Published private(set) var users: [BlueskyActor] = []
    @Published private(set) var isLoadingTop = false
    @Published private(set) var isLoadingNewest = false
    @Published private(set) var isLoadingMoreTop = false
    @Published private(set) var isLoadingMoreNewest = false
    @Published private(set) var isLoadingUsers = false
    @Published private(set) var hasMoreTop = true
    @Published private(set) var hasMoreNewest = true
    @Published var errorMessage: String?

    private var topCursor: String?
    private var newestCursor: String?
    private let historyKey = "custom_search_history"
    private let maxHistory = 10

    @Published private(set) var searchHistory: [String] = []

    init() {
        loadHistory()
    }

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

    func searchAll(account: AppAccount, appPassword: String, using client: LiveBlueskyClient) async {
        reset()
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.searchTop(account: account, appPassword: appPassword, using: client) }
            group.addTask { await self.searchNewest(account: account, appPassword: appPassword, using: client) }
            group.addTask { await self.searchUsers(account: account, appPassword: appPassword, using: client) }
        }
    }

    func deleteHistoryItem(_ item: String) {
        searchHistory.removeAll { $0 == item }
        saveHistory()
    }

    private func saveQuery(_ q: String) {
        searchHistory.removeAll { $0 == q }
        searchHistory.insert(q, at: 0)
        if searchHistory.count > maxHistory {
            searchHistory = Array(searchHistory.prefix(maxHistory))
        }
        saveHistory()
    }

    private func loadHistory() {
        searchHistory = UserDefaults.standard.stringArray(forKey: historyKey) ?? []
    }

    private func saveHistory() {
        UserDefaults.standard.set(searchHistory, forKey: historyKey)
    }
}
