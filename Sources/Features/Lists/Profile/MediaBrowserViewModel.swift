import Foundation

@MainActor
protocol MediaFeedFetching {
    func fetchRichFeed(did: String, cursor: String?, account: AppAccount, appPassword: String?) async throws -> RichFeedResponse
}

extension LiveBlueskyClient: MediaFeedFetching {}

/// Types of media content that can appear in the browser.
enum MediaType {
    case image, video
}

/// Filter options for the media browser.
enum MediaFilter: String, CaseIterable {
    case images
    case videos

    @MainActor
    var label: String {
        switch self {
        case .images: loc("media.filter.images")
        case .videos: loc("media.filter.videos")
        }
    }
}

/// Represents a single media item extracted from a post.
struct MediaItem: Identifiable {
    let id: String
    let url: String
    let thumbnailURL: String?
    let type: MediaType
    let alt: String?
    let postURI: String
    let postText: String?
    let createdAt: String?
    let indexedAt: String?
    let playlistURL: String?
    let indexedDate: Date?
    let ageText: String?
}

/// Outcome of downloading a single media asset.
struct DownloadResult {
    let index: Int
    let name: String?
    let error: String?
}

/// Summary of a completed media download operation.
struct DownloadSummary: Identifiable {
    let id = UUID()
    let directory: URL
    let total: Int
    let succeeded: Int
    let errors: [String]

    var failed: Int {
        total - succeeded
    }
}

/// Selection state is kept separate from the browser's data-loading state so
/// selecting media does not invalidate and rebuild the thumbnail grid.
@MainActor
final class MediaSelectionState: ObservableObject {
    @Published private(set) var selectedIDs = Set<String>()

    var count: Int {
        selectedIDs.count
    }

    var isEmpty: Bool {
        selectedIDs.isEmpty
    }

    func contains(_ id: String) -> Bool {
        selectedIDs.contains(id)
    }

    func toggle(_ id: String) {
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
    }

    func containsAll(_ ids: [String]) -> Bool {
        !ids.isEmpty && selectedIDs.count == ids.count && ids.allSatisfy(selectedIDs.contains)
    }

    func selectAll(_ ids: [String]) {
        let newSelection = Set(ids)
        guard selectedIDs != newSelection else { return }
        selectedIDs = newSelection
    }

    func clear() {
        guard !selectedIDs.isEmpty else { return }
        selectedIDs.removeAll(keepingCapacity: true)
    }

    func retain(_ ids: Set<String>) {
        let retainedSelection = selectedIDs.intersection(ids)
        guard selectedIDs != retainedSelection else { return }
        selectedIDs = retainedSelection
    }
}

/// A 256MB memory / 2GB disk cache dedicated to media thumbnails.
/// Uses its own URLSession — does NOT mutate URLCache.shared.
/// Thumbnail URLs are public CDN content; separating them from
/// viewer-relative API responses prevents cache pollution and
/// unwanted cross-account data sharing.
private let sharedMediaCache: URLCache = .init(memoryCapacity: 256 * 1024 * 1024, diskCapacity: 2 * 1024 * 1024 * 1024, diskPath: "media-thumbnails")

/// URLSession with the dedicated media cache. All thumbnail downloads
/// from `MediaBrowserViewModel` should use this session.
let mediaURLSession: URLSession = {
    let config = URLSessionConfiguration.default
    config.urlCache = sharedMediaCache
    return URLSession(configuration: config)
}()

/// Browses and downloads media (images and videos) from a user's feed.
///
/// Loads pages from `fetchRichFeed`, extracts embeds into `MediaItem` structs,
/// supports filtering by type, multi-select, and batch download with progress.
@MainActor
final class MediaBrowserViewModel: ObservableObject {
    // MARK: - Properties

    /// All loaded media items, sorted newest-first.
    @Published private(set) var items: [MediaItem] = []
    /// Items matching the current `filter` selection.
    @Published private(set) var filteredItems: [MediaItem] = []
    /// True while the initial load is in progress.
    @Published private(set) var isLoading = false
    /// True while loading the next page.
    @Published private(set) var isLoadingMore = false
    /// True while scanning for media (searching, not just loading pages).
    @Published private(set) var isScanning = false
    /// False when there are no more pages on the server.
    @Published private(set) var hasMore = true
    /// Total image count across all loaded items.
    @Published private(set) var imageCount = 0
    /// Total video count across all loaded items.
    @Published private(set) var videoCount = 0
    /// Summary text (currently unused, always empty).
    @Published private(set) var summaryText = ""
    /// Selection publishes independently so it only refreshes selection UI.
    let selection = MediaSelectionState()
    /// User-facing error message.
    @Published var errorMessage: String?
    /// True while a download operation is in progress.
    @Published var isDownloading = false
    /// Fine-grained progress isolated from the media grid's observation graph.
    let downloadState = MediaDownloadProgressState()
    /// Active media type filter; switches `filteredItems` in O(1) from pre-built arrays.
    @Published var filter: MediaFilter = .images {
        didSet {
            switchFilteredItems()
        }
    }

