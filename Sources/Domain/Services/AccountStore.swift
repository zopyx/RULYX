import Foundation

/// View models and stores conforming to this protocol have account-scoped state
/// that must be reset when the active account changes. Register with
/// `AccountStore.registerForReset(_:)` during init; the store iterates
/// every registered observer on `switchAccount` BEFORE publishing the new ID.
/// This replaces the opt-in `NotificationCenter` pattern with a compiler-
/// enforced contract: any view model that forgets to register will ship stale
/// data after a switch.
protocol AccountScopeResettable: AnyObject {
    func resetAccountScopedState()
}

/// Weak wrapper for an `AccountScopeResettable` observer; stored in the registry.
/// Removes the observer automatically when the wrapped object is deallocated.
private struct WeakResettable {
    weak var observer: AccountScopeResettable?
}

/// Manages Bluesky accounts: persistence, activation, authentication, and iCloud sync.
///
/// Responsibilities:
/// - Persists accounts to UserDefaults (encoded JSON).
/// - Stores passwords in the Keychain (not UserDefaults).
/// - Tracks the active account and preferred search account.
/// - Syncs accounts via iCloud (`iCloudAccountSync`).
/// - Reacts to account deactivation/reactivation notifications.
@MainActor
final class AccountStore: ObservableObject, AccountStoreProtocol {
    /// All saved accounts. The first account in the array is the most recently added.
    /// Persisted to UserDefaults as encoded JSON under `"bluesky.savedAccounts"`.
    @Published private(set) var accounts: [AppAccount] = []
    /// The ID of the currently active (selected) account. `nil` when no accounts exist.
    @Published private(set) var activeAccountID: AppAccount.ID?
    /// The ID of the account that was active before the current one. `nil` when there is no previous account.
    /// Used for quick double-tap switching between the last two accounts.
    @Published private(set) var previousActiveAccountID: AppAccount.ID?
    /// The ID of the account used for search operations. Defaults to `activeAccount`.
    /// Persisted to UserDefaults under `"bluesky.preferredSearchAccountID"`.
    @Published var preferredSearchAccountID: AppAccount.ID? {
        didSet {
            defaults.set(preferredSearchAccountID?.uuidString, forKey: preferredSearchKey)
        }
    }

    /// A user-facing error message from the last operation. Set on failure, nil on success.
    @Published var errorMessage: String?
    /// `true` while an account authentication request is in progress.
    @Published private(set) var isAddingAccount = false
    /// Set of account IDs that have been reported as deactivated (via push notification).
    @Published var deactivatedAccountIDs: Set<UUID> = []

    /// Set when the resolved PDS URL for an account's DID differs from the
    /// last-known value. Indicates a potential handle takeover or PDS migration.
    /// The associated DID is the affected account.
    @Published var pdsMigrationDetected: String?

    /// Registry of view models / stores that hold account-scoped state.
    /// Iterated synchronously on `switchAccount` before the active account ID changes.
    /// Weak references prevent accidental retain cycles; unregistration happens
    /// automatically when an observer is deallocated.
    private var resettableObservers: [WeakResettable] = []

    /// The currently active account object. `nil` when no account is active.
    var activeAccount: AppAccount? {
        accounts.first { $0.id == activeAccountID }
    }

    // MARK: - Dependencies

    private let defaults: UserDefaults
    private let keychain: KeychainServicing

    // MARK: - UserDefaults Keys

    private let accountsKey = "bluesky.savedAccounts"
    private let activeAccountKey = "bluesky.activeAccountID"
    private let preferredSearchKey = "bluesky.preferredSearchAccountID"
    private let passwordService = "com.ajung.RULYX.password"

    // MARK: - Init

