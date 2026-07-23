@testable import RULYX
import XCTest

@MainActor
final class AccountStoreTests: XCTestCase {
    private func makeStore(functionName: String = #function) -> (AccountStore, MockKeychainService) {
        let defaults = UserDefaults(suiteName: functionName)!
        defaults.removePersistentDomain(forName: functionName)
        let keychain = MockKeychainService()
        let store = AccountStore(defaults: defaults, keychain: keychain)
        return (store, keychain)
    }

    @discardableResult
    private func addTestAccount(store: AccountStore, client: BlueskyAuthenticating, handle: String = "moderator.bsky.social") async -> AccountStore.AccountAddResult {
        await store.addAccount(handle: handle, appPassword: "abcd-efgh-ijkl-mnop", client: client)
    }

    // MARK: - Add Account

    func testAddAccountPersistsAppPassword() async {
        let (store, keychain) = makeStore()
        let client = MockAuthenticatingClient()

        let didAdd = await addTestAccount(store: store, client: client)

        XCTAssertEqual(didAdd, .success)
        XCTAssertEqual(store.accounts.count, 1)
        XCTAssertNil(store.errorMessage)

        guard let account = store.activeAccount else {
            return XCTFail("Expected active account")
        }
        XCTAssertEqual(account.handle, "moderator.bsky.social")
        XCTAssertEqual(
            keychain.savedValues["com.ajung.RULYX.password:\(account.id.uuidString)"],
            "abcd-efgh-ijkl-mnop"
        )
        XCTAssertEqual(store.appPassword(for: account), "abcd-efgh-ijkl-mnop")
    }

    func testAddAccountRejectsEmptyHandle() async {
        let (store, _) = makeStore()
        let client = MockAuthenticatingClient()

        let didAdd = await store.addAccount(handle: "", appPassword: "abcd-efgh-ijkl-mnop", client: client)

        XCTAssertEqual(didAdd, .failure)
        XCTAssertEqual(store.errorMessage, String.localized("account.error.handle_and_password_required"))
        XCTAssertTrue(store.accounts.isEmpty)
    }

    func testAddAccountRejectsEmptyPassword() async {
        let (store, _) = makeStore()
        let client = MockAuthenticatingClient()

        let didAdd = await store.addAccount(handle: "moderator.bsky.social", appPassword: "", client: client)

        XCTAssertEqual(didAdd, .failure)
        XCTAssertEqual(store.errorMessage, String.localized("account.error.handle_and_password_required"))
        XCTAssertTrue(store.accounts.isEmpty)
    }

    func testAddAccountRejectsDuplicateHandle() async {
        let (store, _) = makeStore()
        let client = MockAuthenticatingClient()

        let first = await addTestAccount(store: store, client: client)
        XCTAssertEqual(first, .success)

        let second = await addTestAccount(store: store, client: client)

        XCTAssertEqual(second, .failure)
        XCTAssertEqual(store.errorMessage, String.localized("account.error.already_exists"))
        XCTAssertEqual(store.accounts.count, 1)
    }

    func testAddAccountTrimsWhitespace() async {
        let (store, _) = makeStore()
        let client = MockAuthenticatingClient()

        let didAdd = await store.addAccount(handle: "  moderator.bsky.social  ", appPassword: "  abcd-efgh-ijkl-mnop  ", client: client)

        XCTAssertEqual(didAdd, .success)
        XCTAssertEqual(store.accounts.count, 1)
        XCTAssertEqual(store.activeAccount?.handle, "moderator.bsky.social")
    }

    func testAddAccountFailsOnAuthError() async {
        let (store, _) = makeStore()
        let client = MockAuthenticatingClient(shouldFailAuth: true)

        let didAdd = await addTestAccount(store: store, client: client)

        XCTAssertEqual(didAdd, .failure)
        XCTAssertNotNil(store.errorMessage)
        XCTAssertTrue(store.accounts.isEmpty)
    }

    // MARK: - Remove Account

    func testRemoveAccountRemovesFromStore() async {
        let (store, _) = makeStore()
        let client = MockAuthenticatingClient()

        await addTestAccount(store: store, client: client)
        guard let account = store.activeAccount else { return XCTFail() }

        store.removeAccount(account, client: client)

        XCTAssertTrue(store.accounts.isEmpty)
        XCTAssertNil(store.activeAccount)
        XCTAssertNil(store.appPassword(for: account))
    }

