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
    @State private var showPreferredSearchInfo = false

    var body: some View {
        NavigationStack {
            List {
                if accountStore.accounts.isEmpty {
                    VStack(spacing: 16) {
                        ContentUnavailableView(
                            loc("account.no_accounts.title"),
                            systemImage: "person.crop.circle.badge.plus",
                            description: Text(loc: "account.no_accounts.desc")
                        )
                        Button {
                            isPresentingAddAccount = true
                        } label: {
                            Label(loc("account.manage.add"), systemImage: "plus")
                                .frame(maxWidth: 200)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    }
                    .listRowBackground(Color.clear)
                    .frame(maxWidth: .infinity)
                } else {
                    Section {
                        ForEach(accountStore.accounts) { account in
                            Button {
                                switchToAccount(account)
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
                            .accessibilityHint(loc("account.switch_tab.hint"))
                        }
                        .onMove(perform: accountStore.moveAccount)
                        .onDelete { indexSet in
                            for index in indexSet {
                                let account = accountStore.accounts[index]
                                accountStore.removeAccount(account, client: blueskyClient)
                            }
                        }
                    } header: {
                        HStack {
                            Text(loc("account.manage.saved"))
                            Spacer()
                            Button(editMode.isEditing ? loc("actions.done") : loc("account.manage.edit")) {
                                withAnimation {
                                    editMode = editMode.isEditing ? .inactive : .active
                                }
                            }
                            .tint(.skyPrimary)
                            Button {
                                isPresentingAddAccount = true
                            } label: {
                                Image(systemName: "plus")
                            }
                            .accessibilityLabel(loc("account.manage.add"))
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
                                            isActive: account.id == accountStore.activeAccountID,
                                            isDeactivated: accountStore.isDeactivated(account)
                                        )
                                        if account.id == accountStore.preferredSearchAccountID {
                                            Spacer()
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        } label: {
                            preferredSearchRow
                        }
                        .buttonStyle(.plain)
                        Text(loc: "account.preferred_search.hint")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } header: {
                        HStack(spacing: 4) {
                            Text(loc: "account.preferred_search.section")
                            HelpInfoButton(
                                action: { showPreferredSearchInfo = true },
                                accessibilityLabel: loc("account.preferred_search.info.hint")
                            )
                        }
                    }
                }
            }
            .navigationTitle(loc("account.manage.title"))
            .navigationBarBackButtonHidden(true)
            .task {
                await accountStore.refreshAccountProfiles(using: blueskyClient)
            }
            .environment(\.editMode, $editMode)
            .sheet(isPresented: $isPresentingAddAccount) {
                AddAccountView()
                    .environmentObject(accountStore)
                    .environmentObject(blueskyClient)
            }
            .alert(Text(loc: "account.manage.title"), isPresented: .constant(accountStore.errorMessage != nil), actions: {
                Button("actions.ok") {
                    accountStore.errorMessage = nil
                }
            }, message: {
                Text(accountStore.errorMessage ?? "")
            })
            .sheet(isPresented: $showPreferredSearchInfo) {
                NavigationStack {
                    List {
                        Section {
                            Text(loc: "account.preferred_search.info.p1")
                                .font(.body)
                            Text(loc: "account.preferred_search.info.p2")
                                .font(.body)
                            Text(loc: "account.preferred_search.info.p3")
                                .font(.body)
                        }
                    }
                    .listStyle(.insetGrouped)
                    .navigationTitle(Text(loc: "account.preferred_search.info.title"))
                    .toolbarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            ToolbarCloseButton(action: { showPreferredSearchInfo = false })
                        }
                    }
                }
            }
            .sheet(item: $editingLabelAccount) { account in
                NavigationStack {
                    List {
                        Section("account.edit_label.section") {
                            TextField("account.edit_label.placeholder", text: $editLabelText)
                                .textInputAutocapitalization(.never)
                            Button(loc("account.edit_label.clear"), role: .destructive) {
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
                    .navigationTitle(loc("account.edit_label.title"))
                    .toolbarTitleDisplayMode(.inline)
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

    @ViewBuilder
    private var preferredSearchRow: some View {
        if let prefID = accountStore.preferredSearchAccountID,
           let prefAccount = accountStore.accounts.first(where: { $0.id == prefID })
        {
            AccountRowView(
                account: prefAccount,
                isActive: prefAccount.id == accountStore.activeAccountID,
                isDeactivated: accountStore.isDeactivated(prefAccount)
            )
        } else if let first = accountStore.accounts.first {
            AccountRowView(
                account: first,
                isActive: first.id == accountStore.activeAccountID,
                isDeactivated: accountStore.isDeactivated(first)
            )
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