    init(
        defaults: UserDefaults = .standard,
        keychain: KeychainServicing = KeychainService(),
        preview: Bool = false
    ) {
        self.defaults = defaults
        self.keychain = keychain

        if preview {
            accounts = [
                AppAccount(handle: "team-alpha.bsky.social", displayName: "Team Alpha"),
                AppAccount(handle: "safety-lab.bsky.social", displayName: "Safety Lab"),
            ]
            activeAccountID = accounts.first?.id
            preferredSearchAccountID = accounts.first?.id
            return
        }

        load()

        // Listen for iCloud account sync.
        NotificationCenter.default.addObserver(
            forName: .iCloudAccountsReceived,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let entries = notification.object as? [[String: String]] else { return }
            Task { @MainActor [weak self] in
                self?.mergeCloudAccounts(entries)
            }
        }

        // Listen for account deactivation.
        NotificationCenter.default.addObserver(
            forName: .accountDeactivated,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let idString = notification.userInfo?["accountID"] as? String,
                  let accountID = UUID(uuidString: idString)
            else { return }
            Task { @MainActor [weak self] in
                self?.deactivatedAccountIDs.insert(accountID)
            }
        }

        // Listen for account reactivation.
        NotificationCenter.default.addObserver(
            forName: .accountReactivated,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let idString = notification.userInfo?["accountID"] as? String,
                  let accountID = UUID(uuidString: idString)
            else { return }
            Task { @MainActor [weak self] in
                self?.deactivatedAccountIDs.remove(accountID)
            }
        }
    }

    // MARK: - Account Management

    /// The result of an `addAccount` attempt.
    enum AccountAddResult {
        /// Account was authenticated and added successfully.
        case success
        /// Email 2FA verification code is required. Call `completeAuthWithFactor` with the code.
        case needsAuthFactorToken
        /// Authentication failed. Check `errorMessage` for details.
        case failure
    }

    /// Authenticates a new account and adds it to the store.
    ///
    /// - Parameters:
    ///   - handle: The Bluesky handle (e.g., `user.bsky.social`).
    ///   - appPassword: The app password for authentication.
    ///   - entrywayURL: Optional PDS entryway URL for custom PDS accounts.
    ///   - client: The authentication client.
    /// - Returns: `.success` on success, `.needsAuthFactorToken` when an email 2FA code is required,
    ///            `.failure` on other errors (`errorMessage` is set).
    ///
    /// Validates inputs, checks for duplicates, authenticates against the PDS,
    /// saves the password to Keychain, persists the session, and inserts the account.
    func addAccount(
        handle: String,
        appPassword: String,
        entrywayURL: URL? = nil,
        client: BlueskyAuthenticating
    ) async -> AccountAddResult {
        let trimmedHandle = handle.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPassword = appPassword.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedHandle.isEmpty, !trimmedPassword.isEmpty else {
            errorMessage = String.localized("account.error.handle_and_password_required")
            return .failure
        }

        if accounts.contains(where: { $0.handle.caseInsensitiveCompare(trimmedHandle) == .orderedSame }) {
            errorMessage = String.localized("account.error.already_exists")
            return .failure
        }

        isAddingAccount = true
        defer { isAddingAccount = false }

        do {
            let session = try await client.authenticate(
                handle: trimmedHandle,
                appPassword: trimmedPassword,
                entrywayURL: entrywayURL,
                authFactorToken: nil
            )
            // Detect PDS migration on every authentication
            recordPDSURL(session.pdsURL, forDID: session.did)
            let account = AppAccount(
                handle: session.handle,
                displayName: session.handle,
                did: session.did,
                pdsURL: session.pdsURL,
                entrywayURL: entrywayURL
            )
            try keychain.save(trimmedPassword, service: passwordService, account: account.id.uuidString)
            try await client.persistSession(session, for: account)
            accounts.insert(account, at: 0)
            errorMessage = nil
            // Route through the single transition primitive for cache clear + reset
            // contract. No previous account exists, so cache clear is a no-op.
            await transitionActiveAccount(to: account, using: nil, reason: "account added")
            return .success
        } catch BlueskyAPIError.authFactorTokenRequired {
            return .needsAuthFactorToken
        } catch let caughtError {
            errorMessage = AppError.userMessage(from: caughtError)
            return .failure
        }
    }

