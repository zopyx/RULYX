import CryptoKit
import Foundation

// MARK: - CacheMetricsProviding

/// Protocol exposing cache hit/miss statistics for the performance monitor overlay.
///
/// Hits are split into **fresh** and **stale** so the exposed ratio reflects reality:
/// a stale read still needs a revalidation, so folding it into the hit count (as an
/// earlier version did) overstated how much traffic the cache actually absorbed.
protocol CacheMetricsProviding: AnyObject {
    /// Fresh hits — entry present and within its TTL. No network work needed.
    var hitCount: Int { get }
    /// Stale hits — entry present but past its TTL. Data was served, revalidation pending.
    var staleCount: Int { get }
    /// Misses — no entry at all.
    var missCount: Int { get }
    /// Lookups served from a fresh cache entry, over all lookups.
    var freshHitRatio: Double { get }
    /// Lookups served from cache regardless of freshness, over all lookups.
    var hitRatio: Double { get }
    /// Current disk cache size in bytes (tracked in memory, not re-scanned per access).
    var currentDiskSizeBytes: Int64 { get }
    /// Reset all counters without clearing the cache entries.
    func resetMetrics()
}

// MARK: - CacheMetricsStore

/// Thread-safe metrics storage using NSLock — accessible from any isolation domain
/// without data races. Actor `BlueskyAPICache` increments via this store.
final class CacheMetricsStore: @unchecked Sendable {
    private let lock = NSLock()
    private var _hitCount = 0
    private var _staleCount = 0
    private var _missCount = 0
    private var _bytes: Int64 = 0
    private var _bytesKnown = false

    var hitCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _hitCount
    }

    var staleCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _staleCount
    }

    var missCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _missCount
    }

    var freshHitRatio: Double {
        lock.lock()
        defer { lock.unlock() }
        return Self.ratio(_hitCount, _hitCount + _staleCount + _missCount)
    }

    var hitRatio: Double {
        lock.lock()
        defer { lock.unlock() }
        return Self.ratio(_hitCount + _staleCount, _hitCount + _staleCount + _missCount)
    }

    var currentBytes: Int64 {
        lock.lock()
        defer { lock.unlock() }
        return max(0, _bytes)
    }

    var isSizeKnown: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _bytesKnown
    }

    func incrementHit() {
        lock.lock()
        _hitCount += 1
        lock.unlock()
    }

    func incrementStale() {
        lock.lock()
        _staleCount += 1
        lock.unlock()
    }

    func incrementMiss() {
        lock.lock()
        _missCount += 1
        lock.unlock()
    }

    /// Seed the tracked disk size after the one-time directory scan.
    func setBytes(_ value: Int64) {
        lock.lock()
        _bytes = max(0, value)
        _bytesKnown = true
        lock.unlock()
    }

    /// Apply a delta (positive on write, negative on removal) without rescanning the directory.
    func addBytes(_ delta: Int64) {
        lock.lock()
        defer { lock.unlock() }
        guard _bytesKnown else { return }
        _bytes = max(0, _bytes + delta)
    }

    func reset() {
        lock.lock()
        _hitCount = 0
        _staleCount = 0
        _missCount = 0
        lock.unlock()
    }

    /// Forget the tracked disk size so the next access re-seeds it from disk.
    func resetSize() {
        lock.lock()
        _bytes = 0
        _bytesKnown = false
        lock.unlock()
    }

    private static func ratio(_ numerator: Int, _ denominator: Int) -> Double {
        guard denominator > 0 else { return 0 }
        return Double(numerator) / Double(denominator)
    }
}

/// Metrics snapshot — value type returned from actor for precise async reads.
struct CacheMetricsSnapshot: Sendable {
    var hitCount: Int = 0
    var staleCount: Int = 0
    var missCount: Int = 0

    /// Cache-served lookups (fresh + stale) over all lookups.
    var hitRatio: Double {
        ratio(hitCount + staleCount)
    }

    /// Freshly served lookups over all lookups.
    var freshHitRatio: Double {
        ratio(hitCount)
    }

    private func ratio(_ served: Int) -> Double {
        let total = hitCount + staleCount + missCount
        guard total > 0 else { return 0 }
        return Double(served) / Double(total)
    }
}

