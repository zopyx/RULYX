import Foundation
@testable import RULYX
import XCTest

final class MediaDownloadServiceTests: XCTestCase {
    private var service: MediaDownloadService!
    private var session: URLSession!
    private var tempDirectory: URL!

    override func setUp() {
        super.setUp()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        session = URLSession(configuration: config)
        service = MediaDownloadService(session: session)
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        session.invalidateAndCancel()
        session = nil
        service = nil
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        tempDirectory = nil
        super.tearDown()
    }

    func testDownloadImagesWritesFileAndReportsProgress() async throws {
        let progress = Locked<[(Int, Int)]>([])
        let assetProgress = Locked<[Double]>([])

        MockURLProtocol.requestHandler = { request in
            let response = try HTTPURLResponse(
                url: XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "image/png"]
            )!
            return (response, Data("png-data".utf8))
        }

        let assets = try [
            MediaAssetDownload(
                index: 0,
                filenameStem: "image-1",
                source: .image(url: XCTUnwrap(URL(string: "https://example.com/image")), preferredExtension: nil)
            ),
        ]

        let results = await service.downloadImages(
            assets,
            to: tempDirectory,
            progress: { completed, total, _ in
                progress.withLock { $0.append((completed, total)) }
            },
            assetProgress: { update in
                assetProgress.withLock { $0.append(update.fractionCompleted) }
            }
        )

