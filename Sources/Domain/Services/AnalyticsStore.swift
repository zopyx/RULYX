import Foundation

/// A time-series snapshot of a post's like, repost, and reply counts.
struct EngagementSnapshot: Codable {
    /// When this snapshot was recorded.
    let timestamp: Date
    /// Number of likes at this point in time.
    let likeCount: Int
    /// Number of reposts at this point in time.
    let repostCount: Int
    /// Number of replies at this point in time.
    let replyCount: Int
}

/// Stores and retrieves engagement snapshots for posts over time.
/// Persisted in UserDefaults under the key `"engagementSnapshots"`.
/// Used by post detail views to display engagement trends (like growth/decline arrows).
/// Implements 30-day TTL per snapshot and 200-post LRU eviction to bound growth.
@MainActor
final class AnalyticsStore: ObservableObject {
    /// Snapshot history keyed by post URI. Each post can have up to 50 snapshots (newest last).
    @Published private(set) var snapshots: [String: [EngagementSnapshot]] = [:]

    private static let saveKey = "engagementSnapshots"
    private static let ttl: TimeInterval = 30 * 24 * 60 * 60 // 30 days
    private static let maxPosts = 200

    // MARK: - Init

    /// Loads persisted engagement snapshots from UserDefaults.
    init() {
        load()
    }

    // MARK: - Public Methods

    /// Records a new engagement snapshot for the given post.
    /// - Parameters:
    ///   - postURI: The AT URI of the post being tracked.
    ///   - likeCount: Current like count.
    ///   - repostCount: Current repost count.
    ///   - replyCount: Current reply count.
    /// Keeps at most the last 50 snapshots per post, prunes snapshots older than 30d,
    /// and evicts oldest posts beyond `maxPosts` (LRU by last snapshot time).
    func record(postURI: String, likeCount: Int, repostCount: Int, replyCount: Int) {
        pruneExpired()
        let snapshot = EngagementSnapshot(
            timestamp: Date(),
            likeCount: likeCount,
            repostCount: repostCount,
            replyCount: replyCount
        )
        var postSnapshots = snapshots[postURI] ?? []
        postSnapshots.append(snapshot)
        if postSnapshots.count > 50 {
            postSnapshots = Array(postSnapshots.suffix(50))
        }
        snapshots[postURI] = postSnapshots
        evictIfNeeded()
        save()
    }

    /// Remove snapshots older than TTL and empty post entries.
    private func pruneExpired() {
        let cutoff = Date().addingTimeInterval(-Self.ttl)
        for (uri, history) in snapshots {
            let filtered = history.filter { $0.timestamp > cutoff }
            if filtered.isEmpty {
                snapshots.removeValue(forKey: uri)
            } else if filtered.count != history.count {
                snapshots[uri] = filtered
            }
        }
    }

    /// If we exceed maxPosts, evict posts whose latest snapshot is oldest.
    private func evictIfNeeded() {
        guard snapshots.count > Self.maxPosts else { return }
        let sorted = snapshots.keys.sorted { a, b in
            (snapshots[a]?.last?.timestamp ?? .distantPast) < (snapshots[b]?.last?.timestamp ?? .distantPast)
        }
        for key in sorted.prefix(snapshots.count - Self.maxPosts) {
            snapshots.removeValue(forKey: key)
        }
    }

    /// Returns the snapshot history for a post, newest-first.
    func history(for postURI: String) -> [EngagementSnapshot] {
        snapshots[postURI] ?? []
    }

    /// Returns a trend indicator string (`"+5"`, `"-3"`, or `"→"`) comparing
    /// the first and last snapshots for a post. Returns empty string if fewer
    /// than 2 snapshots exist.
    func likeTrend(for postURI: String) -> String {
        let history = history(for: postURI)
        guard history.count >= 2 else { return "" }
        let first = history.first!.likeCount
        let last = history.last!.likeCount
        if last > first {
            return "+\(last - first)"
        }
        if last < first {
            return "\(last - first)"
        }
        return "→"
    }

    // MARK: - Private Helpers

    /// Persists all snapshots to UserDefaults.
    private func save() {
        if let data = try? JSONEncoder().encode(snapshots) {
            UserDefaults.standard.set(data, forKey: Self.saveKey)
        }
    }

    /// Loads all snapshots from UserDefaults.
    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.saveKey),
              let decoded = try? JSONDecoder().decode([String: [EngagementSnapshot]].self, from: data)
        else { return }
        snapshots = decoded
    }
}