    func testRemoveAccountClearsKeychain() async {
        let (store, keychain) = makeStore()
        let client = MockAuthenticatingClient()

        await addTestAccount(store: store, client: client)
        guard let account = store.activeAccount else { return XCTFail() }

        let serviceKey = "com.ajung.RULYX.password:\(account.id.uuidString)"
        XCTAssertNotNil(keychain.savedValues[serviceKey])

        store.removeAccount(account, client: client)

        XCTAssertNil(keychain.savedValues[serviceKey])
    }

    func testRemoveAccountDeletesSession() async {
        let (store, _) = makeStore()
        let client = MockAuthenticatingClient()

        await addTestAccount(store: store, client: client)
        guard let account = store.activeAccount else { return XCTFail() }

        XCTAssertFalse(client.didDeleteSession)

        store.removeAccount(account, client: client)

        XCTAssertTrue(client.didDeleteSession)
    }

    func testRemoveAccountSetsActiveToFirstRemaining() async {
        let (store, _) = makeStore()
        let client = MockAuthenticatingClient()

        await addTestAccount(store: store, client: client, handle: "alpha.bsky.social")
        await addTestAccount(store: store, client: client, handle: "beta.bsky.social")
        let firstAccount = store.accounts[0]

        store.removeAccount(firstAccount, client: client)

        XCTAssertEqual(store.accounts.count, 1)
        XCTAssertEqual(store.activeAccount?.handle, "alpha.bsky.social")
    }

    // MARK: - Set Active Account

    func testSetActiveAccountSwitchesActive() async {
        let (store, _) = makeStore()
        let client = MockAuthenticatingClient()

        await addTestAccount(store: store, client: client, handle: "alpha.bsky.social")
        await addTestAccount(store: store, client: client, handle: "beta.bsky.social")
        guard let firstAccount = store.accounts.first(where: { $0.handle == "alpha.bsky.social" }) else { return XCTFail() }
        guard let secondAccount = store.accounts.first(where: { $0.handle == "beta.bsky.social" }) else { return XCTFail() }

        store.setActiveAccount(secondAccount)

        XCTAssertEqual(store.activeAccount?.id, secondAccount.id)

        store.setActiveAccount(firstAccount)

        XCTAssertEqual(store.activeAccount?.id, firstAccount.id)
    }

    func testSetActiveAccountUpdatesLastUsed() async {
        let (store, _) = makeStore()
        let client = MockAuthenticatingClient()

        await addTestAccount(store: store, client: client, handle: "alpha.bsky.social")
        await addTestAccount(store: store, client: client, handle: "beta.bsky.social")
        guard let account = store.accounts.first(where: { $0.handle == "beta.bsky.social" }) else { return XCTFail() }

        let originalLastUsed = account.lastUsedAt

        store.setActiveAccount(account)

        let updatedAccount = store.accounts.first { $0.id == account.id }
        XCTAssertGreaterThan(updatedAccount?.lastUsedAt ?? originalLastUsed, originalLastUsed)
    }

    func testSetActiveAccountIgnoresUnknownAccount() async {
        let (store, _) = makeStore()
        let client = MockAuthenticatingClient()

        await addTestAccount(store: store, client: client)
        let unknownAccount = AppAccount(handle: "unknown.bsky.social")

        store.setActiveAccount(unknownAccount)

        XCTAssertNotNil(store.activeAccount)
        XCTAssertNotEqual(store.activeAccount?.handle, "unknown.bsky.social")
    }

    // MARK: - Switch Account (Cache Reset)

