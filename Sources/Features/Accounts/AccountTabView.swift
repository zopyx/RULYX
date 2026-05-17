import SwiftUI

struct AccountTabView: View {
    @EnvironmentObject private var accountStore: AccountStore
    @EnvironmentObject private var blueskyClient: LiveBlueskyClient
    @EnvironmentObject private var workspaceStore: ModerationWorkspaceStore
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
                        loc("account.no_accounts.title"),
                        systemImage: "person.crop.circle.badge.plus",
                        description: Text(loc("account.no_accounts.desc"))
                    )
                } else {
                    Section(loc("account.manage.saved")) {
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
                            .accessibilityHint(loc("account.switch_tab.hint"))
                        }
                        .onMove(perform: accountStore.moveAccount)
                        .onDelete { indexSet in
                            for index in indexSet {
                                let account = accountStore.accounts[index]
                                accountStore.removeAccount(account, client: blueskyClient)
                            }
                        }
                    }
                }
            }
            .navigationTitle(loc("account.manage.title"))
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
                    .accessibilityLabel(loc("account.manage.add"))
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
                        }
                        Section(loc("account.edit_label.suggestions")) {
                            ForEach(["Work", "Personal", "Community", "Testing"], id: \.self) { option in
                                Button {
                                    editLabelText = option
                                } label: {
                                    HStack {
                                        Text(loc("account.edit_label.\(option.lowercased())")).foregroundStyle(.primary)
                                        if editLabelText == option { Spacer()
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .navigationTitle(loc("account.edit_label.title"))
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button(loc("account.edit_label.save")) {
                                accountStore.setLabel(for: account, label: editLabelText)
                                editingLabelAccount = nil
                            }
                        }
                        ToolbarItem(placement: .cancellationAction) {
                            Button(loc("account.edit_label.cancel")) { editingLabelAccount = nil }
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
