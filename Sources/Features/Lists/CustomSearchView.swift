import SwiftUI
import UIKit

struct CustomSearchView: View {
    @StateObject private var viewModel = CustomSearchViewModel()
    @EnvironmentObject var accountStore: AccountStore
    @EnvironmentObject var blueskyClient: LiveBlueskyClient
    @Environment(\.dismiss) private var dismiss
    @State private var searchAccount: AppAccount?
    @State private var selectedTab: CustomSearchViewModel.Tab = .top
    @State private var selectedPostURI: String?
    @State private var imagePreview: ImagePreviewCollection?
    @State private var videoPreviewURL: URL?
    @State private var showLikesForURI: String?
    @State private var loadMoreTask: Task<Void, Never>?
    @State private var showProfileFor: BlueskyActor?
    @State private var availableTargetLists: [BlueskyList] = []
    @State private var hasAppeared = false
    @FocusState private var searchFocused: Bool
    @EnvironmentObject private var localizationManager: LocalizationManager

    var body: some View {
        listContent
            .listStyle(.insetGrouped)
            .navigationTitle("customsearch.title")
            .navigationBarTitleDisplayMode(.inline)
            .modifier(SearchSheetsModifier(
                selectedPostURI: $selectedPostURI,
                imagePreview: $imagePreview,
                videoPreviewURL: $videoPreviewURL,
                showLikesForURI: $showLikesForURI,
                showProfileFor: $showProfileFor,
                accountStore: accountStore,
                blueskyClient: blueskyClient
            ))
            .task {
                if !hasAppeared {
                    hasAppeared = true
                    if let prefID = accountStore.preferredSearchAccountID,
                       let prefAccount = accountStore.accounts.first(where: { $0.id == prefID })
                    {
                        searchAccount = prefAccount
                    } else {
                        searchAccount = accountStore.activeAccount
                    }
                    await loadAvailableTargetLists()
                }
            }
            .onChange(of: accountStore.activeAccount?.id) { _, _ in
                Task { await loadAvailableTargetLists() }
            }
            .onDisappear {
                loadMoreTask?.cancel()
            }
    }

    private var listContent: some View {
        List {
            searchAccountSection
            searchFieldSection
            if viewModel.query.isEmpty, !viewModel.searchHistory.isEmpty {
                recentSearchesSection
            }
            if !viewModel.query.isEmpty {
                tabPickerSection
                tabContentSection
            }
        }
    }

    private var searchAccountSection: some View {
        Group {
            if let searchAccount {
                searchAccountRow(searchAccount)
            }
        }
        .listRowInsets(EdgeInsets(top: -4, leading: 0, bottom: 0, trailing: 0))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    private func searchAccountRow(_ account: AppAccount) -> some View {
        HStack(spacing: 14) {
            if let avatarURL = account.avatarURL {
                ThumbnailImageView(url: avatarURL, maxPixelSize: 64) {
                    avatarPlaceholder(for: account)
                }
                .scaledToFill()
                .frame(width: 32, height: 32)
                .clipShape(Circle())
            } else {
                avatarPlaceholder(for: account)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("customsearch.searching_as")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.primary)
                Text(account.displayName)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.skyPrimary.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.skyPrimary.opacity(0.12), lineWidth: 1)
        )
    }

    private func avatarPlaceholder(for account: AppAccount) -> some View {
        Circle()
            .fill(Color.skyPrimary.opacity(0.25))
            .frame(width: 32, height: 32)
            .overlay {
                Text(account.displayName.prefix(1).uppercased())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
            }
    }

