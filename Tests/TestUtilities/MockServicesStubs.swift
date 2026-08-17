import Foundation
@testable import RULYX

// Stub mocks for BlueskyServiceContainer.mock()
// Each provides defaults suitable for most unit tests.

@MainActor final class MockAuthService: BlueskyAuthServicing {
    func authenticate(handle: String, appPassword _: String, entrywayURL _: URL?, authFactorToken _: String?) async throws -> BlueskySession {
        BlueskySession(did: "did:plc:mock", handle: handle, accessJWT: "jwt", refreshJWT: nil, pdsURL: URL(string: "https://bsky.social")!)
    }

    func persistSession(_: BlueskySession, for _: AppAccount) async throws {}
    func deletePersistedSession(for _: AppAccount) throws {}
    func restoreSessions(for _: [AppAccount]) async {}
    func clearCache() {}
    func clearAllCaches() async {}
}

@MainActor final class MockFeedService: BlueskyFeedServicing {
    func fetchTimeline(cursor _: String?, limit _: Int, account _: AppAccount, appPassword _: String?) async throws -> RichFeedResponse {
        RichFeedResponse(cursor: nil, feed: [])
    }

    func fetchFeed(feedURI _: String, cursor _: String?, limit _: Int, account _: AppAccount, appPassword _: String?) async throws -> RichFeedResponse {
        RichFeedResponse(cursor: nil, feed: [])
    }

    func fetchListFeed(listURI _: String, cursor _: String?, limit _: Int, account _: AppAccount, appPassword _: String?) async throws -> RichFeedResponse {
        RichFeedResponse(cursor: nil, feed: [])
    }

    func fetchAuthorFeed(did _: String, cursor _: String?, account _: AppAccount, appPassword _: String?) async throws -> GetAuthorFeedResponse {
        GetAuthorFeedResponse(cursor: nil, feed: [])
    }

    func fetchRichFeed(did _: String, cursor _: String?, filter _: String?, account _: AppAccount, appPassword _: String?) async throws -> RichFeedResponse {
        RichFeedResponse(cursor: nil, feed: [])
    }
}

@MainActor final class MockPostService: BlueskyPostServicing {
    func fetchPostThread(uri _: String, depth _: Int?, account _: AppAccount, appPassword _: String?) async throws -> GetPostThreadResponse {
        throw BlueskyAPIError.invalidResponse
    }

    func createPost(text _: String, images _: [PostImageAttachment]?, video _: PostVideoAttachment?, external _: PostExternalAttachment?, replyTo _: (parentURI: String, parentCID: String, rootURI: String, rootCID: String)?, quote _: (uri: String, cid: String)?, threadGate _: ThreadGateRule?, allowQuoting _: Bool, account _: AppAccount, appPassword _: String?) async throws -> CreateRecordResponse {
        CreateRecordResponse(uri: "at://mock/post", cid: "cid")
    }

    func createThreadGate(postURI _: String, rules _: [ThreadGateRule], account _: AppAccount, appPassword _: String?) async throws -> CreateRecordResponse {
        CreateRecordResponse(uri: "at://mock/gate", cid: "cid")
    }

    func createPostGate(postURI _: String, account _: AppAccount, appPassword _: String?) async throws -> CreateRecordResponse {
        CreateRecordResponse(uri: "at://mock/gate", cid: "cid")
    }

    func deleteRecord(recordURI _: String, account _: AppAccount, appPassword _: String?) async throws -> EmptyResponse {
        EmptyResponse()
    }

    func fetchPosts(uris _: [String]) async throws -> [RichPost] {
        []
    }

    func searchPosts(q _: String, mentions _: String?, sort _: String?, cursor _: String?, limit _: Int, account _: AppAccount, appPassword _: String?) async throws -> SearchPostsResponse {
        SearchPostsResponse(cursor: nil, hitsTotal: 0, posts: [])
    }
}

@MainActor final class MockModerationService: BlueskyModerationServicing {
    func reportList(_: BlueskyList, reason _: String?, account _: AppAccount, appPassword _: String?) async throws {}
    func reportList(_: BlueskyList, selectedReason _: ModerationReportReasonType?, reason _: String?, account _: AppAccount, appPassword _: String?) async throws {}
    func reportRecord(uri _: String, cid _: String, reason _: String?, selectedReason _: ModerationReportReasonType?, account _: AppAccount, appPassword _: String?) async throws {}
}

@MainActor final class MockNotificationService: BlueskyNotificationServicing {
    func fetchNotifications(cursor _: String?, limit _: Int, account _: AppAccount, appPassword _: String?) async throws -> ListNotificationsResponse {
        ListNotificationsResponse(cursor: nil, notifications: [])
    }

    func getUnreadCount(account _: AppAccount, appPassword _: String?) async throws -> Int {
        0
    }

    func updateSeen(at _: Date, account _: AppAccount, appPassword _: String?) async throws {}
}

@MainActor final class MockIdentityService: BlueskyIdentityServicing {
    func fetchPLCAuditLog(did _: String) async throws -> [PLCAuditLogEntry] {
        []
    }

    func fetchProfileBatch(identifiers _: [String]) async throws -> [BlueskyActor] {
        []
    }
}

@MainActor final class MockAuthenticatingService: BlueskyAuthenticating {
    func authenticate(handle: String, appPassword _: String, entrywayURL _: URL?, authFactorToken _: String?) async throws -> BlueskySession {
        BlueskySession(
            did: "did:plc:mock",
            handle: handle,
            accessJWT: "access",
            refreshJWT: "refresh",
            pdsURL: URL(string: "https://bsky.social")!
        )
    }

    func persistSession(_: BlueskySession, for _: AppAccount) async throws {}

    func deletePersistedSession(for _: AppAccount) throws {}
}

@MainActor final class MockMediaService: BlueskyMediaServicing {
    func uploadBlob(data: Data, mimeType: String, account _: AppAccount, appPassword _: String?, progress _: (@Sendable (Double) -> Void)?) async throws -> UploadBlobResponse {
        UploadBlobResponse(blob: UploadedBlob(ref: BlobRef(link: "mock"), mimeType: mimeType, size: data.count, blobType: nil))
    }
}
