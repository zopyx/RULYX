import Foundation

/// Provides profile inspection and moderation actions for Bluesky actors.
/// Implementations handle API calls to the AT Protocol for searching, fetching,
/// blocking, muting, following, unfollowing, and reporting actors.
@MainActor
protocol BlueskyProfileInspecting {
    // MARK: - Actor Search

    /// Searches for actors matching the given query string.
    /// - Parameters:
    ///   - query: The search query string (handle, display name, or DID).
    ///   - account: The account to authenticate with.
    ///   - appPassword: The app password for authentication, or `nil` to use the cached session.
    /// - Returns: An array of matching `BlueskyActor` objects.
    func searchActors(query: String, account: AppAccount, appPassword: String?) async throws -> [BlueskyActor]

    /// Searches for actors with cursor-based pagination support.
    /// - Parameters:
    ///   - query: The search query string.
    ///   - cursor: An optional cursor string for fetching the next page of results.
    ///   - account: The account to authenticate with.
    ///   - appPassword: The app password for authentication, or `nil` to use the cached session.
    /// - Returns: A `PagedActorSearch` containing the matching actors and an optional cursor for the next page.
    func searchActorsPage(query: String, cursor: String?, account: AppAccount, appPassword: String?) async throws -> PagedActorSearch

    // MARK: - Profile Fetching

    /// Fetches the full profile for a given actor DID, including viewer state.
    /// - Parameters:
    ///   - actorDID: The DID of the actor to fetch.
    ///   - account: The account to authenticate with.
    ///   - appPassword: The app password for authentication, or `nil` to use the cached session.
    /// - Returns: A `BlueskyProfile` containing profile details and viewer state.
    /// - Throws: If the profile doesn't exist or access is denied.
    func fetchProfile(did actorDID: String, account: AppAccount, appPassword: String?) async throws -> BlueskyProfile

    /// Inspects a profile by handle or DID, returning moderation-relevant data.
    /// - Parameters:
    ///   - query: A handle or DID to inspect.
    ///   - account: The account to authenticate with.
    ///   - appPassword: The app password for authentication, or `nil` to use the cached session.
    /// - Returns: A `ProfileInspection` with moderation details.
    func inspectProfile(query: String, account: AppAccount, appPassword: String?) async throws -> ProfileInspection

    // MARK: - Relationship Actions

    /// Blocks the specified actor.
    /// - Parameters:
    ///   - actorDID: The DID of the actor to block.
    ///   - account: The account to authenticate with.
    ///   - appPassword: The app password for authentication, or `nil` to use the cached session.
    func blockActor(did actorDID: String, account: AppAccount, appPassword: String?) async throws

    /// Unblocks the specified actor using the existing block record URI.
    /// - Parameters:
    ///   - recordURI: The AT URI of the existing block record to delete.
    ///   - account: The account to authenticate with.
    ///   - appPassword: The app password for authentication, or `nil` to use the cached session.
    func unblockActor(recordURI: String, account: AppAccount, appPassword: String?) async throws

    /// Follows the specified actor.
    /// - Parameters:
    ///   - actorDID: The DID of the actor to follow.
    ///   - account: The account to authenticate with.
    ///   - appPassword: The app password for authentication, or `nil` to use the cached session.
    func followActor(did actorDID: String, account: AppAccount, appPassword: String?) async throws

    /// Unfollows the specified actor using the existing follow record URI.
    /// - Parameters:
    ///   - recordURI: The AT URI of the existing follow record to delete.
    ///   - account: The account to authenticate with.
    ///   - appPassword: The app password for authentication, or `nil` to use the cached session.
    func unfollowActor(recordURI: String, account: AppAccount, appPassword: String?) async throws

    /// Mutes the specified actor.
    /// - Parameters:
    ///   - actorDID: The DID of the actor to mute.
    ///   - account: The account to authenticate with.
    ///   - appPassword: The app password for authentication, or `nil` to use the cached session.
    func muteActor(did actorDID: String, account: AppAccount, appPassword: String?) async throws

