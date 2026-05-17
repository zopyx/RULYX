import Foundation

struct DashboardCacheData: Codable {
    let lists: [BlueskyList]
    let profile: BlueskyProfile?
    let blockingCount: Int
    let blockedByCount: Int
}

enum DashboardCache {
    private static var cachesDirectory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("com.ajung.BlueskyModeration")
    }

    private static func fileURL(forKey key: String) -> URL {
        cachesDirectory.appendingPathComponent("dashboard_\(key).json")
    }

    static func load(forKey key: String) -> DashboardCacheData? {
        let url = fileURL(forKey: key)
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(DashboardCacheData.self, from: data)
        else {
            return nil
        }
        return decoded
    }

    static func save(_ data: DashboardCacheData, forKey key: String) {
        let url = fileURL(forKey: key)
        try? FileManager.default.createDirectory(at: cachesDirectory, withIntermediateDirectories: true)
        guard let encoded = try? JSONEncoder().encode(data) else { return }
        try? encoded.write(to: url)
    }

    static func clear(forKey key: String) {
        let url = fileURL(forKey: key)
        try? FileManager.default.removeItem(at: url)
    }

    static func clearAll() {
        try? FileManager.default.removeItem(at: cachesDirectory)
    }
}