    /// Summary shown after download completes.
    @Published var downloadSummary: DownloadSummary?

    // MARK: - Computed Properties

    /// Filters that have at least one matching item. Stored (not computed)
    /// to avoid O(n) scans on every SwiftUI body evaluation.
    @Published private(set) var availableFilters: [MediaFilter] = []

    /// Whether all filtered items are selected.
    var selectAll: Bool {
        get { selection.containsAll(filteredItems.map(\.id)) }
        set {
            if newValue {
                selection.selectAll(filteredItems.map(\.id))
            } else {
                selection.clear()
            }
        }
    }

    var selectedIDs: Set<String> {
        selection.selectedIDs
    }

    // MARK: - Private Properties

    /// Cursor for paginating through the feed.
    private var cursor: String?
    /// The DID of the profile whose media is being browsed.
    private let did: String
    /// Service used for downloading media files.
    private let downloadService: MediaDownloadService
    /// Pre-built image-only items for O(1) filter switching.
    private var imageItems: [MediaItem] = []
    /// Pre-built video-only items for O(1) filter switching.
    private var videoItems: [MediaItem] = []

    // MARK: - Init

    init(did: String, downloadService: MediaDownloadService? = nil) {
        self.did = did
        // Media downloads use the dedicated media URLSession/cache. Keeping
        // this separate from URLSession.shared prevents viewer-relative API
        // responses from being mixed with public CDN media.
        self.downloadService = downloadService ?? MediaDownloadService(session: mediaURLSession)
        _ = sharedMediaCache
    }

    // MARK: - Selection

    /// Removes selection IDs for items no longer in the filtered set.
    func pruneSelection() {
        selection.retain(Set(filteredItems.map(\.id)))
    }

    // MARK: - Data Loading

