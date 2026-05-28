import SwiftUI

/// Main moderation lists view — the primary screen of the Moderation tab.
///
/// Displays the active account summary, follower/following/blocking/blocked-by
/// relationship counts, the user's Bluesky moderation + regular lists, internal
/// (local-only) lists, and advanced search tools (mentions, custom search,
/// direct replies).
struct ListsView: View {
    @EnvironmentObject var accountStore: AccountStore
    @EnvironmentObject var blueskyClient: LiveBlueskyClient
    @EnvironmentObject private var workspaceStore: ModerationWorkspaceStore
    @EnvironmentObject private var localizationManager: LocalizationManager
    @EnvironmentObject var internalListStore: InternalListStore
    @StateObject var viewModel = ListsViewModel()

    // MARK: - Properties

    @State private var presentationState = PresentationState()
    @State private var isShowingUserSearch = false
    @State var exportFormat: ListsExportFormat?
    @State var isShowingListPicker = false
    @State var shareFileURL: URL?
    @State var isExporting = false
    @State var exportProgressMessage: String?
    @State var exportProgressFraction: Double?
    @State var showShareSheet = false
    @State private var showModerationListsHelp = false
    @State private var showListsHelp = false
    @State private var showAdvancedHelp = false
    @State private var showInternalListsHelp = false
    @State private var internalListName = ""
    @State private var internalListColor = InternalListColor.blue

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Group {
                if accountStore.accounts.isEmpty {
                    EmptyStatePanel(
                        title: localizationManager.localized("lists.no_account.title"),
                        message: localizationManager.localized("lists.no_account.desc")
                    )
                } else if viewModel.isLoading, !viewModel.isRefreshing, viewModel.listsByKind.isEmpty {
                    LoadingPanel(message: localizationManager.localized("lists.loading"))
                } else {
                    List {
                        if let activeAccount = accountStore.activeAccount {
                            Section {
                                Button {
                                    presentationState.showProfile = true
                                } label: {
                                    AccountSummaryCard(
                                        account: activeAccount,
                                        avatarURL: viewModel.activeProfile?.avatarURL
                                    )
                                }
                                .buttonStyle(.plain)
                                .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                                .listRowBackground(Color.clear)
                            }
                        }

                        Section {
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading) {
                                Button {
                                    presentationState.showFollowers = true
                                } label: {
                                    relationshipRow(
                                        label: loc("lists.followers"),
                                        count: viewModel.activeProfile?.followersCount
                                    )
                                }
                                .buttonStyle(.plain)

                                Button {
                                    presentationState.showFollowing = true
                                } label: {
                                    relationshipRow(
                                        label: loc("lists.following"),
                                        count: viewModel.activeProfile?.followsCount
                                    )
                                }
                                .buttonStyle(.plain)

                                Button {
                                    presentationState.showBlocking = true
                                } label: {
                                    relationshipRow(
                                        label: loc("lists.blocking"),
                                        count: viewModel.blockingCount,
                                        isLoading: viewModel.blockingCount == nil && (viewModel.isLoading || viewModel.isRefreshing)
                                    )
                                }
                                .buttonStyle(.plain)

                                Button {
                                    presentationState.showBlockedBy = true
                                } label: {
                                    relationshipRow(
                                        label: loc("lists.blocked_by"),
                                        count: viewModel.blockedByCount,
                                        isLoading: viewModel.blockedByCount == nil && (viewModel.isLoading || viewModel.isRefreshing)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .listSectionSeparator(.hidden)

                        Section {
                            if let lists = viewModel.listsByKind[.moderation], !lists.isEmpty {
                                ForEach(lists) { list in
                                    NavigationLink {
                                        ListDetailView(list: list) { updatedList in
                                            viewModel.updateList(updatedList)
                                        }
                                    } label: {
                                        ListRowView(list: list)
                                            .accessibilityLabel(String.localized("list.row.label", replacements: ["name": list.name, "count": "\(list.memberCount ?? 0)"]))
                                    }
                                    .buttonStyle(.plain)
                                }
                            } else {
                                Button {
                                    presentationState.createListKind = .moderation
                                    presentationState.isShowingCreateList = true
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: "plus.circle.fill")
                                            .font(.title3)
                                            .foregroundStyle(.secondary)
                                        Text(loc: "lists.create_first_mod")
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                        Spacer()
                                    }
                                    .padding(.vertical, 4)
                                }
                            }
                        } header: {
                            HStack {
                                Text(loc: "lists.moderation_lists")
                                HelpInfoButton(
                                    action: { showModerationListsHelp = true },
                                    accessibilityLabel: loc("lists.moderation_lists")
                                )
                                Spacer()
                                Button {
                                    presentationState.createListKind = .moderation
                                    presentationState.isShowingCreateList = true
                                } label: {
                                    Image(systemName: "plus")
                                }
                                .accessibilityLabel(loc("lists.create_moderation"))
                            }
                        }

                        Section {
                            if let lists = viewModel.listsByKind[.regular], !lists.isEmpty {
                                ForEach(lists) { list in
                                    NavigationLink {
                                        ListDetailView(list: list) { updatedList in
                                            viewModel.updateList(updatedList)
                                        }
                                    } label: {
                                        ListRowView(list: list)
                                            .accessibilityLabel(String.localized("list.row.label", replacements: ["name": list.name, "count": "\(list.memberCount ?? 0)"]))
                                    }
                                    .buttonStyle(.plain)
                                }
                            } else {
                                Button {
                                    presentationState.createListKind = .regular
                                    presentationState.isShowingCreateList = true
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: "plus.circle.fill")
                                            .font(.title3)
                                            .foregroundStyle(.secondary)
                                        Text(loc: "lists.create_first")
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                        Spacer()
                                    }
                                    .padding(.vertical, 4)
                                }
                            }
                        } header: {
                            HStack {
                                Text(loc: "lists.lists")
                                HelpInfoButton(
                                    action: { showListsHelp = true },
                                    accessibilityLabel: loc("lists.lists")
                                )
                                Spacer()
                                Button {
                                    presentationState.createListKind = .regular
                                    presentationState.isShowingCreateList = true
                                } label: {
                                    Image(systemName: "plus")
                                }
                                .accessibilityLabel(loc("lists.create_regular"))
                            }
                        }

                        Section {
                            if !internalListStore.lists.isEmpty {
                                ForEach(internalListStore.lists) { list in
                                    NavigationLink {
                                        InternalListDetailView(list: list)
                                            .environmentObject(internalListStore)
                                    } label: {
                                        HStack(spacing: 10) {
                                            Circle()
                                                .fill(list.color.colorValue)
                                                .frame(width: 10, height: 10)
                                            Text(list.name)
                                                .font(.subheadline.weight(.semibold))
                                            Spacer()
                                            if list.memberCount > 0 {
                                                Text("\(list.memberCount)")
                                                    .font(.subheadline.weight(.semibold))
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                        .padding(.vertical, 4)
                                    }
                                }
                            }
                        } header: {
                            HStack(spacing: 4) {
                                Text(loc("internal.lists.section"))
                                HelpInfoButton(
                                    action: { showInternalListsHelp = true },
                                    accessibilityLabel: loc("internal.lists.section")
                                )
                                Spacer()
                                Button {
                                    presentationState.isShowingCreateInternalList = true
                                } label: {
                                    Image(systemName: "plus")
                                }
                                .accessibilityLabel(loc("internal.lists.create"))
                            }
                        }

                        Section {
                            Button {
                                presentationState.showMentionsSearch = true
                            } label: {
                                HStack {
                                    Image(systemName: "at")
                                    Text(loc: "lists.advanced.mentions_button")
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .flipsForRightToLeftLayoutDirection(true)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 4)
                            }
                            Button {
                                presentationState.showCustomSearch = true
                            } label: {
                                HStack {
                                    Image(systemName: "magnifyingglass")
                                    Text(loc: "lists.advanced.customsearch_button")
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .flipsForRightToLeftLayoutDirection(true)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 4)
                            }
                            Button {
                                presentationState.showDirectReplies = true
                            } label: {
                                HStack {
                                    Image(systemName: "arrowshape.turn.up.left")
                                    Text(loc: "lists.advanced.directreplies_button")
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .flipsForRightToLeftLayoutDirection(true)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 4)
                            }
                        } header: {
                            HStack(spacing: 4) {
                                Text(loc: "lists.advanced")
                                HelpInfoButton(
                                    action: { showAdvancedHelp = true },
                                    accessibilityLabel: loc("lists.advanced")
                                )
                            }
                        }

                        if let errorMessage = viewModel.errorMessage {
                            ErrorRetryBanner(message: errorMessage) {
                                viewModel.errorMessage = nil
                                Task {
                                    await reload()
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .listSectionSpacing(.compact)
                    .refreshable {
                        await reload()
                    }
                }
            }
            .navigationTitle("")
            .toolbarTitleDisplayMode(.inline)
            .sheet(isPresented: $presentationState.isShowingAccountPicker) {
                AccountSwitcherSheet(isPresented: $presentationState.isShowingAccountPicker)
                    .environmentObject(accountStore)
            }

            .sheet(isPresented: $presentationState.isShowingBulkLookup) {
                NavigationStack {
                    BulkProfileLookupView()
                        .environmentObject(accountStore)
                        .environmentObject(blueskyClient)
                }
            }
            .sheet(isPresented: $presentationState.isShowingCreateList) {
                ListMetadataSheet(mode: .create(kind: presentationState.createListKind)) { name, description, kind in
                    if let account = accountStore.activeAccount,
                       let appPassword = accountStore.appPassword(for: account) {
                        Task {
                            do {
                                let newList = try await blueskyClient.createList(
                                    name: name,
                                    description: description,
                                    kind: kind,
                                    account: account,
                                    appPassword: appPassword
                                )
                                viewModel.addList(newList)
                            } catch {
                                viewModel.errorMessage = AppError.userMessage(from: error)
                            }
                        }
                    }
                }
                .environmentObject(accountStore)
                .environmentObject(blueskyClient)
            }
            .sheet(isPresented: $presentationState.isShowingCreateInternalList) {
                NavigationStack {
                    Form {
                        Section {
                            TextField(loc("internal.lists.name"), text: $internalListName)
                            Picker(loc("internal.lists.color"), selection: $internalListColor) {
                                ForEach(InternalListColor.allCases, id: \.self) { color in
                                    HStack {
                                        Circle()
                                            .fill(color.colorValue)
                                            .frame(width: 16, height: 16)
                                        Text(color.rawValue.capitalized)
                                    }
                                    .tag(color)
                                }
                            }
                            .pickerStyle(.navigationLink)
                        }
                    }
                    .navigationTitle(loc("internal.lists.create"))
                    .toolbarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("actions.save") {
                                internalListStore.addList(name: internalListName, color: internalListColor)
                                internalListName = ""
                                internalListColor = .blue
                                presentationState.isShowingCreateInternalList = false
                            }
                            .disabled(internalListName.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                        ToolbarItem(placement: .cancellationAction) {
                            Button("actions.cancel") { presentationState.isShowingCreateInternalList = false }
                        }
                    }
                }
                .presentationDetents([.medium])
            }
            .sheet(isPresented: $isShowingUserSearch) {
                NavigationStack {
                    UserSearchSheet()
                        .environmentObject(accountStore)
                        .environmentObject(blueskyClient)
                }
            }
            .sheet(isPresented: $isShowingListPicker) {
                exportListPickerSheet
            }
            .sheet(isPresented: $presentationState.isShowingAccountManagement) {
                NavigationStack {
                    AccountSwitcherSheet(isPresented: $presentationState.isShowingAccountManagement)
                        .environmentObject(accountStore)
                        .environmentObject(blueskyClient)
                }
            }
            .sheet(isPresented: $showModerationListsHelp) {
                helpSheet(
                    title: loc("lists.moderation_lists"),
                    text: loc("lists.moderation_lists.help")
                )
            }
            .sheet(isPresented: $showListsHelp) {
                helpSheet(
                    title: loc("lists.lists"),
                    text: loc("lists.lists.help")
                )
            }
            .sheet(isPresented: $showInternalListsHelp) {
                helpSheet(
                    title: loc("internal.lists.section"),
                    text: loc("internal.lists.help")
                )
            }
            .sheet(isPresented: $showAdvancedHelp) {
                helpSheet(
                    title: loc("lists.advanced"),
                    text: loc("lists.advanced.help")
                )
            }
            .task(id: accountStore.activeAccountID) {
                await loadInitial()
            }
            .onChange(of: accountStore.activeAccountID) { _, newValue in
                viewModel.reset()
                if newValue != nil {
                    Task { await loadInitial() }
                }
            }
            .navigationDestination(isPresented: $presentationState.showProfile) {
                if let activeAccount = accountStore.activeAccount {
                    BlueskyProfileView(
                        member: activeAccountMember(activeAccount),
                        list: nil
                    )
                    .environmentObject(accountStore)
                    .environmentObject(blueskyClient)
                }
            }
            .navigationDestination(isPresented: $presentationState.showFollowers) {
                RelationshipsView(mode: .followers, initialCount: viewModel.activeProfile?.followersCount)
                    .environmentObject(accountStore)
                    .environmentObject(blueskyClient)
            }
            .navigationDestination(isPresented: $presentationState.showFollowing) {
                RelationshipsView(mode: .following, initialCount: viewModel.activeProfile?.followsCount)
                    .environmentObject(accountStore)
                    .environmentObject(blueskyClient)
            }
            .navigationDestination(isPresented: $presentationState.showBlocking) {
                RelationshipsView(mode: .blocking, initialCount: viewModel.blockingCount)
                    .environmentObject(accountStore)
                    .environmentObject(blueskyClient)
            }
            .navigationDestination(isPresented: $presentationState.showBlockedBy) {
                RelationshipsView(mode: .blockedBy, initialCount: viewModel.blockedByCount)
                    .environmentObject(accountStore)
                    .environmentObject(blueskyClient)
            }
            .navigationDestination(isPresented: $presentationState.showMentionsSearch) {
                if let activeAccount = accountStore.activeAccount {
                    MentionsSearchView(
                        did: activeAccount.did ?? activeAccount.handle,
                        handle: activeAccount.handle,
                        displayName: activeAccount.displayName
                    )
                    .environmentObject(accountStore)
                    .environmentObject(blueskyClient)
                }
            }
            .navigationDestination(isPresented: $presentationState.showCustomSearch) {
                CustomSearchView()
                    .environmentObject(accountStore)
                    .environmentObject(blueskyClient)
            }
            .navigationDestination(isPresented: $presentationState.showDirectReplies) {
                if let activeAccount = accountStore.activeAccount {
                    DirectRepliesView(
                        did: activeAccount.did ?? activeAccount.handle,
                        handle: activeAccount.handle,
                        displayName: activeAccount.displayName
                    )
                    .environmentObject(accountStore)
                    .environmentObject(blueskyClient)
                }
            }
        }
        .id(workspaceStore.moderationNavigationResetToken)
        .onChange(of: workspaceStore.moderationNavigationResetToken) { _, _ in
            presentationState = PresentationState()
            exportFormat = nil
            isShowingListPicker = false
            shareFileURL = nil
            isExporting = false
            exportProgressMessage = nil
            exportProgressFraction = nil
            showShareSheet = false
        }
    }

    // MARK: - Helpers

    private func helpSheet(title: String, text: String) -> some View {
        NavigationStack {
            List {
                Section {
                    Text(text)
                        .font(.body)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(title)
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    ToolbarCloseButton()
                }
            }
        }
    }

    private func loadInitial() async {
        let password = accountStore.activeAccount.flatMap { accountStore.appPassword(for: $0) }
        await viewModel.load(
            for: accountStore.activeAccount,
            appPassword: password,
            using: blueskyClient
        )
    }

    private func reload() async {
        let password = accountStore.activeAccount.flatMap { accountStore.appPassword(for: $0) }
        await viewModel.load(
            for: accountStore.activeAccount,
            appPassword: password,
            using: blueskyClient,
            isExplicitRefresh: true
        )
    }

    private func relationshipRow(label: String, count: Int?, isLoading: Bool = false) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .appFont(.heading)
                    .lineLimit(1)
                    .foregroundStyle(.primary)
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.7)
                } else {
                    Text(count.map { "\($0)" } ?? "-")
                        .appFont(.statistic)
                        .foregroundStyle(Color.skyPrimary)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .flipsForRightToLeftLayoutDirection(true)
                .appFont(.subheading)
                .foregroundStyle(Color.skyPrimary.opacity(0.8))
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(LinearGradient.cardSurfaceGradient)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.skyPrimary.opacity(0.12), lineWidth: 1)
        }
        .appButtonAccessibility(label: label, hint: loc("rel.view.hint"))
    }

    private func activeAccountMember(_ account: AppAccount) -> BlueskyListMember {
        BlueskyListMember(
            recordURI: "account:\(account.id.uuidString)",
            actor: BlueskyActor(
                did: account.did ?? account.handle,
                handle: account.handle,
                displayName: account.displayName,
                avatarURL: viewModel.activeProfile?.avatarURL
            )
        )
    }

    private func openAccountManagement() {
        presentationState.isShowingAccountManagement = true
    }
}

#Preview {
    ListsView()
        .environmentObject(AccountStore(preview: true))
        .environmentObject(PreviewBlueskyClient())
}
