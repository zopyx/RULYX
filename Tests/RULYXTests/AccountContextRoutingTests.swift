@testable import RULYX
import XCTest

/// Tests verifying account context routing rules from AGENTS.md.
@MainActor
final class AccountContextRoutingTests: XCTestCase {
    // MARK: - AppAccount Basics

    func testAppAccountInitDefaults() {
        let a = AppAccount(handle: "test.bsky.social", did: "did:plc:test")
        XCTAssertEqual(a.handle, "test.bsky.social")
        XCTAssertEqual(a.did, "did:plc:test")
    }

    func testAccountsHaveUniqueIDs() {
        let a1 = AppAccount(handle: "one.bsky.social", did: "did:plc:1")
        let a2 = AppAccount(handle: "two.bsky.social", did: "did:plc:2")
        XCTAssertNotEqual(a1.id, a2.id)
    }

    func testDisplayNameFallsBackToHandle() {
        let a = AppAccount(handle: "user.bsky.social", did: "did:plc:user")
        XCTAssertEqual(a.displayName, "user.bsky.social")
    }

    // MARK: - Preview Store

    func testPreviewStoreHasAccounts() {
        let store = AccountStore(preview: true)
        XCTAssertFalse(store.accounts.isEmpty)
        XCTAssertNotNil(store.activeAccount)
    }

    func testPreviewStoreAccountsHaveLabelsNil() {
        let store = AccountStore(preview: true)
        store.accounts.forEach { XCTAssertNil($0.label) }
    }

    func testPreviewStoreAccountsHaveDistinctIDs() {
        let store = AccountStore(preview: true)
        let ids = store.accounts.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count)
    }

    // MARK: - Fallback Chain

    func testFallbackWhenPreferredIsNil() {
        let store = AccountStore(preview: true)
        let active = store.activeAccount
        XCTAssertNotNil(active, "Active account must exist as fallback")
    }

    func testPreferredSearchAccountPersistsNilByDefault() {
        UserDefaults.standard.removeObject(forKey: "bluesky.preferredSearchAccountID")
        let store = AccountStore(keychain: MockKeychain())
        XCTAssertNil(store.preferredSearchAccountID)
    }

    // MARK: - Handle / DisplayName

    func testHandleIsDisplayNameWhenNil() {
        let account = AppAccount(handle: "test.bsky.social", did: "did:plc:test")
        XCTAssertEqual(account.displayName, "test.bsky.social")
    }

    func testAccountsWithSameHandleHaveDifferentIDs() {
        let a1 = AppAccount(handle: "same.bsky.social", did: "did:plc:1")
        let a2 = AppAccount(handle: "same.bsky.social", did: "did:plc:1")
        XCTAssertNotEqual(a1, a2)
    }
}
