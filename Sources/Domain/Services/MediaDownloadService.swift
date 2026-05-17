import AVFoundation
import Foundation

private enum MediaDownloadFailure: LocalizedError {
    case nonHTTPResponse
    case invalidStatusCode(Int)
    case invalidPlaylist
    case missingSegments
    case remuxFailed

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
        case .remuxFailed:
            "Video remux failed."
        }
    }
}

struct MediaAssetDownload {
    let index: Int
    let filenameStem: String
    let source: MediaAssetSource
}

enum MediaAssetSource {
    case image(url: URL, preferredExtension: String?)
    case videoPlaylist(URL)
}

struct MediaAssetDownloadOutcome {
    let index: Int
    let savedFilename: String?
    let error: String?
}

actor MediaDownloadService {
    static let shared = MediaDownloadService()

    private let imageDownloadConcurrency = 8
    private let mediaItemDownloadConcurrency = 4
    private let videoSegmentDownloadConcurrency = 6

    private let downloadSession: URLSession

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
    }

    func downloadImages(
        _ assets: [MediaAssetDownload],
        to targetDir: URL,
        progress: @Sendable @escaping (_ completed: Int, _ total: Int, _ latestResult: MediaAssetDownloadOutcome) async -> Void
    ) async -> [MediaAssetDownloadOutcome] {
        await download(assets, to: targetDir, concurrencyLimit: imageDownloadConcurrency, progress: progress)
    }

    func downloadMedia(
        _ assets: [MediaAssetDownload],
        to targetDir: URL,
        progress: @Sendable @escaping (_ completed: Int, _ total: Int, _ latestResult: MediaAssetDownloadOutcome) async -> Void
    ) async -> [MediaAssetDownloadOutcome] {
        await download(assets, to: targetDir, concurrencyLimit: mediaItemDownloadConcurrency, progress: progress)
    }

    private func download(
        _ assets: [MediaAssetDownload],
        to targetDir: URL,
        concurrencyLimit: Int,
        progress: @Sendable @escaping (_ completed: Int, _ total: Int, _ latestResult: MediaAssetDownloadOutcome) async -> Void
    ) async -> [MediaAssetDownloadOutcome] {
        guard !assets.isEmpty else { return [] }

        try? FileManager.default.createDirectory(at: targetDir, withIntermediateDirectories: true)

        var results: [MediaAssetDownloadOutcome] = []
        results.reserveCapacity(assets.count)

        var nextAssetIndex = 0
        var completed = 0
        let session = downloadSession
        let segmentLimit = videoSegmentDownloadConcurrency

        await withTaskGroup(of: MediaAssetDownloadOutcome.self) { group in
            let initialCount = min(concurrencyLimit, assets.count)
            for _ in 0 ..< initialCount {
                let asset = assets[nextAssetIndex]
                nextAssetIndex += 1
                group.addTask {
                    await Self.process(asset, in: targetDir, using: session, segmentLimit: segmentLimit)
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
                    group.addTask {
                        await Self.process(asset, in: targetDir, using: session, segmentLimit: segmentLimit)
                    }
                }
            }
        }

        return results.sorted { $0.index < $1.index }
    }

    private static func process(
        _ asset: MediaAssetDownload,
        in targetDir: URL,
        using session: URLSession,
        segmentLimit: Int
    ) async -> MediaAssetDownloadOutcome {
        do {
            try Task.checkCancellation()
            switch asset.source {
            case let .image(url, preferredExtension):
                let filename = try await downloadImage(
                    from: url,
                    filenameStem: asset.filenameStem,
                    preferredExtension: preferredExtension,
                    in: targetDir,
                    using: session
                )
                return MediaAssetDownloadOutcome(index: asset.index, savedFilename: filename, error: nil)

            case let .videoPlaylist(playlistURL):
                let filename = try await downloadVideo(
                    playlistURL: playlistURL,
                    filenameStem: asset.filenameStem,
                    in: targetDir,
                    using: session,
                    segmentLimit: segmentLimit
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
        using session: URLSession
    ) async throws -> String {
        var request = URLRequest(url: url)
        request.cachePolicy = .useProtocolCachePolicy
        request.timeoutInterval = 120

        try Task.checkCancellation()
        let (temporaryURL, response) = try await session.download(for: request)
        _ = try validate(response)

        let fileExtension = preferredExtension ?? fileExtension(for: response, fallbackURL: url, defaultValue: "jpg")
        let filename = "\(filenameStem).\(fileExtension)"
        let destinationURL = targetDir.appendingPathComponent(filename)
        try moveDownloadedFile(from: temporaryURL, to: destinationURL)
        return filename
    }

    private static func downloadVideo(
        playlistURL: URL,
        filenameStem: String,
        in targetDir: URL,
        using session: URLSession,
        segmentLimit: Int
    ) async throws -> String {
        try Task.checkCancellation()
        let resolvedPlaylistURL = try await resolvePlaylistURL(from: playlistURL, using: session)
        let playlistContents = try await loadPlaylist(from: resolvedPlaylistURL, using: session)
        let segmentURLs = playlistSegmentURLs(from: playlistContents, baseURL: resolvedPlaylistURL.deletingLastPathComponent())
        guard !segmentURLs.isEmpty else {
            throw MediaDownloadFailure.invalidPlaylist
        }

        let tempDirectory = targetDir.appendingPathComponent(".\(filenameStem)-segments", isDirectory: true)
        try? FileManager.default.removeItem(at: tempDirectory)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        var segmentFiles: [Int: URL] = [:]
        var nextSegmentIndex = 0

        await withTaskGroup(of: (Int, URL?).self) { group in
            let initialCount = min(segmentLimit, segmentURLs.count)
            for _ in 0 ..< initialCount {
                let currentIndex = nextSegmentIndex
                let segmentURL = segmentURLs[currentIndex]
                nextSegmentIndex += 1
                group.addTask {
                    let fileURL = try? await downloadSegment(
                        from: segmentURL,
                        index: currentIndex,
                        tempDirectory: tempDirectory,
                        using: session
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

                if nextSegmentIndex < segmentURLs.count {
                    let currentIndex = nextSegmentIndex
                    let segmentURL = segmentURLs[currentIndex]
                    nextSegmentIndex += 1
                    group.addTask {
                        let fileURL = try? await downloadSegment(
                            from: segmentURL,
                            index: currentIndex,
                            tempDirectory: tempDirectory,
                            using: session
                        )
                        return (currentIndex, fileURL)
                    }
                }
            }
        }

        guard segmentFiles.count == segmentURLs.count else {
            throw MediaDownloadFailure.missingSegments
        }

        let transportStreamURL = targetDir.appendingPathComponent("\(filenameStem).ts")
        if FileManager.default.fileExists(atPath: transportStreamURL.path) {
            try FileManager.default.removeItem(at: transportStreamURL)
        }
        FileManager.default.createFile(atPath: transportStreamURL.path, contents: nil)

        let outputHandle = try FileHandle(forWritingTo: transportStreamURL)
        defer { try? outputHandle.close() }

        for index in 0 ..< segmentURLs.count {
            try Task.checkCancellation()
            guard let fileURL = segmentFiles[index] else {
                throw URLError(.resourceUnavailable)
            }
            let data = try Data(contentsOf: fileURL, options: .mappedIfSafe)
            try outputHandle.write(contentsOf: data)
            try? FileManager.default.removeItem(at: fileURL)
        }

        let mp4URL = targetDir.appendingPathComponent("\(filenameStem).mp4")
        if await VideoRemuxer.remuxToMP4(source: transportStreamURL, destination: mp4URL) {
            try? FileManager.default.removeItem(at: transportStreamURL)
            return mp4URL.lastPathComponent
        }

        AppLogger.performance.error("Falling back to transport stream for \(filenameStem, privacy: .public) after remux failure.")
        return transportStreamURL.lastPathComponent
    }

    private static func loadPlaylist(from url: URL, using session: URLSession) async throws -> String {
        var request = URLRequest(url: url)
        request.cachePolicy = .useProtocolCachePolicy
        request.timeoutInterval = 60

        try Task.checkCancellation()
        let (data, response) = try await session.data(for: request)
        _ = try validate(response)
        guard let playlist = String(data: data, encoding: .utf8) else {
            throw URLError(.cannotDecodeContentData)
        }
        return playlist
    }

    private static func resolvePlaylistURL(from url: URL, using session: URLSession) async throws -> URL {
        let playlistContents = try await loadPlaylist(from: url, using: session)
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

        return try await resolvePlaylistURL(from: bestVariant.url, using: session)
    }

    private static func parseBandwidth(from streamInfoLine: String) -> Int? {
        streamInfoLine
            .components(separatedBy: ",")
            .first(where: { $0.contains("BANDWIDTH=") })?
            .components(separatedBy: "=")
            .last
            .flatMap(Int.init)
    }

    private static func playlistSegmentURLs(from playlist: String, baseURL: URL) -> [URL] {
        playlist
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .compactMap { line in
                guard !line.hasPrefix("#"), !line.isEmpty else { return nil }
                return URL(string: line, relativeTo: baseURL)
            }
    }

    private static func downloadSegment(
        from url: URL,
        index: Int,
        tempDirectory: URL,
        using session: URLSession
    ) async throws -> URL {
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 120

        try Task.checkCancellation()
        let (temporaryURL, response) = try await session.download(for: request)
        _ = try validate(response)

        let fileURL = tempDirectory.appendingPathComponent(String(format: "%05d.ts", index))
        try moveDownloadedFile(from: temporaryURL, to: fileURL)
        return fileURL
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

private enum VideoRemuxer {
    private final class Context: @unchecked Sendable {
        let reader: AVAssetReader
        let writer: AVAssetWriter
        let pairs: [(AVAssetReaderTrackOutput, AVAssetWriterInput)]

        init(reader: AVAssetReader, writer: AVAssetWriter, pairs: [(AVAssetReaderTrackOutput, AVAssetWriterInput)]) {
            self.reader = reader
            self.writer = writer
            self.pairs = pairs
        }
    }

    static func remuxToMP4(source: URL, destination: URL) async -> Bool {
        if FileManager.default.fileExists(atPath: destination.path) {
            try? FileManager.default.removeItem(at: destination)
        }

        let asset = AVAsset(url: source)
        guard let reader = try? AVAssetReader(asset: asset),
              let writer = try? AVAssetWriter(outputURL: destination, fileType: .mp4)
        else {
            return false
        }

        let pairs = await makeTrackPairs(asset: asset, reader: reader, writer: writer)
        guard !pairs.isEmpty, reader.startReading(), writer.startWriting() else {
            return false
        }

        writer.startSession(atSourceTime: .zero)
        let context = Context(reader: reader, writer: writer, pairs: pairs)

        await withCheckedContinuation { continuation in
            let queue = DispatchQueue(label: "media-remux", qos: .utility)
            queue.async {
                while context.reader.status == .reading {
                    var copiedSample = false
                    for (output, input) in context.pairs where input.isReadyForMoreMediaData {
                        if let sample = output.copyNextSampleBuffer() {
                            copiedSample = true
                            input.append(sample)
                        }
                    }
                    if !copiedSample {
                        break
                    }
                }

                for (_, input) in context.pairs {
                    input.markAsFinished()
                }

                context.writer.finishWriting {
                    continuation.resume()
                }
            }
        }

        return context.writer.status == .completed
    }

    private static func makeTrackPairs(
        asset: AVAsset,
        reader: AVAssetReader,
        writer: AVAssetWriter
    ) async -> [(AVAssetReaderTrackOutput, AVAssetWriterInput)] {
        var pairs: [(AVAssetReaderTrackOutput, AVAssetWriterInput)] = []

        do {
            let videoTracks = try await asset.loadTracks(withMediaType: .video)
            appendTrackPairs(for: videoTracks, mediaType: .video, reader: reader, writer: writer, into: &pairs)
        } catch {}

        do {
            let audioTracks = try await asset.loadTracks(withMediaType: .audio)
            appendTrackPairs(for: audioTracks, mediaType: .audio, reader: reader, writer: writer, into: &pairs)
        } catch {}

        return pairs
    }

    private static func appendTrackPairs(
        for tracks: [AVAssetTrack],
        mediaType: AVMediaType,
        reader: AVAssetReader,
        writer: AVAssetWriter,
        into pairs: inout [(AVAssetReaderTrackOutput, AVAssetWriterInput)]
    ) {
        for track in tracks {
            let input = AVAssetWriterInput(mediaType: mediaType, outputSettings: nil)
            input.expectsMediaDataInRealTime = false
            guard writer.canAdd(input) else { continue }

            let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
            guard reader.canAdd(output) else { continue }

            writer.add(input)
            reader.add(output)
            pairs.append((output, input))
        }
    }
}
