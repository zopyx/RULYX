import Foundation

/// ClearSky third-party block/blocker data operations.
@MainActor
protocol BlueskyClearSkyServicing: Sendable {
    /// Fetch blocked actor results from ClearSky.
    func fetchBlockedActors(
        account: AppAccount,
        appPassword: String?
    ) async throws -> ClearskyBlocklistResult

    /// Fetch blocked-by actor results from ClearSky.
    func fetchBlockedByActors(
        account: AppAccount,
        appPassword: String?
    ) async throws -> ClearskyBlocklistResult

    /// Fetch the count of actors the user is blocking.
    func fetchBlockingCount(for account: AppAccount) async throws -> Int

    /// Fetch the count of actors blocking the user.
    func fetchBlockedByCount(for account: AppAccount) async throws -> Int

    /// Fetch the count of unblocked blockers.
    func fetchUnblockedBlockersCount(for account: AppAccount) async throws -> Int

    /// Fetch the list of unblocked blocker actors.
    func fetchUnblockedBlockerActors(
        account: AppAccount,
        appPassword: String?
    ) async throws -> [BlueskyActor]

    /// Fetch ClearSky list entries for a handle.
    func fetchClearskyLists(handle: String) async throws -> [ClearskyListEntry]
}
