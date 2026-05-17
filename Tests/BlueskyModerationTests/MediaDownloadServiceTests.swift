@testable import BlueskyModeration
import Foundation
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

        let results = await service.downloadImages(assets, to: tempDirectory) { completed, total, _ in
            progress.withLock { $0.append((completed, total)) }
        }

        let progressUpdates = progress.withLock { $0 }
        XCTAssertEqual(progressUpdates.count, 1)
        XCTAssertEqual(progressUpdates.first?.0, 1)
        XCTAssertEqual(progressUpdates.first?.1, 1)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.savedFilename, "image-1.png")
        let fileURL = tempDirectory.appendingPathComponent("image-1.png")
        XCTAssertEqual(try String(contentsOf: fileURL), "png-data")
    }

    func testDownloadMediaSelectsHighestBandwidthVariantAndPreservesSegmentOrder() async throws {
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

        XCTAssertEqual(results.first?.savedFilename, "media-1.ts")
        XCTAssertTrue(requestedURLs.withLock { $0.contains("https://video.example/high.m3u8") })
        XCTAssertFalse(requestedURLs.withLock { $0.contains("https://video.example/low.m3u8") })

        let outputURL = tempDirectory.appendingPathComponent("media-1.ts")
        XCTAssertEqual(try String(contentsOf: outputURL), "firstsecond")
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
