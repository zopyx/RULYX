import AVFoundation
import Foundation

/// Errors that can occur during media download and processing.
private enum MediaDownloadFailure: LocalizedError {
    case nonHTTPResponse
    case invalidStatusCode(Int)
    case invalidPlaylist
    case missingSegments
    case remuxFailed(String?)

    var errorDescription: String? {
        switch self {
        case .nonHTTPResponse:
            "Non-HTTP response."
        case let .invalidStatusCode(code):
            "HTTP \(code)"
        case .invalidPlaylist:
            "Invalid playlist."
        case .missingSegments:
            "Missing video segments."
        case let .remuxFailed(reason):
            if let reason, !reason.isEmpty {
                "Video remux failed: \(reason)"
            } else {
                "Video remux failed."
            }
        }
    }
}

/// Describes a single media asset to be downloaded (image or HLS video).
struct MediaAssetDownload {
    /// Index used for ordering results.
    let index: Int
    /// Base filename stem (without extension) for the saved file.
    let filenameStem: String
    /// The source type (image URL or video playlist URL).
    let source: MediaAssetSource
}

/// The source type of a media asset for download.
enum MediaAssetSource {
    /// A static image to download directly.
    case image(url: URL, preferredExtension: String?)
    /// An HLS video playlist URL to be fetched and remuxed.
    case videoPlaylist(URL)
}

private struct MediaByteRange: Sendable {
    let offset: Int64
    let length: Int64

    var headerValue: String {
        "bytes=\(offset)-\(offset + length - 1)"
    }
}

private struct PendingMediaByteRange {
    let length: Int64
    let offset: Int64?
}

private struct VideoSegment: Sendable {
    let url: URL
    let byteRange: MediaByteRange?
}

private struct VideoInitSegment: Sendable {
    let url: URL
    let byteRange: MediaByteRange?
}

/// The result of downloading a single media asset.
struct MediaAssetDownloadOutcome: Sendable {
    /// The asset index for ordering.
    let index: Int
    /// The filename of the saved file, or `nil` on failure.
    let savedFilename: String?
    /// Error message if the download failed.
    let error: String?
}

/// Fine-grained progress for one asset in a bulk media download.
struct MediaAssetProgress: Sendable {
    let index: Int
    let filenameStem: String
    let fractionCompleted: Double
}

