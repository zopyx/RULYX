import CryptoKit
import Foundation
import ImageIO
import SwiftUI
import UIKit

// MARK: - AsyncSemaphore (T01)

/// Simple async semaphore to cap concurrent work without blocking threads.
actor AsyncSemaphore {
    private var value: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []
    init(value: Int) {
        self.value = value
    }

    func wait() async {
        if value > 0 {
            value -= 1
            return
        }
        await withCheckedContinuation { c in waiters.append(c) }
    }

    func signal() {
        if let waiter = waiters.first {
            waiters.removeFirst()
            waiter.resume()
        } else {
            value += 1
        }
    }
}

// MARK: - ThumbnailPipeline

/// Shared pipeline for fetching and downsampling remote images.
/// Used by both `ThumbnailImageView` and `FreshAvatarImage` so avatar and
/// media thumbnails share the same in-memory + disk cache (deduped by URL +
/// maxPixelSize + scale). No duplicate network fetch for the same URL.
///
/// Lookup order: in-memory cache → disk cache → network fetch.
actor ThumbnailPipeline {
    static let shared = ThumbnailPipeline()

    // MARK: - Constants

    /// Maximum disk cache size before LRU eviction fires.
    private static let maxDiskCacheBytes: Int64 = 50 * 1024 * 1024 // 50 MB
    /// Target disk cache size after eviction.
    private static let targetDiskCacheBytes: Int64 = 40 * 1024 * 1024 // 40 MB
    /// Subdirectory name inside the caches directory.
    private static let diskCacheSubdir = "com.ajung.RULYX.ThumbnailPipeline"

    // MARK: - State

    private let cache = NSCache<NSString, UIImage>()
    /// Caps concurrent network + decode work to avoid 200 parallel ImageIO decodes on 4-up feeds (T01).
    private let decodeSemaphore = AsyncSemaphore(value: 6)
    /// In-flight dedup — same URL+size requested twice shares one task (T01).
    private var inflight: [String: Task<UIImage, Error>] = [:]
    private let httpClient: HTTPClient = {
        let config = URLSessionConfiguration.default
        config.requestCachePolicy = .useProtocolCachePolicy
        config.urlCache = mediaThumbnailCache
        config.waitsForConnectivity = true
        return HTTPClient(session: URLSession(configuration: config))
    }()

    /// FileManager reference (main actor is fine for caches directory lookups).
    private let fileManager = FileManager.default

    // MARK: - Public

    /// Fetch and downsample an image to fit within `maxPixelSize` at the given display scale.
    ///
    /// Checks in-memory cache first, then on-disk cache, then fetches from the network.
    /// - Parameters:
    ///   - url: The remote image URL.
    ///   - maxPixelSize: Maximum pixel dimension for downsampling.
    ///   - scale: Display scale for pixel-accurate downsampling.
    ///   - ttl: Time-to-live in seconds for the disk cache entry (default 86400 = 24h).
    ///          The in-memory cache has no TTL (evicted by NSCache pressure).
    func image(for url: URL, maxPixelSize: CGFloat, scale: CGFloat, ttl: TimeInterval = 86400) async throws -> UIImage {
        let cacheKey = "\(url.absoluteString)|\(Int(maxPixelSize))|\(Int(scale))" as NSString
        let inflightKey = cacheKey as String

        // 1. In-memory cache
        if let cached = cache.object(forKey: cacheKey) {
            return cached
        }

        // Dedup: if same URL+size already in flight, share it
        if let existing = inflight[inflightKey] {
            return try await existing.value
        }

        let task = Task<UIImage, Error> {
            await decodeSemaphore.wait()
            defer { Task { await decodeSemaphore.signal() } }

            // Re-check disk cache under semaphore (may have been populated while waiting)
            let diskKey = diskCacheKey(for: url, maxPixelSize: maxPixelSize, scale: scale)
            if let diskData = loadFromDisk(key: diskKey, ttl: ttl) {
                let image = try downsample(data: diskData, maxPixelSize: maxPixelSize * scale)
                cache.setObject(image, forKey: cacheKey)
                return image
            }

            // Network fetch
            let (data, httpResponse) = try await httpClient.data(from: url, source: "Thumbnail Image")
            guard (200 ..< 300).contains(httpResponse.statusCode) else {
                throw URLError(.badServerResponse)
            }

            let image = try downsample(data: data, maxPixelSize: maxPixelSize * scale)
            cache.setObject(image, forKey: cacheKey)
            saveToDisk(data: data, key: diskKey)
            return image
        }
        inflight[inflightKey] = task
        defer { inflight[inflightKey] = nil }
        return try await task.value
    }

    /// Clears both the in-memory and on-disk caches.
    func clearAllCaches() {
        cache.removeAllObjects()
        clearDiskCache()
    }

    /// Removes all files from the disk cache directory.
    func clearDiskCache() {
        guard let diskURL = diskCacheDirectory() else { return }
        try? fileManager.removeItem(at: diskURL)
    }

    // MARK: - Disk Cache Helpers

    /// Returns the full path to the disk cache directory, creating it if needed.
    private func diskCacheDirectory() -> URL? {
        guard let cachesDir = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
        else { return nil }
        let dir = cachesDir.appendingPathComponent(Self.diskCacheSubdir)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Stable file name for a cache entry derived from its URL + pixel config.
    private func diskCacheKey(for url: URL, maxPixelSize: CGFloat, scale: CGFloat) -> String {
        let input = "\(url.absoluteString)|\(Int(maxPixelSize))|\(Int(scale))"
        return cacheKeyHash(input)
    }

    /// Attempt to load raw image data from the disk cache.
    /// Returns nil if the file doesn't exist or has exceeded its TTL.
    private func loadFromDisk(key: String, ttl: TimeInterval) -> Data? {
        guard let dir = diskCacheDirectory() else { return nil }
        let fileURL = dir.appendingPathComponent(key)

        guard let attrs = try? fileManager.attributesOfItem(atPath: fileURL.path),
              let modDate = attrs[.modificationDate] as? Date
        else { return nil }

        // TTL check
        guard Date().timeIntervalSince(modDate) < ttl else {
            // Stale — remove and return nil
            try? fileManager.removeItem(at: fileURL)
            return nil
        }

        // Touch the file's modification date to track LRU access
        try? fileManager.setAttributes([.modificationDate: Date()], ofItemAtPath: fileURL.path)
        AppLogger.performance.debug("Disk cache HIT for \(key.prefix(12))...")
        return try? Data(contentsOf: fileURL)
    }

    /// Write raw image data to the disk cache.
    /// Fires LRU eviction if the total cache size exceeds the maximum.
    private func saveToDisk(data: Data, key: String) {
        guard let dir = diskCacheDirectory() else { return }
        let fileURL = dir.appendingPathComponent(key)
        do {
            try data.write(to: fileURL)
            AppLogger.performance.debug("Disk cache WRITE for \(key.prefix(12))...")
            // Check size and evict if needed
            evictIfNeeded()
        } catch {
            AppLogger.performance.debug("Disk cache write failed for \(key.prefix(12))...: \(error.localizedDescription)")
        }
    }

    /// Computes total disk cache size by summing file sizes.
    private func totalDiskCacheSize() -> Int64 {
        guard let dir = diskCacheDirectory() else { return 0 }
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

    /// Evict oldest files (by access/modification date) until usage drops below the target.
    private func evictIfNeeded() {
        guard let dir = diskCacheDirectory() else { return }
        let total = totalDiskCacheSize()
        guard total > Self.maxDiskCacheBytes else { return }

        // Collect all files with their modification dates
        guard let enumerator = fileManager.enumerator(at: dir, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey]) else { return }
        var files: [(url: URL, date: Date, size: Int64)] = []
        for case let fileURL as URL in enumerator {
            guard let attrs = try? fileManager.attributesOfItem(atPath: fileURL.path),
                  let modDate = attrs[.modificationDate] as? Date,
                  let size = attrs[.size] as? Int64
            else { continue }
            files.append((fileURL, modDate, size))
        }

        // Sort by oldest modification date first (LRU)
        files.sort { $0.date < $1.date }

        var currentSize = total
        for file in files {
            guard currentSize > Self.targetDiskCacheBytes else { break }
            try? fileManager.removeItem(at: file.url)
            currentSize -= file.size
        }
        AppLogger.performance.debug("Disk cache LRU eviction: removed \(total - currentSize) bytes, now at \(currentSize) bytes")
    }

    // MARK: - Downsampling

    /// Downsample image data to the target pixel size using ImageIO (avoids full decode).
    private func downsample(data: Data, maxPixelSize: CGFloat) throws -> UIImage {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, options) else {
            throw URLError(.cannotDecodeRawData)
        }

        let downsampleOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, Int(maxPixelSize)),
        ] as CFDictionary

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, downsampleOptions) else {
            throw URLError(.cannotDecodeContentData)
        }

        return UIImage(cgImage: cgImage)
    }

    // MARK: - Cache Key Hash

    /// Returns the SHA-256 hex digest of a string (used for stable cache keys).
    private func cacheKeyHash(_ string: String) -> String {
        let data = Data(string.utf8)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - ThumbnailImageView

/// An efficient thumbnail image view that downloads and down-samples remote images
/// using ImageIO, with in-memory and disk caching. Shows a `Placeholder` view while loading.
///
/// Use this instead of plain `AsyncImage` for consistent sizing and memory efficiency.
struct ThumbnailImageView<Placeholder: View>: View {
    /// The remote image URL.
    let url: URL
    /// Maximum pixel dimension for the downsampled thumbnail.
    let maxPixelSize: CGFloat
    /// Time-to-live in seconds for the disk cache entry (default 86400 = 24h).
    var cacheTTL: TimeInterval = 86400
    /// Optional callback delivering the loaded image's pixel aspect ratio (width / height),
    /// so callers can pre-compute stable integral display sizes.
    var onLoadedAspectRatio: ((CGFloat) -> Void)?
    /// Placeholder view shown while loading.
    @ViewBuilder let placeholder: () -> Placeholder

    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?
    @State private var loadedTaskID: String?

    // MARK: - Body

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
            } else {
                placeholder()
            }
        }
        .task(id: taskID) {
            await loadImage()
        }
    }

    // MARK: - Private Helpers

    /// Stable task identifier combining URL, pixel size, and display scale so the task
    /// restarts only when one of these changes.
    private var taskID: String {
        "\(url.absoluteString)|\(Int(maxPixelSize))|\(Int(displayScale))|\(Int(cacheTTL))"
    }

    /// Load the thumbnail via the shared pipeline.
    private func loadImage() async {
        if loadedTaskID != taskID {
            image = nil
        }
        do {
            let loaded = try await ThumbnailPipeline.shared.image(for: url, maxPixelSize: maxPixelSize, scale: displayScale, ttl: cacheTTL)
            image = loaded
            loadedTaskID = taskID
            onLoadedAspectRatio?(loaded.size.width / max(loaded.size.height, 1))
        } catch is CancellationError {
            return
        } catch let error as URLError where error.code == .cancelled {
            return
        } catch {
            AppLogger.performance.debug("Thumbnail load failed for \(url.absoluteString, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }
}
