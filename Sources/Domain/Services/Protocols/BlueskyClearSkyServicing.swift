import Foundation

/// ClearSky third-party block/blocker data operations.
@MainActor
protocol BlueskyClearSkyServicing: Sendable {
    /// Fetch blocked actor results from ClearSky.
    func fetchBlockedActors(
        account: AppAccount,
        appPassword: String?
    ) async throws -> ClearskyBlocklistResult

    /// Fetch blocked actor results from ClearSky and report partial counts as pages load.
    func fetchBlockedActors(
        account: AppAccount,
        appPassword: String?,
        onProgress: (@MainActor @Sendable (Int) async -> Void)?
    ) async throws -> ClearskyBlocklistResult

    /// Fetch blocked-by actor results from ClearSky.
    func fetchBlockedByActors(
        account: AppAccount,
        appPassword: String?
    ) async throws -> ClearskyBlocklistResult

    /// Fetch blocked-by actor results from ClearSky and report partial counts as pages load.
    func fetchBlockedByActors(
        account: AppAccount,
        appPassword: String?,
        onProgress: (@MainActor @Sendable (Int) async -> Void)?
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

    /// Fetch DIDs from a ClearSky endpoint (DIDs only, no profile resolution).
    /// - Parameters:
    ///   - endpoint: ClearSky endpoint name (e.g. `"blocklist"`, `"single-blocklist"`).
    ///   - account: The account to query.
    /// - Returns: A set of DIDs from the endpoint.
    func fetchClearskyBlockDIDs(endpoint: String, for account: AppAccount) async throws -> Set<String>

    /// Fetch ClearSky list entries for a handle.
    func fetchClearskyLists(handle: String) async throws -> [ClearskyListEntry]
}

extension BlueskyClearSkyServicing {
    func fetchBlockedActors(
        account: AppAccount,
        appPassword: String?,
        onProgress _: (@MainActor @Sendable (Int) async -> Void)?
    ) async throws -> ClearskyBlocklistResult {
        try await fetchBlockedActors(account: account, appPassword: appPassword)
    }

    func fetchBlockedByActors(
        account: AppAccount,
        appPassword: String?,
        onProgress _: (@MainActor @Sendable (Int) async -> Void)?
    ) async throws -> ClearskyBlocklistResult {
        try await fetchBlockedByActors(account: account, appPassword: appPassword)
    }
}