    /// Completes authentication with an email 2FA verification code.
    /// Must be called after `addAccount` returns `.needsAuthFactorToken`.
    ///
    /// - Parameters:
    ///   - handle: The same handle used in the initial `addAccount` call.
    ///   - appPassword: The same app password used in the initial call.
    ///   - authFactorToken: The verification code sent via email.
    ///   - entrywayURL: The same entryway URL used in the initial call.
    ///   - client: The authentication client.
    /// - Returns: `true` on success, `false` on failure (`errorMessage` is set).
    func completeAuthWithFactor(
        handle: String,
        appPassword: String,
        authFactorToken: String,
        entrywayURL: URL? = nil,
        client: BlueskyAuthenticating
    ) async -> Bool {
        let trimmedHandle = handle.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPassword = appPassword.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedToken = authFactorToken.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedHandle.isEmpty, !trimmedPassword.isEmpty, !trimmedToken.isEmpty else {
            errorMessage = String.localized("account.error.handle_and_password_required")
            return false
        }

        isAddingAccount = true
        defer { isAddingAccount = false }

        do {
            let session = try await client.authenticate(
                handle: trimmedHandle,
                appPassword: trimmedPassword,
                entrywayURL: entrywayURL,
                authFactorToken: trimmedToken
            )
            let account = AppAccount(
                handle: session.handle,
                displayName: session.handle,
                did: session.did,
                pdsURL: session.pdsURL,
                entrywayURL: entrywayURL
            )
            try keychain.save(trimmedPassword, service: passwordService, account: account.id.uuidString)
            try await client.persistSession(session, for: account)
            accounts.insert(account, at: 0)
            errorMessage = nil
            await transitionActiveAccount(to: account, using: nil, reason: "2FA completed")
            return true
        } catch let caughtError as BlueskyAPIError {
            if case .authFactorTokenRequired = caughtError {
                errorMessage = AppError.userMessage(from: BlueskyAPIError.authFactorTokenRequired)
            } else {
                errorMessage = AppError.userMessage(from: caughtError)
            }
            return false
        } catch let genericError {
            errorMessage = AppError.userMessage(from: genericError)
            return false
        }
    }

    /// Removes an account from the store, deletes its Keychain entry, its persisted
    /// session, and all of its on-disk caches. If it was the active or preferred
    /// search account, falls back to the first remaining account.
    ///
    /// ## Per-account data wiped by this method:
    ///
    /// | Component | Location | Method |
    /// |-----------|----------|--------|
    /// | Keychain password | `passwordService` | `keychain.delete` |
    /// | Persisted session | Keychain `persistedSessionService` | `client.deletePersistedSession` |
    /// | BlueskyAPICache | `~/Library/Caches/...BlueskyAPICache/<SHA256(did)>/` | `BlueskyAPICache.shared.clear(for:)` |
    /// | DashboardCache | `~/Library/Caches/...dashboard/<SHA256(key)>.json` | `DashboardCache.clear(forKey:)` |
    /// | RelationshipCache | `~/Library/Caches/...relationships/<SHA256(key)>.json` | `RelationshipCache.clear(forKey:)` |
    ///
    /// ## Global data NOT reset by account removal:
    ///
    /// - `MutedWordsStore` (user preference, account-independent)
    /// - `InternalListStore` (app-local lists, shared across accounts)
    /// - `AnalyticsStore` (engagement snapshots keyed by post URI)
    /// - `FeedStore` (per-DID keys)
    /// - `WorkspacePreferencesStore` (saved searches)
    /// - Media thumbnails (public CDN content)
    ///
    /// ## "Delete All App Data" action (Settings > Delete All Data):
    ///
    /// Clears ALL stores: audit log, API caches, dashboard/relationship
    /// caches, internal lists, workspaces preferences, analytics, and
    /// muted words. Does NOT remove accounts or credentials — those
    /// require explicit per-account deletion.
    ///
    /// Cache contract: account removal is a logout — the account's social graph and
    /// moderation data must not linger on disk. Clears the account-keyed entries in
    /// `DashboardCache`/`RelationshipCache` and all `BlueskyAPICache` entries for the
    /// account DID. When the LAST account is removed, both caches are wiped entirely
    /// (they also contain entries keyed by inspected third-party subjects).
    func removeAccount(_ account: AppAccount, client: BlueskyAuthenticating? = nil) {
        do {
            try keychain.delete(service: passwordService, account: account.id.uuidString)
        } catch {
            errorMessage = String.localized("account.error.failed_to_delete_credentials")
        }

        if let client {
            try? client.deletePersistedSession(for: account)
        }

        accounts.removeAll { $0.id == account.id }

        // Snapshot the client for the async transition — removeAccount is
        // synchronous but the transition primitive is async.
        let liveClient = client as? LiveBlueskyClient

        if activeAccountID == account.id {
            if let fallback = accounts.first {
                if let liveClient {
                    Task { [weak self] in
                        await self?.transitionActiveAccount(to: fallback, using: liveClient, reason: "active account removed")
                    }
                } else {
                    activeAccountID = fallback.id
                }
            } else {
                activeAccountID = nil
            }
        }

        if preferredSearchAccountID == account.id {
            preferredSearchAccountID = accounts.first?.id
        }

        if previousActiveAccountID == account.id {
            previousActiveAccountID = nil
        }

        // Logout hygiene: wipe the removed account's on-disk caches.
        if accounts.isEmpty {
            DashboardCache.clearAll()
            RelationshipCache.clearAll()
        } else {
            let key = account.did ?? account.handle
            DashboardCache.clear(forKey: key)
            if let did = account.did {
                RelationshipCache.clear(forKey: "blocking_\(did)")
                RelationshipCache.clear(forKey: "blockedBy_\(did)")
                RelationshipCache.clear(forKey: "followers_diff_\(did)")
            }
        }
        if let did = account.did {
            Task { await BlueskyAPICache.shared.clear(for: did) }
        }

        persist()
    }