// MARK: - CachedResponse

/// Metadata and raw data for a single cached API response.
private struct CachedResponse: Codable {
    /// When this entry was written (used for TTL checks).
    let createdAt: Date
    /// The raw JSON response data.
    let data: Data
    /// `ETag` from the origin response, replayed as `If-None-Match` on revalidation.
    var etag: String?
    /// `Last-Modified` from the origin response, replayed as `If-Modified-Since`.
    var lastModified: String?
    /// `Cache-Control: max-age` advertised by the origin, when present.
    var serverMaxAge: TimeInterval?
}

// MARK: - BlueskyAPICache

/// Actor-based on-disk cache for Bluesky API responses, keyed by a scope + normalized URL.
///
/// Scopes (`BlueskyAPICache.Scope`):
/// - `.shared` — payloads identical for every viewer (public profiles, list metadata, the
///   Constellation backlink index). One entry serves every account.
/// - `.account(did)` — payloads that depend on who is signed in (viewer state, the account's
///   own lists and repo). Keyed per account so a switch cannot leak state.
///
/// Features:
/// - JSON-file store in the caches directory
/// - Per-scope isolation via a hashed scope prefix in the file name (so `clear(for:)` works)
/// - Per-entry TTL (time-to-live) with stale-while-revalidate semantics
/// - Conditional revalidation: stored `ETag`/`Last-Modified` are replayed by callers
/// - LRU eviction above a 50 MB ceiling, tracked with a running counter (no per-write scan)
/// - Cache metrics exposed via `CacheMetricsProviding`
actor BlueskyAPICache: CacheMetricsProviding {
    static let shared = BlueskyAPICache()

    // MARK: - Scope

    /// Namespace a cache entry belongs to.
    enum Scope: Sendable, Hashable {
        /// Data that is identical regardless of which account is signed in.
        case shared
        /// Data that depends on the signed-in account.
        case account(String)

        /// Token used as the file-name prefix (hashed) and part of the entry key.
        var token: String {
            switch self {
            case .shared: "__shared__"
            case let .account(did): did
            }
        }
    }

    /// Cache key for one public profile row.
    ///
    /// Deliberately a single shared definition: the batch lookup (`fetchProfileBatch`), the
    /// blocker walk and the listed-on resolver all read and write this key, so a profile
    /// resolved by any one of them is reused by the others.
    static func profileKey(for identifier: String) -> String {
        "public.api.bsky.app/getProfiles?actor=\(identifier)"
    }

    // MARK: - Constants

    private static let cacheSubdir = "com.ajung.RULYX.BlueskyAPICache"
    private static let maxDiskBytes: Int64 = 50 * 1024 * 1024 // 50 MB
    private static let targetDiskBytes: Int64 = 40 * 1024 * 1024 // 40 MB
    /// Minimum spacing between eviction passes, so a burst of writes cannot trigger a
    /// directory sweep per write.
    private static let evictionInterval: TimeInterval = 30

    /// Default TTL values (in seconds).
    ///
    /// These are *freshness* windows, not validity limits: an expired entry is still served
    /// (stale-while-revalidate) and revalidated in the background. Public profile and list
    /// data changes rarely, so the windows are generous — mutations invalidate explicitly.
    enum DefaultTTL {
        static let profile: TimeInterval = 300 // 5 minutes
        static let list: TimeInterval = 900 // 15 minutes
        static let member: TimeInterval = 600 // 10 minutes
        static let relationship: TimeInterval = 300 // 5 minutes
        static let search: TimeInterval = 300 // 5 minutes
        static let feed: TimeInterval = 120 // 2 minutes
        static let notification: TimeInterval = 120 // 2 minutes
    }

    // MARK: - State

    private let fileManager = FileManager.default
    private let metrics = CacheMetricsStore()
    private var lastEviction: Date = .distantPast

    // MARK: - CacheMetricsProviding

    nonisolated var hitCount: Int {
        metrics.hitCount
    }

    nonisolated var staleCount: Int {
        metrics.staleCount
    }

    nonisolated var missCount: Int {
        metrics.missCount
    }

    nonisolated var freshHitRatio: Double {
        metrics.freshHitRatio
    }

    nonisolated var hitRatio: Double {
        metrics.hitRatio
    }

    nonisolated var currentDiskSizeBytes: Int64 {
        metrics.currentBytes
    }

    nonisolated func resetMetrics() {
        metrics.reset()
    }

    /// Actor-isolated reset (use when you can await).
    func resetMetricsAsync() {
        metrics.reset()
    }

    /// Actor-isolated snapshot for precise metrics.
    func snapshot() -> CacheMetricsSnapshot {
        CacheMetricsSnapshot(
            hitCount: metrics.hitCount,
            staleCount: metrics.staleCount,
            missCount: metrics.missCount
        )
    }

    // MARK: - Public API

    /// A cache lookup result.
    ///
    /// `isStale == true` means the entry outlived its TTL: the caller should schedule a
    /// revalidation, and may pass `etag`/`lastModified` to make it conditional.
    struct Entry: Sendable {
        let data: Data
        let isStale: Bool
        let etag: String?
        let lastModified: String?
    }

    /// Attempt to read a cached response for the given scope.
    /// - Returns: The entry, or `nil` when nothing is cached.
    func read(scope: Scope, url: String, maxAge: TimeInterval) -> Entry? {
        ensureSizeIndexed()
        let key = cacheKey(scope: scope, url: url)
        guard let entry = loadFromDisk(key: key) else {
            metrics.incrementMiss()
            return nil
        }

        let isStale = Date().timeIntervalSince(entry.createdAt) > maxAge
        if isStale {
            metrics.incrementStale()
        } else {
            // Fresh hit — touch file access time for LRU tracking
            touchFile(key: key)
            metrics.incrementHit()
        }
        return Entry(data: entry.data, isStale: isStale, etag: entry.etag, lastModified: entry.lastModified)
    }

    /// Write a response to the cache, recording origin freshness metadata for revalidation.
    func write(
        scope: Scope,
        url: String,
        data: Data,
        etag: String? = nil,
        lastModified: String? = nil,
        serverMaxAge: TimeInterval? = nil
    ) {
        ensureSizeIndexed()
        let key = cacheKey(scope: scope, url: url)
        let entry = CachedResponse(
            createdAt: Date(),
            data: data,
            etag: etag,
            lastModified: lastModified,
            serverMaxAge: serverMaxAge
        )
        saveToDisk(entry: entry, key: key)
    }

    /// Mark an entry as revalidated after a `304 Not Modified`: refreshes its timestamp
    /// while keeping the payload, without re-writing the body.
    func markRevalidated(scope: Scope, url: String) {
        ensureSizeIndexed()
        let key = cacheKey(scope: scope, url: url)
        guard let entry = loadFromDisk(key: key) else { return }
        saveToDisk(
            entry: CachedResponse(
                createdAt: Date(),
                data: entry.data,
                etag: entry.etag,
                lastModified: entry.lastModified,
                serverMaxAge: entry.serverMaxAge
            ),
            key: key
        )
    }

    /// Remove a single entry — used to invalidate on mutation (block, mute, list change).
    func remove(scope: Scope, url: String) {
        guard let dir = cacheDirectory() else { return }
        let fileURL = dir.appendingPathComponent(cacheKey(scope: scope, url: url))
        let size = fileSize(at: fileURL)
        guard (try? fileManager.removeItem(at: fileURL)) != nil else { return }
        metrics.addBytes(-size)
    }

    /// Remove all cached entries for a specific account. Shared entries are untouched.
    func clear(for accountDID: String) {
        clearEntries(withPrefix: Self.prefix(for: .account(accountDID)))
    }

    /// Remove ALL cached entries.
    func clearAll() {
        guard let dir = cacheDirectory() else { return }
        try? fileManager.removeItem(at: dir)
        metrics.resetSize()
    }

    // MARK: - Internal (for metrics)

    /// Returns total byte size of all cache files on disk (one-time full scan).
    func totalDiskSize() -> Int64 {
        guard let dir = cacheDirectory() else { return 0 }
        let total = scanDirectorySize(dir)
        metrics.setBytes(total)
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

    /// Stable unique key for a cache entry: the **scope prefix** followed by the hash
    /// of `scope + "|" + url`.
    ///
    /// The prefix is part of the file name on purpose: `clear(for:)` drops one account's
    /// entries by matching it. A key hashed from the scope and URL together could never
    /// be matched back to an account, which silently turned per-account invalidation
    /// (account removal) into a no-op.
    private func cacheKey(scope: Scope, url: String) -> String {
        let input = "\(scope.token)|\(url)"
        let data = Data(input.utf8)
        let hash = SHA256.hash(data: data)
        let entryHash = hash.map { String(format: "%02x", $0) }.joined()
        return "\(Self.prefix(for: scope))-\(entryHash)"
    }

    /// SHA-256 of the scope token, used as the cache file name prefix.
    private static func prefix(for scope: Scope) -> String {
        SHA256.hash(data: Data(scope.token.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private func clearEntries(withPrefix prefix: String) {
        guard let dir = cacheDirectory() else { return }
        guard let enumerator = fileManager.enumerator(at: dir, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey]) else { return }
        for case let fileURL as URL in enumerator {
            guard fileURL.lastPathComponent.hasPrefix(prefix) else { continue }
            let size = fileSize(at: fileURL)
            try? fileManager.removeItem(at: fileURL)
            metrics.addBytes(-size)
        }
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
        let previousSize = fileSize(at: fileURL)
        do {
            try encoded.write(to: fileURL)
        } catch {
            return
        }
        metrics.addBytes(Int64(encoded.count) - previousSize)
        evictIfNeeded()
    }

    /// Touch a file's modification date to update LRU order.
    private func touchFile(key: String) {
        guard let dir = cacheDirectory() else { return }
        let fileURL = dir.appendingPathComponent(key)
        try? fileManager.setAttributes([.modificationDate: Date()], ofItemAtPath: fileURL.path)
    }

    private func fileSize(at url: URL) -> Int64 {
        (try? fileManager.attributesOfItem(atPath: url.path))?[.size] as? Int64 ?? 0
    }

    private func scanDirectorySize(_ dir: URL) -> Int64 {
        guard let enumerator = fileManager.enumerator(at: dir, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey]) else { return 0 }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values?.isRegularFile == true else { continue }
            total += Int64(values?.fileSize ?? 0)
        }
        return total
    }

    /// Seed the in-memory size counter once, so eviction and the metrics overlay stop
    /// re-scanning the directory on every access.
    private func ensureSizeIndexed() {
        guard !metrics.isSizeKnown else { return }
        guard let dir = cacheDirectory() else {
            metrics.setBytes(0)
            return
        }
        metrics.setBytes(scanDirectorySize(dir))
    }

    /// Evict least-recently-touched files until the total drops below the target.
    ///
    /// Runs at most once per `evictionInterval`: previously every write enumerated the
    /// directory and summed every file, which is O(N) per write on a hot path.
    private func evictIfNeeded() {
        guard metrics.currentBytes > Self.maxDiskBytes else { return }
        guard Date().timeIntervalSince(lastEviction) >= Self.evictionInterval else { return }
        lastEviction = Date()

        guard let dir = cacheDirectory() else { return }
        guard let enumerator = fileManager.enumerator(at: dir, includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey, .fileSizeKey]) else { return }
        var files: [(url: URL, date: Date, size: Int64)] = []
        for case let fileURL as URL in enumerator {
            let values = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey, .fileSizeKey])
            guard values?.isRegularFile == true else { continue }
            files.append((fileURL, values?.contentModificationDate ?? .distantPast, Int64(values?.fileSize ?? 0)))
        }

        files.sort { $0.date < $1.date }
        var currentSize = metrics.currentBytes
        var removed: Int64 = 0
        for file in files {
            guard currentSize > Self.targetDiskBytes else { break }
            try? fileManager.removeItem(at: file.url)
            currentSize -= file.size
            removed += file.size
        }
        metrics.setBytes(currentSize)
        AppLogger.performance.debug("BlueskyAPICache LRU eviction: removed \(removed) bytes, now at \(currentSize) bytes")
    }
}
