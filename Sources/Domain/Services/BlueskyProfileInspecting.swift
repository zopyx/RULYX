import Foundation

@MainActor
protocol BlueskyProfileInspecting {
    func searchActors(query: String, account: AppAccount, appPassword: String?) async throws -> [BlueskyActor]
    func searchActorsPage(query: String, cursor: String?, account: AppAccount, appPassword: String?) async throws -> PagedActorSearch
    func fetchProfile(did actorDID: String, account: AppAccount, appPassword: String?) async throws -> BlueskyProfile
    func inspectProfile(query: String, account: AppAccount, appPassword: String?) async throws -> ProfileInspection
    func blockActor(did actorDID: String, account: AppAccount, appPassword: String?) async throws
    func unblockActor(recordURI: String, account: AppAccount, appPassword: String?) async throws
    func followActor(did actorDID: String, account: AppAccount, appPassword: String?) async throws
    func unfollowActor(recordURI: String, account: AppAccount, appPassword: String?) async throws
    func muteActor(did actorDID: String, account: AppAccount, appPassword: String?) async throws
    func unmuteActor(did actorDID: String, account: AppAccount, appPassword: String?) async throws
    func fetchFollowers(actor actorDID: String, account: AppAccount, appPassword: String?) async throws -> [BlueskyActor]
    func fetchFollowersPage(actor actorDID: String, cursor: String?, account: AppAccount, appPassword: String?) async throws -> PagedActorSearch
    func fetchFollowing(actor actorDID: String, account: AppAccount, appPassword: String?) async throws -> [BlueskyActor]
    func fetchFollowingPage(actor actorDID: String, cursor: String?, account: AppAccount, appPassword: String?) async throws -> PagedActorSearch
}