    func testSwitchAccountClearsThreadCacheAndTracksPrevious() async {
        let (store, _) = makeStore()
        let client = MockAuthenticatingClient()

        await addTestAccount(store: store, client: client, handle: "alpha.bsky.social")
        await addTestAccount(store: store, client: client, handle: "beta.bsky.social")
        guard let firstAccount = store.accounts.first(where: { $0.handle == "alpha.bsky.social" }) else { return XCTFail("alpha account missing") }
        guard let secondAccount = store.accounts.first(where: { $0.handle == "beta.bsky.social" }) else { return XCTFail("beta account missing") }

        // Seed the in-memory thread cache with a stale entry
        let postNode = ThreadPostNode(
            uri: "at://did:plc:x/app.bsky.feed.post/1",
            cid: nil, author: nil, record: nil, embed: nil, viewer: nil,
            replyCount: nil, repostCount: nil, likeCount: nil, indexedAt: nil,
            isBlocked: false, isNotFound: false
        )
        let threadURI = postNode.uri ?? ""
        ThreadCacheService.shared.set(uri: threadURI, thread: ThreadNode(post: postNode, parent: nil, replies: nil))
        XCTAssertNotNil(ThreadCacheService.shared.get(uri: threadURI))

        // Second account is active after addAccount; switch back to the first
        await store.switchAccount(to: firstAccount, using: LiveBlueskyClient())

        XCTAssertEqual(store.activeAccountID, firstAccount.id)
        XCTAssertEqual(store.previousActiveAccountID, secondAccount.id)
        XCTAssertNil(ThreadCacheService.shared.get(uri: threadURI), "Thread cache must be cleared on account switch")
    }

    func testSwitchAccountToSameAccountIsNoOp() async {
        let (store, _) = makeStore()
        let client = MockAuthenticatingClient()

        await addTestAccount(store: store, client: client)
        guard let account = store.activeAccount else { return XCTFail("Expected active account") }

        await store.switchAccount(to: account, using: LiveBlueskyClient())

        XCTAssertEqual(store.activeAccountID, account.id)
        XCTAssertNil(store.previousActiveAccountID)
    }

