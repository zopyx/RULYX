import CryptoKit
import Foundation

// MARK: - CacheMetricsProviding

/// Protocol exposing cache hit/miss statistics for the performance monitor overlay.
protocol CacheMetricsProviding: AnyObject {
    /// Total number of cache hits since the last reset.
    var hitCount: Int { get }
    /// Total number of cache misses since the last reset.
    var missCount: Int { get }
    /// Combined hit ratio (0.0 – 1.0).
    var hitRatio: Double { get }
    /// Approximate current disk cache size in bytes.
    var currentDiskSizeBytes: Int64 { get }
    /// Reset all counters without clearing the cache entries.
    func resetMetrics()
}

// MARK: - CacheMetricsStore

/// Thread-safe metrics storage for cache statistics.
/// Uses a simple class with atomic-like access via the actor.
final class CacheMetricsStore: @unchecked Sendable {
    var hitCount = 0
    var missCount = 0
}

// MARK: - CachedResponse

/// Metadata and raw data for a single cached API response.
private struct CachedResponse: Codable {
    /// When this entry was written (used for TTL checks).
    let createdAt: Date
    /// The raw JSON response data.
    let data: Data
}

// MARK: - BlueskyAPICache

/// Actor-based on-disk cache for Bluesky API responses, keyed by account DID + normalized URL.
///
/// Features:
/// - JSON-file store in the caches directory
/// - Per-account isolation via DID prefix in the key
/// - Per-entry TTL (time-to-live)
/// - LRU eviction when total size exceeds 10 MB
/// - Cache metrics exposed via `CacheMetricsProviding`
///
/// Lookup pattern: stale-while-revalidate — returns stale data immediately (with isStale flag)
/// so the caller can display it while scheduling a background refresh.
actor BlueskyAPICache: CacheMetricsProviding {
    static let shared = BlueskyAPICache()

    // MARK: - Constants

    private static let cacheSubdir = "com.ajung.RULYX.BlueskyAPICache"
    private static let maxDiskBytes: Int64 = 10 * 1024 * 1024 // 10 MB
    private static let targetDiskBytes: Int64 = 8 * 1024 * 1024 // 8 MB

    /// Default TTL values (in seconds).
    enum DefaultTTL {
        static let profile: TimeInterval = 120 // 2 minutes
        static let list: TimeInterval = 300 // 5 minutes
        static let member: TimeInterval = 300 // 5 minutes
        static let relationship: TimeInterval = 120 // 2 minutes
    }

    // MARK: - State

    private let fileManager = FileManager.default
    private let metrics = CacheMetricsStore()

    // MARK: - CacheMetricsProviding

    nonisolated var hitCount: Int {
        metrics.hitCount
    }

    nonisolated var missCount: Int {
        metrics.missCount
    }

    nonisolated var hitRatio: Double {
        let total = metrics.hitCount + metrics.missCount
        guard total > 0 else { return 0 }
        return Double(metrics.hitCount) / Double(total)
    }

    nonisolated var currentDiskSizeBytes: Int64 {
        guard let dir = Self.cacheDirectoryStatic() else { return 0 }
        guard let enumerator = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
                  let size = attrs[.size] as? Int64
            else { continue }
            total += size
        }
        return total
    }

    nonisolated func resetMetrics() {
        metrics.hitCount = 0
        metrics.missCount = 0
    }

    // MARK: - Public API

    /// Attempt to read a cached response.
    /// - Returns: The cached data and a boolean indicating whether it is stale (exceeded TTL).
    ///   Returns `nil` if no entry exists.
    func read(accountDID: String, url: String, maxAge: TimeInterval) -> (data: Data, isStale: Bool)? {
        let key = cacheKey(accountDID: accountDID, url: url)
        guard let entry = loadFromDisk(key: key) else {
            metrics.missCount += 1
            return nil
        }

        let age = Date().timeIntervalSince(entry.createdAt)
        let isStale = age > maxAge

        if isStale {
            metrics.hitCount += 1
            return (entry.data, true)
        }

        // Fresh hit — touch file access time for LRU tracking
        touchFile(key: key)
        metrics.hitCount += 1
        return (entry.data, false)
    }

    /// Write a response to the cache.
    func write(accountDID: String, url: String, data: Data) {
        let key = cacheKey(accountDID: accountDID, url: url)
        let entry = CachedResponse(createdAt: Date(), data: data)
        saveToDisk(entry: entry, key: key)
    }

    /// Remove all cached entries for a specific account.
    func clear(for accountDID: String) {
        guard let dir = cacheDirectory() else { return }
        guard let enumerator = fileManager.enumerator(at: dir, includingPropertiesForKeys: nil) else { return }
        let prefix = SHA256.hash(data: Data(accountDID.utf8)).map { String(format: "%02x", $0) }.joined()
        for case let fileURL as URL in enumerator {
            if fileURL.lastPathComponent.hasPrefix(prefix) {
                try? fileManager.removeItem(at: fileURL)
            }
        }
    }

    /// Remove ALL cached entries.
    func clearAll() {
        guard let dir = cacheDirectory() else { return }
        try? fileManager.removeItem(at: dir)
    }

    // MARK: - Internal (for metrics)

    /// Returns total byte size of all cache files on disk.
    func totalDiskSize() -> Int64 {
        guard let dir = cacheDirectory() else { return 0 }
        guard let enumerator = fileManager.enumerator(at: dir, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let attrs = try? fileManager.attributesOfItem(atPath: fileURL.path),
                  let size = attrs[.size] as? Int64
            else { continue }
            total += size
        }
        return total
    }

    // MARK: - Private Helpers

    /// Returns the cache directory URL, creating it if needed.
    private func cacheDirectory() -> URL? {
        Self.cacheDirectoryStatic()
    }

    /// Static version for nonisolated access.
    private static func cacheDirectoryStatic() -> URL? {
        guard let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        let dir = cachesDir.appendingPathComponent(cacheSubdir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Stable unique key for a cache entry: SHA-256 of `accountDID + "|" + url`.
    private func cacheKey(accountDID: String, url: String) -> String {
        let input = "\(accountDID)|\(url)"
        let data = Data(input.utf8)
        let hash = SHA256.hash(data: data)
        return hash.map { String(format: "%02x", $0) }.joined()
    }

    /// Load a `CachedResponse` from disk by its key.
    private func loadFromDisk(key: String) -> CachedResponse? {
        guard let dir = cacheDirectory() else { return nil }
        let fileURL = dir.appendingPathComponent(key)
        guard let rawData = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(CachedResponse.self, from: rawData)
    }

    /// Save a `CachedResponse` entry to disk, evicting old entries if needed.
    private func saveToDisk(entry: CachedResponse, key: String) {
        guard let dir = cacheDirectory() else { return }
        let fileURL = dir.appendingPathComponent(key)
        guard let encoded = try? JSONEncoder().encode(entry) else { return }
        try? encoded.write(to: fileURL)
        evictIfNeeded()
    }

    /// Touch a file's modification date to update LRU order.
    private func touchFile(key: String) {
        guard let dir = cacheDirectory() else { return }
        let fileURL = dir.appendingPathComponent(key)
        try? fileManager.setAttributes([.modificationDate: Date()], ofItemAtPath: fileURL.path)
    }

    /// Evict oldest files until total size drops below the target.
    private func evictIfNeeded() {
        guard let dir = cacheDirectory() else { return }
        let total = totalDiskSize()
        guard total > Self.maxDiskBytes else { return }

        guard let enumerator = fileManager.enumerator(at: dir, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey]) else { return }
        var files: [(url: URL, date: Date, size: Int64)] = []
        for case let fileURL as URL in enumerator {
            guard let attrs = try? fileManager.attributesOfItem(atPath: fileURL.path),
                  let modDate = attrs[.modificationDate] as? Date,
                  let size = attrs[.size] as? Int64
            else { continue }
            files.append((fileURL, modDate, size))
        }

        files.sort { $0.date < $1.date }
        var currentSize = total
        for file in files {
            guard currentSize > Self.targetDiskBytes else { break }
            try? fileManager.removeItem(at: file.url)
            currentSize -= file.size
        }
        AppLogger.performance.debug("BlueskyAPICache LRU eviction: removed \(total - currentSize) bytes, now at \(currentSize) bytes")
    }
}