/// Actor-based service for downloading media assets (images and HLS videos)
/// with configurable concurrency limits. Handles HLS playlist resolution,
/// segment downloading, fragmented MP4 assembly, and TS-to-MP4 export.
actor MediaDownloadService {
    static let shared = MediaDownloadService()

    private let imageDownloadConcurrency = 8
    private let mediaItemDownloadConcurrency = 4
    private let videoSegmentDownloadConcurrency = 6

    private let downloadSession: URLSession
    private let httpClient: HTTPClient

    init(session: URLSession? = nil) {
        if let session {
            downloadSession = session
        } else {
            let config = URLSessionConfiguration.default
            config.httpMaximumConnectionsPerHost = 12
            config.timeoutIntervalForRequest = 60
            config.timeoutIntervalForResource = 300
            config.waitsForConnectivity = true
            config.requestCachePolicy = .useProtocolCachePolicy
            downloadSession = URLSession(configuration: config)
        }
        httpClient = HTTPClient(session: downloadSession)
    }

    func downloadImages(
        _ assets: [MediaAssetDownload],
        to targetDir: URL,
        progress: @Sendable @escaping (_ completed: Int, _ total: Int, _ latestResult: MediaAssetDownloadOutcome) async -> Void,
        assetProgress: @Sendable @escaping (MediaAssetProgress) async -> Void = { _ in }
    ) async -> [MediaAssetDownloadOutcome] {
        await download(
            assets,
            to: targetDir,
            concurrencyLimit: imageDownloadConcurrency,
            progress: progress,
            assetProgress: assetProgress
        )
    }

    func downloadMedia(
        _ assets: [MediaAssetDownload],
        to targetDir: URL,
        progress: @Sendable @escaping (_ completed: Int, _ total: Int, _ latestResult: MediaAssetDownloadOutcome) async -> Void,
        assetProgress: @Sendable @escaping (MediaAssetProgress) async -> Void = { _ in }
    ) async -> [MediaAssetDownloadOutcome] {
        await download(
            assets,
            to: targetDir,
            concurrencyLimit: mediaItemDownloadConcurrency,
            progress: progress,
            assetProgress: assetProgress
        )
    }

    private func download(
        _ assets: [MediaAssetDownload],
        to targetDir: URL,
        concurrencyLimit: Int,
        progress: @Sendable @escaping (_ completed: Int, _ total: Int, _ latestResult: MediaAssetDownloadOutcome) async -> Void,
        assetProgress: @Sendable @escaping (MediaAssetProgress) async -> Void
    ) async -> [MediaAssetDownloadOutcome] {
        guard !assets.isEmpty else { return [] }

        try? FileManager.default.createDirectory(at: targetDir, withIntermediateDirectories: true)

        var results: [MediaAssetDownloadOutcome] = []
        results.reserveCapacity(assets.count)

        var nextAssetIndex = 0
        var completed = 0
        let segmentLimit = videoSegmentDownloadConcurrency

        await withTaskGroup(of: MediaAssetDownloadOutcome.self) { group in
            let initialCount = min(concurrencyLimit, assets.count)
            for _ in 0 ..< initialCount {
                let asset = assets[nextAssetIndex]
                nextAssetIndex += 1
                group.addTask { [httpClient] in
                    await Self.process(
                        asset,
                        in: targetDir,
                        using: httpClient,
                        segmentLimit: segmentLimit,
                        progress: assetProgress
                    )
                }
            }

            while let result = await group.next() {
                guard !Task.isCancelled else {
                    group.cancelAll()
                    return
                }
                results.append(result)
                completed += 1
                await progress(completed, assets.count, result)

                if nextAssetIndex < assets.count {
                    let asset = assets[nextAssetIndex]
                    nextAssetIndex += 1
                    group.addTask { [httpClient] in
                        await Self.process(
                            asset,
                            in: targetDir,
                            using: httpClient,
                            segmentLimit: segmentLimit,
                            progress: assetProgress
                        )
                    }
                }
            }
        }

        return results.sorted { $0.index < $1.index }
    }

    private static func process(
        _ asset: MediaAssetDownload,
        in targetDir: URL,
        using httpClient: HTTPClient,
        segmentLimit: Int,
        progress: @Sendable @escaping (MediaAssetProgress) async -> Void
    ) async -> MediaAssetDownloadOutcome {
        do {
            try Task.checkCancellation()
            await progress(
                MediaAssetProgress(index: asset.index, filenameStem: asset.filenameStem, fractionCompleted: 0.01)
            )
            switch asset.source {
            case let .image(url, preferredExtension):
                let filename = try await downloadImage(
                    from: url,
                    filenameStem: asset.filenameStem,
                    preferredExtension: preferredExtension,
                    in: targetDir,
                    using: httpClient
                )
                await progress(
                    MediaAssetProgress(index: asset.index, filenameStem: asset.filenameStem, fractionCompleted: 1)
                )
                return MediaAssetDownloadOutcome(index: asset.index, savedFilename: filename, error: nil)

            case let .videoPlaylist(playlistURL):
                let filename = try await downloadVideo(
                    playlistURL: playlistURL,
                    filenameStem: asset.filenameStem,
                    in: targetDir,
                    using: httpClient,
                    segmentLimit: segmentLimit,
                    progress: { fraction in
                        await progress(
                            MediaAssetProgress(
                                index: asset.index,
                                filenameStem: asset.filenameStem,
                                fractionCompleted: fraction
                            )
                        )
                    }
                )
                await progress(
                    MediaAssetProgress(index: asset.index, filenameStem: asset.filenameStem, fractionCompleted: 1)
                )
                return MediaAssetDownloadOutcome(index: asset.index, savedFilename: filename, error: nil)
            }
        } catch {
            let message = AppError.userMessage(from: error)
            AppLogger.performance.error("Media download failed for \(asset.filenameStem, privacy: .public): \(message, privacy: .public)")
            return MediaAssetDownloadOutcome(index: asset.index, savedFilename: nil, error: message)
        }
    }

    private static func downloadImage(
        from url: URL,
        filenameStem: String,
        preferredExtension: String?,
        in targetDir: URL,
        using httpClient: HTTPClient
    ) async throws -> String {
        var request = URLRequest(url: url)
        request.cachePolicy = .useProtocolCachePolicy
        request.timeoutInterval = 120

        try Task.checkCancellation()
        let (temporaryURL, httpResponse) = try await httpClient.download(for: request, source: "Media Export Image")
        _ = try validate(httpResponse)

        let fileExtension = preferredExtension ?? fileExtension(for: httpResponse, fallbackURL: url, defaultValue: "jpg")
        let filename = "\(filenameStem).\(fileExtension)"
        let destinationURL = targetDir.appendingPathComponent(filename)
        try moveDownloadedFile(from: temporaryURL, to: destinationURL)
        return filename
    }

    private static func downloadVideo(
        playlistURL: URL,
        filenameStem: String,
        in targetDir: URL,
        using httpClient: HTTPClient,
        segmentLimit: Int,
        progress: @Sendable @escaping (Double) async -> Void
    ) async throws -> String {
        try Task.checkCancellation()
        let resolvedPlaylistURL = try await resolvePlaylistURL(from: playlistURL, using: httpClient)
        let playlistContents = try await loadPlaylist(from: resolvedPlaylistURL, using: httpClient)
        let baseURL = resolvedPlaylistURL.deletingLastPathComponent()
        let initSegment = playlistInitSegment(from: playlistContents, baseURL: baseURL)
        let segments = playlistSegments(from: playlistContents, baseURL: baseURL, initSegment: initSegment)
        guard !segments.isEmpty else {
            throw MediaDownloadFailure.invalidPlaylist
        }
        await progress(0.05)

        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("media-download-\(filenameStem)-segments", isDirectory: true)
        try? FileManager.default.removeItem(at: tempDirectory)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        // Download init segment for fMP4 streams (required for valid output).
        var initSegmentData: Data?
        if let initSegment {
            do {
                initSegmentData = try await downloadInitSegment(initSegment, using: httpClient)
            } catch {
                AppLogger.performance.debug("Init segment download failed for \(filenameStem, privacy: .public): \(error.localizedDescription) — continuing without")
            }
        }
        if initSegmentData == nil {
            AppLogger.performance.debug("No init segment for \(filenameStem, privacy: .public) — stream may be TS-based")
        }

        let segmentFiles = await downloadVideoSegments(
            segments,
            to: tempDirectory,
            using: httpClient,
            concurrencyLimit: segmentLimit,
            progress: progress
        )

        guard segmentFiles.count == segments.count else {
            throw MediaDownloadFailure.missingSegments
        }
        await progress(0.92)

        let mp4URL = targetDir.appendingPathComponent("\(filenameStem).mp4")
        if let initSegmentData {
            try writeFragmentedMP4(
                initSegmentData: initSegmentData,
                segmentFiles: segmentFiles,
                segmentCount: segments.count,
                outputURL: mp4URL
            )
            await progress(0.99)
            return mp4URL.lastPathComponent
        }

        // TS playlists are first written directly to the target folder. If MP4
        // export fails, this transport stream remains as the successful download.
        let transportStreamURL = targetDir.appendingPathComponent("\(filenameStem).ts")
        if FileManager.default.fileExists(atPath: transportStreamURL.path) {
            try FileManager.default.removeItem(at: transportStreamURL)
        }
        FileManager.default.createFile(atPath: transportStreamURL.path, contents: nil)
        let outputHandle = try FileHandle(forWritingTo: transportStreamURL)

        for index in 0 ..< segments.count {
            try Task.checkCancellation()
            guard let fileURL = segmentFiles[index] else {
                try? outputHandle.close()
                try? FileManager.default.removeItem(at: transportStreamURL)
                throw URLError(.resourceUnavailable)
            }
            let data = try Data(contentsOf: fileURL, options: .mappedIfSafe)
            try outputHandle.write(contentsOf: data)
            try? FileManager.default.removeItem(at: fileURL)
        }
        try outputHandle.close()

        let concatSize = (try? FileManager.default.attributesOfItem(atPath: transportStreamURL.path)[.size] as? Int) ?? 0
        AppLogger.performance.debug("Concatenated \(concatSize) bytes for \(filenameStem, privacy: .public) (\(segments.count) segments, init=no)")

        // Use AVAssetExportSession with passthrough for robust remux.
        // Handles common TS timestamp discontinuities better than manual reader/writer.
        if FileManager.default.fileExists(atPath: mp4URL.path) {
            try FileManager.default.removeItem(at: mp4URL)
        }

        // Try passthrough first (no re-encoding), fall back to highest quality.
        let asset = AVAsset(url: transportStreamURL)
        var export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough)
        if export == nil {
            AppLogger.performance.debug("Passthrough unavailable for \(filenameStem, privacy: .public) — falling back to highest quality")
            export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality)
        }
        guard let export else {
            AppLogger.performance.error("Falling back to transport stream for \(filenameStem, privacy: .public): AVAssetExportSession could not be created")
            return transportStreamURL.lastPathComponent
        }
        export.outputURL = mp4URL
        export.outputFileType = .mp4

        await progress(0.96)
        await export.export()

        guard export.status == .completed else {
            try? FileManager.default.removeItem(at: mp4URL)
            let reason = export.error?.localizedDescription
            AppLogger.performance.error("Falling back to transport stream for \(filenameStem, privacy: .public): export status=\(export.status.rawValue), error=\(reason ?? "none", privacy: .public)")
            return transportStreamURL.lastPathComponent
        }

        try? FileManager.default.removeItem(at: transportStreamURL)
        await progress(0.99)
        return mp4URL.lastPathComponent
    }

    private static func downloadVideoSegments(
        _ segments: [VideoSegment],
        to tempDirectory: URL,
        using httpClient: HTTPClient,
        concurrencyLimit: Int,
        progress: @Sendable @escaping (Double) async -> Void
    ) async -> [Int: URL] {
        var segmentFiles: [Int: URL] = [:]
        var nextSegmentIndex = 0
        var completedSegmentCount = 0

        await withTaskGroup(of: (Int, URL?).self) { group in
            let initialCount = min(concurrencyLimit, segments.count)
            for _ in 0 ..< initialCount {
                let currentIndex = nextSegmentIndex
                let segment = segments[currentIndex]
                nextSegmentIndex += 1
                group.addTask {
                    let fileURL = try? await downloadSegment(
                        segment,
                        index: currentIndex,
                        tempDirectory: tempDirectory,
                        using: httpClient
                    )
                    return (currentIndex, fileURL)
                }
            }

            while let (segmentIndex, fileURL) = await group.next() {
                guard !Task.isCancelled else {
                    group.cancelAll()
                    return
                }
                if let fileURL {
                    segmentFiles[segmentIndex] = fileURL
                }
                completedSegmentCount += 1
                await progress(0.05 + (0.85 * Double(completedSegmentCount) / Double(segments.count)))

                if nextSegmentIndex < segments.count {
                    let currentIndex = nextSegmentIndex
                    let segment = segments[currentIndex]
                    nextSegmentIndex += 1
                    group.addTask {
                        let fileURL = try? await downloadSegment(
                            segment,
                            index: currentIndex,
                            tempDirectory: tempDirectory,
                            using: httpClient
                        )
                        return (currentIndex, fileURL)
                    }
                }
            }
        }

        return segmentFiles
    }

    private static func loadPlaylist(from url: URL, using httpClient: HTTPClient) async throws -> String {
        var request = URLRequest(url: url)
        request.cachePolicy = .useProtocolCachePolicy
        request.timeoutInterval = 60

        try Task.checkCancellation()
        let (data, httpResponse) = try await httpClient.data(for: request, source: "Media Playlist")
        _ = try validate(httpResponse)
        guard let playlist = String(data: data, encoding: .utf8) else {
            throw URLError(.cannotDecodeContentData)
        }
        return playlist
    }

    private static func resolvePlaylistURL(from url: URL, using httpClient: HTTPClient) async throws -> URL {
        let playlistContents = try await loadPlaylist(from: url, using: httpClient)
        let baseURL = url.deletingLastPathComponent()
        let lines = playlistContents
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }

        guard playlistContents.contains("#EXT-X-STREAM-INF") else {
            return url
        }

        var bestVariant: (bandwidth: Int, url: URL)?
        for (index, line) in lines.enumerated() where line.hasPrefix("#EXT-X-STREAM-INF") {
            guard index + 1 < lines.count else { continue }
            let candidateLine = lines[index + 1]
            guard !candidateLine.hasPrefix("#"),
                  !candidateLine.isEmpty,
                  let candidateURL = URL(string: candidateLine, relativeTo: baseURL)
            else {
                continue
            }

            let bandwidth = parseBandwidth(from: line) ?? 0
            if bestVariant == nil || bandwidth > bestVariant?.bandwidth ?? 0 {
                bestVariant = (bandwidth, candidateURL)
            }
        }

        guard let bestVariant else {
            throw MediaDownloadFailure.invalidPlaylist
        }

        return try await resolvePlaylistURL(from: bestVariant.url, using: httpClient)
    }

    private static func parseBandwidth(from streamInfoLine: String) -> Int? {
        streamInfoLine
            .components(separatedBy: ",")
            .first(where: { $0.contains("BANDWIDTH=") })?
            .components(separatedBy: "=")
            .last
            .flatMap(Int.init)
    }

    private static func playlistSegments(from playlist: String, baseURL: URL, initSegment: VideoInitSegment?) -> [VideoSegment] {
        var segments: [VideoSegment] = []
        var pendingByteRange: PendingMediaByteRange?
        var nextOffsetByURL: [URL: Int64] = [:]
        if let initSegment, let byteRange = initSegment.byteRange {
            nextOffsetByURL[initSegment.url] = byteRange.offset + byteRange.length
        }

        for line in playlist.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("#EXT-X-BYTERANGE:") {
                pendingByteRange = parsePendingByteRange(String(trimmed.dropFirst("#EXT-X-BYTERANGE:".count)))
                continue
            }
            guard !trimmed.hasPrefix("#"), !trimmed.isEmpty,
                  let url = URL(string: trimmed, relativeTo: baseURL)?.absoluteURL
            else {
                continue
            }

            let byteRange: MediaByteRange?
            if let pendingByteRange {
                let offset = pendingByteRange.offset ?? nextOffsetByURL[url] ?? 0
                byteRange = MediaByteRange(offset: offset, length: pendingByteRange.length)
                nextOffsetByURL[url] = offset + pendingByteRange.length
            } else {
                byteRange = nil
            }
            segments.append(VideoSegment(url: url, byteRange: byteRange))
            pendingByteRange = nil
        }

        return segments
    }

    /// Extracts the fMP4 initialization segment URL from an HLS playlist's
    /// `#EXT-X-MAP:URI="..."` directive. Returns `nil` for TS-based playlists.
    private static func playlistInitSegment(from playlist: String, baseURL: URL) -> VideoInitSegment? {
        for line in playlist.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("#EXT-X-MAP:"),
                  let uriValue = hlsAttributeValue(named: "URI", in: trimmed),
                  let url = URL(string: uriValue, relativeTo: baseURL)?.absoluteURL
            else { continue }

            let byteRange = hlsAttributeValue(named: "BYTERANGE", in: trimmed)
                .flatMap { parseExplicitByteRange($0) }
            return VideoInitSegment(url: url, byteRange: byteRange)
        }
        return nil
    }

    private static func parsePendingByteRange(_ value: String) -> PendingMediaByteRange? {
        let normalized = value.trimmingCharacters(in: CharacterSet(charactersIn: "\"'").union(.whitespaces))
        let parts = normalized.split(separator: "@", maxSplits: 1).map(String.init)
        guard let length = parts.first.flatMap(Int64.init), length > 0 else {
            return nil
        }
        return PendingMediaByteRange(length: length, offset: parts.dropFirst().first.flatMap(Int64.init))
    }

    private static func parseExplicitByteRange(_ value: String, defaultOffset: Int64 = 0) -> MediaByteRange? {
        guard let pending = parsePendingByteRange(value) else {
            return nil
        }
        let offset = pending.offset ?? defaultOffset
        return MediaByteRange(offset: offset, length: pending.length)
    }

    private static func hlsAttributeValue(named name: String, in line: String) -> String? {
        guard let nameRange = line.range(of: "\(name)=") else {
            return nil
        }
        var value = line[nameRange.upperBound...]
        if value.first == "\"" {
            value = value.dropFirst()
            guard let endIndex = value.firstIndex(of: "\"") else {
                return nil
            }
            return String(value[..<endIndex])
        }
        let endIndex = value.firstIndex(of: ",") ?? value.endIndex
        return String(value[..<endIndex])
    }

    private static func downloadInitSegment(_ segment: VideoInitSegment, using httpClient: HTTPClient) async throws -> Data {
        var request = URLRequest(url: segment.url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 60
        if let byteRange = segment.byteRange {
            request.setValue(byteRange.headerValue, forHTTPHeaderField: "Range")
        }
        let (data, httpResponse) = try await httpClient.data(for: request, source: "Media Init Segment")
        _ = try validate(httpResponse)
        return data
    }

    private static func downloadSegment(
        _ segment: VideoSegment,
        index: Int,
        tempDirectory: URL,
        using httpClient: HTTPClient
    ) async throws -> URL {
        var request = URLRequest(url: segment.url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 120
        if let byteRange = segment.byteRange {
            request.setValue(byteRange.headerValue, forHTTPHeaderField: "Range")
        }

        try Task.checkCancellation()
        let (temporaryURL, httpResponse) = try await httpClient.download(for: request, source: "Media Segment Download")
        _ = try validate(httpResponse)

        let fileURL = tempDirectory.appendingPathComponent(String(format: "%05d.ts", index))
        try moveDownloadedFile(from: temporaryURL, to: fileURL)
        return fileURL
    }

    private static func writeFragmentedMP4(
        initSegmentData: Data,
        segmentFiles: [Int: URL],
        segmentCount: Int,
        outputURL: URL
    ) throws {
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }
        FileManager.default.createFile(atPath: outputURL.path, contents: nil)

        let outputHandle = try FileHandle(forWritingTo: outputURL)
        var completed = false
        defer {
            try? outputHandle.close()
            if !completed {
                try? FileManager.default.removeItem(at: outputURL)
            }
        }

        try outputHandle.write(contentsOf: initSegmentData)
        for index in 0 ..< segmentCount {
            guard let fileURL = segmentFiles[index] else {
                throw URLError(.resourceUnavailable)
            }
            let data = try Data(contentsOf: fileURL, options: .mappedIfSafe)
            try outputHandle.write(contentsOf: data)
            try? FileManager.default.removeItem(at: fileURL)
        }
        completed = true
    }

    private static func validate(_ response: URLResponse) throws -> HTTPURLResponse {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw MediaDownloadFailure.nonHTTPResponse
        }
        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            throw MediaDownloadFailure.invalidStatusCode(httpResponse.statusCode)
        }
        return httpResponse
    }

    private static func moveDownloadedFile(from sourceURL: URL, to destinationURL: URL) throws {
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }
        try FileManager.default.moveItem(at: sourceURL, to: destinationURL)
    }

    private static func fileExtension(for response: URLResponse, fallbackURL: URL, defaultValue: String) -> String {
        if let mimeType = response.mimeType {
            switch mimeType.lowercased() {
            case "image/png":
                return "png"
            case "image/webp":
                return "webp"
            case "image/gif":
                return "gif"
            case "image/jpeg", "image/jpg":
                return "jpg"
            case "video/mp4":
                return "mp4"
            default:
                break
            }
        }

        let urlExtension = fallbackURL.pathExtension.lowercased()
        if !urlExtension.isEmpty {
            return urlExtension == "jpeg" ? "jpg" : urlExtension
        }

        return defaultValue
    }
}
