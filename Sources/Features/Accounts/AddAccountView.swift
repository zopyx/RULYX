import SwiftUI

/// PDS provider options for account creation.
enum ProviderOption: String, CaseIterable, Identifiable {
    case bluesky = "Bluesky"
    case eurosky = "Eurosky"
    case other = "Other"

    var id: String {
        rawValue
    }

    var entrywayURL: URL {
        switch self {
        case .bluesky: URL(string: "https://bsky.social")!
        case .eurosky: URL(string: "https://eurosky.social")!
        case .other: URL(string: "https://bsky.social")!
        }
    }
}

/// Form view for adding a new Bluesky account.
/// Supports two authentication methods:
/// - **App Password** (classic): handle + app password via `createSession`
/// - **Sign in with Browser** (OAuth): pick a provider, then authenticate via browser
struct AddAccountView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var accountStore: AccountStore
    @EnvironmentObject private var blueskyClient: LiveBlueskyClient
    @EnvironmentObject private var localizationManager: LocalizationManager
    @EnvironmentObject private var oauthAuthorizationFlow: OAuthAuthorizationFlow
    @EnvironmentObject private var oauthTokenStore: OAuthTokenStore

    @State private var authMethod: AuthMethod = .password
    @State private var handle = ""
    @State private var appPassword = ""
    @State private var selectedProvider: ProviderOption = .bluesky
    @State private var customPDS = ""
    @State private var oauthProvider: ProviderOption?
    @State private var oauthCustomPDS = ""
    @State private var needsAuthFactorToken = false
    @State private var authFactorToken = ""
    @State private var authFactorEntrywayURL: URL?

    var body: some View {
        NavigationStack {
            Form {
                if needsAuthFactorToken {
                    Section {
                        Text(loc: "account.add.2fa.description")
                            .foregroundStyle(.secondary)

                        TextField(loc("account.add.2fa.code_placeholder"), text: $authFactorToken)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.asciiCapable)
                    } header: {
                        Text(loc: "account.add.2fa.title")
                    }
                } else {
                    Section {
                        Picker(selection: $authMethod) {
                            Text(loc: "account.add.auth.password").tag(AuthMethod.password)
                            Text(loc: "account.add.auth.oauth").tag(AuthMethod.oauth)
                        } label: {
                            Text(loc: "account.add.auth.method")
                        }
                        .pickerStyle(.segmented)
                    }

                    if authMethod == .password {
                        passwordProviderSection
                        credentialsSection
                        passwordHintSection
                    } else {
                        oauthProviderSection
                    }
                }
            }
            .pageTitle(Text(loc: "account.add.title"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(loc("account.add.cancel")) {
                        dismiss()
                    }
                    .accessibilityHint(loc("account.discard_add.hint"))
                }

                ToolbarItem(placement: .confirmationAction) {
                    if needsAuthFactorToken {
                        Button(loc("account.add.2fa.verify")) {
                            Task {
                                let entrywayURL = authFactorEntrywayURL
                                let success = await accountStore.completeAuthWithFactor(
                                    handle: handle,
                                    appPassword: appPassword,
                                    authFactorToken: authFactorToken,
                                    entrywayURL: entrywayURL,
                                    client: blueskyClient
                                )
                                if success {
                                    await accountStore.refreshAccountProfiles(using: blueskyClient)
                                    dismiss()
                                }
                            }
                        }
                        .disabled(authFactorToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || accountStore.isAddingAccount)
                    } else if authMethod == .password {
                        Button(loc("account.add.save")) {
                            Task {
                                await saveWithPassword()
                            }
                        }
                        .disabled(
                            handle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                                appPassword.isEmpty ||
                                accountStore.isAddingAccount
                        )
                        .accessibilityHint(loc("account.validate.hint"))
                    }
                }
            }
            .overlay {
                if accountStore.isAddingAccount {
                    ZStack {
                        Color.black.opacity(0.08).ignoresSafeArea()
                        ProgressView(loc("account.add.validating"))
                            .padding(20)
                            .background {
                                if #available(iOS 26, *) {
                                    Color.clear
                                        .glassEffect(.regular, in: .rect(cornerRadius: 16))
                                } else {
                                    Color.clear.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                }
                            }
                    }
                }
            }
        }
    }

    // MARK: - Password Sections

    private var passwordProviderSection: some View {
        Section {
            Picker(selection: $selectedProvider) {
                ForEach(ProviderOption.allCases) { option in
                    if option == .bluesky {
                        Text(loc: "account.add.bluesky").tag(option)
                    } else if option == .eurosky {
                        Text(loc: "account.add.eurosky").tag(option)
                    } else {
                        Text(loc: "account.add.other").tag(option)
                    }
                }
            } label: {
                Text(loc: "account.add.provider")
            }
            .accessibilityHint(loc("account.select_pds.hint"))

            if selectedProvider == .other {
                TextField(loc("account.add.placeholder.url"), text: $customPDS)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
            }
        } header: {
            Text(loc: "account.add.provider")
        }
    }

    private var credentialsSection: some View {
        Section {
            TextField(loc("account.add.placeholder.handle"), text: $handle)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            SecureField(loc("account.add.placeholder.password"), text: $appPassword)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        } header: {
            Text(loc: "account.add.credentials")
        }
    }

    private var passwordHintSection: some View {
        Section {
            Text(loc: "account.add.password_hint")
                .foregroundStyle(.secondary)
        } header: {
            Text(loc: "account.add.why_password")
        }
    }

    // MARK: - OAuth Section

    private var oauthProviderSection: some View {
        Section {
            Picker(selection: $oauthProvider) {
                Text(loc: "account.add.select_provider").tag(Optional<ProviderOption>.none)
                ForEach(ProviderOption.allCases) { option in
                    if option == .bluesky {
                        Text(loc: "account.add.bluesky").tag(Optional(option))
                    } else if option == .eurosky {
                        Text(loc: "account.add.eurosky").tag(Optional(option))
                    } else {
                        Text(loc: "account.add.other").tag(Optional(option))
                    }
                }
            } label: {
                Text(loc: "account.add.provider")
            }

            if oauthProvider == .other {
                TextField(loc("account.add.placeholder.url"), text: $oauthCustomPDS)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
            }

            if let provider = oauthProvider {
                VStack(spacing: 14) {
                    Button {
                        Task { await signInWithOAuth() }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "person.badge.key.fill")
                                .font(.body.weight(.semibold))
                            Text(signInButtonLabel(for: provider))
                                .font(.body.weight(.semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.skyPrimary)
                    .disabled(accountStore.isAddingAccount)

                    HStack(spacing: 8) {
                        Image(systemName: "lock.shield")
                            .foregroundStyle(.secondary)
                        Text(loc: "account.add.oauth.note")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 8)
            }
        } header: {
            Text(loc: "account.add.provider")
        }
    }

    private func signInButtonLabel(for provider: ProviderOption) -> String {
        let name: String = switch provider {
        case .bluesky: "Bluesky"
        case .eurosky: "Eurosky"
        case .other:
            oauthCustomPDS.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? loc("account.add.auth.oauth.sign_in")
                : oauthCustomPDS.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return "\(loc("account.add.auth.oauth.sign_in")) \(name)"
    }

    // MARK: - Actions

    private func saveWithPassword() async {
        let entrywayURL: URL? = if selectedProvider == .other, !customPDS.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            URL(string: customPDS.trimmingCharacters(in: .whitespacesAndNewlines))
        } else {
            selectedProvider.entrywayURL
        }
        let result = await accountStore.addAccount(
            handle: handle,
            appPassword: appPassword,
            entrywayURL: entrywayURL,
            client: blueskyClient
        )
        switch result {
        case .success:
            await accountStore.refreshAccountProfiles(using: blueskyClient)
            dismiss()
        case .needsAuthFactorToken:
            needsAuthFactorToken = true
            authFactorEntrywayURL = entrywayURL
        case .failure:
            break
        }
    }

    private func signInWithOAuth() async {
        guard let provider = oauthProvider else { return }

        let entrywayURL: URL? = if provider == .other, !oauthCustomPDS.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            URL(string: oauthCustomPDS.trimmingCharacters(in: .whitespacesAndNewlines))
        } else {
            provider.entrywayURL
        }

        guard let entrywayURL else { return }

        do {
            let session = try await oauthAuthorizationFlow.signIn(entrywayURL: entrywayURL)
            try oauthTokenStore.saveSession(session, for: session.did)

            // Resolve the handle from the DID after successful auth
            let handle = try await blueskyClient.resolveHandleFromDID(session.did)

            accountStore.addOAuthAccount(
                handle: handle,
                did: session.did,
                pdsURL: session.pdsURL,
                entrywayURL: entrywayURL
            )

            await accountStore.refreshAccountProfiles(using: blueskyClient)
            dismiss()
        } catch OAuthFlowError.userCancelled {
            // User cancelled — no error to show
        } catch {
            accountStore.errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    AddAccountView()
        .environmentObject(AccountStore(preview: true))
        .environmentObject(PreviewBlueskyClient())
}
