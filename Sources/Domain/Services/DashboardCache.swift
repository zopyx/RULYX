import Foundation

struct DashboardCacheData: Codable {
    let lists: [BlueskyList]
    let profile: BlueskyProfile?
    let blockingCount: Int?
    let blockedByCount: Int?
}

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