    func testSwitchAccountPostsWillSwitchBeforeIDChange() async {
        let (store, _) = makeStore()
        let client = MockAuthenticatingClient()

        await addTestAccount(store: store, client: client, handle: "alpha.bsky.social")
        await addTestAccount(store: store, client: client, handle: "beta.bsky.social")
        guard let firstAccount = store.accounts.first(where: { $0.handle == "alpha.bsky.social" }) else { return XCTFail("alpha account missing") }
        let oldID = store.activeAccountID

        var postedOldID: UUID??
        var postedObject: AppAccount?
        let observer = NotificationCenter.default.addObserver(
            forName: .accountWillSwitch, object: nil, queue: nil
        ) { notification in
            let object = notification.object as? AppAccount
            MainActor.assumeIsolated {
                postedOldID = store.activeAccountID
                postedObject = object
            }
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        await store.switchAccount(to: firstAccount, using: LiveBlueskyClient())

        XCTAssertEqual(postedOldID ?? nil, oldID, "accountWillSwitch must fire before activeAccountID changes")
        XCTAssertEqual(postedObject?.id, firstAccount.id)
    }

    func testSwitchAccountNoOpDoesNotPostWillSwitch() async {
        let (store, _) = makeStore()
        let client = MockAuthenticatingClient()

        await addTestAccount(store: store, client: client)
        guard let account = store.activeAccount else { return XCTFail("Expected active account") }

        var didPost = false
        let observer = NotificationCenter.default.addObserver(
            forName: .accountWillSwitch, object: nil, queue: nil
        ) { _ in didPost = true }
        defer { NotificationCenter.default.removeObserver(observer) }

        await store.switchAccount(to: account, using: LiveBlueskyClient())

        XCTAssertFalse(didPost)
    }

    // MARK: - Labels

    func testSetLabelUpdatesLabel() async {
        let (store, _) = makeStore()
        let client = MockAuthenticatingClient()

        await addTestAccount(store: store, client: client)
        guard let account = store.activeAccount else { return XCTFail() }

        store.setLabel(for: account, label: "Work")

        let updatedAccount = store.accounts.first { $0.id == account.id }
        XCTAssertEqual(updatedAccount?.label, "Work")
    }

    func testSetLabelRemovesLabelWhenEmpty() async {
        let (store, _) = makeStore()
        let client = MockAuthenticatingClient()

        await addTestAccount(store: store, client: client)
        guard let account = store.activeAccount else { return XCTFail() }

        store.setLabel(for: account, label: "Work")
        var updatedAccount = store.accounts.first { $0.id == account.id }
        XCTAssertEqual(updatedAccount?.label, "Work")

        guard let reFetched = updatedAccount else { return XCTFail() }
        store.setLabel(for: reFetched, label: "")

        updatedAccount = store.accounts.first { $0.id == account.id }
        XCTAssertNil(updatedAccount?.label)
    }

    func testSetLabelPersistsAcrossStoreRecreation() async throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: #function))
        defaults.removePersistentDomain(forName: #function)
        let keychain = MockKeychainService()

        let store1 = AccountStore(defaults: defaults, keychain: keychain)
        let client = MockAuthenticatingClient()
        await addTestAccount(store: store1, client: client)
        guard let account = store1.activeAccount else { return XCTFail() }

        store1.setLabel(for: account, label: "Work")

        let store2 = AccountStore(defaults: defaults, keychain: keychain)

        XCTAssertEqual(store2.accounts.first?.label, "Work")
    }

    // MARK: - Move / Reorder

    func testMoveAccountChangesOrder() async {
        let (store, _) = makeStore()
        let client = MockAuthenticatingClient()

        await addTestAccount(store: store, client: client, handle: "alpha.bsky.social")
        await addTestAccount(store: store, client: client, handle: "beta.bsky.social")
        await addTestAccount(store: store, client: client, handle: "gamma.bsky.social")

        XCTAssertEqual(store.accounts.map(\.handle), ["gamma.bsky.social", "beta.bsky.social", "alpha.bsky.social"])

        store.moveAccount(from: IndexSet(integer: 0), to: 3)

        XCTAssertEqual(store.accounts.map(\.handle), ["beta.bsky.social", "alpha.bsky.social", "gamma.bsky.social"])
    }

    // MARK: - Active Account

    func testActiveAccountReturnsFirstWhenNoneSet() async {
        let (store, _) = makeStore()
        let client = MockAuthenticatingClient()

        await addTestAccount(store: store, client: client, handle: "alpha.bsky.social")
        await addTestAccount(store: store, client: client, handle: "beta.bsky.social")

        XCTAssertEqual(store.activeAccount?.handle, "beta.bsky.social")
    }

    func testActiveAccountIsNilWhenEmpty() {
        let (store, _) = makeStore()

        XCTAssertNil(store.activeAccount)
    }

    // MARK: - Persistence

    func testLoadRestoresSavedAccounts() async throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: #function))
        defaults.removePersistentDomain(forName: #function)
        let keychain = MockKeychainService()

        let store1 = AccountStore(defaults: defaults, keychain: keychain)
        let client = MockAuthenticatingClient()
        await addTestAccount(store: store1, client: client, handle: "alpha.bsky.social")
        await addTestAccount(store: store1, client: client, handle: "beta.bsky.social")
        store1.setLabel(for: store1.accounts[1], label: "Work")

        let store2 = AccountStore(defaults: defaults, keychain: keychain)

        XCTAssertEqual(store2.accounts.count, 2)
        XCTAssertEqual(store2.accounts[0].handle, "beta.bsky.social")
        XCTAssertEqual(store2.accounts[1].handle, "alpha.bsky.social")
        XCTAssertEqual(store2.activeAccount?.handle, "beta.bsky.social")
        XCTAssertEqual(store2.accounts[1].label, "Work")
    }

    func testLoadHandlesCorruptedDataGracefully() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: #function))
        defaults.removePersistentDomain(forName: #function)
        defaults.set("not-valid-json".data(using: .utf8), forKey: "bluesky.savedAccounts")

        let (store, _) = makeStore(functionName: #function)

        XCTAssertTrue(store.accounts.isEmpty)
        XCTAssertNil(store.activeAccount)
    }

    // MARK: - Error Messages

    func testErrorMessageClearsOnSuccess() async {
        let (store, _) = makeStore()
        let client = MockAuthenticatingClient()

        _ = await store.addAccount(handle: "", appPassword: "", client: client)
        XCTAssertNotNil(store.errorMessage)

        let didAdd = await addTestAccount(store: store, client: client)

        XCTAssertEqual(didAdd, .success)
        XCTAssertNil(store.errorMessage)
    }

    func testIsAddingAccountFlag() async {
        let (store, _) = makeStore()
        let client = MockAuthenticatingClient()

        let task = Task {
            await addTestAccount(store: store, client: client)
        }
        try? await Task.sleep(for: .milliseconds(10))

        let flagsDuringAdd = store.isAddingAccount
        await task.value

        XCTAssertFalse(flagsDuringAdd)
        XCTAssertFalse(store.isAddingAccount)
    }

    // MARK: - Refresh Account Profiles

    func testRefreshAccountProfilesUpdatesHandleWhenChanged() async {
        let (store, _) = makeStore()
        let authClient = MockAuthenticatingClient()
        let profileService = MockProfileService()

        await addTestAccount(store: store, client: authClient, handle: "old-handle.bsky.social")
        guard let account = store.activeAccount else { return XCTFail() }
        XCTAssertEqual(account.handle, "old-handle.bsky.social")

        profileService.fetchProfileHandler = { did, _, _ in
            BlueskyProfile(
                id: did,
                did: did,
                handle: "new-handle.bsky.social",
                displayName: "old-handle.bsky.social",
                description: nil,
                websiteURL: nil,
                avatarURL: nil,
                bannerURL: nil,
                followersCount: 0,
                followsCount: 0,
                postsCount: 0,
                listsCount: nil,
                starterPacksCount: nil,
                createdAt: nil,
                labels: [],
                viewerState: nil
            )
        }

        await store.refreshAccountProfiles(using: profileService)

        XCTAssertEqual(store.activeAccount?.handle, "new-handle.bsky.social")
    }

    func testRefreshAccountProfilesUpdatesDisplayNameAndHandle() async {
        let (store, _) = makeStore()
        let authClient = MockAuthenticatingClient()
        let profileService = MockProfileService()

        await addTestAccount(store: store, client: authClient, handle: "old.bsky.social")
        XCTAssertEqual(store.activeAccount?.displayName, "old.bsky.social")

        profileService.fetchProfileHandler = { did, _, _ in
            BlueskyProfile(
                id: did,
                did: did,
                handle: "renamed.bsky.social",
                displayName: "Renamed User",
                description: nil,
                websiteURL: nil,
                avatarURL: nil,
                bannerURL: nil,
                followersCount: 0,
                followsCount: 0,
                postsCount: 0,
                listsCount: nil,
                starterPacksCount: nil,
                createdAt: nil,
                labels: [],
                viewerState: nil
            )
        }

        await store.refreshAccountProfiles(using: profileService)

        XCTAssertEqual(store.activeAccount?.handle, "renamed.bsky.social")
        XCTAssertEqual(store.activeAccount?.displayName, "Renamed User")
    }

    func testRefreshAccountProfilesPersistsHandleAcrossStoreRecreation() async throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: #function))
        defaults.removePersistentDomain(forName: #function)
        let keychain = MockKeychainService()

        let store1 = AccountStore(defaults: defaults, keychain: keychain)
        let authClient = MockAuthenticatingClient()
        let profileService = MockProfileService()

        await addTestAccount(store: store1, client: authClient, handle: "old.bsky.social")

        profileService.fetchProfileHandler = { did, _, _ in
            BlueskyProfile(
                id: did,
                did: did,
                handle: "persisted.bsky.social",
                displayName: "old.bsky.social",
                description: nil,
                websiteURL: nil,
                avatarURL: nil,
                bannerURL: nil,
                followersCount: 0,
                followsCount: 0,
                postsCount: 0,
                listsCount: nil,
                starterPacksCount: nil,
                createdAt: nil,
                labels: [],
                viewerState: nil
            )
        }

        await store1.refreshAccountProfiles(using: profileService)
        XCTAssertEqual(store1.activeAccount?.handle, "persisted.bsky.social")

        let store2 = AccountStore(defaults: defaults, keychain: keychain)
        XCTAssertEqual(store2.activeAccount?.handle, "persisted.bsky.social")
    }

    func testRefreshAccountProfilesHandlesNetworkErrorGracefully() async {
        let (store, _) = makeStore()
        let authClient = MockAuthenticatingClient()
        let profileService = MockProfileService()

        await addTestAccount(store: store, client: authClient, handle: "unchanged.bsky.social")
        XCTAssertEqual(store.activeAccount?.handle, "unchanged.bsky.social")

        // Simulate a network error
        profileService.fetchProfileHandler = { _, _, _ in
            throw BlueskyAPIError.server("Network error")
        }

        await store.refreshAccountProfiles(using: profileService)

        // Account unchanged after error
        XCTAssertEqual(store.activeAccount?.handle, "unchanged.bsky.social")
    }

    func testRefreshAccountProfilesUpdatesDidWhenChanged() async {
        let (store, _) = makeStore()
        let authClient = MockAuthenticatingClient()
        let profileService = MockProfileService()

        await addTestAccount(store: store, client: authClient, handle: "did-test.bsky.social")
        XCTAssertEqual(store.activeAccount?.did, "did:plc:test")

        profileService.fetchProfileHandler = { did, _, _ in
            BlueskyProfile(
                id: did,
                did: "did:plc:updated",
                handle: "did-test.bsky.social",
                displayName: "did-test.bsky.social",
                description: nil,
                websiteURL: nil,
                avatarURL: nil,
                bannerURL: nil,
                followersCount: 0,
                followsCount: 0,
                postsCount: 0,
                listsCount: nil,
                starterPacksCount: nil,
                createdAt: nil,
                labels: [],
                viewerState: nil
            )
        }

        await store.refreshAccountProfiles(using: profileService)

        XCTAssertEqual(store.activeAccount?.did, "did:plc:updated")
    }

    func testRefreshAccountProfilesUpdatesMultipleAccounts() async {
        let (store, _) = makeStore()
        let authClient = MockAuthenticatingClient()
        let profileService = MockProfileService()

        await addTestAccount(store: store, client: authClient, handle: "alpha.bsky.social")
        await addTestAccount(store: store, client: authClient, handle: "beta.bsky.social")

        final class FetchCounter: @unchecked Sendable {
            var value = 0
        }
        let counter = FetchCounter()

        profileService.fetchProfileHandler = { [counter] did, _, _ in
            counter.value += 1
            if counter.value == 1 {
                return BlueskyProfile(
                    id: did, did: did, handle: "alpha-renamed.bsky.social",
                    displayName: "Alpha Renamed", description: nil,
                    websiteURL: nil, avatarURL: nil, bannerURL: nil,
                    followersCount: 0, followsCount: 0, postsCount: 0,
                    listsCount: nil, starterPacksCount: nil,
                    createdAt: nil, labels: [], viewerState: nil
                )
            }
            return BlueskyProfile(
                id: did, did: did, handle: "beta-renamed.bsky.social",
                displayName: "Beta Renamed", description: nil,
                websiteURL: nil, avatarURL: nil, bannerURL: nil,
                followersCount: 0, followsCount: 0, postsCount: 0,
                listsCount: nil, starterPacksCount: nil,
                createdAt: nil, labels: [], viewerState: nil
            )
        }

        await store.refreshAccountProfiles(using: profileService)

        XCTAssertEqual(counter.value, 2)
        XCTAssertEqual(store.accounts.count, 2)

        let alpha = store.accounts.first { $0.handle == "alpha-renamed.bsky.social" }
        let beta = store.accounts.first { $0.handle == "beta-renamed.bsky.social" }
        XCTAssertNotNil(alpha)
        XCTAssertNotNil(beta)
        XCTAssertEqual(alpha?.displayName, "Alpha Renamed")
        XCTAssertEqual(beta?.displayName, "Beta Renamed")
    }
}

private final class MockKeychainService: KeychainServicing, @unchecked Sendable {
    var savedValues: [String: String] = [:]

    func save(_ value: String, service: String, account: String) throws {
        savedValues["\(service):\(account)"] = value
    }

    func read(service: String, account: String) throws -> String? {
        savedValues["\(service):\(account)"]
    }

    func delete(service: String, account: String) throws {
        savedValues.removeValue(forKey: "\(service):\(account)")
    }
}

@MainActor
private final class MockAuthenticatingClient: BlueskyAuthenticating {
    let shouldFailAuth: Bool
    var didDeleteSession = false

    init(shouldFailAuth: Bool = false) {
        self.shouldFailAuth = shouldFailAuth
    }

    func authenticate(handle: String, appPassword _: String, entrywayURL _: URL? = nil, authFactorToken _: String? = nil) async throws -> BlueskySession {
        if shouldFailAuth {
            throw BlueskyAPIError.unauthorized
        }
        return BlueskySession(
            did: "did:plc:test",
            handle: handle,
            accessJWT: "access",
            refreshJWT: "refresh",
            pdsURL: URL(string: "https://bsky.social")!
        )
    }

    func persistSession(_: BlueskySession, for _: AppAccount) async throws {}

    func deletePersistedSession(for _: AppAccount) throws {
        didDeleteSession = true
    }
}
