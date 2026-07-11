@testable import RULYX
import Foundation

/// Mock implementation of BlueskySocialServicing for unit testing.
@MainActor
struct MockSocialService: BlueskySocialServicing {
    var createLikeHandler: @Sendable (String, String, AppAccount, String?) async throws -> CreateRecordResponse = { _, _, _, _ in
        CreateRecordResponse(uri: "at://mock/like/1", cid: "mock-cid", rkey: "1")
    }
    var createRepostHandler: @Sendable (String, String, AppAccount, String?) async throws -> CreateRecordResponse = { _, _, _, _ in
        CreateRecordResponse(uri: "at://mock/repost/1", cid: "mock-cid", rkey: "1")
    }
    var fetchLikesHandler: @Sendable (String, String?, AppAccount, String?) async throws -> GetLikesResponse = { _, _, _, _ in
        GetLikesResponse(uri: "at://mock/post/1", cid: nil, cursor: nil, likes: [])
    }
    var blockActorHandler: @Sendable (String, AppAccount, String?) async throws -> Void = { _, _, _ in }
    var unblockActorHandler: @Sendable (String, AppAccount, String?) async throws -> Void = { _, _, _ in }
    var followActorHandler: @Sendable (String, AppAccount, String?) async throws -> Void = { _, _, _ in }
    var unfollowActorHandler: @Sendable (String, AppAccount, String?) async throws -> Void = { _, _, _ in }
    var muteActorHandler: @Sendable (String, AppAccount, String?) async throws -> Void = { _, _, _ in }
    var unmuteActorHandler: @Sendable (String, AppAccount, String?) async throws -> Void = { _, _, _ in }

    func createLike(uri: String, cid: String, account: AppAccount, appPassword: String?) async throws -> CreateRecordResponse {
        try await createLikeHandler(uri, cid, account, appPassword)
    }

    func createRepost(uri: String, cid: String, account: AppAccount, appPassword: String?) async throws -> CreateRecordResponse {
        try await createRepostHandler(uri, cid, account, appPassword)
    }

    func fetchLikes(uri: String, cursor: String?, account: AppAccount, appPassword: String?) async throws -> GetLikesResponse {
        try await fetchLikesHandler(uri, cursor, account, appPassword)
    }

    func blockActor(did actorDID: String, account: AppAccount, appPassword: String?) async throws {
        try await blockActorHandler(actorDID, account, appPassword)
    }

    func unblockActor(recordURI: String, account: AppAccount, appPassword: String?) async throws {
        try await unblockActorHandler(recordURI, account, appPassword)
    }

    func followActor(did actorDID: String, account: AppAccount, appPassword: String?) async throws {
        try await followActorHandler(actorDID, account, appPassword)
    }

    func unfollowActor(recordURI: String, account: AppAccount, appPassword: String?) async throws {
        try await unfollowActorHandler(recordURI, account, appPassword)
    }

    func muteActor(did actorDID: String, account: AppAccount, appPassword: String?) async throws {
        try await muteActorHandler(actorDID, account, appPassword)
    }

    func unmuteActor(did actorDID: String, account: AppAccount, appPassword: String?) async throws {
        try await unmuteActorHandler(actorDID, account, appPassword)
    }
}
