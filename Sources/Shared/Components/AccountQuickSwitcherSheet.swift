import SwiftUI
import UIKit

struct AccountQuickSwitcherSheet: View {
    @Binding var isPresented: Bool
    let onManageAccounts: () -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var accountStore: AccountStore
    @EnvironmentObject private var workspaceStore: ModerationWorkspaceStore
    @EnvironmentObject private var blueskyClient: LiveBlueskyClient
    @State private var switchingAccountID: AppAccount.ID?

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
                                    isActive: account.id == accountStore.activeAccountID
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
                    Text(loc("account.switcher.accounts_section"))
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
            .navigationTitle(loc("account.switcher.title"))
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.height(360), .medium])
        .presentationDragIndicator(.visible)
    }

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
