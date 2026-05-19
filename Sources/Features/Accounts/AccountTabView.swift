import SwiftUI

struct AccountTabView: View {
    @EnvironmentObject private var accountStore: AccountStore
    @EnvironmentObject private var blueskyClient: LiveBlueskyClient
    @EnvironmentObject private var workspaceStore: ModerationWorkspaceStore
    @EnvironmentObject private var localizationManager: LocalizationManager
    @State private var isPresentingAddAccount = false
    @State private var editingLabelAccount: AppAccount?
    @State private var editLabelText = ""
    @State private var editMode: EditMode = .inactive
    @State private var switchingAccountID: AppAccount.ID?

    var body: some View {
        NavigationStack {
            List {
                if accountStore.accounts.isEmpty {
                    ContentUnavailableView(
                        String(localized: "account.no_accounts.title"),
                        systemImage: "person.crop.circle.badge.plus",
                        description: Text("account.no_accounts.desc")
                    )
                } else {
                    Section("account.manage.saved") {
                        ForEach(accountStore.accounts) { account in
                            Button {
                                switchToAccount(account)
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
                            .disabled(switchingAccountID != nil)
                            .accessibilityHint("account.switch_tab.hint")
                        }
                        .onMove(perform: accountStore.moveAccount)
                        .onDelete { indexSet in
                            for index in indexSet {
                                let account = accountStore.accounts[index]
                                accountStore.removeAccount(account, client: blueskyClient)
                            }
                        }
                    }

                    Section {
                        Menu {
                            ForEach(accountStore.accounts) { account in
                                Button {
                                    accountStore.preferredSearchAccountID = account.id
                                } label: {
                                    HStack {
                                        AccountRowView(
                                            account: account,
                                            isActive: account.id == accountStore.activeAccountID
                                        )
                                        if account.id == accountStore.preferredSearchAccountID {
                                            Spacer()
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        } label: {
                            if let prefID = accountStore.preferredSearchAccountID,
                               let prefAccount = accountStore.accounts.first(where: { $0.id == prefID }) {
                                AccountRowView(
                                    account: prefAccount,
                                    isActive: prefAccount.id == accountStore.activeAccountID
                                )
                            } else if let first = accountStore.accounts.first {
                                AccountRowView(
                                    account: first,
                                    isActive: first.id == accountStore.activeAccountID
                                )
                            }
                        }
                        .buttonStyle(.plain)
                        Text("account.preferred_search.hint")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } header: {
                        Text("account.preferred_search.section")
                    }
                }
            }
            .navigationTitle("account.manage.title")
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(editMode.isEditing ? String(localized: "actions.done") : String(localized: "account.manage.edit")) {
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
                    .accessibilityLabel("account.manage.add")
                }
            }
            .task {
                await accountStore.refreshAccountProfiles(using: blueskyClient)
            }
            .environment(\.editMode, $editMode)
            .sheet(isPresented: $isPresentingAddAccount) {
                AddAccountView()
                    .environmentObject(accountStore)
                    .environmentObject(blueskyClient)
            }
            .alert("account.manage.title", isPresented: .constant(accountStore.errorMessage != nil), actions: {
                Button("actions.ok") {
                    accountStore.errorMessage = nil
                }
            }, message: {
                Text(accountStore.errorMessage ?? "")
            })
            .sheet(item: $editingLabelAccount) { account in
                NavigationStack {
                    List {
                        Section("account.edit_label.section") {
                            TextField("account.edit_label.placeholder", text: $editLabelText)
                                .textInputAutocapitalization(.never)
                            Button(String(localized: "account.edit_label.clear"), role: .destructive) {
                                accountStore.setLabel(for: account, label: nil)
                                editingLabelAccount = nil
                            }
                        }
                        Section("account.edit_label.suggestions") {
                            ForEach(["Work", "Personal", "Community", "Testing"], id: \.self) { option in
                                Button {
                                    editLabelText = option
                                } label: {
                                    HStack {
                                        Text("account.edit_label.\(option.lowercased())").foregroundStyle(.primary)
                                        if editLabelText == option { Spacer()
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .navigationTitle("account.edit_label.title")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("account.edit_label.save") {
                                accountStore.setLabel(for: account, label: editLabelText)
                                editingLabelAccount = nil
                            }
                        }
                        ToolbarItem(placement: .cancellationAction) {
                            Button("account.edit_label.cancel") { editingLabelAccount = nil }
                        }
                    }
                }
                .presentationDetents([.medium])
            }
        }
    }

    private func switchToAccount(_ account: AppAccount) {
        switchingAccountID = account.id
        workspaceStore.returnToModerationRoot()
        Task { @MainActor in
            await accountStore.switchAccount(to: account, using: blueskyClient)
            switchingAccountID = nil
        }
    }
}

#Preview {
    AccountTabView()
        .environmentObject(AccountStore(preview: true))
        .environmentObject(PreviewBlueskyClient())
        .environmentObject(ModerationWorkspaceStore(preview: true))
}