    /// Deprecated: use `switchAccount(to:using:)` instead — this bypass resets all
    /// caches and resettable observers, leading to stale data from the previous
    /// account surfacing in the active view. Kept only for internal migration paths.
    @available(*, deprecated, message: "Use switchAccount(to:using:) — this method bypasses the transition primitive and ships stale account state. Production code must route through transitionActiveAccount.")
    func setActiveAccount(_ account: AppAccount) {
        guard accounts.contains(account) else { return }
        activeAccountID = account.id
        if let index = accounts.firstIndex(of: account) {
            accounts[index].lastUsedAt = .now
        }
        persist()
    }

    /// Records the resolved PDS URL for a DID. If a previous PDS URL exists
    /// and differs from the new one, sets `pdsMigrationDetected` to flag a
    /// potential handle takeover or PDS migration.
    func recordPDSURL(_ url: URL, forDID did: String) {
        let key = "pds.known.\(did)"
        if let previous = UserDefaults.standard.string(forKey: key),
           let previousURL = URL(string: previous),
           previousURL.absoluteString != url.absoluteString
        {
            AppLogger.persistence.warning("PDS URL changed for \(did): \(previous) → \(url)")
            pdsMigrationDetected = did
        }
        UserDefaults.standard.set(url.absoluteString, forKey: key)
    }

    /// Dismisses the PDS migration warning.
    func dismissPDSMigrationWarning() {
        pdsMigrationDetected = nil
    }

    /// Serializes account transitions. Non-nil while a transition is in
    /// progress; concurrent switch attempts are rejected.
    private var activeTransitionToken: UUID?

