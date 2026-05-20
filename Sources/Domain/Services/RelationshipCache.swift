import Foundation

enum RelationshipCache {
    private static var cachesDirectory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("com.ajung.RULYX")
    }

    private static func fileURL(forKey key: String) -> URL {
        cachesDirectory.appendingPathComponent("\(key).json")
    }

    static func load(forKey key: String) -> [BlueskyActor] {
        let url = fileURL(forKey: key)
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode([BlueskyActor].self, from: data)
        } catch {
            AppLogger.persistence.error("RelationshipCache load failed for key \(key, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    static func save(_ actors: [BlueskyActor], forKey key: String) {
        let url = fileURL(forKey: key)
        do {
            try FileManager.default.createDirectory(at: cachesDirectory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(actors)
            try data.write(to: url)
        } catch {
            AppLogger.persistence.error("RelationshipCache save failed for key \(key, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    static func clear(forKey key: String) {
        let url = fileURL(forKey: key)
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            AppLogger.persistence.error("RelationshipCache clear failed for key \(key, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    static func clearAll() {
        do {
            try FileManager.default.removeItem(at: cachesDirectory)
        } catch {
            AppLogger.persistence.error("RelationshipCache clearAll failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
