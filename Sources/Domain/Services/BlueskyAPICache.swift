import CryptoKit
import Foundation

// MARK: - CacheMetricsProviding

/// Protocol exposing cache hit/miss statistics for the performance monitor overlay.
protocol CacheMetricsProviding: AnyObject, Sendable {
    /// Returns an immutable snapshot of current cache metrics.
    func metricsSnapshot() -> CacheMetrics
    /// Reset all counters without clearing the cache entries.
    func resetMetrics()
}

/// Immutable snapshot of cache statistics (cross-actor safe).
struct CacheMetrics: Sendable {
    let hitCount: Int
    let missCount: Int
    var hitRatio: Double {
        let total = hitCount + missCount
        guard total > 0 else { return 0 }
        return Double(hitCount) / Double(total)
    }
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

/// Actor-based on-disk cache for Bluesky API responses.
///
/// **Directory layout (post-BET-102):** one hashed subdirectory per account,
/// containing hashed filename-per-URL entries. This makes per-account deletion
/// a single directory removal and eliminates the hash-mismatch bug where
/// `clear(for:)` used a different hash than `cacheKey`.
///
///     BlueskyAPICache/
///       <SHA256(accountDID)>/
///         <SHA256(normalizedURL)>.cache
///
/// Features:
/// - Per-account directory isolation
/// - Per-entry TTL (time-to-live)
/// - LRU eviction when total size exceeds 10 MB
/// - Actor-isolated metrics (no `@unchecked Sendable`)
/// - Stale-while-revalidate: returns stale data with `isStale` flag
actor BlueskyAPICache: @preconcurrency CacheMetricsProviding {
    static let shared = BlueskyAPICache()

    // MARK: - Constants

    private static let cacheSubdir = "com.ajung.RULYX.BlueskyAPICache"
    private static let maxDiskBytes: Int64 = 10 * 1024 * 1024 // 10 MB
    private static let targetDiskBytes: Int64 = 8 * 1024 * 1024 // 8 MB
    private static let versionFile = ".cache_version_2"

    /// Default TTL values (in seconds).
    enum DefaultTTL {
        static let profile: TimeInterval = 120 // 2 minutes
        static let list: TimeInterval = 300 // 5 minutes
        static let member: TimeInterval = 300 // 5 minutes
        static let relationship: TimeInterval = 120 // 2 minutes
    }

    // MARK: - State

    private let fileManager = FileManager.default
    private var hitCount = 0
    private var missCount = 0

    // MARK: - CacheMetricsProviding

    func metricsSnapshot() -> CacheMetrics {
        CacheMetrics(hitCount: hitCount, missCount: missCount)
    }

    func resetMetrics() {
        hitCount = 0
        missCount = 0
    }

    /// Approximate current disk cache size in bytes.
    var currentDiskSizeBytes: Int64 {
        guard let dir = cacheRootDirectory() else { return 0 }
        return totalDiskSize(in: dir)
    }

    // MARK: - Public API

    /// Attempt to read a cached response.
    /// - Returns: The cached data and a boolean indicating whether it is stale (exceeded TTL).
    ///   Returns `nil` if no entry exists.
    func read(accountDID: String, url: String, maxAge: TimeInterval) -> (data: Data, isStale: Bool)? {
        let (dir, key) = cacheLocation(accountDID: accountDID, url: url)
        guard let dir, let entry = loadFromDisk(in: dir, key: key) else {
            missCount += 1
            return nil
        }

        let age = Date().timeIntervalSince(entry.createdAt)
        let isStale = age > maxAge

        if isStale {
            hitCount += 1
            return (entry.data, true)
        }

        // Fresh hit — touch file access time for LRU tracking
        touchFile(in: dir, key: key)
        hitCount += 1
        return (entry.data, false)
    }

    /// Write a response to the cache.
    func write(accountDID: String, url: String, data: Data) {
        guard let dir = accountDirectory(for: accountDID) else { return }
        let key = urlHash(url)
        let entry = CachedResponse(createdAt: Date(), data: data)
        saveToDisk(in: dir, key: key, entry: entry)
    }

    /// Remove all cached entries for a specific account.
    func clear(for accountDID: String) {
        guard let dir = accountDirectory(for: accountDID) else { return }
        // Per-account deletion: remove the entire hashed directory.
        // Missing directory is a successful no-op.
        try? fileManager.removeItem(at: dir)
    }

    /// Remove ALL cached entries across all accounts.
    func clearAll() {
        guard let dir = cacheRootDirectory() else { return }
        try? fileManager.removeItem(at: dir)
    }

    // MARK: - Internal

    /// Returns total byte size of all cache files on disk.
    func totalDiskSize() -> Int64 {
        guard let dir = cacheRootDirectory() else { return 0 }
        return totalDiskSize(in: dir)
    }

    /// Migrate old flat-directory cache files to the new per-account layout.
    /// Old files (single directory, SHA256(did|url) filenames) are deleted
    /// since they cannot be attributed to a specific account.
    func migrateFromV1() {
        guard let root = cacheRootDirectory() else { return }
        let versionMarker = root.appendingPathComponent(Self.versionFile)
        guard !fileManager.fileExists(atPath: versionMarker.path) else { return }

        // Enumerate root: if there are .cache files directly in the root
        // (instead of subdirectories), they're from the v1 layout. Delete them.
        guard let enumerator = fileManager.enumerator(at: root, includingPropertiesForKeys: nil) else { return }
        var legacyFiles: [URL] = []
        for case let fileURL as URL in enumerator {
            if fileURL.pathExtension == "cache", fileURL.deletingLastPathComponent() == root {
                // Flat cache file — v1, cannot attribute to account
                legacyFiles.append(fileURL)
            }
        }
        for file in legacyFiles {
            try? fileManager.removeItem(at: file)
        }
        // Write version marker
        try? Data("2".utf8).write(to: versionMarker, options: .atomic)
    }

    // MARK: - Private Helpers

    /// Root cache directory: ~/Library/Caches/com.ajung.RULYX.BlueskyAPICache/
    private func cacheRootDirectory() -> URL? {
        guard let cachesDir = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        let dir = cachesDir.appendingPathComponent(Self.cacheSubdir)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Hashed per-account subdirectory: <root>/<SHA256(accountDID)>/
    private func accountDirectory(for accountDID: String) -> URL? {
        guard let root = cacheRootDirectory() else { return nil }
        let hashedDID = SHA256.hash(data: Data(accountDID.utf8))
            .map { String(format: "%02x", $0) }.joined()
        let dir = root.appendingPathComponent(hashedDID)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Returns the per-account directory and the hashed URL cache key.
    private func cacheLocation(accountDID: String, url: String) -> (directory: URL?, key: String) {
        let dir = accountDirectory(for: accountDID)
        return (dir, urlHash(url))
    }

    /// SHA-256 of the normalized URL string (no account identity in the filename).
    private func urlHash(_ url: String) -> String {
        SHA256.hash(data: Data(url.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// Load a `CachedResponse` from disk by its key within an account directory.
    private func loadFromDisk(in dir: URL, key: String) -> CachedResponse? {
        let fileURL = dir.appendingPathComponent(key).appendingPathExtension("cache")
        guard let rawData = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(CachedResponse.self, from: rawData)
    }

    /// Save a `CachedResponse` entry to disk, evicting old entries if needed.
    private func saveToDisk(in dir: URL, key: String, entry: CachedResponse) {
        let fileURL = dir.appendingPathComponent(key).appendingPathExtension("cache")
        guard let encoded = try? JSONEncoder().encode(entry) else { return }
        try? encoded.write(to: fileURL, options: [.atomic, .completeFileProtection])
        evictIfNeeded()
    }

    /// Touch a file's modification date to update LRU order.
    private func touchFile(in dir: URL, key: String) {
        let fileURL = dir.appendingPathComponent(key).appendingPathExtension("cache")
        try? fileManager.setAttributes([.modificationDate: Date()], ofItemAtPath: fileURL.path)
    }

    /// Evict oldest files until total size drops below the target.
    private func evictIfNeeded() {
        guard let dir = cacheRootDirectory() else { return }
        let total = totalDiskSize(in: dir)
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

    /// Recursively compute total file size within a directory.
    private func totalDiskSize(in dir: URL) -> Int64 {
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
}
