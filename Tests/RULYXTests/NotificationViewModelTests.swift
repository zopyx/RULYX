@testable import RULYX
import XCTest

@MainActor
final class NotificationViewModelTests: XCTestCase {
    func testLoadResolvesRelatedPostForLikeNotification() async {
        let viewModel = NotificationViewModel()
        let client = MockNotificationClient()
        let account = makeAccount()

        client.notificationsResponse = ListNotificationsResponse(
            cursor: nil,
            notifications: [
                NotificationItem(
                    uri: "at://did:plc:notif/app.bsky.notification/1",
                    cid: "notif-cid-1",
                    author: ActorView(
                        did: "did:plc:author",
                        handle: "author.bsky.social",
                        displayName: "Author",
                        avatar: nil,
                        createdAt: nil,
                        viewer: nil
                    ),
                    reason: "like",
                    reasonSubject: "at://did:plc:post/app.bsky.feed.post/1",
                    isRead: false,
                    indexedAt: "2026-05-18T10:00:00Z"
                ),
            ]
        )
        client.posts = [
            RichPost(
                uri: "at://did:plc:post/app.bsky.feed.post/1",
                cid: "post-cid-1",
                author: RichAuthor(did: "did:plc:post-author", handle: "poster.bsky.social", displayName: "Poster", avatar: nil),
                record: RichRecord(text: "Hello from the post", createdAt: "2026-05-18T09:00:00Z"),
                embed: nil,
                viewer: nil,
                replyCount: nil,
                repostCount: nil,
                likeCount: nil,
                indexedAt: nil
            ),
        ]

        await viewModel.load(account: account, appPassword: "pass", using: client)

        XCTAssertEqual(viewModel.entries.count, 1)
        XCTAssertEqual(viewModel.entries.first?.relatedPost?.uri, "at://did:plc:post/app.bsky.feed.post/1")
        XCTAssertEqual(viewModel.entries.first?.relatedPost?.safeRecord.text, "Hello from the post")
    }

    func testLoadKeepsFollowNotificationWithoutRelatedPost() async {
        let viewModel = NotificationViewModel()
        let client = MockNotificationClient()
        let account = makeAccount()

        client.notificationsResponse = ListNotificationsResponse(
            cursor: nil,
            notifications: [
                NotificationItem(
                    uri: "at://did:plc:notif/app.bsky.notification/2",
                    cid: "notif-cid-2",
                    author: ActorView(
                        did: "did:plc:follower",
                        handle: "follower.bsky.social",
                        displayName: "Follower",
                        avatar: nil,
                        createdAt: nil,
                        viewer: nil
                    ),
                    reason: "follow",
                    reasonSubject: nil,
                    isRead: false,
                    indexedAt: "2026-05-18T10:00:00Z"
                ),
            ]
        )

        await viewModel.load(account: account, appPassword: "pass", using: client)

        XCTAssertEqual(viewModel.entries.count, 1)
        XCTAssertNil(viewModel.entries.first?.relatedPost)
        XCTAssertTrue(client.fetchedPostURIs.isEmpty)
    }

    func testLoadFallsBackToPerPostFetchWhenBatchFails() async {
        let viewModel = NotificationViewModel()
        let client = MockNotificationClient()
        let account = makeAccount()

        client.shouldFailBatchFetch = true
        client.notificationsResponse = ListNotificationsResponse(
            cursor: nil,
            notifications: [
                NotificationItem(
                    uri: "at://did:plc:notif/app.bsky.notification/3",
                    cid: "notif-cid-3",
                    author: ActorView(
                        did: "did:plc:author-2",
                        handle: "author2.bsky.social",
                        displayName: "Author Two",
                        avatar: nil,
                        createdAt: nil,
                        viewer: nil
                    ),
                    reason: "like",
                    reasonSubject: "at://did:plc:post/app.bsky.feed.post/2",
                    isRead: false,
                    indexedAt: "2026-05-18T10:00:00Z"
                ),
            ]
        )
        client.posts = [
            RichPost(
                uri: "at://did:plc:post/app.bsky.feed.post/2",
                cid: "post-cid-2",
                author: RichAuthor(did: "did:plc:post-author-2", handle: "poster2.bsky.social", displayName: "Poster Two", avatar: nil),
                record: RichRecord(text: "Recovered from single fetch", createdAt: "2026-05-18T09:30:00Z"),
                embed: nil,
                viewer: nil,
                replyCount: nil,
                repostCount: nil,
                likeCount: nil,
                indexedAt: nil
            ),
        ]

        await viewModel.load(account: account, appPassword: "pass", using: client)

        XCTAssertEqual(viewModel.entries.first?.relatedPost?.safeRecord.text, "Recovered from single fetch")
        XCTAssertEqual(client.fetchPostsCallCount, 2)
    }
}

@MainActor
private final class MockNotificationClient: LiveBlueskyClient {
    var notificationsResponse = ListNotificationsResponse(cursor: nil, notifications: [])
    var posts: [RichPost] = []
    var fetchedPostURIs: [String] = []
    var fetchPostsCallCount = 0
    var shouldFailBatchFetch = false

    override func fetchNotifications(cursor _: String? = nil, limit _: Int = 50, account _: AppAccount, appPassword _: String?) async throws -> ListNotificationsResponse {
        notificationsResponse
    }

    override func fetchPosts(uris: [String]) async throws -> [RichPost] {
        fetchPostsCallCount += 1
        fetchedPostURIs = uris
        if shouldFailBatchFetch, uris.count > 1 || uris == ["at://did:plc:post/app.bsky.feed.post/2"] {
            shouldFailBatchFetch = false
            throw URLError(.badServerResponse)
        }
        return posts
    }

    override func getUnreadCount(account _: AppAccount, appPassword _: String?) async throws -> Int {
        0
    }
}
