import CryptoKit
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
/// Keys are SHA-256 hashed to prevent filesystem-incompatible characters
/// (DIDs contain colons, handles can contain dots and slashes).
enum DashboardCache {
    private static var cachesDirectory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("com.ajung.RULYX/dashboard")
    }

    private static func fileURL(forKey key: String) -> URL {
        let hashed = SHA256.hash(data: Data(key.utf8))
            .map { String(format: "%02x", $0) }.joined()
        return cachesDirectory.appendingPathComponent("\(hashed).json")
    }

    static func load(forKey key: String) -> DashboardCacheData? {
        let url = fileURL(forKey: key)
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(DashboardCacheData.self, from: data)
        } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError {
            // Normal cache miss — no log needed
            return nil
        } catch {
            AppLogger.persistence.error("DashboardCache load failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    static func save(_ data: DashboardCacheData, forKey key: String) {
        let url = fileURL(forKey: key)
        do {
            try FileManager.default.createDirectory(at: cachesDirectory, withIntermediateDirectories: true)
            let encoded = try JSONEncoder().encode(data)
            try encoded.write(to: url, options: [.atomic, .completeFileProtection])
        } catch {
            AppLogger.persistence.error("DashboardCache save failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    static func clear(forKey key: String) {
        let url = fileURL(forKey: key)
        do {
            try FileManager.default.removeItem(at: url)
        } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileNoSuchFileError {
            // Already gone — no-op
        } catch {
            AppLogger.persistence.error("DashboardCache clear failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    static func clearAll() {
        do {
            try FileManager.default.removeItem(at: cachesDirectory)
        } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileNoSuchFileError {
            // Already gone
        } catch {
            AppLogger.persistence.error("DashboardCache clearAll failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
