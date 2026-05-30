import Foundation

/// The available tabs in the main workspace. Persisted across app launches.
enum WorkspaceTab: String, Hashable {
    case moderation
    case account
    case settings
    case info
    case timeline
    case notifications
    case chat
}

/// A saved profile search query with metadata for sorting by recency.
struct SavedProfileSearch: Identifiable, Codable, Hashable {
    let id: UUID
    var query: String
    let createdAt: Date
    var lastUsedAt: Date

    init(
        id: UUID = UUID(),
        query: String,
        createdAt: Date = .now,
        lastUsedAt: Date = .now
    ) {
        self.id = id
        self.query = query
        self.createdAt = createdAt
        self.lastUsedAt = lastUsedAt
    }
}

/// A recently-used profile search query. Automatically removed when the same query is saved.
struct RecentProfileSearch: Identifiable, Codable, Hashable {
    let id: UUID
    let query: String
    let usedAt: Date

    init(id: UUID = UUID(), query: String, usedAt: Date = .now) {
        self.id = id
        self.query = query
        self.usedAt = usedAt
    }
}

/// Persists workspace-level preferences: saved/recent profile searches,
/// selected tab, and last profile query. All data is stored in UserDefaults.
@MainActor
final class WorkspacePreferencesStore: ObservableObject {
    /// Saved profile searches sorted by last-used date (most recent first).
    @Published private(set) var savedSearches: [SavedProfileSearch] = []
    /// Recent profile searches capped at 12 entries.
    @Published private(set) var recentSearches: [RecentProfileSearch] = []
    /// The currently selected workspace tab. Changes are immediately persisted.
    @Published var selectedTab: WorkspaceTab = .moderation {
        didSet {
            defaults.set(selectedTab.rawValue, forKey: selectedTabKey)
        }
    }

    /// The last profile query string. Changes are immediately persisted.
    @Published var lastProfileQuery = "" {
        didSet {
            defaults.set(lastProfileQuery, forKey: lastProfileQueryKey)
        }
    }

    private let defaults: UserDefaults

    // MARK: - UserDefaults Keys

    private let savedSearchesKey = "moderation.savedProfileSearches"
    private let recentSearchesKey = "moderation.recentProfileSearches"
    private let selectedTabKey = "moderation.selectedTab"
    private let lastProfileQueryKey = "moderation.lastProfileQuery"
    private let recentSearchLimit = 12

    // MARK: - Init

    init(defaults: UserDefaults = .standard, preview: Bool = false) {
        self.defaults = defaults

        if preview {
            savedSearches = [
                SavedProfileSearch(query: "safety"),
                SavedProfileSearch(query: "did:plc:moderator"),
            ]
            recentSearches = [
                RecentProfileSearch(query: "alice.bsky.social"),
                RecentProfileSearch(query: "reply filters"),
            ]
            selectedTab = .moderation
            lastProfileQuery = "safety"
            return
        }

        load()
    }

    // MARK: - Public Methods

    /// Saves a profile search query. If it already exists, updates its `lastUsedAt`.
    /// Sorted most-recently-used first.
    func saveProfileSearch(_ query: String) {
        let trimmed = normalizedQuery(query)
        guard !trimmed.isEmpty else { return }

        if let index = savedSearches.firstIndex(where: { $0.query.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            savedSearches[index].lastUsedAt = .now
        } else {
            savedSearches.insert(SavedProfileSearch(query: trimmed), at: 0)
        }

        savedSearches.sort { $0.lastUsedAt > $1.lastUsedAt }
        persistSavedSearches()
    }

    /// Removes a saved search by identity.
    func deleteSavedSearch(_ search: SavedProfileSearch) {
        savedSearches.removeAll { $0.id == search.id }
        persistSavedSearches()
    }

    /// Records a recent search query. Deduplicates and caps at 12 entries.
    /// If the query matches a saved search, updates the saved search's `lastUsedAt`.
    func noteRecentSearch(_ query: String) {
        let trimmed = normalizedQuery(query)
        guard !trimmed.isEmpty else { return }

        recentSearches.removeAll { $0.query.caseInsensitiveCompare(trimmed) == .orderedSame }
        recentSearches.insert(RecentProfileSearch(query: trimmed), at: 0)
        recentSearches = Array(recentSearches.prefix(recentSearchLimit))

        // Touch the saved search's lastUsedAt if this query matches one.
        if let index = savedSearches.firstIndex(where: { $0.query.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            savedSearches[index].lastUsedAt = .now
            savedSearches.sort { $0.lastUsedAt > $1.lastUsedAt }
            persistSavedSearches()
        }

        persistRecentSearches()
    }

    // MARK: - Private Helpers

    /// Loads all preferences from UserDefaults.
    private func load() {
        if let data = defaults.data(forKey: savedSearchesKey),
           let decoded = try? JSONDecoder().decode([SavedProfileSearch].self, from: data)
        {
            savedSearches = decoded.sorted { $0.lastUsedAt > $1.lastUsedAt }
        }

        if let data = defaults.data(forKey: recentSearchesKey),
           let decoded = try? JSONDecoder().decode([RecentProfileSearch].self, from: data)
        {
            recentSearches = decoded.sorted { $0.usedAt > $1.usedAt }
        }

        if let storedSelectedTab = defaults.string(forKey: selectedTabKey),
           let selectedTab = WorkspaceTab(rawValue: storedSelectedTab)
        {
            self.selectedTab = selectedTab
        }

        lastProfileQuery = defaults.string(forKey: lastProfileQueryKey) ?? ""
    }

    /// Persists saved searches to UserDefaults.
    private func persistSavedSearches() {
        if let data = try? JSONEncoder().encode(savedSearches) {
            defaults.set(data, forKey: savedSearchesKey)
        }
    }

    /// Persists recent searches to UserDefaults.
    private func persistRecentSearches() {
        if let data = try? JSONEncoder().encode(recentSearches) {
            defaults.set(data, forKey: recentSearchesKey)
        }
    }

    /// Trims whitespace and newlines from a query string.
    private func normalizedQuery(_ query: String) -> String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
