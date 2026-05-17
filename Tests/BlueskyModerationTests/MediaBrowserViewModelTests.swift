@testable import BlueskyModeration
import XCTest

@MainActor
final class MediaBrowserViewModelTests: XCTestCase {
    func testInitialLoadOnlyFetchesFirstPageUntilLoadMore() async {
        let viewModel = MediaBrowserViewModel(did: "did:plc:test")
        let client = MockMediaFeedClient(
            pages: [
                RichFeedResponse(
                    cursor: "page-2",
                    feed: [
                        RichFeedEntry(
                            post: RichPost(
                                uri: "at://post/1",
                                cid: nil,
                                author: nil,
                                record: RichRecord(text: "First", createdAt: "2024-01-01T00:00:00Z"),
                                embed: makeImageEmbed(fullsize: "https://cdn.example/full-1.jpg", thumb: "https://cdn.example/thumb-1.jpg"),
                                viewer: nil,
                                replyCount: nil,
                                repostCount: nil,
                                likeCount: nil,
                                indexedAt: "2024-01-01T00:00:00Z"
                            ),
                            reply: nil
                        ),
                    ]
                ),
                RichFeedResponse(
                    cursor: nil,
                    feed: [
                        RichFeedEntry(
                            post: RichPost(
                                uri: "at://post/2",
                                cid: nil,
                                author: nil,
                                record: RichRecord(text: "Second", createdAt: "2024-01-02T00:00:00Z"),
                                embed: makeVideoEmbed(thumbnail: "https://cdn.example/video-thumb.jpg", playlist: "https://cdn.example/video.m3u8"),
                                viewer: nil,
                                replyCount: nil,
                                repostCount: nil,
                                likeCount: nil,
                                indexedAt: "2024-01-02T00:00:00Z"
                            ),
                            reply: nil
                        ),
                    ]
                ),
            ]
        )

        await viewModel.load(account: makeAccount(), appPassword: "pw", using: client)

        XCTAssertEqual(client.requests.count, 1)
        XCTAssertNil(client.requests.first ?? "unexpected")
        XCTAssertEqual(viewModel.items.count, 1)
        XCTAssertEqual(viewModel.imageCount, 1)
        XCTAssertEqual(viewModel.videoCount, 0)
        XCTAssertTrue(viewModel.hasMore)

        await viewModel.loadMore(account: makeAccount(), appPassword: "pw", using: client)

        XCTAssertEqual(client.requests, [nil, "page-2"])
        XCTAssertEqual(viewModel.items.count, 2)
        XCTAssertEqual(viewModel.imageCount, 1)
        XCTAssertEqual(viewModel.videoCount, 1)
        XCTAssertFalse(viewModel.hasMore)
    }
}

@MainActor
private final class MockMediaFeedClient: MediaFeedFetching {
    private let pages: [RichFeedResponse]
    private var nextPageIndex = 0
    private(set) var requests: [String?] = []

    init(pages: [RichFeedResponse]) {
        self.pages = pages
    }

    func fetchRichFeed(did _: String, cursor: String?, account _: AppAccount, appPassword _: String?) async throws -> RichFeedResponse {
        requests.append(cursor)
        defer { nextPageIndex += 1 }
        return pages[nextPageIndex]
    }
}

private func makeImageEmbed(fullsize: String, thumb: String) -> RichEmbed? {
    try? JSONDecoder().decode(
        RichEmbed.self,
        from: Data(
            """
            {
              "$type": "app.bsky.embed.images#view",
              "images": [
                {
                  "fullsize": "\(fullsize)",
                  "thumb": "\(thumb)",
                  "alt": "image"
                }
              ]
            }
            """.utf8
        )
    )
}

private func makeVideoEmbed(thumbnail: String, playlist: String) -> RichEmbed? {
    try? JSONDecoder().decode(
        RichEmbed.self,
        from: Data(
            """
            {
              "$type": "app.bsky.embed.video#view",
              "thumbnail": "\(thumbnail)",
              "playlist": "\(playlist)"
            }
            """.utf8
        )
    )
}
