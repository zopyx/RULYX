import Foundation

enum WorkspaceTab: String, Hashable {
    case moderation
    case account
    case settings
    case info
    case timeline
    case chat
}

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

@MainActor
final class WorkspacePreferencesStore: ObservableObject {
    @Published private(set) var savedSearches: [SavedProfileSearch] = []
    @Published private(set) var recentSearches: [RecentProfileSearch] = []
    @Published var selectedTab: WorkspaceTab = .moderation {
        didSet {
            defaults.set(selectedTab.rawValue, forKey: selectedTabKey)
        }
    }
    @Published var lastProfileQuery = "" {
        didSet {
            defaults.set(lastProfileQuery, forKey: lastProfileQueryKey)
        }
    }

    private let defaults: UserDefaults
    private let savedSearchesKey = "moderation.savedProfileSearches"
    private let recentSearchesKey = "moderation.recentProfileSearches"
    private let selectedTabKey = "moderation.selectedTab"
    private let lastProfileQueryKey = "moderation.lastProfileQuery"
    private let recentSearchLimit = 12

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

    func deleteSavedSearch(_ search: SavedProfileSearch) {
        savedSearches.removeAll { $0.id == search.id }
        persistSavedSearches()
    }

    func noteRecentSearch(_ query: String) {
        let trimmed = normalizedQuery(query)
        guard !trimmed.isEmpty else { return }

        recentSearches.removeAll { $0.query.caseInsensitiveCompare(trimmed) == .orderedSame }
        recentSearches.insert(RecentProfileSearch(query: trimmed), at: 0)
        recentSearches = Array(recentSearches.prefix(recentSearchLimit))

        if let index = savedSearches.firstIndex(where: { $0.query.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            savedSearches[index].lastUsedAt = .now
            savedSearches.sort { $0.lastUsedAt > $1.lastUsedAt }
            persistSavedSearches()
        }

        persistRecentSearches()
    }

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

    private func persistSavedSearches() {
        if let data = try? JSONEncoder().encode(savedSearches) {
            defaults.set(data, forKey: savedSearchesKey)
        }
    }

    private func persistRecentSearches() {
        if let data = try? JSONEncoder().encode(recentSearches) {
            defaults.set(data, forKey: recentSearchesKey)
        }
    }

    private func normalizedQuery(_ query: String) -> String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
