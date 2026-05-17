import Foundation

struct RecentFeedEntry: Codable, Hashable {
    let uri: String
    let name: String
    let lastUsedAt: Date
}

@MainActor
final class FeedStore: ObservableObject {
    @Published var customFeedURI: String? = nil
    @Published var customFeedName: String = ""

    private var did: String = ""

    var isUsingCustomFeed: Bool {
        guard let uri = customFeedURI, !uri.isEmpty else { return false }
        return true
    }

    @Published private(set) var recentFeeds: [RecentFeedEntry] = []

    init(did: String? = nil) {
        self.did = did ?? ""
        customFeedURI = UserDefaults.standard.string(forKey: key("customFeedURI"))
        customFeedName = UserDefaults.standard.string(forKey: key("customFeedName")) ?? loc("timeline.following")
        recentFeeds = loadRecentFeeds()
    }

    func setAccount(did: String?) {
        self.did = did ?? ""
        customFeedURI = UserDefaults.standard.string(forKey: key("customFeedURI"))
        customFeedName = UserDefaults.standard.string(forKey: key("customFeedName")) ?? loc("timeline.following")
        recentFeeds = loadRecentFeeds()
    }

    private func key(_ suffix: String) -> String {
        did.isEmpty ? suffix : "feed_\(did)_\(suffix)"
    }

    func save() {
        UserDefaults.standard.set(customFeedURI, forKey: key("customFeedURI"))
        UserDefaults.standard.set(customFeedName, forKey: key("customFeedName"))
    }

    func setFeed(uri: String?, name: String) {
        customFeedURI = uri
        customFeedName = name
        save()
        if let uri, !uri.isEmpty {
            addRecentFeed(uri: uri, name: name)
        }
    }

    func resetToFollowing() {
        customFeedURI = nil
        customFeedName = loc("timeline.following")
        save()
    }

    func addRecentFeed(uri: String, name: String) {
        recentFeeds.removeAll { $0.uri == uri }
        let entry = RecentFeedEntry(uri: uri, name: name, lastUsedAt: .now)
        recentFeeds.insert(entry, at: 0)
        if recentFeeds.count > 5 {
            recentFeeds = Array(recentFeeds.prefix(5))
        }
        saveRecentFeeds()
    }

    private func loadRecentFeeds() -> [RecentFeedEntry] {
        guard let data = UserDefaults.standard.data(forKey: key("recentFeeds")),
              let decoded = try? JSONDecoder().decode([RecentFeedEntry].self, from: data)
        else { return [] }
        return decoded
    }

    private func saveRecentFeeds() {
        if let data = try? JSONEncoder().encode(recentFeeds) {
            UserDefaults.standard.set(data, forKey: key("recentFeeds"))
        }
    }
}
