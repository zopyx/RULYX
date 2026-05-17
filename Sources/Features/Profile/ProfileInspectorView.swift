import SwiftUI

struct ProfileInspectorView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @EnvironmentObject private var accountStore: AccountStore
    @EnvironmentObject private var blueskyClient: LiveBlueskyClient
    @EnvironmentObject private var workspaceStore: ModerationWorkspaceStore
    @EnvironmentObject private var localizationManager: LocalizationManager
    @StateObject private var viewModel = ProfileInspectorViewModel()
    @State private var isShowingQuickAccountSwitcher = false
    @State private var isShowingAccountManagement = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField(loc("profile.search.placeholder"), text: $viewModel.query)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityLabel(loc("profile.search.label"))
                        .accessibilityHint(loc("profile.search.hint"))

                    if viewModel.isSearching {
                        LoadingPanel(message: localizationManager.localized("profile.searching"))
                    } else if !viewModel.query.isEmpty, viewModel.query.trimmingCharacters(in: .whitespacesAndNewlines).count < 2 {
                        Text(verbatim: localizationManager.localized("profile.search.hint"))
                            .foregroundStyle(.secondary)
                    } else if !viewModel.searchResults.isEmpty {
                        ForEach(viewModel.searchResults) { actor in
                            Button {
                                Task {
                                    await viewModel.inspect(
                                        actor: actor,
                                        account: accountStore.activeAccount,
                                        appPassword: activePassword,
                                        using: blueskyClient
                                    )
                                }
                            } label: {
                                BlueskyActorRow(actor: actor)
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint(localizationManager.localized("profile.result.hint"))
                        }
                    } else if !viewModel.query.isEmpty, !viewModel.isSearching {
                        EmptyStatePanel(title: localizationManager.localized("profile.search.no_results"))
                    }

                    Button {
                        Task {
                            await viewModel.inspect(
                                account: accountStore.activeAccount,
                                appPassword: activePassword,
                                using: blueskyClient
                            )
                        }
                    } label: {
                        if viewModel.isLoading {
                            HStack {
                                ProgressView()
                                Text(verbatim: localizationManager.localized("profile.inspecting"))
                            }
                        } else {
                            Label {
                                Text(verbatim: localizationManager.localized("profile.inspect"))
                            } icon: {
                                Image(systemName: "magnifyingglass")
                            }
                        }
                    }
                    .disabled(viewModel.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isLoading)
                    .accessibilityLabel(localizationManager.localized("profile.inspect.label"))
                    .accessibilityHint(localizationManager.localized("profile.inspect.hint"))

                    Button {
                        workspaceStore.saveProfileSearch(viewModel.query)
                    } label: {
                        Label {
                            Text(verbatim: localizationManager.localized("profile.save_search"))
                        } icon: {
                            Image(systemName: "bookmark")
                        }
                    }
                    .disabled(viewModel.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityLabel(loc("profile.save_search.label"))
                    .accessibilityHint(loc("profile.save_search.hint"))

                    if let activeAccount = accountStore.activeAccount {
                        Text(verbatim: localizationManager.localized("profile.using_account").replacingOccurrences(of: "{handle}", with: activeAccount.handle))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(verbatim: localizationManager.localized("profile.add_account_first"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if horizontalSizeClass == .regular, accountStore.activeAccount != nil {
                        Button {
                            isShowingQuickAccountSwitcher = true
                        } label: {
                            Label(localizationManager.localized("account.switch"), systemImage: "person.crop.circle")
                        }
                        .accessibilityLabel(localizationManager.localized("account.switcher.label"))
                        .accessibilityHint(localizationManager.localized("account.switcher.hint"))
                    }
                }

                if let errorMessage = viewModel.errorMessage {
                    ErrorRetryBanner(message: errorMessage) {
                        viewModel.errorMessage = nil
                        Task {
                            await viewModel.search(
                                account: accountStore.activeAccount,
                                appPassword: activePassword,
                                using: blueskyClient
                            )
                        }
                    }
                }

                if !workspaceStore.savedSearches.isEmpty {
                    Section {
                        ForEach(workspaceStore.savedSearches) { search in
                            Button {
                                viewModel.query = search.query
                            } label: {
                                HStack {
                                    Text(search.query)
                                    Spacer()
                                    Image(systemName: "bookmark.fill")
                                        .foregroundStyle(Color.skyPrimary)
                                }
                            }
                            .accessibilityLabel(loc("profile.saved_search.label").replacingOccurrences(of: "{query}", with: search.query))
                            .buttonStyle(.plain)
                            .swipeActions {
                                Button(role: .destructive) {
                                    workspaceStore.deleteSavedSearch(search)
                                } label: {
                                    Label(loc("actions.delete"), systemImage: "trash")
                                }
                            }
                        }
                    } header: {
                        Text(verbatim: localizationManager.localized("profile.saved_searches"))
                    }
                }

                if !workspaceStore.recentSearches.isEmpty {
                    Section {
                        ForEach(workspaceStore.recentSearches) { search in
                            Button {
                                viewModel.query = search.query
                            } label: {
                                HStack {
                                    Text(search.query)
                                    Spacer()
                                    Text(search.usedAt, style: .time)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .accessibilityLabel(loc("profile.recent_search.label").replacingOccurrences(of: "{query}", with: search.query))
                            .buttonStyle(.plain)
                        }
                    } header: {
                        Text(verbatim: localizationManager.localized("profile.recent_searches"))
                    }
                }

                if let inspection = viewModel.inspection {
                    Section {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(inspection.profile.title)
                                .font(.title3.weight(.semibold))
                            Text(inspection.profile.handle)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text(inspection.profile.did)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)

                            if let description = inspection.profile.description, !description.isEmpty {
                                Text(description)
                                    .font(.body)
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    Section {
                        if isOwnProfile {
                            NavigationLink {
                                RelationshipsView(mode: .followers, initialCount: inspection.profile.followersCount)
                            } label: {
                                HStack {
                                    Text(verbatim: loc("profile.stats.followers"))
                                    Spacer()
                                    Text(countText(inspection.profile.followersCount))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            NavigationLink {
                                RelationshipsView(mode: .following, initialCount: inspection.profile.followsCount)
                            } label: {
                                HStack {
                                    Text(verbatim: loc("profile.stats.following"))
                                    Spacer()
                                    Text(countText(inspection.profile.followsCount))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        } else {
                            LabeledContent(loc("profile.stats.followers"), value: countText(inspection.profile.followersCount))
                            LabeledContent(loc("profile.stats.following"), value: countText(inspection.profile.followsCount))
                        }
                        LabeledContent(loc("profile.stats.posts"), value: countText(inspection.profile.postsCount))
                        LabeledContent(loc("profile.stats.lists"), value: countText(inspection.profile.listsCount))
                        LabeledContent(loc("profile.stats.starter_packs"), value: countText(inspection.profile.starterPacksCount))
                    } header: {
                        Text(verbatim: loc("profile.stats"))
                    }

                    Section {
                        NavigationLink {
                            BlueskyProfileView(
                                member: BlueskyListMember(
                                    recordURI: "inspection:\(inspection.profile.did)",
                                    actor: BlueskyActor(
                                        did: inspection.profile.did,
                                        handle: inspection.profile.handle,
                                        displayName: inspection.profile.displayName,
                                        avatarURL: inspection.profile.avatarURL
                                    )
                                ),
                                list: nil
                            )
                        } label: {
                            Label {
                                Text(verbatim: loc("profile.open_controls"))
                            } icon: {
                                Image(systemName: "slider.horizontal.3")
                            }
                        }
                        .accessibilityLabel(loc("profile.open_controls.label"))
                        .accessibilityHint(loc("profile.open_controls.hint"))
                    } header: {
                        Text(verbatim: loc("profile.moderation_actions"))
                    }

                    if !inspection.profile.labels.isEmpty {
                        Section {
                            ForEach(inspection.profile.labels, id: \.self) { label in
                                Text(label)
                            }
                        } header: {
                            Text(verbatim: loc("profile.labels_section"))
                        }
                    }

                    Section {
                        if inspection.listMemberships.isEmpty {
                            Text(verbatim: loc("profile.no_lists"))
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(inspection.listMemberships) { item in
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(item.name)
                                        Text(item.kind.title)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(item.isMember ? loc("profile.member_status") : loc("profile.not_in_list_status"))
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(item.isMember ? .green : .secondary)
                                }
                            }
                        }
                    } header: {
                        Text(verbatim: loc("profile.your_lists_section"))
                    }

                    Section {
                        if inspection.starterPackMemberships.isEmpty {
                            Text(verbatim: loc("profile.no_starter_packs"))
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(inspection.starterPackMemberships) { item in
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(item.name)
                                        if let joined = item.joinedAllTimeCount {
                                            Text(verbatim: loc("profile.joined_all_time").replacingOccurrences(of: "{count}", with: "\(joined)"))
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer()
                                    Text(item.isMember ? loc("profile.included_status") : loc("profile.not_included_status"))
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(item.isMember ? .green : .secondary)
                                }
                            }
                        }
                    } header: {
                        Text(verbatim: loc("profile.your_starter_packs_section"))
                    }

                    if let profileURL = inspection.profile.profileURL {
                        Section {
                            Link(destination: profileURL) {
                                Label {
                                    Text(verbatim: loc("profile.open_bluesky"))
                                } icon: {
                                    Image(systemName: "arrow.up.right.square")
                                }
                            }
                            .accessibilityLabel(loc("profile.open_bluesky.label"))
                            .accessibilityHint(loc("profile.open_bluesky.hint"))
                        } header: {
                            Text(verbatim: loc("profile.open_section"))
                        }
                    }
                }
            }
            .navigationTitle(loc("profile.title"))
            .toolbar {
                if horizontalSizeClass == .compact {
                    accountSwitcherToolbar(isPresented: $isShowingQuickAccountSwitcher, accountStore: accountStore, localizationManager: localizationManager)
                }
            }
            .sheet(isPresented: $isShowingQuickAccountSwitcher) {
                AccountQuickSwitcherSheet(
                    isPresented: $isShowingQuickAccountSwitcher,
                    onManageAccounts: openAccountManagement
                )
                .environmentObject(accountStore)
                .environmentObject(blueskyClient)
            }
            .sheet(isPresented: $isShowingAccountManagement) {
                AccountSwitcherSheet(isPresented: $isShowingAccountManagement)
                    .environmentObject(accountStore)
                    .environmentObject(blueskyClient)
            }
            .task {
                if viewModel.query.isEmpty {
                    viewModel.query = workspaceStore.lastProfileQuery
                }
            }
            .task(id: viewModel.query) {
                do {
                    try await Task.sleep(for: .milliseconds(300))
                } catch {
                    return
                }

                await viewModel.search(
                    account: accountStore.activeAccount,
                    appPassword: activePassword,
                    using: blueskyClient
                )
            }
            .refreshable {
                await viewModel.search(
                    account: accountStore.activeAccount,
                    appPassword: activePassword,
                    using: blueskyClient
                )
            }
            .onChange(of: viewModel.query) { _, newValue in
                workspaceStore.lastProfileQuery = newValue
            }
            .onChange(of: viewModel.inspection) { _, newInspection in
                if let newInspection {
                    workspaceStore.noteRecentSearch(newInspection.profile.handle)
                }
            }
        }
    }

    private var isOwnProfile: Bool {
        guard let account = accountStore.activeAccount,
              let inspection = viewModel.inspection else { return false }
        if let activeDID = account.did, activeDID == inspection.profile.did { return true }
        return account.handle.lowercased() == inspection.profile.handle.lowercased()
    }

    private var activePassword: String? {
        accountStore.activeAccount.flatMap { accountStore.appPassword(for: $0) }
    }

    private func countText(_ value: Int?) -> String {
        if let value {
            return "\(value)"
        }
        return "-"
    }

    private func openAccountManagement() {
        isShowingQuickAccountSwitcher = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            isShowingAccountManagement = true
        }
    }
}

#Preview {
    ProfileInspectorView()
        .environmentObject(AccountStore(preview: true))
        .environmentObject(PreviewBlueskyClient())
        .environmentObject(ModerationWorkspaceStore(preview: true))
}
