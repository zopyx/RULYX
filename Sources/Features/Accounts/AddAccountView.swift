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

/// Form view for adding a new Bluesky account — select PDS provider
/// (Bluesky, Eurosky, or custom), enter handle and app password.
struct AddAccountView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var accountStore: AccountStore
    @EnvironmentObject private var blueskyClient: LiveBlueskyClient
    @EnvironmentObject private var localizationManager: LocalizationManager

    @State private var handle = ""
    @State private var appPassword = ""
    @State private var selectedProvider: ProviderOption = .bluesky
    @State private var customPDS = ""
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

                    Section {
                        Text(loc: "account.add.password_hint")
                            .foregroundStyle(.secondary)
                    } header: {
                        Text(loc: "account.add.why_password")
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
                    } else {
                        Button(loc("account.add.save")) {
                            Task {
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

}

#Preview {
    AddAccountView()
        .environmentObject(AccountStore(preview: true))
        .environmentObject(PreviewBlueskyClient())
}
