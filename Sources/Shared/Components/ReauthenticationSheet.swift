import SwiftUI

// MARK: - ReauthenticationPromptState

/// Tracks whether the most recent account-scoped failure was an authentication failure,
/// so error surfaces can offer "Re-Login" instead of only "Retry".
/// Cleared on successful re-authentication or account switch.
@MainActor
final class ReauthenticationPromptState: ObservableObject {
    static let shared = ReauthenticationPromptState()

    /// True while the most recent account-scoped failure was an auth failure
    /// (expired token / rejected credentials / missing stored password).
    @Published private(set) var isAuthFailure = false
    /// Optional server-provided reason (e.g. "Token has expired").
    @Published private(set) var reason: String?
    /// The account ID that failed; `nil` when unknown.
    @Published private(set) var failedAccountID: UUID?

    private init() {
        NotificationCenter.default.addObserver(
            forName: .authenticationFailed,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            // Extract Sendable values before hopping to the main actor.
            let reason = notification.userInfo?["message"] as? String
            let accountID = (notification.userInfo?["accountID"] as? String).flatMap(UUID.init)
            Task { @MainActor [weak self] in
                self?.isAuthFailure = true
                self?.reason = reason
                self?.failedAccountID = accountID
            }
        }
        NotificationCenter.default.addObserver(
            forName: .accountReauthenticated,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.reset()
            }
        }
        NotificationCenter.default.addObserver(
            forName: .accountWillSwitch,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.reset()
            }
        }
    }

    /// Re-posts `.authenticationFailed` so the root-level observers present the
    /// re-authentication sheet for the failed account.
    func presentReauthentication() {
        var userInfo: [AnyHashable: Any] = [:]
        if let failedAccountID {
            userInfo["accountID"] = failedAccountID.uuidString
        }
        if let reason {
            userInfo["message"] = reason
        }
        NotificationCenter.default.post(name: .authenticationFailed, object: nil, userInfo: userInfo)
    }

    private func reset() {
        isAuthFailure = false
        reason = nil
        failedAccountID = nil
    }
}

// MARK: - ReauthenticationRequest

/// Identifiable request describing which account needs re-authentication and why.
struct ReauthenticationRequest: Identifiable {
    /// Stable identity so repeated failures don't re-present the sheet mid-flight.
    let id: UUID
    /// The account whose session/token was rejected.
    let account: AppAccount
    /// Optional server-provided reason (e.g. "Token has expired").
    let reason: String?

    init(id: UUID = UUID(), account: AppAccount, reason: String?) {
        self.id = id
        self.account = account
        self.reason = reason
    }
}

// MARK: - ReauthenticationSheet

/// Sheet offering a re-login for an account whose Bluesky session/token was rejected.
/// The entered app password replaces the stored Keychain password and the persisted
/// session, so previously failing requests recover.
struct ReauthenticationSheet: View {
    let request: ReauthenticationRequest

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var accountStore: AccountStore
    @EnvironmentObject private var container: BlueskyServiceContainerWrapper
    @EnvironmentObject private var localizationManager: LocalizationManager

    @State private var appPassword = ""
    @State private var authFactorToken = ""
    @State private var needsAuthFactorToken = false
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    AccountRowView(
                        account: request.account,
                        isActive: true,
                        isDeactivated: false
                    )
                }

                Section {
                    if let reason = request.reason, !reason.isEmpty {
                        Text(reason)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.warningOrange)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Text(loc("account.reauth.message"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    SecureField(loc("account.add.placeholder.password"), text: $appPassword)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    if needsAuthFactorToken {
                        Text(loc: "account.add.2fa.description")
                            .foregroundStyle(.secondary)

                        TextField(loc("account.add.2fa.code_placeholder"), text: $authFactorToken)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.asciiCapable)
                            .submitLabel(.done)
                            .onSubmit {
                                guard !authFactorToken.isEmpty, !isSubmitting else { return }
                                Task { await submit() }
                            }

                        Button(loc("account.add.2fa.resend")) {
                            Task { await submit(forceResend: true) }
                        }
                        .disabled(isSubmitting)
                    }
                } header: {
                    if needsAuthFactorToken {
                        Text(loc("account.add.2fa.title"))
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.subheadline)
                            .foregroundStyle(Color.warningOrange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .pageTitle(loc("account.reauth.title"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(loc("actions.cancel")) {
                        dismiss()
                    }
                    .disabled(isSubmitting)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(loc(needsAuthFactorToken ? "account.add.2fa.verify" : "account.reauth.sign_in")) {
                        Task { await submit() }
                    }
                    .disabled(
                        appPassword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                            (needsAuthFactorToken && authFactorToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) ||
                            isSubmitting
                    )
                }
            }
            .onChange(of: accountStore.errorMessage) { _, newValue in
                if newValue == nil, !isSubmitting {
                    errorMessage = nil
                }
            }
        }
        .presentationDetents([.medium, .large])
        .interactiveDismissDisabled(isSubmitting)
    }

    // MARK: - Private Helpers

    @MainActor
    private func submit(forceResend: Bool = false) async {
        isSubmitting = true
        defer { isSubmitting = false }

        let result = await accountStore.reauthenticate(
            account: request.account,
            appPassword: appPassword,
            authFactorToken: needsAuthFactorToken && !forceResend ? authFactorToken : nil,
            client: container.blueskyClient
        )

        switch result {
        case .success:
            await accountStore.refreshAccountProfiles(using: container.blueskyClient)
            dismiss()
        case .needsAuthFactorToken:
            needsAuthFactorToken = true
            authFactorToken = ""
            errorMessage = accountStore.errorMessage
        case .failure:
            errorMessage = accountStore.errorMessage ?? loc("account.reauth.failed")
        }
    }
}

// MARK: - Preview

#Preview {
    ReauthenticationSheet(
        request: ReauthenticationRequest(
            account: AppAccount(handle: "team-alpha.bsky.social", displayName: "Team Alpha"),
            reason: "Token has expired"
        )
    )
    .environmentObject(AccountStore(preview: true))
    .environmentObject(BlueskyServiceContainerWrapper(
        liveClient: LiveBlueskyClient(),
        accountStore: AccountStore(preview: true)
    ))
    .environmentObject(LocalizationManager.shared)
}
