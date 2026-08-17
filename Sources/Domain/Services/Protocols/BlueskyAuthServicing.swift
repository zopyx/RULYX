import Foundation

/// AT Protocol authentication and session lifecycle.
@MainActor
protocol BlueskyAuthServicing: Sendable {
    /// Authenticate with handle + app password, returning a session.
    func authenticate(
        handle: String,
        appPassword: String,
        entrywayURL: URL?,
        authFactorToken: String?
    ) async throws -> BlueskySession

    /// Persist a session for the given account.
    func persistSession(_ session: BlueskySession, for account: AppAccount) async throws

    /// Delete the persisted session for the given account.
    func deletePersistedSession(for account: AppAccount) throws

    /// Restore sessions for the given accounts from persistent storage.
    func restoreSessions(for accounts: [AppAccount]) async

    /// Clear the internal session cache.
    func clearCache()

    /// Async clear that awaits disk cache removal (preferred for account switch).
    func clearAllCaches() async
}