    private var searchFieldSection: some View {
        Section {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.tertiary)
                TextField("customsearch.placeholder", text: $viewModel.query)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($searchFocused)
                    .onSubmit {
                        performSearch()
                    }
                if !viewModel.query.isEmpty {
                    Button {
                        viewModel.query = ""
                        viewModel.reset()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .onChange(of: viewModel.query) { _, newValue in
            if newValue.isEmpty {
                viewModel.reset()
            }
        }
    }

    private var recentSearchesSection: some View {
        Section("customsearch.recent") {
            ForEach(viewModel.searchHistory, id: \.self) { query in
                HStack {
                    Button {
                        viewModel.query = query
                        searchFocused = false
                        performSearch()
                    } label: {
                        HStack {
                            Image(systemName: "clock.arrow.circlepath")
                                .foregroundStyle(.tertiary)
                            Text(query)
                                .lineLimit(1)
                                .foregroundStyle(.primary)
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Button {
                        viewModel.deleteHistoryItem(query)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var tabPickerSection: some View {
        Section {
            Picker("customsearch.tab", selection: $selectedTab) {
                ForEach(CustomSearchViewModel.Tab.allCases, id: \.self) { tab in
                    Text(verbatim: tabLabel(tab)).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
        }
    }

    @ViewBuilder
    private var tabContentSection: some View {
        switch selectedTab {
        case .top:
            postsSection(
                entries: viewModel.topEntries,
                isLoading: viewModel.isLoadingTop,
                isLoadingMore: viewModel.isLoadingMoreTop,
                hasMore: viewModel.hasMoreTop,
                loadMore: { await loadMoreTop() }
            )
        case .newest:
            postsSection(
                entries: viewModel.newestEntries,
                isLoading: viewModel.isLoadingNewest,
                isLoadingMore: viewModel.isLoadingMoreNewest,
                hasMore: viewModel.hasMoreNewest,
                loadMore: { await loadMoreNewest() }
            )
        case .users:
            usersSection
        }
    }

    @ViewBuilder
    private func postsSection(entries: [RichFeedEntry], isLoading: Bool, isLoadingMore: Bool, hasMore: Bool, loadMore: @escaping () async -> Void) -> some View {
        if isLoading {
            loadingRow
        } else if let error = viewModel.errorMessage, entries.isEmpty {
            errorRow(error)
        } else if entries.isEmpty {
            emptyRow
        } else {
            postRows(entries: entries, isLoadingMore: isLoadingMore, hasMore: hasMore, loadMore: loadMore)
        }
    }

    private var loadingRow: some View {
        HStack {
            Spacer()
            ProgressView("customsearch.loading")
            Spacer()
        }
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    private func errorRow(_ error: String) -> some View {
        HStack {
            Spacer()
            ContentUnavailableView(
                String(localized: "list.detail.alert_title"),
                systemImage: "exclamationmark.bubble",
                description: Text(error)
            )
            Spacer()
        }
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    private var emptyRow: some View {
        HStack {
            Spacer()
            ContentUnavailableView(
                String(localized: "customsearch.empty"),
                systemImage: "magnifyingglass",
                description: Text("customsearch.empty_desc")
            )
            Spacer()
        }
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    @ViewBuilder
    private func postRows(entries: [RichFeedEntry], isLoadingMore: Bool, hasMore: Bool, loadMore: @escaping () async -> Void) -> some View {
        ForEach(entries, id: \.post.uri) { entry in
            postRowView(entry: entry, entries: entries, loadMore: loadMore)
        }
        if isLoadingMore {
            HStack {
                Spacer()
                ProgressView()
                    .scaleEffect(0.8)
                Spacer()
            }
            .listRowSeparator(.hidden)
        }
        if !hasMore, !entries.isEmpty {
            Text("customsearch.end")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity)
                .listRowSeparator(.hidden)
        }
    }

    private func postRowView(entry: RichFeedEntry, entries: [RichFeedEntry], loadMore: @escaping () async -> Void) -> some View {
        CustomSearchPostRow(
            entry: entry,
            entries: entries,
            loadMore: loadMore,
            imagePreview: $imagePreview,
            videoPreviewURL: $videoPreviewURL,
            showLikesForURI: $showLikesForURI,
            showProfileFor: $showProfileFor,
            availableTargetLists: availableTargetLists
        )
    }

    @ViewBuilder
    private var usersSection: some View {
        if viewModel.isLoadingUsers {
            HStack {
                Spacer()
                ProgressView("customsearch.loading")
                Spacer()
            }
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
        } else if viewModel.users.isEmpty {
            HStack {
                Spacer()
                ContentUnavailableView(
                    String(localized: "customsearch.empty_users"),
                    systemImage: "person.slash",
                    description: Text("customsearch.empty_users_desc")
                )
                Spacer()
            }
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
        } else {
            ForEach(viewModel.users) { actor in
                Button {
                    showProfileFor = actor
                } label: {
                    BlueskyActorRow(actor: actor) {
                        EmptyView()
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func tabLabel(_ tab: CustomSearchViewModel.Tab) -> String {
        switch tab {
        case .top: String(localized: "customsearch.tab.top")
        case .newest: String(localized: "customsearch.tab.newest")
        case .users: String(localized: "customsearch.tab.users")
        }
    }

    private func performSearch() {
        guard let searchAccount,
              let appPassword = accountStore.appPassword(for: searchAccount) else { return }
        Task {
            await viewModel.searchAll(account: searchAccount, appPassword: appPassword, using: blueskyClient)
        }
    }

    private func loadMoreTop() async {
        guard let searchAccount,
              let appPassword = accountStore.appPassword(for: searchAccount) else { return }
        await viewModel.loadMoreTop(account: searchAccount, appPassword: appPassword, using: blueskyClient)
    }

    private func loadMoreNewest() async {
        guard let searchAccount,
              let appPassword = accountStore.appPassword(for: searchAccount) else { return }
        await viewModel.loadMoreNewest(account: searchAccount, appPassword: appPassword, using: blueskyClient)
    }

    private func loadAvailableTargetLists() async {
        guard let account = accountStore.activeAccount,
              let appPassword = accountStore.appPassword(for: account)
        else {
            availableTargetLists = []
            return
        }
        do {
            availableTargetLists = try await blueskyClient.fetchLists(for: account, appPassword: appPassword)
                .sorted {
                    if $0.kind != $1.kind {
                        return $0.kind == .moderation
                    }
                    return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                }
        } catch {
            availableTargetLists = []
        }
    }
}

#Preview {
    CustomSearchView()
        .environmentObject(AccountStore(preview: true))
        .environmentObject(PreviewBlueskyClient())
}