    /// Single private primitive for all active-account-ID changes.
    /// Every production path that assigns `activeAccountID` MUST route through
    /// this method — `addAccount`, `completeAuthWithFactor`, `removeAccount`,
    /// `switchAccount`, and resolution of the preferred-search-account fallback.
    ///
    /// Ordering invariant (preserved exactly):
    /// 1. Reject no-op transitions (same account)
    /// 2. Serialize (reject concurrent transitions)
    /// 3. Clear HTTP/URL caches, BlueskyAPICache (disk)
    /// 4. Clear Dashboard/Relationship caches (disk)
    /// 5. Invalidate in-memory services (ThreadCache)
    /// 6. Post .accountWillSwitch notification (backward compat)
    /// 7. Iterate AccountScopeResettable registry
    /// 8. Assign activeAccountID (publishes the change)
    /// 9. Update lastUsedAt timestamp
    /// 10. Persist
    /// 11. End transition
    private func transitionActiveAccount(
        to account: AppAccount,
        using client: LiveBlueskyClient?,
        reason: String
    ) async {
        guard accounts.contains(account) else { return }
        guard account.id != activeAccountID else { return } // no-op if already active

        // Serialize: reject concurrent transitions
        guard activeTransitionToken == nil else {
            AppLogger.persistence.warning("Account switch rejected — transition already in progress")
            return
        }
        let token = UUID()
        activeTransitionToken = token

        AppLogger.persistence.info("Account switch requested for \(account.handle) (reason: \(reason))")
        // Track the previous account before switching
        previousActiveAccountID = activeAccountID
        // Clear ALL caches — await URL/API cache, Dashboard/Relationship cache, thread cache
        if let client {
            await client.clearAllCaches()
        }
        DashboardCache.clearAll()
        RelationshipCache.clearAll()
        ThreadCacheService.shared.invalidateAll()
        // Notify old NotificationCenter observers (backward compat). New code
        // conforms to AccountScopeResettable and registers via registerForReset(_:).
        NotificationCenter.default.post(name: .accountWillSwitch, object: account)
        // Iterate the compiled registry — every registered observer gets its
        // reset callback BEFORE the active account ID changes. Prune deallocated
        // observers in the same pass.
        resettableObservers.removeAll { $0.observer == nil }
        for wrapper in resettableObservers {
            wrapper.observer?.resetAccountScopedState()
        }
        // Guard: another transition may have been started during an await above.
        guard activeTransitionToken == token else {
            AppLogger.persistence.info("Account switch superseded — newer transition took priority")
            return
        }
        // Assign last: publishes the change only after every reset above has completed.
        activeAccountID = account.id
        if let index = accounts.firstIndex(of: account) {
            accounts[index].lastUsedAt = .now
        }
        persist()
        activeTransitionToken = nil
        AppLogger.persistence.info("Account switch completed for \(account.handle)")
    }

    /// Public API: switches the active account through the single transition
    /// primitive, clearing all account-scoped caches and state before publishing.
    func switchAccount(to account: AppAccount, using client: LiveBlueskyClient) async {
        await transitionActiveAccount(to: account, using: client, reason: "user-initiated switch")
    }

    /// Registers an observer whose `resetAccountScopedState()` will be called
    /// synchronously on every account switch before the active account ID changes.
    /// Observers are held weakly — no need to unregister manually.
    func registerForReset(_ observer: AccountScopeResettable) {
        // Deduplicate
        resettableObservers.removeAll { $0.observer === observer || $0.observer == nil }
        resettableObservers.append(WeakResettable(observer: observer))
    }

    /// Manually unregisters an observer (optional — weak references auto-clean).
    func unregisterForReset(_ observer: AccountScopeResettable) {
        resettableObservers.removeAll { $0.observer === observer }
    }

    /// Returns `true` if the given account has been flagged as deactivated.
    func isDeactivated(_ account: AppAccount) -> Bool {
        deactivatedAccountIDs.contains(account.id)
    }

    /// Sets or clears a user-defined label for an account.
    func setLabel(for account: AppAccount, label: String?) {
        guard let index = accounts.firstIndex(of: account) else { return }
        accounts[index].label = label?.isEmpty == true ? nil : label
        persist()
    }

    /// Reorders accounts by moving from the given source offsets to the given destination.
    func moveAccount(from source: IndexSet, to destination: Int) {
        accounts.move(fromOffsets: source, toOffset: destination)
        persist()
    }

    /// Retrieves the app password for an account from the Keychain.
    func appPassword(for account: AppAccount) -> String? {
        try? keychain.read(service: passwordService, account: account.id.uuidString)
    }