    /// Loads the first page of media, replacing all existing items.
    func load(account: AppAccount, appPassword: String, using client: some MediaFeedFetching) async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        isScanning = false
        replaceItems([])
        cursor = nil
        hasMore = true
        await fetchPage(account: account, appPassword: appPassword, using: client)
        isLoading = false
    }

    /// Loads the next page of media and appends to existing items.
    func loadMore(account: AppAccount, appPassword: String, using client: some MediaFeedFetching) async {
        guard !isLoadingMore, cursor != nil else { return }
        isLoadingMore = true
        await fetchPage(account: account, appPassword: appPassword, using: client)
        isLoadingMore = false
    }

    // MARK: - Private Helpers

    /// Fetches one page of the author feed and extracts media embeds into items.
    private func fetchPage(account: AppAccount, appPassword: String, using client: some MediaFeedFetching) async {
        do {
            guard !Task.isCancelled else { return }
            let response = try await client.fetchRichFeed(did: did, cursor: cursor, account: account, appPassword: appPassword)
            var batch: [MediaItem] = []
            for entry in response.feed {
                guard !Task.isCancelled else { return }
                guard let embed = entry.post.embed else { continue }
                extractMedia(
                    from: embed,
                    postURI: entry.post.uri,
                    postText: entry.post.safeRecord.text,
                    createdAt: entry.post.safeRecord.createdAt,
                    indexedAt: entry.post.indexedAt,
                    into: &batch
                )
            }
            if !batch.isEmpty {
                appendItems(batch)
            }
            cursor = response.cursor
            hasMore = response.cursor != nil
        } catch is CancellationError {
            return
        } catch {
            errorMessage = AppError.userMessage(from: error)
            AppLogger.moderation.error("Failed to load media: \(error.localizedDescription, privacy: .private)")
        }
    }

    /// Extracts media items from an embed directly into the `items` array (legacy path).
    private func extractMedia(from embed: RichEmbed, postURI: String, postText: String?, createdAt: String?, indexedAt: String?) {
        extractMedia(from: embed, postURI: postURI, postText: postText, createdAt: createdAt, indexedAt: indexedAt, into: &items)
    }

    /// Extracts images and videos from a post embed into a mutable batch array.
    /// Images get one `MediaItem` per image; videos get a single item with playlist URL.
    private func extractMedia(
        from embed: RichEmbed,
        postURI: String,
        postText: String?,
        createdAt: String?,
        indexedAt: String?,
        into batch: inout [MediaItem]
    ) {
        if let images = embed.images {
            for img in images {
                guard let fullsize = img.fullsize else { continue }
                let indexedDate = parseDate(indexedAt)
                let media = MediaItem(
                    id: "\(postURI)/\(fullsize)",
                    url: fullsize,
                    thumbnailURL: img.thumb ?? fullsize,
                    type: .image,
                    alt: img.alt,
                    postURI: postURI,
                    postText: postText,
                    createdAt: createdAt,
                    indexedAt: indexedAt,
                    playlistURL: nil,
                    indexedDate: indexedDate,
                    ageText: Self.makeAgeText(from: indexedDate)
                )
                batch.append(media)
            }
        }
        if let video = embed.video, let thumb = video.thumbnail {
            let indexedDate = parseDate(indexedAt)
            let media = MediaItem(
                id: "\(postURI)/video",
                url: video.playlist ?? thumb,
                thumbnailURL: thumb,
                type: .video,
                alt: nil,
                postURI: postURI,
                postText: postText,
                createdAt: createdAt,
                indexedAt: indexedAt,
                playlistURL: video.playlist,
                indexedDate: indexedDate,
                ageText: Self.makeAgeText(from: indexedDate)
            )
            batch.append(media)
        }
    }

    /// Replaces all items with a sorted new set and rebuilds derived state.
    private func replaceItems(_ newItems: [MediaItem]) {
        items = Self.sortedItems(newItems)
        // Single-pass: counts, availableFilters, and type-specific arrays.
        imageCount = 0
        videoCount = 0
        imageItems.removeAll(keepingCapacity: true)
        videoItems.removeAll(keepingCapacity: true)
        var hasImage = false, hasVideo = false
        for item in items {
            if item.type == .image {
                imageCount += 1
                imageItems.append(item)
                hasImage = true
            } else {
                videoCount += 1
                videoItems.append(item)
                hasVideo = true
            }
        }
        updateAvailableFilters(hasImage: hasImage, hasVideo: hasVideo)
    }

    /// Appends new items, sorts the combined array, and updates counts incrementally.
    private func appendItems(_ newItems: [MediaItem]) {
        guard !newItems.isEmpty else { return }
        // Incremental counts and type-specific arrays — O(k) on new items only.
        for item in newItems {
            if item.type == .image {
                imageCount += 1
                imageItems.append(item)
            } else {
                videoCount += 1
                videoItems.append(item)
            }
        }
        items = Self.sortedItems(items + newItems)
        updateAvailableFilters(hasImage: imageCount > 0, hasVideo: videoCount > 0)
    }

    /// Updates filter availability without scanning the media arrays. If the
    /// current filter is empty, switches to the first media type that exists.
    private func updateAvailableFilters(hasImage: Bool, hasVideo: Bool) {
        var filters: [MediaFilter] = []
        if hasImage {
            filters.append(.images)
        }
        if hasVideo {
            filters.append(.videos)
        }
        availableFilters = filters

        if !filters.contains(filter), let firstFilter = filters.first {
            filter = firstFilter
        } else {
            switchFilteredItems()
        }
    }

    /// Switches `filteredItems` in O(1) from pre-built arrays.
    private func switchFilteredItems() {
        switch filter {
        case .images:
            filteredItems = imageItems
        case .videos:
            filteredItems = videoItems
        }
    }

    /// Sorts items newest-first by indexed date, falling back to ID comparison.
    private static func sortedItems(_ items: [MediaItem]) -> [MediaItem] {
        items.sorted { a, b in
            switch (a.indexedDate, b.indexedDate) {
            case let (lhs?, rhs?):
                lhs > rhs
            case (.some, nil):
                true
            case (nil, .some):
                false
            case (nil, nil):
                a.id > b.id
            }
        }
    }

    /// Converts a `Date` to a compact relative age string (e.g. "3d", "2w", "1mo").
    private static func makeAgeText(from date: Date?) -> String? {
        guard let date else { return nil }
        let interval = max(0, date.distance(to: .now))
        if interval < 3600 {
            return "\(Int(interval / 60))m"
        }
        if interval < 86400 {
            return "\(Int(interval / 3600))h"
        }
        if interval < 604_800 {
            return "\(Int(interval / 86400))d"
        }
        if interval < 2_592_000 {
            return "\(Int(interval / 604_800))w"
        }
        if interval < 31_536_000 {
            return "\(Int(interval / 2_592_000))mo"
        }
        return "\(Int(interval / 31_536_000))y"
    }

    // MARK: - Download

    /// Downloads all selected media items to `directory/handle/` with progress tracking.
    func downloadSelected(to directory: URL, handle: String) async {
        let selected = items.filter { selectedIDs.contains($0.id) }
        guard !selected.isEmpty else { return }
        guard !Task.isCancelled else { return }

        isDownloading = true
        downloadSummary = nil
        downloadState.start(total: selected.count)
        defer {
            isDownloading = false
        }

        let targetDir = directory.appendingPathComponent(handle, isDirectory: true)
        try? FileManager.default.createDirectory(at: targetDir, withIntermediateDirectories: true)

        var assets: [MediaAssetDownload] = []
        var invalidResults: [MediaAssetDownloadOutcome] = []
        var mediaCountsByPost: [String: (images: Int, videos: Int)] = [:]
        assets.reserveCapacity(selected.count)

        for (idx, item) in selected.enumerated() {
            let filenameStem = Self.filenameStem(for: item, counts: &mediaCountsByPost)
            if item.type == .video, let playlist = item.playlistURL.flatMap(URL.init) {
                assets.append(MediaAssetDownload(index: idx, filenameStem: filenameStem, source: .videoPlaylist(playlist)))
            } else if let url = URL(string: item.url) {
                let preferredExtension = URL(string: item.thumbnailURL ?? "")?.pathExtension
                assets.append(
                    MediaAssetDownload(
                        index: idx,
                        filenameStem: filenameStem,
                        source: .image(url: url, preferredExtension: preferredExtension?.isEmpty == true ? nil : preferredExtension)
                    )
                )
            } else {
                invalidResults.append(MediaAssetDownloadOutcome(index: idx, savedFilename: nil, error: "Invalid URL"))
            }
        }

        if !invalidResults.isEmpty {
            for (completed, result) in invalidResults.enumerated() {
                downloadState.complete(
                    index: result.index,
                    completed: completed + 1,
                    detail: result.error
                )
            }
        }

        let invalidCount = invalidResults.count
        let downloadedResults = await downloadService.downloadMedia(
            assets,
            to: targetDir,
            progress: { completed, _, latestResult in
                await MainActor.run {
                    self.downloadState.complete(
                        index: latestResult.index,
                        completed: completed + invalidCount,
                        detail: latestResult.savedFilename ?? latestResult.error
                    )
                }
            },
            assetProgress: { progress in
                await MainActor.run {
                    self.downloadState.update(progress)
                }
            }
        )
        guard !Task.isCancelled else { return }
        let results = (invalidResults + downloadedResults).sorted { $0.index < $1.index }

        downloadSummary = DownloadSummary(
            directory: targetDir,
            total: selected.count,
            succeeded: results.count(where: { $0.savedFilename != nil }),
            errors: results.compactMap(\.error)
        )
    }

    /// Clears the download summary after it has been shown.
    func clearDownloadSummary() {
        downloadSummary = nil
    }

    // MARK: - Private Download Helpers

    /// Date formatter for filenames: `yyyy-MM-dd_HH-mm-ss` in UTC.
    private static let filenameDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return formatter
    }()

    /// Generates a unique filename stem for a media item based on its timestamp, post ID, and type.
    private static func filenameStem(for item: MediaItem, counts: inout [String: (images: Int, videos: Int)]) -> String {
        let timestamp = parseDate(item.createdAt)
            .map { filenameDateFormatter.string(from: $0) }
            ?? "unknown-date"
        let postIdentifier = sanitizeFilenameComponent(item.postURI.split(separator: "/").last.map(String.init) ?? "post")

        let nextCounts: (images: Int, videos: Int)
        switch item.type {
        case .image:
            let imageIndex = (counts[item.postURI]?.images ?? 0) + 1
            nextCounts = (images: imageIndex, videos: counts[item.postURI]?.videos ?? 0)
            counts[item.postURI] = nextCounts
            return "\(timestamp)_\(postIdentifier)_image-\(imageIndex)"
        case .video:
            let videoIndex = (counts[item.postURI]?.videos ?? 0) + 1
            nextCounts = (images: counts[item.postURI]?.images ?? 0, videos: videoIndex)
            counts[item.postURI] = nextCounts
            return "\(timestamp)_\(postIdentifier)_video-\(videoIndex)"
        }
    }

    /// Removes non-alphanumeric characters (except `-` and `_`) from a filename component.
    private static func sanitizeFilenameComponent(_ value: String) -> String {
        let sanitizedScalars = value.unicodeScalars.map { scalar -> Character in
            if CharacterSet.alphanumerics.contains(scalar) || scalar == "-" || scalar == "_" {
                return Character(scalar)
            }
            return "_"
        }
        let sanitized = String(sanitizedScalars)
            .replacingOccurrences(of: "__+", with: "_", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        return sanitized.isEmpty ? "item" : sanitized
    }
}
