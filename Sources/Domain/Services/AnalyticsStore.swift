import Foundation

struct EngagementSnapshot: Codable {
    let timestamp: Date
    let likeCount: Int
    let repostCount: Int
    let replyCount: Int
}

@MainActor
final class AnalyticsStore: ObservableObject {
    @Published private(set) var snapshots: [String: [EngagementSnapshot]] = [:]

    private static let saveKey = "engagementSnapshots"

    init() {
        load()
    }

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

    func history(for postURI: String) -> [EngagementSnapshot] {
        snapshots[postURI] ?? []
    }

    func likeTrend(for postURI: String) -> String {
        let history = self.history(for: postURI)
        guard history.count >= 2 else { return "" }
        let first = history.first!.likeCount
        let last = history.last!.likeCount
        if last > first { return "+\(last - first)" }
        if last < first { return "\(last - first)" }
        return "→"
    }

    private func save() {
        if let data = try? JSONEncoder().encode(snapshots) {
            UserDefaults.standard.set(data, forKey: Self.saveKey)
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.saveKey),
              let decoded = try? JSONDecoder().decode([String: [EngagementSnapshot]].self, from: data)
        else { return }
        snapshots = decoded
    }
}
