import Foundation

/// A recently-used custom feed entry, persisted to UserDefaults.
struct RecentFeedEntry: Codable, Hashable {
    /// The AT URI of the feed generator.
    let uri: String
    /// The display name of the feed.
    let name: String
    /// When this feed was last selected.
    let lastUsedAt: Date
}

/// Manages the current feed selection (Following vs. custom feed) and
/// a history of recently-used custom feeds for quick switching.
///
/// Persists state to UserDefaults under per-DID keys so that each account
/// can have an independent feed preference.
@MainActor
final class FeedStore: ObservableObject {
    /// The AT URI of the currently selected custom feed. `nil` means "Following".
    @Published var customFeedURI: String? = nil
    /// The display name of the currently selected feed.
    @Published var customFeedName: String = ""

    /// The DID of the current account, used to scope UserDefaults keys.
    private var did: String = ""

    /// Whether a custom feed (rather than Following) is active.
    var isUsingCustomFeed: Bool {
        guard let uri = customFeedURI, !uri.isEmpty else { return false }
        return true
    }

    /// List of recently-used custom feeds (max 5 entries).
    @Published private(set) var recentFeeds: [RecentFeedEntry] = []

    // MARK: - Init

    /// Initializes the store from UserDefaults, scoped to the given DID (if any).
    init(did: String? = nil) {
        self.did = did ?? ""
        customFeedURI = UserDefaults.standard.string(forKey: key("customFeedURI"))
        customFeedName = UserDefaults.standard.string(forKey: key("customFeedName")) ?? String.localized("timeline.following")
        recentFeeds = loadRecentFeeds()
    }

    // MARK: - Public Methods

    /// Switches the active account DID and reloads preferences from UserDefaults.
    func setAccount(did: String?) {
        self.did = did ?? ""
        customFeedURI = UserDefaults.standard.string(forKey: key("customFeedURI"))
        customFeedName = UserDefaults.standard.string(forKey: key("customFeedName")) ?? String.localized("timeline.following")
        recentFeeds = loadRecentFeeds()
    }

    /// Persists the current feed URI and name to UserDefaults.
    func save() {
        UserDefaults.standard.set(customFeedURI, forKey: key("customFeedURI"))
        UserDefaults.standard.set(customFeedName, forKey: key("customFeedName"))
    }

    /// Sets the active feed. If `uri` is non-nil, also adds it to recent feeds.
    func setFeed(uri: String?, name: String) {
        customFeedURI = uri
        customFeedName = name
        save()
        if let uri, !uri.isEmpty {
            addRecentFeed(uri: uri, name: name)
        }
    }

    /// Resets to the default "Following" view (no custom feed).
    func resetToFollowing() {
        customFeedURI = nil
        customFeedName = String.localized("timeline.following")
        save()
    }

    // MARK: - Recent Feeds

    /// Adds a feed to the recent list (deduplicated, max 5). Existing entries are moved to the top.
    func addRecentFeed(uri: String, name: String) {
        recentFeeds.removeAll { $0.uri == uri }
        let entry = RecentFeedEntry(uri: uri, name: name, lastUsedAt: .now)
        recentFeeds.insert(entry, at: 0)
        if recentFeeds.count > 5 {
            recentFeeds = Array(recentFeeds.prefix(5))
        }
        saveRecentFeeds()
    }

    // MARK: - Private Helpers

    /// Returns a UserDefaults key scoped to the current DID.
    /// When no DID is set, the key is unscoped (backward-compatible).
    private func key(_ suffix: String) -> String {
        did.isEmpty ? suffix : "feed_\(did)_\(suffix)"
    }

    /// Loads recent feeds from UserDefaults for the current DID.
    private func loadRecentFeeds() -> [RecentFeedEntry] {
        guard let data = UserDefaults.standard.data(forKey: key("recentFeeds")),
              let decoded = try? JSONDecoder().decode([RecentFeedEntry].self, from: data)
        else { return [] }
        return decoded
    }

    /// Persists the recent feeds list to UserDefaults for the current DID.
    private func saveRecentFeeds() {
        if let data = try? JSONEncoder().encode(recentFeeds) {
            UserDefaults.standard.set(data, forKey: key("recentFeeds"))
        }
    }
}
