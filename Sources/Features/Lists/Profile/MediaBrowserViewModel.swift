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

/// A 256MB memory / 2GB disk cache for media thumbnails.
private let sharedCache: URLCache = {
    let cache = URLCache(memoryCapacity: 256 * 1024 * 1024, diskCapacity: 2 * 1024 * 1024 * 1024, diskPath: "media-thumbnails")
    URLCache.shared = cache
    return cache
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
    /// Set of media item IDs selected for download.
    @Published var selectedIDs = Set<String>()
    /// User-facing error message.
    @Published var errorMessage: String?
    /// True while a download operation is in progress.
    @Published var isDownloading = false
    /// Tracks (completed, total) during download for progress UI.
    @Published var downloadProgress: (current: Int, total: Int)?
    /// Detailed status of the current download (last file name or error).
    @Published var downloadStatusDetail: String?
    /// Active media type filter; triggers `rebuildDerivedState`.
    @Published var filter: MediaFilter = .images {
        didSet {
            rebuildDerivedState()
        }
    }

    /// Summary shown after download completes.
    @Published var downloadSummary: DownloadSummary?

    // MARK: - Computed Properties

    /// Filters that have at least one matching item.
    var availableFilters: [MediaFilter] {
        var result = [MediaFilter]()
        if items.contains(where: { $0.type == .image }) { result.append(.images) }
        if items.contains(where: { $0.type == .video }) { result.append(.videos) }
        return result
    }

    /// Whether all filtered items are selected.
    var selectAll: Bool {
        get { selectedIDs.count == filteredItems.count && !filteredItems.isEmpty }
        set {
            if newValue {
                selectedIDs = Set(filteredItems.map(\.id))
            } else {
                selectedIDs.removeAll()
            }
        }
    }

    // MARK: - Private Properties

    /// Cursor for paginating through the feed.
    private var cursor: String?
    /// The DID of the profile whose media is being browsed.
    private let did: String
    /// Service used for downloading media files.
    private let downloadService: MediaDownloadService

    // MARK: - Init

    init(did: String, downloadService: MediaDownloadService = .shared) {
        self.did = did
        self.downloadService = downloadService
        _ = sharedCache
    }

    // MARK: - Selection

    /// Removes selection IDs for items no longer in the filtered set.
    func pruneSelection() {
        selectedIDs = Set(filteredItems.filter { selectedIDs.contains($0.id) }.map(\.id))
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
            if !batch.isEmpty { appendItems(batch) }
            cursor = response.cursor
            hasMore = response.cursor != nil
        } catch is CancellationError {
            return
        } catch {
            errorMessage = AppError.userMessage(from: error)
            AppLogger.moderation.error("Failed to load media: \(error.localizedDescription, privacy: .public)")
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
        rebuildDerivedState()
    }

    /// Appends new items, sorts the combined array, and rebuilds derived state.
    private func appendItems(_ newItems: [MediaItem]) {
        guard !newItems.isEmpty else { return }
        items = Self.sortedItems(items + newItems)
        rebuildDerivedState()
    }

    /// Recomputes image/video counts, filtered items, and clears summary text.
    private func rebuildDerivedState() {
        imageCount = items.reduce(into: 0) { count, item in
            if item.type == .image {
                count += 1
            }
        }
        videoCount = items.count - imageCount

        switch filter {
        case .images:
            filteredItems = items.filter { $0.type == .image }
        case .videos:
            filteredItems = items.filter { $0.type == .video }
        }

        summaryText = ""
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
        if interval < 3600 { return "\(Int(interval / 60))m" }
        if interval < 86400 { return "\(Int(interval / 3600))h" }
        if interval < 604_800 { return "\(Int(interval / 86400))d" }
        if interval < 2_592_000 { return "\(Int(interval / 604_800))w" }
        if interval < 31_536_000 { return "\(Int(interval / 2_592_000))mo" }
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
        downloadStatusDetail = nil
        defer {
            isDownloading = false
            downloadStatusDetail = nil
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
            downloadProgress = (invalidResults.count, selected.count)
            downloadStatusDetail = invalidResults.first?.error
        }

        let invalidCount = invalidResults.count
        let downloadedResults = await downloadService.downloadMedia(assets, to: targetDir) { completed, _, latestResult in
            await MainActor.run {
                self.downloadProgress = (completed + invalidCount, selected.count)
                self.downloadStatusDetail = latestResult.savedFilename ?? latestResult.error
            }
        }
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
