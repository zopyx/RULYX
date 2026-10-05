import Foundation

/// Blocklist reads, sourced from the AT Protocol itself:
///
/// * **"Blocking"** (who *I* block) comes from my own repo — the `app.bsky.graph.block`
///   records *are* the blocklist (`AtProtoRepoClient`).
/// * **"Blocked by"** (who blocks me) comes from the Constellation backlink index, which
///   indexes the `app.bsky.graph.block` records pointing at me (`ConstellationClient`).
///
/// No third-party moderation service is involved. Implementations differ only in how they
/// read those two sources; the protocol keeps feature code independent of the concrete
/// client.
@MainActor
protocol BlueskyBlocklistServicing: Sendable {
    /// The actors the account has blocked.
    func fetchBlockedActors(
        account: AppAccount,
        appPassword: String?
    ) async throws -> BlocklistResult

    /// The actors the account has blocked, reporting partial counts as records load.
    func fetchBlockedActors(
        account: AppAccount,
        appPassword: String?,
        onProgress: (@MainActor @Sendable (Int) async -> Void)?
    ) async throws -> BlocklistResult

    /// The actors blocking the account.
    func fetchBlockedByActors(
        account: AppAccount,
        appPassword: String?
    ) async throws -> BlocklistResult

    /// The actors blocking the account, reporting partial counts as records load.
    func fetchBlockedByActors(
        account: AppAccount,
        appPassword: String?,
        onProgress: (@MainActor @Sendable (Int) async -> Void)?
    ) async throws -> BlocklistResult

    /// The actors blocking the account, reporting partial counts as records load and
    /// emitting each resolved batch of actors as it becomes available, so a caller can
    /// render the list while profiles are still being resolved.
    func fetchBlockedByActors(
        account: AppAccount,
        appPassword: String?,
        onProgress: (@MainActor @Sendable (Int) async -> Void)?,
        onActors: (@MainActor @Sendable ([BlueskyActor]) async -> Void)?
    ) async throws -> BlocklistResult

    /// Number of actors the account has blocked.
    func fetchBlockingCount(for account: AppAccount) async throws -> Int

    /// Number of actors blocking the account.
    func fetchBlockedByCount(for account: AppAccount) async throws -> Int

    /// Number of actors that block the account but are not blocked back.
    func fetchUnblockedBlockersCount(for account: AppAccount) async throws -> Int

    /// The actors that block the account but are not blocked back.
    func fetchUnblockedBlockerActors(
        account: AppAccount,
        appPassword: String?
    ) async throws -> [BlueskyActor]

    /// DIDs of the accounts the account has blocked (own repo).
    func fetchBlockedDIDs(for account: AppAccount) async throws -> Set<String>

    /// DIDs of the accounts blocking the account (backlink index).
    func fetchBlockerDIDs(for account: AppAccount) async throws -> Set<String>
}

extension BlueskyBlocklistServicing {
    func fetchBlockedActors(
        account: AppAccount,
        appPassword: String?,
        onProgress _: (@MainActor @Sendable (Int) async -> Void)?
    ) async throws -> BlocklistResult {
        try await fetchBlockedActors(account: account, appPassword: appPassword)
    }

    func fetchBlockedByActors(
        account: AppAccount,
        appPassword: String?,
        onProgress _: (@MainActor @Sendable (Int) async -> Void)?
    ) async throws -> BlocklistResult {
        try await fetchBlockedByActors(account: account, appPassword: appPassword)
    }

    func fetchBlockedByActors(
        account: AppAccount,
        appPassword: String?,
        onProgress: (@MainActor @Sendable (Int) async -> Void)?,
        onActors _: (@MainActor @Sendable ([BlueskyActor]) async -> Void)?
    ) async throws -> BlocklistResult {
        try await fetchBlockedByActors(account: account, appPassword: appPassword, onProgress: onProgress)
    }
}
