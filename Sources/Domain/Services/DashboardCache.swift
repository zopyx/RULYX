import Foundation

/// Data persisted by the dashboard cache, containing lists, profile, and
/// blocking/blocked-by counts.
struct DashboardCacheData: Codable {
    /// Cached moderation lists.
    let lists: [BlueskyList]
    /// Cached profile data.
    let profile: BlueskyProfile?
    /// Cached blocking count.
    let blockingCount: Int?
    /// Cached blocked-by count.
    let blockedByCount: Int?
}

/// JSON file-based cache for dashboard data, keyed by account identifier.
/// Stores/loads data from the app's caches directory.
enum DashboardCache {
    private static var cachesDirectory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("com.ajung.RULYX")
    }

    private static func fileURL(forKey key: String) -> URL {
        cachesDirectory.appendingPathComponent("dashboard_\(key).json")
    }

    static func load(forKey key: String) -> DashboardCacheData? {
        let url = fileURL(forKey: key)
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(DashboardCacheData.self, from: data)
        } catch {
            AppLogger.persistence.error("DashboardCache load failed for key \(key, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    static func save(_ data: DashboardCacheData, forKey key: String) {
        let url = fileURL(forKey: key)
        do {
            try FileManager.default.createDirectory(at: cachesDirectory, withIntermediateDirectories: true)
            let encoded = try JSONEncoder().encode(data)
            try encoded.write(to: url)
        } catch {
            AppLogger.persistence.error("DashboardCache save failed for key \(key, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    static func clear(forKey key: String) {
        let url = fileURL(forKey: key)
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            AppLogger.persistence.error("DashboardCache clear failed for key \(key, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    static func clearAll() {
        do {
            try FileManager.default.removeItem(at: cachesDirectory)
        } catch {
            AppLogger.persistence.error("DashboardCache clearAll failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
