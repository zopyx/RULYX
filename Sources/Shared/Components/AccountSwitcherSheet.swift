import SwiftUI
import UIKit

// MARK: - AccountSwitcherSheet

/// Full account management sheet — lists all saved accounts with active/switch/edit/delete actions.
/// Includes drag-to-reorder, swipe-to-delete, label editing, and an add-account entry point.
struct AccountSwitcherSheet: View {
    /// Controls whether the sheet is presented.
    @Binding var isPresented: Bool
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var accountStore: AccountStore
    @EnvironmentObject private var container: BlueskyServiceContainerWrapper
    @EnvironmentObject private var workspaceStore: ModerationWorkspaceStore
    @EnvironmentObject private var localizationManager: LocalizationManager
    @State private var isPresentingAddAccount = false
    @State private var editingLabelAccount: AppAccount?
    @State private var editLabelText = ""
    @State private var switchingAccountID: AppAccount.ID?
    @State private var editMode: EditMode = .inactive
    @State private var showAccountHelp = false

    // MARK: - Body

    var body: some View {
        NavigationStack {
            List {
                if accountStore.accounts.isEmpty {
                    ContentUnavailableView(
                        loc("account.no_accounts.title"),
                        systemImage: "person.crop.circle.badge.plus",
                        description: Text(loc: "account.no_accounts.desc")
                    )
                } else {
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
                            .disabled(switchingAccountID != nil)
                            .accessibilityHint("Switches the active account to \(account.label ?? account.handle)")
                            .contextMenu {
                                Button(role: .destructive) {
                                    accountStore.removeAccount(account, client: container.blueskyClient)
                                } label: {
                                    Label(loc("account.remove"), systemImage: "trash")
                                }
                                .accessibilityHint("Permanently removes this saved account")

                                Button {
                                    editLabelText = account.label ?? ""
                                    editingLabelAccount = account
                                } label: {
                                    Label(loc("account.edit_label"), systemImage: "tag")
                                }
                                .accessibilityHint("Sets a custom label to help identify this account")
                            }
                        }
                        .onMove(perform: accountStore.moveAccount)
                        .onDelete { indexSet in
                            for index in indexSet {
                                let account = accountStore.accounts[index]
                                accountStore.removeAccount(account, client: container.blueskyClient)
                            }
                        }
                    } header: {
                        HStack {
                            Text(loc("account.manage.saved"))
                            HelpInfoButton(action: { showAccountHelp = true }, accessibilityLabel: loc("account.manage.saved"))
                        }
                    }
                }
            }
            .listStyle(.plain)
            .listSectionSpacing(.compact)
            .environment(\.defaultMinListHeaderHeight, 0)
            .pageTitle(loc("account.manage.title"))
            .task {
                await accountStore.refreshAccountProfiles(using: container.blueskyClient)
            }
            .environment(\.editMode, $editMode)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(editMode.isEditing ? loc("actions.done") : loc("account.manage.edit")) {
                        withAnimation {
                            editMode = editMode.isEditing ? .inactive : .active
                        }
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isPresentingAddAccount = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel(loc: "account.manage.add")
                    .accessibilityHint("Opens the form to add a new Bluesky account")
                }
            }
            .sheet(isPresented: $isPresentingAddAccount) {
                AddAccountView()
                    .environmentObject(accountStore)
                    .environmentObject(container.blueskyClient)
            }
            .sheet(isPresented: $showAccountHelp) {
                NavigationStack {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(loc("account.manage.saved.info"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding()
                    .pageTitle(loc("account.manage.saved"))
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            ToolbarCloseButton(action: { showAccountHelp = false })
                        }
                    }
                }
                .presentationDetents([.height(200)])
            }
            .alert(loc("account.manage.title"), isPresented: .constant(accountStore.errorMessage != nil), actions: {
                Button(loc("actions.ok")) {
                    accountStore.errorMessage = nil
                }
            }, message: {
                Text(accountStore.errorMessage ?? "")
            })
            .sheet(item: $editingLabelAccount) { account in
                NavigationStack {
                    List {
                        Section(loc("account.edit_label.section")) {
                            TextField(loc("account.edit_label.placeholder"), text: $editLabelText)
                                .textInputAutocapitalization(.never)
                            Button(loc("account.edit_label.clear"), role: .destructive) {
                                accountStore.setLabel(for: account, label: nil)
                                editingLabelAccount = nil
                            }
                            .accessibilityHint("Removes the current label from this account")
                        }
                        Section(loc("account.edit_label.suggestions")) {
                            ForEach(["Work", "Personal", "Community", "Testing"], id: \.self) { option in
                                Button {
                                    editLabelText = option
                                } label: {
                                    HStack {
                                        Text(loc: "account.edit_label.\(option.lowercased())").foregroundStyle(.primary)
                                        if editLabelText == option {
                                            Spacer()
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                                .accessibilityHint("Sets the label to \(option)")
                            }
                        }
                    }
                    .pageTitle(loc("account.edit_label.title"))
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button(loc("account.edit_label.save")) {
                                accountStore.setLabel(for: account, label: editLabelText)
                                editingLabelAccount = nil
                            }
                            .accessibilityHint("Saves the label for this account")
                        }
                        ToolbarItem(placement: .cancellationAction) {
                            Button(loc("account.edit_label.cancel")) { editingLabelAccount = nil }
                                .accessibilityHint("Discards changes and closes the label editor")
                        }
                    }
                }
                .presentationDetents([.medium])
            }
        }
        .presentationDetents([.large])
    }

    // MARK: - Private Helpers

    /// Switch to the given account with haptic feedback, then dismiss the sheet.
    private func switchAccount(to account: AppAccount) {
        switchingAccountID = account.id
        let generator = UIImpactFeedbackGenerator(style: .rigid)
        generator.prepare()
        Task { @MainActor in
            await accountStore.switchAccount(to: account, using: container.blueskyClient)
            workspaceStore.returnToModerationRoot()
            generator.impactOccurred()
            switchingAccountID = nil
            dismiss()
        }
    }
}

#Preview {
    AccountSwitcherSheet(isPresented: .constant(true))
        .environmentObject(AccountStore(preview: true))
        .environmentObject(PreviewBlueskyClient())
}
