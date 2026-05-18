@testable import RULYX
import XCTest

@MainActor
final class FeedTimelineViewModelTests: XCTestCase {
    private var viewModel: FeedTimelineViewModel!
    private var client: MockTimelineClient!
    private let account = AppAccount(handle: "test.bsky.social")
    private let appPassword = "password"

    override func setUp() {
        super.setUp()
        client = MockTimelineClient()
        viewModel = FeedTimelineViewModel()
        UserDefaults.standard.removeObject(forKey: "mutedWords")
    }

    override func tearDown() {
        super.tearDown()
        viewModel.stopPolling()
        client = nil
        viewModel = nil
    }

    func testInitialState() {
        XCTAssertEqual(viewModel.state, .initialLoading)
        XCTAssertTrue(viewModel.entries.isEmpty)
        XCTAssertEqual(viewModel.newPostCount, 0)
    }

    func testLoadTimelinePopulatesEntries() async {
        client.timelineResult = .success(makeResponse(cursor: "c1", uris: ["at://post/1", "at://post/2"]))
        await viewModel.loadTimeline(account: account, appPassword: appPassword, using: client)
        XCTAssertEqual(viewModel.entries.count, 2)
        XCTAssertEqual(viewModel.state, .loaded)
    }

    func testLoadTimelineEmpty() async {
        client.timelineResult = .success(makeResponse(cursor: nil, uris: []))
        await viewModel.loadTimeline(account: account, appPassword: appPassword, using: client)
        XCTAssertTrue(viewModel.entries.isEmpty)
        XCTAssertEqual(viewModel.state, .empty)
    }

    func testLoadTimelineFailure() async {
        client.timelineResult = .failure(BlueskyAPIError.server("Down"))
        await viewModel.loadTimeline(account: account, appPassword: appPassword, using: client)
        XCTAssertTrue(viewModel.state.errorMessage?.contains("Down") == true)
    }

    func testLoadTimelineSkipsIfAlreadyLoaded() async {
        client.timelineResult = .success(makeResponse(cursor: "c1", uris: ["at://post/1"]))
        await viewModel.loadTimeline(account: account, appPassword: appPassword, using: client)
        client.timelineResult = .success(makeResponse(cursor: "c2", uris: ["at://post/2"]))
        await viewModel.loadTimeline(account: account, appPassword: appPassword, using: client)
        XCTAssertEqual(viewModel.entries.count, 1)
    }

    func testRefreshReplacesEntries() async {
        client.timelineResult = .success(makeResponse(cursor: "c1", uris: ["at://post/1"]))
        await viewModel.loadTimeline(account: account, appPassword: appPassword, using: client)
        client.timelineResult = .success(makeResponse(cursor: "c2", uris: ["at://post/2"]))
        await viewModel.refresh(account: account, appPassword: appPassword, using: client)
        XCTAssertEqual(viewModel.entries.count, 1)
        XCTAssertEqual(viewModel.entries[0].post.uri, "at://post/2")
    }

    func testRefreshSetsNewPostCount() async {
        client.timelineResult = .success(makeResponse(cursor: "c1", uris: ["at://post/a"]))
        await viewModel.loadTimeline(account: account, appPassword: appPassword, using: client)
        client.timelineResult = .success(makeResponse(cursor: "c2", uris: ["at://post/a"]))
        await viewModel.refresh(account: account, appPassword: appPassword, using: client)
        client.timelineResult = .success(makeResponse(cursor: "c3", uris: ["at://post/a", "at://post/b"]))
        await viewModel.refresh(account: account, appPassword: appPassword, using: client)
        XCTAssertEqual(viewModel.newPostCount, 1)
    }

    func testRefreshFailureRestoresPreviousState() async {
        client.timelineResult = .success(makeResponse(cursor: "c1", uris: ["at://post/1"]))
        await viewModel.loadTimeline(account: account, appPassword: appPassword, using: client)
        client.timelineResult = .failure(BlueskyAPIError.server("Down"))
        await viewModel.refresh(account: account, appPassword: appPassword, using: client)
        XCTAssertEqual(viewModel.entries.count, 1)
        XCTAssertEqual(viewModel.state, .loaded)
    }

    func testRefreshCalculatesNewPostCountCorrectly() async {
        client.timelineResult = .success(makeResponse(cursor: "c1", uris: ["at://post/a"]))
        await viewModel.loadTimeline(account: account, appPassword: appPassword, using: client)
        client.timelineResult = .success(makeResponse(cursor: "c2", uris: ["at://post/a"]))
        await viewModel.refresh(account: account, appPassword: appPassword, using: client)
        client.timelineResult = .success(makeResponse(cursor: "c3", uris: ["at://post/a", "at://post/b"]))
        await viewModel.refresh(account: account, appPassword: appPassword, using: client)
        XCTAssertEqual(viewModel.newPostCount, 1)
    }

    func testLoadMoreAppendsEntries() async {
        client.timelineResult = .success(makeResponse(cursor: "c1", uris: ["at://post/1"]))
        await viewModel.loadTimeline(account: account, appPassword: appPassword, using: client)
        client.timelineResult = .success(makeResponse(cursor: nil, uris: ["at://post/2"]))
        await viewModel.loadMore(account: account, appPassword: appPassword, using: client)
        XCTAssertEqual(viewModel.entries.count, 2)
        XCTAssertEqual(viewModel.state, .exhausted)
    }

