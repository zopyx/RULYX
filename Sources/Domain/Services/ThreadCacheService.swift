import Foundation

// MARK: - ThreadCacheService

/// An in-memory cache for thread data (`ThreadNode`) keyed by post URI.
/// Entries expire after 60 seconds. Uses `NSCache` with a limit of 50 entries.
@MainActor
final class ThreadCacheService {
    static let shared = ThreadCacheService()

    private let cache = NSCache<NSString, CacheEntry>()

    private final class CacheEntry {
        let thread: ThreadNode
        let timestamp: Date
        init(thread: ThreadNode, timestamp: Date) {
            self.thread = thread
            self.timestamp = timestamp
        }
    }

    private init() {
        cache.countLimit = 50
    }

    func get(uri: String) -> ThreadNode? {
        guard let entry = cache.object(forKey: uri as NSString),
              Date().timeIntervalSince(entry.timestamp) < 60 else { return nil }
        return entry.thread
    }

    func set(uri: String, thread: ThreadNode) {
        let entry = CacheEntry(thread: thread, timestamp: Date())
        cache.setObject(entry, forKey: uri as NSString)
    }

    func invalidate(uri: String) {
        cache.removeObject(forKey: uri as NSString)
    }

    func invalidateAll() {
        cache.removeAllObjects()
    }
}