    /// Fetches profile data for all accounts and updates their display names, avatars, and DIDs.
    func refreshAccountProfiles(using client: BlueskyProfileInspecting) async {
        guard !accounts.isEmpty else { return }

        var updatedAccounts = accounts
        var didChange = false

        for index in updatedAccounts.indices {
            let account = updatedAccounts[index]
            let appPassword = appPassword(for: account)

            do {
                let profile = try await client.fetchProfile(
                    did: account.did ?? account.handle,
                    account: account,
                    appPassword: appPassword
                )

                let title = profile.title
                if updatedAccounts[index].displayName != title {
                    updatedAccounts[index].displayName = title
                    didChange = true
                }
                if updatedAccounts[index].avatarURL != profile.avatarURL {
                    updatedAccounts[index].avatarURL = profile.avatarURL
                    didChange = true
                }
                // Update the handle if it changed on the server (e.g. user renamed via web).
                if updatedAccounts[index].handle != profile.handle {
                    updatedAccounts[index].handle = profile.handle
                    didChange = true
                }
                // Always invalidate cached avatar so AsyncImage re-fetches
                // (Bluesky may reuse the same CDN URL after avatar changes)
                if let url = updatedAccounts[index].avatarURL {
                    URLCache.shared.removeCachedResponse(for: URLRequest(url: url))
                }
                if updatedAccounts[index].did != profile.did {
                    updatedAccounts[index].did = profile.did
                    didChange = true
                }
            } catch {
                AppLogger.moderation.error("Failed to refresh profile for \(account.handle, privacy: .private): \(error.localizedDescription, privacy: .public)")
                continue
            }
        }

        if didChange {
            accounts = updatedAccounts
            persist()
        }
    }

    // MARK: - Persistence

    /// Loads accounts and preferences from UserDefaults.
    private func load() {
        guard let data = defaults.data(forKey: accountsKey) else {
            return
        }

        do {
            accounts = try JSONDecoder().decode([AppAccount].self, from: data)
            if let activeIDString = defaults.string(forKey: activeAccountKey),
               let activeID = UUID(uuidString: activeIDString),
               accounts.contains(where: { $0.id == activeID })
            {
                activeAccountID = activeID
            } else {
                activeAccountID = accounts.first?.id
            }
            if let prefIDString = defaults.string(forKey: preferredSearchKey),
               let prefID = UUID(uuidString: prefIDString),
               accounts.contains(where: { $0.id == prefID })
            {
                preferredSearchAccountID = prefID
            }
        } catch {
            errorMessage = String.localized("account.error.failed_to_restore")
        }
    }

    /// Persists accounts and active account ID to UserDefaults.
    /// Also pushes the account list to iCloud sync.
    private func persist() {
        do {
            let data = try JSONEncoder().encode(accounts)
            defaults.set(data, forKey: accountsKey)
            defaults.set(activeAccountID?.uuidString, forKey: activeAccountKey)
        } catch {
            errorMessage = String.localized("account.error.failed_to_save")
        }
        iCloudAccountSync.shared.pushAccounts(accounts)
    }

    /// Merges accounts received from iCloud sync into the local store.
    /// New accounts are appended; existing accounts have their labels updated.
    private func mergeCloudAccounts(_ entries: [[String: String]]) {
        for entry in entries {
            guard let idString = entry["id"], let id = UUID(uuidString: idString),
                  let handle = entry["handle"] else { continue }
            let displayName = entry["displayName"] ?? handle
            let did = entry["did"]
            let label = entry["label"].flatMap { $0.isEmpty ? nil : $0 }
            let pdsURL = entry["pdsURL"].flatMap { $0.isEmpty ? nil : URL(string: $0) }
            let entrywayURL = entry["entrywayURL"].flatMap { $0.isEmpty ? nil : URL(string: $0) }

            if !accounts.contains(where: { $0.id == id }) {
                let account = AppAccount(
                    id: id, handle: handle, displayName: displayName,
                    did: did, pdsURL: pdsURL, entrywayURL: entrywayURL,
                    label: label
                )
                accounts.append(account)
                persist()
            } else if let index = accounts.firstIndex(where: { $0.id == id }) {
                var updated = accounts[index]
                if label != updated.label {
                    updated.label = label
                    accounts[index] = updated
                    persist()
                }
            }
        }
    }
}

extension Notification.Name {
    /// Posted synchronously inside `AccountStore.switchAccount(to:using:)` — after all caches
    /// are cleared, but BEFORE `activeAccountID` changes. `object` is the new `AppAccount`.
    /// Account-scoped view models observe this to zero counters/visible state immediately,
    /// independent of view lifecycle (works for tabs that are alive but not visible).
    static let accountWillSwitch = Notification.Name("accountWillSwitch")
}
