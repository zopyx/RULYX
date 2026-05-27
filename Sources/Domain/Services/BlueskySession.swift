import Foundation

struct BlueskySession: Codable {
    let did: String
    let handle: String
    let accessJWT: String
    let refreshJWT: String?
    let pdsURL: URL
}

struct PagedListMembers {
    let members: [BlueskyListMember]
    let cursor: String?
}

struct PagedActorSearch {
    let actors: [BlueskyActor]
    let cursor: String?
}

/// Provides minimal authentication interface for Bluesky sessions.
/// Implementations handle login, session persistence, and session deletion.
/// This is a subset of `BlueskySessionServicing` used where only basic
/// auth operations are needed without the full request-execution pipeline.
@MainActor
protocol BlueskyAuthenticating {
    /// Authenticates with the Bluesky AT Protocol and returns a session.
    /// - Parameters:
    ///   - handle: The Bluesky handle of the account.
    ///   - appPassword: The app password for authentication.
    ///   - entrywayURL: An optional custom entryway URL; if `nil`, resolves automatically.
    /// - Returns: A `BlueskySession` with access and refresh JWTs.
    /// - Throws: If authentication fails or the PDS cannot be resolved.
    func authenticate(handle: String, appPassword: String, entrywayURL: URL?) async throws -> BlueskySession

    /// Persists a session to secure storage (keychain) for later restoration.
    /// - Parameters:
    ///   - session: The session to persist.
    ///   - account: The account associated with the session.
    func persistSession(_ session: BlueskySession, for account: AppAccount) async throws

    /// Removes a persisted session from secure storage.
    /// - Parameter account: The account whose session to delete.
    func deletePersistedSession(for account: AppAccount) throws
}
