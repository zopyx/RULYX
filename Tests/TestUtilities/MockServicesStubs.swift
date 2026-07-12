@testable import RULYX
import Foundation

// Stub mocks for BlueskyServiceContainer.mock()
// Each provides defaults suitable for most unit tests.

@MainActor final class MockAuthService: BlueskyAuthServicing {
    func authenticate(handle: String, appPassword: String, entrywayURL: URL?, authFactorToken: String?) async throws -> BlueskySession {
        BlueskySession(did: "did:plc:mock", handle: handle, accessJWT: "jwt", refreshJWT: nil, pdsURL: URL(string: "https://bsky.social")!)
    }
    func persistSession(_: BlueskySession, for _: AppAccount) async throws {}
    func deletePersistedSession(for _: AppAccount) throws {}
    func restoreSessions(for _: [AppAccount]) async {}
    func clearCache() {}
}

@MainActor final class MockFeedService: BlueskyFeedServicing {
    func fetchTimeline(cursor: String?, limit: Int, account: AppAccount, appPassword: String?) async throws -> RichFeedResponse { RichFeedResponse(cursor: nil, feed: []) }
    func fetchFeed(feedURI: String, cursor: String?, limit: Int, account: AppAccount, appPassword: String?) async throws -> RichFeedResponse { RichFeedResponse(cursor: nil, feed: []) }
    func fetchListFeed(listURI: String, cursor: String?, limit: Int, account: AppAccount, appPassword: String?) async throws -> RichFeedResponse { RichFeedResponse(cursor: nil, feed: []) }
    func fetchAuthorFeed(did: String, cursor: String?, account: AppAccount, appPassword: String?) async throws -> GetAuthorFeedResponse { GetAuthorFeedResponse(cursor: nil, feed: []) }
    func fetchRichFeed(did: String, cursor: String?, account: AppAccount, appPassword: String?) async throws -> RichFeedResponse { RichFeedResponse(cursor: nil, feed: []) }
}

@MainActor final class MockPostService: BlueskyPostServicing {
    func fetchPostThread(uri: String, depth: Int?, account: AppAccount, appPassword: String?) async throws -> GetPostThreadResponse { throw BlueskyAPIError.invalidResponse }
    func createPost(text: String, images: [PostImageAttachment]?, video: PostVideoAttachment?, external: PostExternalAttachment?, replyTo: (parentURI: String, parentCID: String, rootURI: String, rootCID: String)?, quote: (uri: String, cid: String)?, threadGate: ThreadGateRule?, allowQuoting: Bool, account: AppAccount, appPassword: String?) async throws -> CreateRecordResponse { CreateRecordResponse(uri: "at://mock/post", cid: "cid") }
    func createThreadGate(postURI: String, rules: [ThreadGateRule], account: AppAccount, appPassword: String?) async throws -> CreateRecordResponse { CreateRecordResponse(uri: "at://mock/gate", cid: "cid") }
    func createPostGate(postURI: String, account: AppAccount, appPassword: String?) async throws -> CreateRecordResponse { CreateRecordResponse(uri: "at://mock/gate", cid: "cid") }
    func deleteRecord(recordURI: String, account: AppAccount, appPassword: String?) async throws -> EmptyResponse { EmptyResponse() }
    func fetchPosts(uris: [String]) async throws -> [RichPost] { [] }
    func searchPosts(q: String, mentions: String?, sort: String?, cursor: String?, limit: Int, account: AppAccount, appPassword: String?) async throws -> SearchPostsResponse { SearchPostsResponse(cursor: nil, hitsTotal: 0, posts: []) }
}

@MainActor final class MockModerationService: BlueskyModerationServicing {
    func reportList(_: BlueskyList, reason: String?, account: AppAccount, appPassword: String?) async throws {}
    func reportList(_: BlueskyList, selectedReason: ModerationReportReasonType?, reason: String?, account: AppAccount, appPassword: String?) async throws {}
    func reportRecord(uri: String, cid: String, reason: String?, selectedReason: ModerationReportReasonType?, account: AppAccount, appPassword: String?) async throws {}
}

@MainActor final class MockNotificationService: BlueskyNotificationServicing {
    func fetchNotifications(cursor: String?, limit: Int, account: AppAccount, appPassword: String?) async throws -> ListNotificationsResponse { ListNotificationsResponse(cursor: nil, notifications: []) }
    func getUnreadCount(account: AppAccount, appPassword: String?) async throws -> Int { 0 }
    func updateSeen(at: Date, account: AppAccount, appPassword: String?) async throws {}
}

@MainActor final class MockIdentityService: BlueskyIdentityServicing {
    func fetchPLCAuditLog(did: String) async throws -> [PLCAuditLogEntry] { [] }
    func fetchProfileBatch(identifiers: [String]) async throws -> [BlueskyActor] { [] }
}

@MainActor final class MockMediaService: BlueskyMediaServicing {
    func uploadBlob(data: Data, mimeType: String, account: AppAccount, appPassword: String?, progress: (@Sendable (Double) -> Void)?) async throws -> UploadBlobResponse {
        UploadBlobResponse(blob: UploadedBlob(ref: BlobRef(link: "mock"), mimeType: mimeType, size: data.count, blobType: nil))
    }
}
