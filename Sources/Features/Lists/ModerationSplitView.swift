import SwiftUI

struct ModerationSplitView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @EnvironmentObject private var accountStore: AccountStore
    @EnvironmentObject private var blueskyClient: LiveBlueskyClient
    @EnvironmentObject private var workspaceStore: ModerationWorkspaceStore
    @EnvironmentObject private var localizationManager: LocalizationManager

    @StateObject private var viewModel = ListsViewModel()
    @State private var selectedList: BlueskyList?
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    // Relationships / profile sheets on iPad
    @State private var showProfile = false
    @State private var showFollowers = false
    @State private var showFollowing = false
    @State private var showBlocking = false
    @State private var showBlockedBy = false
    @State private var isShowingCreateList = false
    @State private var createListKind: BlueskyList.Kind = .moderation
    @State private var isShowingBulkLookup = false
    @State private var isShowingAccountManagement = false

    var body: some View {
        Group {
            if horizontalSizeClass == .compact {
                compactContent
            } else {
                regularContent
            }
        }
        .task(id: accountStore.activeAccountID) {
            await loadInitial()
        }
        .onChange(of: accountStore.activeAccountID) { _, newValue in
            if newValue != nil {
                Task { await loadInitial() }
            }
        }
        .onChange(of: workspaceStore.moderationNavigationResetToken) { _, _ in
            selectedList = nil
            showProfile = false
            showFollowers = false
            showFollowing = false
            showBlocking = false
            showBlockedBy = false
            isShowingCreateList = false
            isShowingBulkLookup = false
            isShowingAccountManagement = false
            columnVisibility = .all
        }
    }

    // MARK: - Compact (iPhone) — delegate to existing ListsView

    private var compactContent: some View {
        ListsView()
            .environmentObject(accountStore)
            .environmentObject(blueskyClient)
            .environmentObject(workspaceStore)
            .environmentObject(localizationManager)
    }

    // MARK: - Regular (iPad) — NavigationSplitView with sidebar + detail

    private var regularContent: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebarContent
                .navigationTitle("")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            Task { await reload() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .disabled(accountStore.activeAccount == nil)
                    }
                }
                .sheet(isPresented: $isShowingCreateList) {
                    ListMetadataSheet(mode: .create(kind: createListKind)) { name, description, kind in
                        if let account = accountStore.activeAccount,
                           let appPassword = accountStore.appPassword(for: account)
                        {
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
                .sheet(isPresented: $isShowingBulkLookup) {
                    NavigationStack {
                        BulkProfileLookupView()
                            .environmentObject(accountStore)
                            .environmentObject(blueskyClient)
                    }
                }
                .sheet(isPresented: $isShowingAccountManagement) {
                    NavigationStack {
                        AccountSwitcherSheet(isPresented: $isShowingAccountManagement)
                            .environmentObject(accountStore)
                            .environmentObject(blueskyClient)
                    }
                }
        } detail: {
            NavigationStack {
                detailColumnContent
            }
        }
        // Profile and relationship sheets (triggered from sidebar)
        .sheet(isPresented: $showProfile) {
            if let activeAccount = accountStore.activeAccount {
                NavigationStack {
                    BlueskyProfileView(
                        member: activeAccountMember(activeAccount),
                        list: nil
                    )
                    .environmentObject(accountStore)
                    .environmentObject(blueskyClient)
                }
            }
        }
        .sheet(isPresented: $showFollowers) {
            NavigationStack {
                RelationshipsView(mode: .followers, initialCount: viewModel.activeProfile?.followersCount)
                    .environmentObject(accountStore)
                    .environmentObject(blueskyClient)
            }
        }
        .sheet(isPresented: $showFollowing) {
            NavigationStack {
                RelationshipsView(mode: .following, initialCount: viewModel.activeProfile?.followsCount)
                    .environmentObject(accountStore)
                    .environmentObject(blueskyClient)
            }
        }
        .sheet(isPresented: $showBlocking) {
            NavigationStack {
                RelationshipsView(mode: .blocking, initialCount: viewModel.blockingCount)
                    .environmentObject(accountStore)
                    .environmentObject(blueskyClient)
            }
        }
        .sheet(isPresented: $showBlockedBy) {
            NavigationStack {
                RelationshipsView(mode: .blockedBy, initialCount: viewModel.blockedByCount)
                    .environmentObject(accountStore)
                    .environmentObject(blueskyClient)
            }
        }
    }

    // MARK: - Detail column (selected list or placeholder)

    @ViewBuilder
    private var detailColumnContent: some View {
        if let list = selectedList {
            ListDetailView(list: list) { updatedList in
                viewModel.updateList(updatedList)
            }
            .environmentObject(accountStore)
            .environmentObject(blueskyClient)
            .environmentObject(workspaceStore)
            .id(list.id)
        } else {
            Color(.systemGroupedBackground)
                .ignoresSafeArea()
        }
    }

    // MARK: - Sidebar (lists overview)

    @ViewBuilder
    private var sidebarContent: some View {
        if accountStore.accounts.isEmpty {
            ContentUnavailableView {
                Label(localizationManager.localized("lists.no_account.title"), systemImage: "person.crop.circle.badge.plus")
            } description: {
                Text(verbatim: localizationManager.localized("lists.no_account.desc"))
            }
        } else if viewModel.isLoading && !viewModel.isRefreshing {
            loadingSkeleton
        } else {
            sidebarList
        }
    }

    private var loadingSkeleton: some View {
        List {
            Section {
                SkeletonCard()
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                    .listRowBackground(Color.clear)
            }
            Section {
                SkeletonGrid()
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            } header: {
                Text(verbatim: localizationManager.localized("lists.relationships"))
                    .redacted(reason: .placeholder)
            }
            Section {
                SkeletonRow()
                SkeletonRow()
            } header: {
                Text(verbatim: localizationManager.localized("lists.moderation_lists"))
                    .redacted(reason: .placeholder)
            }
        }
        .listStyle(.insetGrouped)
        .redacted(reason: .placeholder)
    }

    private var sidebarList: some View {
        List(selection: $selectedList) {
            // Account summary card
            if let activeAccount = accountStore.activeAccount {
                Section {
                    Button {
                        showProfile = true
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

            // Relationships grid
            Section {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading) {
                    sidebarRelationshipButton(
                        icon: "person.3",
                        label: loc("lists.followers"),
                        count: viewModel.activeProfile?.followersCount ?? 0,
                        action: { showFollowers = true }
                    )
                    sidebarRelationshipButton(
                        icon: "person.3.fill",
                        label: loc("lists.following"),
                        count: viewModel.activeProfile?.followsCount ?? 0,
                        action: { showFollowing = true }
                    )
                    sidebarRelationshipButton(
                        icon: "hand.raised",
                        label: loc("lists.blocking"),
                        count: viewModel.blockingCount,
                        action: { showBlocking = true }
                    )
                    sidebarRelationshipButton(
                        icon: "hand.raised.slash",
                        label: loc("lists.blocked_by"),
                        count: viewModel.blockedByCount,
                        action: { showBlockedBy = true }
                    )
                }
            } header: {
                Text(verbatim: localizationManager.localized("lists.relationships"))
            }

            // Moderation lists
            if let lists = viewModel.listsByKind[.moderation], !lists.isEmpty {
                Section {
                    ForEach(lists) { list in
                        ListRowView(list: list)
                            .tag(list as BlueskyList?)
                            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                    }
                } header: {
                    sectionHeader(
                        title: loc("lists.moderation_lists"),
                        icon: "checklist.checked",
                        kind: .moderation
                    )
                }
            } else {
                Section {
                    Button {
                        createListKind = .moderation
                        isShowingCreateList = true
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "plus.circle.fill")
                                .font(.title3)
                                .foregroundStyle(.tertiary)
                            Text(verbatim: localizationManager.localized("lists.create_first_mod"))
                                .font(.subheadline)
                                .foregroundStyle(.tertiary)
                            Spacer()
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    sectionHeader(
                        title: loc("lists.moderation_lists"),
                        icon: "checklist.checked",
                        kind: .moderation
                    )
                }
            }

            // Regular lists
            if let lists = viewModel.listsByKind[.regular], !lists.isEmpty {
                Section {
                    ForEach(lists) { list in
                        ListRowView(list: list)
                            .tag(list as BlueskyList?)
                            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                    }
                } header: {
                    sectionHeader(
                        title: loc("lists.lists"),
                        icon: "list.bullet",
                        kind: .regular
                    )
                }
            } else {
                Section {
                    Button {
                        createListKind = .regular
                        isShowingCreateList = true
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "plus.circle.fill")
                                .font(.title3)
                                .foregroundStyle(.tertiary)
                            Text(verbatim: localizationManager.localized("lists.create_first"))
                                .font(.subheadline)
                                .foregroundStyle(.tertiary)
                            Spacer()
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    sectionHeader(
                        title: loc("lists.lists"),
                        icon: "list.bullet",
                        kind: .regular
                    )
                }
            }

            // Error banner
            if let errorMessage = viewModel.errorMessage {
                ErrorRetryBanner(message: errorMessage) {
                    viewModel.errorMessage = nil
                    Task { await reload() }
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable { await reload() }
    }

    // MARK: - Helpers

    private func sidebarRelationshipButton(icon: String, label: String, count: Int, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: label)
                        .appFont(.heading)
                        .foregroundStyle(.primary)
                    Text("\(count)")
                        .appFont(.statistic)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isButton)
    }

    private func sectionHeader(title: String, icon: String, kind: BlueskyList.Kind) -> some View {
        HStack {
            Image(systemName: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(kind == .moderation ? .orange : .skyPrimary)
            Text(verbatim: title)
                .font(.subheadline.weight(.semibold))
                .textCase(.none)
            Spacer()
            Button {
                createListKind = kind
                isShowingCreateList = true
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.title3)
                    .foregroundStyle(kind == .moderation ? .orange : .skyPrimary)
                    .symbolRenderingMode(.hierarchical)
            }
            .buttonStyle(.plain)
        }
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
}

#Preview {
    ModerationSplitView()
        .environmentObject(AccountStore(preview: true))
        .environmentObject(PreviewBlueskyClient())
        .environmentObject(ModerationWorkspaceStore(preview: true))
        .environmentObject(LocalizationManager.shared)
}
