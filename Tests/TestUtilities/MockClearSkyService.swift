@testable import RULYX
import Foundation

/// Mock implementation of BlueskyClearSkyServicing for unit testing.
@MainActor
struct MockClearSkyService: BlueskyClearSkyServicing {
    var fetchBlockedActorsHandler: @Sendable (AppAccount, String?) async throws -> ClearskyBlocklistResult = { _, _ in
        ClearskyBlocklistResult(actors: [], totalCount: 0)
    }
    var fetchBlockedByActorsHandler: @Sendable (AppAccount, String?) async throws -> ClearskyBlocklistResult = { _, _ in
        ClearskyBlocklistResult(actors: [], totalCount: 0)
    }
    var fetchBlockingCountHandler: @Sendable (AppAccount) async throws -> Int = { _ in 0 }
    var fetchBlockedByCountHandler: @Sendable (AppAccount) async throws -> Int = { _ in 0 }
    var fetchUnblockedBlockersCountHandler: @Sendable (AppAccount) async throws -> Int = { _ in 0 }
    var fetchUnblockedBlockerActorsHandler: @Sendable (AppAccount, String?) async throws -> [BlueskyActor] = { _, _ in [] }
    var fetchClearskyListsHandler: @Sendable (String) async throws -> [ClearskyListEntry] = { _ in [] }

    func fetchBlockedActors(account: AppAccount, appPassword: String?) async throws -> ClearskyBlocklistResult {
        try await fetchBlockedActorsHandler(account, appPassword)
    }

    func fetchBlockedByActors(account: AppAccount, appPassword: String?) async throws -> ClearskyBlocklistResult {
        try await fetchBlockedByActorsHandler(account, appPassword)
    }

    func fetchBlockingCount(for account: AppAccount) async throws -> Int {
        try await fetchBlockingCountHandler(account)
    }

    func fetchBlockedByCount(for account: AppAccount) async throws -> Int {
        try await fetchBlockedByCountHandler(account)
    }

    func fetchUnblockedBlockersCount(for account: AppAccount) async throws -> Int {
        try await fetchUnblockedBlockersCountHandler(account)
    }

    func fetchUnblockedBlockerActors(account: AppAccount, appPassword: String?) async throws -> [BlueskyActor] {
        try await fetchUnblockedBlockerActorsHandler(account, appPassword)
    }

    func fetchClearskyLists(handle: String) async throws -> [ClearskyListEntry] {
        try await fetchClearskyListsHandler(handle)
    }
}
