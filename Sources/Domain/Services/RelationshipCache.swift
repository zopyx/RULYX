import Foundation

/// JSON file-based cache for relationship data (followers/following lists),
/// keyed by account identifier and relationship type. Stores data in the
/// app's caches directory.
enum RelationshipCache {
    /// Dedicated subdirectory so `clearAll()` cannot delete sibling cache files.
    private static var cachesDirectory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("com.ajung.RULYX/relationships")
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
            let nsError = error as NSError
            if nsError.domain != NSCocoaErrorDomain || nsError.code != NSFileReadNoSuchFileError {
                AppLogger.persistence.error("RelationshipCache load failed for key \(key, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
            return []
        }
    }

    /// Async variant — runs file IO off the main actor.
    static func loadAsync(forKey key: String) async -> [BlueskyActor] {
        await Task.detached(priority: .userInitiated) { load(forKey: key) }.value
    }

    static func save(_ actors: [BlueskyActor], forKey key: String) {
        let url = fileURL(forKey: key)
        do {
            try FileManager.default.createDirectory(at: cachesDirectory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(actors)
            try data.write(to: url, options: .atomic)
        } catch {
            AppLogger.persistence.error("RelationshipCache save failed for key \(key, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Async variant — runs file IO off the main actor.
    static func saveAsync(_ actors: [BlueskyActor], forKey key: String) async {
        await Task.detached(priority: .utility) { save(actors, forKey: key) }.value
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
        guard FileManager.default.fileExists(atPath: cachesDirectory.path) else { return }
        do {
            try FileManager.default.removeItem(at: cachesDirectory)
        } catch {
            AppLogger.persistence.error("RelationshipCache clearAll failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