    func testLoadMoreExhausted() async {
        client.timelineResult = .success(makeResponse(cursor: nil, uris: ["at://post/1"]))
        await viewModel.loadTimeline(account: account, appPassword: appPassword, using: client)
        XCTAssertEqual(viewModel.state, .exhausted)
        await viewModel.loadMore(account: account, appPassword: appPassword, using: client)
        XCTAssertEqual(viewModel.entries.count, 1)
    }

    func testLoadMoreFailure() async {
        client.timelineResult = .success(makeResponse(cursor: "c1", uris: ["at://post/1"]))
        await viewModel.loadTimeline(account: account, appPassword: appPassword, using: client)
        client.timelineResult = .failure(BlueskyAPIError.server("Down"))
        await viewModel.loadMore(account: account, appPassword: appPassword, using: client)
        XCTAssertTrue(viewModel.state.errorMessage?.contains("Down") == true)
        XCTAssertEqual(viewModel.entries.count, 1)
    }

    func testVisibleEntriesFiltersMutedWords() async {
        let mutedStore = MutedWordsStore()
        mutedStore.add("spoiler")
        viewModel = FeedTimelineViewModel(mutedWords: mutedStore)
        client.timelineResult = .success(makeResponse(
            cursor: nil,
            uris: ["at://post/1", "at://post/2"],
            texts: ["This is fine", "This contains spoiler alert"]
        ))
        await viewModel.loadTimeline(account: account, appPassword: appPassword, using: client)
        XCTAssertEqual(viewModel.visibleEntries.count, 1)
        XCTAssertEqual(viewModel.visibleEntries[0].post.uri, "at://post/1")
    }

    func testRemoveEntry() {
        viewModel = FeedTimelineViewModel()
        viewModel.insertEntry(makeEntry(uri: "at://post/1"), at: 0)
        viewModel.insertEntry(makeEntry(uri: "at://post/2"), at: 1)
        viewModel.removeEntry(uri: "at://post/1")
        XCTAssertEqual(viewModel.entries.count, 1)
        XCTAssertEqual(viewModel.entries[0].post.uri, "at://post/2")
    }

    func testInsertEntry() {
        viewModel.insertEntry(makeEntry(uri: "at://post/1"), at: 0)
        viewModel.insertEntry(makeEntry(uri: "at://post/2"), at: 0)
        XCTAssertEqual(viewModel.entries.count, 2)
        XCTAssertEqual(viewModel.entries[0].post.uri, "at://post/2")
    }

    func testPrepareForAccountChange() {
        viewModel.insertEntry(makeEntry(uri: "at://post/1"), at: 0)
        viewModel.prepareForAccountChange()
        XCTAssertTrue(viewModel.entries.isEmpty)
        XCTAssertEqual(viewModel.state, .initialLoading)
        XCTAssertEqual(viewModel.newPostCount, 0)
    }

    func testPrepareForFeedChange() {
        viewModel.insertEntry(makeEntry(uri: "at://post/1"), at: 0)
        viewModel.prepareForFeedChange()
        XCTAssertTrue(viewModel.entries.isEmpty)
        XCTAssertEqual(viewModel.state, .initialLoading)
    }

    func testUsesCustomFeedWhenSet() async {
        let feedStore = FeedStore(did: "customFeedTest")
        feedStore.setFeed(uri: "at://feed/custom", name: "Custom")
        viewModel = FeedTimelineViewModel(feedStore: feedStore)
        client.feedResult = .success(makeResponse(cursor: nil, uris: ["at://post/c1"]))
        await viewModel.loadTimeline(account: account, appPassword: appPassword, using: client)
        XCTAssertEqual(viewModel.entries.count, 1)
        XCTAssertTrue(client.lastUsedFeedURI == "at://feed/custom")
        UserDefaults.standard.removeObject(forKey: "feed_customFeedTest_customFeedURI")
        UserDefaults.standard.removeObject(forKey: "feed_customFeedTest_customFeedName")
    }

    // MARK: - Helpers

    private func makeResponse(cursor: String?, uris: [String], texts: [String]? = nil) -> RichFeedResponse {
        let entries = uris.enumerated().map { i, uri in
            makeEntry(uri: uri, text: texts?[i] ?? "Post \(i)")
        }
        return RichFeedResponse(cursor: cursor, feed: entries)
    }

    private func makeEntry(uri: String, text: String = "Post") -> RichFeedEntry {
        RichFeedEntry(
            post: RichPost(
                uri: uri,
                cid: "cid-\(uri)",
                author: RichAuthor(did: "did:plc:a", handle: "author.bsky.social", displayName: "Author", avatar: nil),
                record: RichRecord(text: text, createdAt: "2024-01-01T00:00:00Z"),
                embed: nil,
                viewer: nil,
                replyCount: 0,
                repostCount: 0,
                likeCount: 0,
                indexedAt: "2024-01-01T00:00:00Z"
            ),
            reply: nil
        )
    }
}

@MainActor
private final class MockTimelineClient: LiveBlueskyClient {
    var timelineResult: Result<RichFeedResponse, Error>?
    var feedResult: Result<RichFeedResponse, Error>?
    private(set) var lastUsedFeedURI: String?

    init() {
        super.init()
    }

    override func fetchTimeline(cursor _: String?, limit _: Int, account _: AppAccount, appPassword _: String?) async throws -> RichFeedResponse {
        guard let result = timelineResult else {
            throw BlueskyAPIError.server("No mock result set")
        }
        return try result.get()
    }

    override func fetchFeed(feedURI: String, cursor _: String?, limit _: Int, account _: AppAccount, appPassword _: String?) async throws -> RichFeedResponse {
        lastUsedFeedURI = feedURI
        guard let result = feedResult else {
            throw BlueskyAPIError.server("No mock result set")
        }
        return try result.get()
    }
}
