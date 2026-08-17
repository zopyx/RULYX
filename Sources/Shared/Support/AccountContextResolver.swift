import Foundation

/// Centralizes which account to use for read vs write operations.
/// See AGENTS.md "Account Context — Which Account for Which Operation".
enum AccountContextResolver {
    /// Account used for search/read operations — preferred search if set, else active.
    static func dataAccount(preferred: AppAccount?, active: AppAccount?) -> AppAccount? {
        preferred ?? active
    }

    /// Alias for search — same as `dataAccount`.
    static func searchAccount(preferred: AppAccount?, active: AppAccount?) -> AppAccount? {
        preferred ?? active
    }

    /// Account used for mutations (block/mute/follow/list membership) — always active.
    static func actingAccount(active: AppAccount?) -> AppAccount? {
        active
    }

    /// Resolve from `AccountStore` directly (convenience).
    @MainActor
    static func resolve(from store: AccountStore) -> (active: AppAccount?, data: AppAccount?) {
        let active = store.activeAccount
        let preferred = store.accounts.first { $0.id == store.preferredSearchAccountID }
        return (active, dataAccount(preferred: preferred, active: active))
    }
}
