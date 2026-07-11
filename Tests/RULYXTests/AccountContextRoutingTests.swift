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

    // MARK: - Preferred Search Account Routing

    func testPreferredSearchFallsBackToActiveAccount() {
        let store = AccountStore(preview: true)
        store.preferredSearchAccountID = nil
        let search = store.preferredSearchAccountID ?? store.activeAccount?.id
        XCTAssertEqual(search, store.activeAccount?.id, "Should fall back to active account")
    }

    func testPreferredSearchNilWhenNoAccounts() {
        UserDefaults.standard.removeObject(forKey: "bluesky.preferredSearchAccountID")
        let store = AccountStore(keychain: MockKeychain())
        XCTAssertNil(store.preferredSearchAccountID)
        XCTAssertNil(store.activeAccount)
    }

    func testPreferredSearchPersistsAcrossInstances() {
        let store1 = AccountStore(preview: true)
        guard let first = store1.accounts.first else {
            XCTFail("Preview store must have accounts")
            return
        }
        store1.preferredSearchAccountID = first.id

        let store2 = AccountStore(keychain: MockKeychain())
        XCTAssertEqual(store2.preferredSearchAccountID, first.id,
                       "Preferred search must persist across instances via UserDefaults")
    }

    // MARK: - Account Removal Routing

    func testRemoveActiveAccountPromotesNext() {
        let store = AccountStore(preview: true)
        guard store.accounts.count >= 2 else {
            XCTFail("Need ≥2 accounts")
            return
        }
        let first = store.accounts[0]
        store.setActiveAccount(first)
        XCTAssertEqual(store.activeAccount?.id, first.id)

        store.removeAccount(first)
        XCTAssertNotEqual(store.activeAccount?.id, first.id, "Removed account must not remain active")
        if !store.accounts.isEmpty {
            XCTAssertNotNil(store.activeAccount, "Must have active account after removal")
        }
    }

    func testRemovePreferredSearchAccountResets() {
        let store = AccountStore(preview: true)
        guard store.accounts.count >= 2 else {
            XCTFail("Need ≥2 accounts")
            return
        }
        let target = store.accounts[0]
        store.preferredSearchAccountID = target.id

        store.removeAccount(target)
        XCTAssertNotEqual(store.preferredSearchAccountID, target.id,
                          "Removed account must not remain preferred search")
        if !store.accounts.isEmpty {
            XCTAssertNotNil(store.preferredSearchAccountID,
                            "Preferred search must fall back to remaining account")
        }
    }

    func testRemoveLastAccountClearsBoth() {
        let preview = AccountStore(preview: true)
        for acc in preview.accounts {
            preview.removeAccount(acc)
        }
        XCTAssertNil(preview.activeAccount)
        XCTAssertNil(preview.preferredSearchAccountID)
    }

    // MARK: - Active vs Search Separation

    func testActiveAndSearchAccountsCanDiffer() {
        let store = AccountStore(preview: true)
        guard store.accounts.count >= 2 else {
            XCTFail("Need ≥2 accounts")
            return
        }
        let first = store.accounts[0]
        let second = store.accounts[1]
        store.setActiveAccount(first)
        store.preferredSearchAccountID = second.id

        XCTAssertEqual(store.activeAccount?.id, first.id)
        XCTAssertEqual(store.preferredSearchAccountID, second.id)
        XCTAssertNotEqual(store.activeAccount?.id, store.preferredSearchAccountID,
                          "Active and search accounts must be independently configurable")
    }

    // MARK: - Data Account Fallback

    func testDataAccountFallbackChain() {
        let store = AccountStore(preview: true)
        guard let active = store.activeAccount else {
            XCTFail("Preview store must have active account")
            return
        }

        // Nil preferred → active
        store.preferredSearchAccountID = nil
        let data1 = store.preferredSearchAccountID ?? store.activeAccount?.id
        XCTAssertEqual(data1, active.id)

        // Set preferred → preferred
        if let other = store.accounts.first(where: { $0.id != active.id }) {
            store.preferredSearchAccountID = other.id
            let data2 = store.preferredSearchAccountID ?? store.activeAccount?.id
            XCTAssertEqual(data2, other.id, "dataAccount must use preferred search when set")
        }
    }
}
