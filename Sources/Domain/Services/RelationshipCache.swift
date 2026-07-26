import CryptoKit
import Foundation

/// JSON file-based cache for relationship data (followers/following lists),
/// keyed by account identifier and relationship type. Keys are SHA-256 hashed
/// to prevent filesystem-incompatible characters.
enum RelationshipCache {
    private static var cachesDirectory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("com.ajung.RULYX/relationships")
    }

    private static func fileURL(forKey key: String) -> URL {
        let hashed = SHA256.hash(data: Data(key.utf8))
            .map { String(format: "%02x", $0) }.joined()
        return cachesDirectory.appendingPathComponent("\(hashed).json")
    }

    static func load(forKey key: String) -> [BlueskyActor] {
        let url = fileURL(forKey: key)
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode([BlueskyActor].self, from: data)
        } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError {
            guard !key.contains("/"), key != ".." else { return [] }
            let legacyURL = cachesDirectory.appendingPathComponent("\(key).json")
            guard let data = try? Data(contentsOf: legacyURL),
                  let decoded = try? JSONDecoder().decode([BlueskyActor].self, from: data)
            else { return [] }
            save(decoded, forKey: key)
            try? FileManager.default.removeItem(at: legacyURL)
            return decoded
        } catch {
            AppLogger.persistence.error("RelationshipCache load failed: \(error.localizedDescription, privacy: .private)")
            return []
        }
    }

    static func save(_ actors: [BlueskyActor], forKey key: String) {
        let url = fileURL(forKey: key)
        do {
            try FileManager.default.createDirectory(at: cachesDirectory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(actors)
            try data.write(to: url, options: [.atomic, .completeFileProtection])
        } catch {
            AppLogger.persistence.error("RelationshipCache save failed: \(error.localizedDescription, privacy: .private)")
        }
    }

    static func clear(forKey key: String) {
        let url = fileURL(forKey: key)
        do {
            try FileManager.default.removeItem(at: url)
        } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileNoSuchFileError {
            // Already gone
        } catch {
            AppLogger.persistence.error("RelationshipCache clear failed: \(error.localizedDescription, privacy: .private)")
        }
    }

    static func clearAll() {
        do {
            try FileManager.default.removeItem(at: cachesDirectory)
        } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileNoSuchFileError {
            // Already gone
        } catch {
            AppLogger.persistence.error("RelationshipCache clearAll failed: \(error.localizedDescription, privacy: .private)")
        }
    }
}
