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
@MainActor
final class AnalyticsStore: ObservableObject {
    /// Snapshot history keyed by post URI. Each post can have up to 50 snapshots.
    @Published private(set) var snapshots: [String: [EngagementSnapshot]] = [:]

    private static let saveKey = "engagementSnapshots"

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
    /// Keeps at most the last 50 snapshots per post.
    func record(postURI: String, likeCount: Int, repostCount: Int, replyCount: Int) {
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
        save()
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
        if last > first { return "+\(last - first)" }
        if last < first { return "\(last - first)" }
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