        let progressUpdates = progress.withLock { $0 }
        XCTAssertEqual(progressUpdates.count, 1)
        XCTAssertEqual(progressUpdates.first?.0, 1)
        XCTAssertEqual(progressUpdates.first?.1, 1)
        let assetProgressUpdates = assetProgress.withLock { $0 }
        XCTAssertEqual(assetProgressUpdates.first, 0.01)
        XCTAssertEqual(assetProgressUpdates.last, 1)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.savedFilename, "image-1.png")
        let fileURL = tempDirectory.appendingPathComponent("image-1.png")
        XCTAssertEqual(try String(contentsOf: fileURL), "png-data")
    }

    func testLargeImageBatchCompletesEveryAssetAndReportsMonotonicCounts() async throws {
        let progressUpdates = Locked<[(completed: Int, total: Int)]>([])
        let assetCount = 200

        MockURLProtocol.requestHandler = { request in
            let response = try HTTPURLResponse(
                url: XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "image/jpeg"]
            )!
            return (response, Data("jpeg-data".utf8))
        }

        let assets = try (0 ..< assetCount).map { index in
            MediaAssetDownload(
                index: index,
                filenameStem: "image-\(index)",
                source: .image(
                    url: try XCTUnwrap(URL(string: "https://example.com/image-\(index)")),
                    preferredExtension: nil
                )
            )
        }

        let results = await service.downloadImages(assets, to: tempDirectory) { completed, total, _ in
            progressUpdates.withLock { $0.append((completed, total)) }
        }

        XCTAssertEqual(results.count, assetCount)
        XCTAssertTrue(results.allSatisfy { $0.savedFilename != nil && $0.error == nil })
        let updates = progressUpdates.withLock { $0 }
        XCTAssertEqual(updates.map(\.completed), Array(1 ... assetCount))
        XCTAssertTrue(updates.allSatisfy { $0.total == assetCount })
    }

    func testDownloadMediaSelectsHighestBandwidthVariant() async throws {
        let requestedURLs = Locked<[String]>([])

        MockURLProtocol.requestHandler = { request in
            let url = try XCTUnwrap(request.url)
            requestedURLs.withLock { $0.append(url.absoluteString) }

            let body: Data
            let headers: [String: String]

            switch url.absoluteString {
            case "https://video.example/master.m3u8":
                body = Data(
                    """
                    #EXTM3U
                    #EXT-X-STREAM-INF:BANDWIDTH=100
                    low.m3u8
                    #EXT-X-STREAM-INF:BANDWIDTH=200
                    high.m3u8
                    """.utf8
                )
                headers = ["Content-Type": "application/x-mpegURL"]
            case "https://video.example/high.m3u8":
                body = Data(
                    """
                    #EXTM3U
                    #EXTINF:2.0,
                    second.ts
                    #EXTINF:2.0,
                    first.ts
                    """.utf8
                )
                headers = ["Content-Type": "application/x-mpegURL"]
            case "https://video.example/first.ts":
                body = Data("first".utf8)
                headers = ["Content-Type": "video/mp2t"]
            case "https://video.example/second.ts":
                body = Data("second".utf8)
                headers = ["Content-Type": "video/mp2t"]
            default:
                throw URLError(.badURL)
            }

            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: headers)!
            return (response, body)
        }

        let assets = try [
            MediaAssetDownload(
                index: 0,
                filenameStem: "media-1",
                source: .videoPlaylist(XCTUnwrap(URL(string: "https://video.example/master.m3u8")))
            ),
        ]

        let results = await service.downloadMedia(assets, to: tempDirectory) { _, _, _ in }

        // Verify highest bandwidth variant was selected.
        XCTAssertTrue(requestedURLs.withLock { $0.contains("https://video.example/high.m3u8") })
        XCTAssertFalse(requestedURLs.withLock { $0.contains("https://video.example/low.m3u8") })

        // Mock data isn't valid TS for AVFoundation remux, so the downloader
        // preserves the concatenated transport stream instead of failing.
        XCTAssertEqual(results.first?.savedFilename, "media-1.ts")
        XCTAssertNil(results.first?.error)
        let outputURL = tempDirectory.appendingPathComponent("media-1.ts")
        XCTAssertEqual(try String(contentsOf: outputURL), "secondfirst")
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: tempDirectory.appendingPathComponent("media-1.mp4").path))
    }

    func testDownloadMediaAssemblesFMP4ByteRangesWithoutRemux() async throws {
        let requestedRanges = Locked<[String: [String]]>([:])
        let mediaData = Data("init-fragment-one-fragment-two".utf8)

        MockURLProtocol.requestHandler = { request in
            let url = try XCTUnwrap(request.url)
            if let range = request.value(forHTTPHeaderField: "Range") {
                requestedRanges.withLock { ranges in
                    ranges[url.absoluteString, default: []].append(range)
                }
            }

            let body: Data
            let headers: [String: String]
            let statusCode: Int

            switch url.absoluteString {
            case "https://video.example/playlist.m3u8":
                body = Data(
                    """
                    #EXTM3U
                    #EXT-X-VERSION:7
                    #EXT-X-MAP:URI="media.mp4",BYTERANGE="4@0"
                    #EXTINF:2.0,
                    #EXT-X-BYTERANGE:13@5
                    media.mp4
                    #EXTINF:2.0,
                    #EXT-X-BYTERANGE:12
                    media.mp4
                    #EXT-X-ENDLIST
                    """.utf8
                )
                headers = ["Content-Type": "application/x-mpegURL"]
                statusCode = 200
            case "https://video.example/media.mp4":
                let range = try XCTUnwrap(request.value(forHTTPHeaderField: "Range"))
                body = try Self.bytes(from: mediaData, rangeHeader: range)
                headers = ["Content-Type": "video/mp4"]
                statusCode = 206
            default:
                throw URLError(.badURL)
            }

            let response = HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: nil, headerFields: headers)!
            return (response, body)
        }

        let assets = try [
            MediaAssetDownload(
                index: 0,
                filenameStem: "media-1",
                source: .videoPlaylist(XCTUnwrap(URL(string: "https://video.example/playlist.m3u8")))
            ),
        ]

        let results = await service.downloadMedia(assets, to: tempDirectory) { _, _, _ in }

        XCTAssertEqual(results.first?.savedFilename, "media-1.mp4")
        XCTAssertNil(results.first?.error)
        let outputURL = tempDirectory.appendingPathComponent("media-1.mp4")
        XCTAssertEqual(try String(contentsOf: outputURL), "initfragment-one-fragment-two")
        XCTAssertFalse(FileManager.default.fileExists(atPath: tempDirectory.appendingPathComponent("media-1.ts").path))

        let mediaRanges = requestedRanges.withLock { $0["https://video.example/media.mp4"] ?? [] }
        XCTAssertEqual(Set(mediaRanges), Set(["bytes=0-3", "bytes=5-17", "bytes=18-29"]))
    }

    func testDownloadMediaSupportsImplicitFMP4ByteRangeOffsets() async throws {
        let requestedRanges = Locked<[String]>([])
        let mediaData = Data("initfragment-onefragment-two".utf8)

        MockURLProtocol.requestHandler = { request in
            let url = try XCTUnwrap(request.url)

            let body: Data
            let headers: [String: String]
            let statusCode: Int

            switch url.absoluteString {
            case "https://video.example/playlist.m3u8":
                body = Data(
                    """
                    #EXTM3U
                    #EXT-X-VERSION:7
                    #EXT-X-MAP:URI="media.mp4",BYTERANGE="4"
                    #EXTINF:2.0,
                    #EXT-X-BYTERANGE:12
                    media.mp4
                    #EXTINF:2.0,
                    #EXT-X-BYTERANGE:12
                    media.mp4
                    #EXT-X-ENDLIST
                    """.utf8
                )
                headers = ["Content-Type": "application/x-mpegURL"]
                statusCode = 200
            case "https://video.example/media.mp4":
                let range = try XCTUnwrap(request.value(forHTTPHeaderField: "Range"))
                requestedRanges.withLock { $0.append(range) }
                body = try Self.bytes(from: mediaData, rangeHeader: range)
                headers = ["Content-Type": "video/mp4"]
                statusCode = 206
            default:
                throw URLError(.badURL)
            }

            let response = HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: nil, headerFields: headers)!
            return (response, body)
        }

        let assets = try [
            MediaAssetDownload(
                index: 0,
                filenameStem: "media-implicit",
                source: .videoPlaylist(XCTUnwrap(URL(string: "https://video.example/playlist.m3u8")))
            ),
        ]

        let results = await service.downloadMedia(assets, to: tempDirectory) { _, _, _ in }

        XCTAssertEqual(results.first?.savedFilename, "media-implicit.mp4")
        XCTAssertNil(results.first?.error)
        let outputURL = tempDirectory.appendingPathComponent("media-implicit.mp4")
        XCTAssertEqual(try String(contentsOf: outputURL), "initfragment-onefragment-two")

        XCTAssertEqual(Set(requestedRanges.withLock { $0 }), Set(["bytes=0-3", "bytes=4-15", "bytes=16-27"]))
    }

    func testDownloadMediaReportsInvalidServerResponse() async throws {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 500,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data())
        }

        let assets = try [
            MediaAssetDownload(
                index: 0,
                filenameStem: "image-1",
                source: .image(url: XCTUnwrap(URL(string: "https://example.com/bad.jpg")), preferredExtension: nil)
            ),
        ]

        let results = await service.downloadMedia(assets, to: tempDirectory) { _, _, _ in }

        XCTAssertNil(results.first?.savedFilename)
        XCTAssertFalse(results.first?.error?.isEmpty ?? true)
    }

    private static func bytes(from data: Data, rangeHeader: String) throws -> Data {
        let prefix = "bytes="
        guard rangeHeader.hasPrefix(prefix) else {
            throw URLError(.badServerResponse)
        }
        let parts = rangeHeader.dropFirst(prefix.count).split(separator: "-", maxSplits: 1)
        guard parts.count == 2,
              let start = Int(parts[0]),
              let end = Int(parts[1]),
              start >= 0,
              end >= start,
              end < data.count
        else {
            throw URLError(.badServerResponse)
        }
        return data.subdata(in: start ..< end + 1)
    }
}

private final class Locked<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value

    init(_ value: Value) {
        self.value = value
    }

    func withLock<Result>(_ operation: (inout Value) -> Result) -> Result {
        lock.lock()
        defer { lock.unlock() }
        return operation(&value)
    }
}
