import Foundation

/// Likes, reposts, and social graph mutations (block, mute, follow).
@MainActor
protocol BlueskySocialServicing: Sendable {
    /// Create a like for a post.
    func createLike(
        uri: String,
        cid: String,
        account: AppAccount,
        appPassword: String?
    ) async throws -> CreateRecordResponse

    /// Create a repost for a post.
    func createRepost(
        uri: String,
        cid: String,
        account: AppAccount,
        appPassword: String?
    ) async throws -> CreateRecordResponse

    /// Fetch likes for a post.
    func fetchLikes(
        uri: String,
        cursor: String?,
        account: AppAccount,
        appPassword: String?
    ) async throws -> GetLikesResponse

    /// Block an actor.
    func blockActor(
        did actorDID: String,
        account: AppAccount,
        appPassword: String?
    ) async throws

    /// Unblock an actor by block record URI.
    func unblockActor(
        recordURI: String,
        account: AppAccount,
        appPassword: String?
    ) async throws

    /// Soft-block an actor: blocks them (removes follower) then immediately unblocks.
    /// Used to force-remove a follower without permanently blocking them.
    func softBlockActor(
        did actorDID: String,
        account: AppAccount,
        appPassword: String?
    ) async throws

    /// Fetches a mapping of blocked actor DID → block record URI from the PDS.
    /// Used by the Blocking mode swipe to perform unblocking.
    func fetchExistingBlockRecordURIs(account: AppAccount, appPassword: String?) async throws -> [String: String]

    /// Follow an actor.
    func followActor(
        did actorDID: String,
        account: AppAccount,
        appPassword: String?
    ) async throws

    /// Unfollow an actor by follow record URI.
    func unfollowActor(
        recordURI: String,
        account: AppAccount,
        appPassword: String?
    ) async throws

    /// Mute an actor.
    func muteActor(
        did actorDID: String,
        account: AppAccount,
        appPassword: String?
    ) async throws

    /// Unmute an actor.
    func unmuteActor(
        did actorDID: String,
        account: AppAccount,
        appPassword: String?
    ) async throws
}
