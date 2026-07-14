import Foundation
@testable import RULYX

/// Mock implementation of AccountStoreProtocol for unit testing.
@MainActor
final class MockAccountStore: AccountStoreProtocol {
    var activeAccountHandler: () -> AppAccount? = {
        AppAccount(handle: "test.bsky.social", did: "did:plc:test")
    }

    var appPasswordHandler: (AppAccount) -> String? = { _ in "mock-password" }

    var activeAccount: AppAccount? {
        activeAccountHandler()
    }

    func appPassword(for account: AppAccount) -> String? {
        appPasswordHandler(account)
    }
}
