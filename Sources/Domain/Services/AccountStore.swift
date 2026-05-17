import Foundation

@MainActor
final class AccountStore: ObservableObject {
    @Published private(set) var accounts: [AppAccount] = []
    @Published private(set) var activeAccountID: AppAccount.ID?
    @Published var errorMessage: String?
    @Published private(set) var isAddingAccount = false

    var activeAccount: AppAccount? {
        accounts.first { $0.id == activeAccountID }
    }

    private let defaults: UserDefaults
    private let keychain: KeychainServicing
    private let accountsKey = "bluesky.savedAccounts"
    private let activeAccountKey = "bluesky.activeAccountID"
    private let passwordService = "com.ajung.BlueskyModeration.password"

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
            return
        }

        load()
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
    }

    func addAccount(
        handle: String,
        appPassword: String,
        entrywayURL: URL? = nil,
        client: BlueskyAuthenticating
    ) async -> Bool {
        let trimmedHandle = handle.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPassword = appPassword.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedHandle.isEmpty, !trimmedPassword.isEmpty else {
            errorMessage = loc("account.error.handle_and_password_required")
            return false
        }

        if accounts.contains(where: { $0.handle.caseInsensitiveCompare(trimmedHandle) == .orderedSame }) {
            errorMessage = loc("account.error.already_exists")
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

    func removeAccount(_ account: AppAccount, client: BlueskyAuthenticating? = nil) {
        do {
            try keychain.delete(service: passwordService, account: account.id.uuidString)
        } catch {
            errorMessage = loc("account.error.failed_to_delete_credentials")
        }

        if let client {
            try? client.deletePersistedSession(for: account)
        }

        accounts.removeAll { $0.id == account.id }

        if activeAccountID == account.id {
            activeAccountID = accounts.first?.id
        }

        persist()
    }

    func setActiveAccount(_ account: AppAccount) {
        guard accounts.contains(account) else { return }

        activeAccountID = account.id
        if let index = accounts.firstIndex(of: account) {
            accounts[index].lastUsedAt = .now
        }
        persist()
    }

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

    func setLabel(for account: AppAccount, label: String?) {
        guard let index = accounts.firstIndex(of: account) else { return }
        accounts[index].label = label?.isEmpty == true ? nil : label
        persist()
    }

    func moveAccount(from source: IndexSet, to destination: Int) {
        accounts.move(fromOffsets: source, toOffset: destination)
        persist()
    }

    func appPassword(for account: AppAccount) -> String? {
        try? keychain.read(service: passwordService, account: account.id.uuidString)
    }

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
                AppLogger.moderation.error("Failed to refresh profile for \(account.handle, privacy: .public): \(error.localizedDescription, privacy: .public)")
                continue
            }
        }

        if didChange {
            accounts = updatedAccounts
            persist()
        }
    }

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
        } catch {
            errorMessage = loc("account.error.failed_to_restore")
        }
    }

    private func persist() {
        do {
            let data = try JSONEncoder().encode(accounts)
            defaults.set(data, forKey: accountsKey)
            defaults.set(activeAccountID?.uuidString, forKey: activeAccountKey)
        } catch {
            errorMessage = loc("account.error.failed_to_save")
        }
        iCloudAccountSync.shared.pushAccounts(accounts)
    }

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
