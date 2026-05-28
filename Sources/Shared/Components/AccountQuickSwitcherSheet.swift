import SwiftUI
import UIKit

// MARK: - AccountQuickSwitcherSheet

/// A compact, fast account switcher presented as a sheet.
/// Shows accounts in a list with a single tap to switch, plus a "Manage Accounts" link.
/// Used from toolbar buttons for quick context switching.
struct AccountQuickSwitcherSheet: View {
    /// Controls whether the sheet is presented.
    @Binding var isPresented: Bool
    /// Called when the user taps "Manage Accounts" to open the full account management UI.
    let onManageAccounts: () -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var accountStore: AccountStore
    @EnvironmentObject private var workspaceStore: ModerationWorkspaceStore
    @EnvironmentObject private var blueskyClient: LiveBlueskyClient
    @EnvironmentObject private var localizationManager: LocalizationManager
    @State private var switchingAccountID: AppAccount.ID?

    // MARK: - Body

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(accountStore.accounts) { account in
                        Button {
                            switchAccount(to: account)
                        } label: {
                            HStack {
                                AccountRowView(
                                    account: account,
                                    isActive: account.id == accountStore.activeAccountID,
                                    isDeactivated: accountStore.isDeactivated(account)
                                )
                                if switchingAccountID == account.id {
                                    Spacer()
                                    ProgressView()
                                        .scaleEffect(0.7)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(switchingAccountID != nil || account.id == accountStore.activeAccountID)
                        .accessibilityHint("Switches to \(account.label ?? account.handle)")
                    }
                } header: {
                    Text(loc: "account.switcher.accounts_section")
                }

                Section {
                    Button {
                        isPresented = false
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(250))
                            onManageAccounts()
                        }
                    } label: {
                        Label(loc("account.switcher.manage"), systemImage: "slider.horizontal.3")
                    }
                    .accessibilityHint("Opens the full account management screen")
                }
            }
            .pageTitle(loc("account.switcher.title"))
        }
        .presentationDetents([.height(360), .medium])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Private Helpers

    /// Switch to the given account with haptic feedback, then dismiss the sheet.
    private func switchAccount(to account: AppAccount) {
        switchingAccountID = account.id
        let generator = UISelectionFeedbackGenerator()
        generator.prepare()
        Task { @MainActor in
            await accountStore.switchAccount(to: account, using: blueskyClient)
            workspaceStore.returnToModerationRoot()
            generator.selectionChanged()
            switchingAccountID = nil
            dismiss()
        }
    }
}

#Preview {
    AccountQuickSwitcherSheet(
        isPresented: .constant(true),
        onManageAccounts: {}
    )
    .environmentObject(AccountStore(preview: true))
    .environmentObject(PreviewBlueskyClient())
}
