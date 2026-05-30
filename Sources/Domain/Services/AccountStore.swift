import Foundation

/// Manages Bluesky accounts: persistence, activation, authentication, and iCloud sync.
///
/// Responsibilities:
/// - Persists accounts to UserDefaults (encoded JSON).
/// - Stores passwords in the Keychain (not UserDefaults).
/// - Tracks the active account and preferred search account.
/// - Syncs accounts via iCloud (`iCloudAccountSync`).
/// - Reacts to account deactivation/reactivation notifications.
@MainActor
final class AccountStore: ObservableObject {
    /// All saved accounts. The first account in the array is the most recently added.
    /// Persisted to UserDefaults as encoded JSON under `"bluesky.savedAccounts"`.
    @Published private(set) var accounts: [AppAccount] = []
    /// The ID of the currently active (selected) account. `nil` when no accounts exist.
    @Published private(set) var activeAccountID: AppAccount.ID?
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

    /// Authenticates a new account and adds it to the store.
    ///
    /// - Parameters:
    ///   - handle: The Bluesky handle (e.g., `user.bsky.social`).
    ///   - appPassword: The app password for authentication.
    ///   - entrywayURL: Optional PDS entryway URL for custom PDS accounts.
    ///   - client: The authentication client.
    /// - Returns: `true` on success, `false` on failure (`errorMessage` is set).
    ///
    /// Validates inputs, checks for duplicates, authenticates against the PDS,
    /// saves the password to Keychain, persists the session, and inserts the account.
    func addAccount(
        handle: String,
        appPassword: String,
        entrywayURL: URL? = nil,
        client: BlueskyAuthenticating
    ) async -> Bool {
        let trimmedHandle = handle.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPassword = appPassword.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedHandle.isEmpty, !trimmedPassword.isEmpty else {
            errorMessage = String.localized("account.error.handle_and_password_required")
            return false
        }

        if accounts.contains(where: { $0.handle.caseInsensitiveCompare(trimmedHandle) == .orderedSame }) {
            errorMessage = String.localized("account.error.already_exists")
            return false
        }

        isAddingAccount = true
        defer { isAddingAccount = false }

        do {
            let session = try await client.authenticate(
                handle: trimmedHandle,
                appPassword: trimmedPassword,
                entrywayURL: entrywayURL
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
            activeAccountID = account.id
            persist()
            errorMessage = nil
            return true
        } catch {
            errorMessage = AppError.userMessage(from: error)
            return false
        }
    }

    /// Removes an account from the store, deletes its Keychain entry, and optionally
    /// deletes its persisted session. If it was the active or preferred search account,
    /// falls back to the first remaining account.
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

        if activeAccountID == account.id {
            activeAccountID = accounts.first?.id
        }

        if preferredSearchAccountID == account.id {
            preferredSearchAccountID = accounts.first?.id
        }

        persist()
    }

    /// Sets the active account and updates its `lastUsedAt` timestamp.
    func setActiveAccount(_ account: AppAccount) {
        guard accounts.contains(account) else { return }

        activeAccountID = account.id
        if let index = accounts.firstIndex(of: account) {
            accounts[index].lastUsedAt = .now
        }
        persist()
    }

    /// Switches the active account and clears all caches (HTTP cache, DashboardCache, RelationshipCache).
    func switchAccount(to account: AppAccount, using client: LiveBlueskyClient) async {
        guard accounts.contains(account) else { return }
        client.clearCache()
        await Task.detached(priority: .utility) {
            DashboardCache.clearAll()
            RelationshipCache.clearAll()
        }.value
        activeAccountID = account.id
        if let index = accounts.firstIndex(of: account) {
            accounts[index].lastUsedAt = .now
        }
        persist()
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
