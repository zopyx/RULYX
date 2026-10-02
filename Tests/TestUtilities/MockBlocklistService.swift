import Foundation
@testable import RULYX

/// Mock implementation of BlueskyBlocklistServicing for unit testing.
/// Uses class semantics so handlers can be overridden after VM construction.
@MainActor
final class MockBlocklistService: BlueskyBlocklistServicing {
    var fetchBlockedActorsHandler: @Sendable (AppAccount, String?) async throws -> BlocklistResult = { _, _ in
        BlocklistResult(actors: [], totalCount: 0)
    }

    var fetchBlockedByActorsHandler: @Sendable (AppAccount, String?) async throws -> BlocklistResult = { _, _ in
        BlocklistResult(actors: [], totalCount: 0)
    }

    var fetchBlockingCountHandler: @Sendable (AppAccount) async throws -> Int = { _ in 0 }
    var fetchBlockedByCountHandler: @Sendable (AppAccount) async throws -> Int = { _ in 0 }
    var fetchUnblockedBlockersCountHandler: @Sendable (AppAccount) async throws -> Int = { _ in 0 }
    var fetchUnblockedBlockerActorsHandler: @Sendable (AppAccount, String?) async throws -> [BlueskyActor] = { _, _ in [] }
    var fetchBlockedDIDsHandler: @Sendable (AppAccount) async throws -> Set<String> = { _ in [] }
    var fetchBlockerDIDsHandler: @Sendable (AppAccount) async throws -> Set<String> = { _ in [] }

    func fetchBlockedActors(account: AppAccount, appPassword: String?) async throws -> BlocklistResult {
        try await fetchBlockedActorsHandler(account, appPassword)
    }

    func fetchBlockedByActors(account: AppAccount, appPassword: String?) async throws -> BlocklistResult {
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

    func fetchBlockedDIDs(for account: AppAccount) async throws -> Set<String> {
        try await fetchBlockedDIDsHandler(account)
    }

    func fetchBlockerDIDs(for account: AppAccount) async throws -> Set<String> {
        try await fetchBlockerDIDsHandler(account)
    }
}