    /// Unmutes the specified actor.
    /// - Parameters:
    ///   - actorDID: The DID of the actor to unmute.
    ///   - account: The account to authenticate with.
    ///   - appPassword: The app password for authentication, or `nil` to use the cached session.
    func unmuteActor(did actorDID: String, account: AppAccount, appPassword: String?) async throws

    // MARK: - Followers & Following

    /// Fetches all followers for the specified actor.
    /// - Parameters:
    ///   - actorDID: The DID of the actor whose followers to fetch.
    ///   - account: The account to authenticate with.
    ///   - appPassword: The app password for authentication, or `nil` to use the cached session.
    /// - Returns: An array of `BlueskyActor` representing the actor's followers.
    func fetchFollowers(actor actorDID: String, account: AppAccount, appPassword: String?) async throws -> [BlueskyActor]

    /// Fetches a paginated page of followers for the specified actor.
    /// - Parameters:
    ///   - actorDID: The DID of the actor whose followers to fetch.
    ///   - cursor: An optional cursor string for fetching the next page.
    ///   - account: The account to authenticate with.
    ///   - appPassword: The app password for authentication, or `nil` to use the cached session.
    /// - Returns: A `PagedActorSearch` containing a page of followers and an optional next cursor.
    func fetchFollowersPage(actor actorDID: String, cursor: String?, account: AppAccount, appPassword: String?) async throws -> PagedActorSearch

    /// Fetches all actors the specified actor is following.
    /// - Parameters:
    ///   - actorDID: The DID of the actor whose follow list to fetch.
    ///   - account: The account to authenticate with.
    ///   - appPassword: The app password for authentication, or `nil` to use the cached session.
    /// - Returns: An array of `BlueskyActor` representing followed accounts.
    func fetchFollowing(actor actorDID: String, account: AppAccount, appPassword: String?) async throws -> [BlueskyActor]

    /// Fetches a paginated page of actors the specified actor is following.
    /// - Parameters:
    ///   - actorDID: The DID of the actor whose follow list to fetch.
    ///   - cursor: An optional cursor string for fetching the next page.
    ///   - account: The account to authenticate with.
    ///   - appPassword: The app password for authentication, or `nil` to use the cached session.
    /// - Returns: A `PagedActorSearch` containing a page of followed actors and an optional next cursor.
    func fetchFollowingPage(actor actorDID: String, cursor: String?, account: AppAccount, appPassword: String?) async throws -> PagedActorSearch

    // MARK: - Reporting

    /// Reports an account with a specified reason type.
    /// - Parameters:
    ///   - targetDID: The DID of the account being reported.
    ///   - reasonType: The reason type string for the report (e.g. "com.atproto.moderation.reportReasonType.spam").
    ///   - reason: An optional human-readable explanation for the report.
    ///   - account: The account to authenticate with.
    ///   - appPassword: The app password for authentication, or `nil` to use the cached session.
    func reportAccount(did targetDID: String, reasonType: String, reason: String?, account: AppAccount, appPassword: String?) async throws

    /// Reports an account with an optional free-form reason (uses the default reason type).
    /// - Parameters:
    ///   - targetDID: The DID of the account being reported.
    ///   - reason: An optional human-readable explanation for the report.
    ///   - account: The account to authenticate with.
    ///   - appPassword: The app password for authentication, or `nil` to use the cached session.
    func reportAccount(did targetDID: String, reason: String?, account: AppAccount, appPassword: String?) async throws

    /// Reports an account with a typed moderation reason.
    /// - Parameters:
    ///   - targetDID: The DID of the account being reported.
    ///   - selectedReason: An optional `ModerationReportReasonType` specifying the report category.
    ///   - reason: An optional human-readable explanation for the report.
    ///   - account: The account to authenticate with.
    ///   - appPassword: The app password for authentication, or `nil` to use the cached session.
    func reportAccount(did targetDID: String, selectedReason: ModerationReportReasonType?, reason: String?, account: AppAccount, appPassword: String?) async throws
}
