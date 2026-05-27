import SwiftUI

// MARK: - ManagePostsView

/// View for browsing, searching, filtering by date, and deleting posts
/// (single, bulk-selected, or "nuclear" delete-all) for a given account.
struct ManagePostsView: View {
    let did: String
    @StateObject private var viewModel: ManagePostsViewModel
    @EnvironmentObject private var accountStore: AccountStore
    @EnvironmentObject private var blueskyClient: LiveBlueskyClient
    @Environment(\.dismiss) private var dismiss

    init(did: String) {
        self.did = did
        _viewModel = StateObject(wrappedValue: ManagePostsViewModel(did: did))
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading, viewModel.posts.isEmpty {
                    LoadingPanel(message: loc("profile.posts.loading"))
                } else if let error = viewModel.errorMessage, viewModel.posts.isEmpty {
                    ContentUnavailableView(
                        loc("list.detail.alert_title"),
                        systemImage: "exclamationmark.bubble",
                        description: Text(error)
                    )
                } else if viewModel.posts.isEmpty {
                    ContentUnavailableView(
                        loc("profile.posts.empty"),
                        systemImage: "bubble.left",
                        description: Text(loc: "profile.manage_posts.empty_hint")
                    )
                } else {
                    listContent
                }
            }
            .navigationTitle(loc("profile.manage_posts.title"))
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if viewModel.isSelecting {
                        Button(
                            viewModel.selectedURIs.count == viewModel.sortedFilteredPosts.count
                                ? loc("profile.manage_posts.deselect_all")
                                : loc("profile.manage_posts.select_all")
                        ) {
                            if viewModel.selectedURIs.count == viewModel.sortedFilteredPosts.count {
                                viewModel.deselectAll()
                            } else {
                                viewModel.selectAllFiltered()
                            }
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if viewModel.isSelecting {
                        Button(loc("actions.cancel")) {
                            viewModel.exitSelectMode()
                        }
                    } else {
                        Button(loc("profile.manage_posts.select")) {
                            viewModel.isSelecting = true
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    ToolbarCloseButton()
                }
            }
            .confirmationDialog(
                loc("post.delete.confirm"),
                isPresented: .init(
                    get: { viewModel.pendingDeleteEntry != nil },
                    set: { if !$0 { viewModel.pendingDeleteEntry = nil } }
                ),
                titleVisibility: .visible,
                presenting: viewModel.pendingDeleteEntry
            ) { entry in
                Button(loc("post.delete"), role: .destructive) {
                    Task {
                        guard let account = accountStore.activeAccount,
                              let password = accountStore.appPassword(for: account) else { return }
                        await viewModel.deletePost(entry, account: account, appPassword: password, using: blueskyClient)
                    }
                }
                Button(loc("actions.cancel"), role: .cancel) {}
            } message: { _ in
                Text(loc: "post.delete.message")
            }
            .confirmationDialog(
                loc("profile.manage_posts.bulk_confirm")
                    .replacingOccurrences(of: "{n}", with: "\(viewModel.selectedURIs.count)"),
                isPresented: $viewModel.showBulkConfirm,
                titleVisibility: .visible
            ) {
                Button(
                    loc("profile.manage_posts.delete_selected").replacingOccurrences(of: "{n}", with: "\(viewModel.selectedURIs.count)"),
                    role: .destructive
                ) {
                    Task {
                        guard let account = accountStore.activeAccount,
                              let password = accountStore.appPassword(for: account) else { return }
                        await viewModel.deleteSelectedPosts(account: account, appPassword: password, using: blueskyClient)
                    }
                }
                Button(loc("actions.cancel"), role: .cancel) {}
            } message: {
                Text(loc: "profile.manage_posts.bulk_confirm_msg")
            }
            .confirmationDialog(
                loc("profile.manage_posts.nuclear.title"),
                isPresented: .init(
                    get: { viewModel.nuclearDeleteLevel == 1 },
                    set: { if !$0 { viewModel.nuclearDeleteLevel = 0 } }
                ),
                titleVisibility: .visible
            ) {
                Button(loc("profile.manage_posts.nuclear.confirm_1"), role: .destructive) {
                    viewModel.nuclearDeleteLevel = 2
                }
                Button(loc("actions.cancel"), role: .cancel) {
                    viewModel.nuclearDeleteLevel = 0
                }
            } message: {
                Text(loc: "profile.manage_posts.nuclear.desc_1")
            }
            .confirmationDialog(
                loc("profile.manage_posts.nuclear.title"),
                isPresented: .init(
                    get: { viewModel.nuclearDeleteLevel == 2 },
                    set: { if !$0 { viewModel.nuclearDeleteLevel = 0 } }
                ),
                titleVisibility: .visible
            ) {
                Button(loc("profile.manage_posts.nuclear.confirm_2"), role: .destructive) {
                    viewModel.nuclearDeleteLevel = 3
                }
                Button(loc("actions.cancel"), role: .cancel) {
                    viewModel.nuclearDeleteLevel = 0
                }
            } message: {
                Text(loc: "profile.manage_posts.nuclear.desc_2")
            }
            .confirmationDialog(
                loc("profile.manage_posts.nuclear.title"),
                isPresented: .init(
                    get: { viewModel.nuclearDeleteLevel == 3 },
                    set: { if !$0 { viewModel.nuclearDeleteLevel = 0 } }
                ),
                titleVisibility: .visible
            ) {
                Button(loc("profile.manage_posts.nuclear.confirm_3"), role: .destructive) {
                    viewModel.nuclearDeleteLevel = 0
                    Task {
                        guard let account = accountStore.activeAccount,
                              let password = accountStore.appPassword(for: account) else { return }
                        await viewModel.deleteAllPosts(account: account, appPassword: password, using: blueskyClient)
                    }
                }
                Button(loc("actions.cancel"), role: .cancel) {
                    viewModel.nuclearDeleteLevel = 0
                }
            } message: {
                Text(loc: "profile.manage_posts.nuclear.desc_3")
            }
            .overlay {
                if viewModel.isDeleting, let progress = viewModel.deleteProgress {
                    deleteProgressOverlay(progress: progress)
                }
            }
            .task {
                guard let account = accountStore.activeAccount,
                      let password = accountStore.appPassword(for: account) else { return }
                await viewModel.loadPosts(account: account, appPassword: password, using: blueskyClient)
            }
        }
    }

    /// Main list with search, date filter, bulk/nuclear delete, and posts.
    private var listContent: some View {
        List {
            searchSection
            dateFilterSection

            if viewModel.isSelecting, !viewModel.selectedURIs.isEmpty {
                Section {
                    Button(role: .destructive) {
                        viewModel.showBulkConfirm = true
                    } label: {
                        HStack {
                            Image(systemName: "trash")
                            Text(
                                loc("profile.manage_posts.delete_selected")
                                    .replacingOccurrences(of: "{n}", with: "\(viewModel.selectedURIs.count)")
                            )
                        }
                    }
                    Button(role: .destructive) {
                        viewModel.nuclearDeleteLevel = 1
                    } label: {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                            Text(loc("profile.manage_posts.delete_all"))
                                .foregroundStyle(.red)
                        }
                    }
                }
            }

            ForEach(viewModel.sortedFilteredPosts, id: \.post.uri) { entry in
                postRow(for: entry)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            viewModel.pendingDeleteEntry = entry
                        } label: {
                            Label { Text(loc("post.delete")) } icon: { Image(systemName: "trash") }
                        }
                    }
                    .onTapGesture {
                        if viewModel.isSelecting {
                            if viewModel.selectedURIs.contains(entry.post.uri) {
                                viewModel.selectedURIs.remove(entry.post.uri)
                            } else {
                                viewModel.selectedURIs.insert(entry.post.uri)
                            }
                        }
                    }
                    .opacity(viewModel.isSelecting && !viewModel.selectedURIs.contains(entry.post.uri) ? 0.6 : 1)
            }
            .postInfiniteScroll(
                entry: viewModel.sortedFilteredPosts.last ?? viewModel.posts.first!,
                entries: viewModel.sortedFilteredPosts,
                hasMore: viewModel.hasMore,
                isLoadingMore: viewModel.isLoadingMore,
                loadMore: {
                    guard let account = accountStore.activeAccount,
                          let password = accountStore.appPassword(for: account) else { return }
                    await viewModel.loadMore(account: account, appPassword: password, using: blueskyClient)
                }
            )

            if viewModel.isLoadingMore {
                HStack {
                    Spacer()
                    ProgressView()
                        .scaleEffect(0.8)
                    Spacer()
                }
                .listRowSeparator(.hidden)
            }

            if !viewModel.hasMore, !viewModel.posts.isEmpty {
                Text(loc: "profile.posts.end")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
                    .listRowSeparator(.hidden)
            }
        }
        .listStyle(.insetGrouped)
        .refreshable {
            guard let account = accountStore.activeAccount,
                  let password = accountStore.appPassword(for: account) else { return }
            await viewModel.refresh(account: account, appPassword: password, using: blueskyClient)
        }
        .environment(\.editMode, .constant(viewModel.isSelecting ? .active : .inactive))
    }

    /// Search text field with clear button.
    private var searchSection: some View {
        Section {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.tertiary)
                    .font(.subheadline)
                TextField(loc("profile.manage_posts.search"), text: $viewModel.searchText)
                    .textFieldStyle(.plain)
                    .font(.subheadline)
                if !viewModel.searchText.isEmpty {
                    Button {
                        viewModel.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
        }
    }

    /// Preset date range filter chips and custom date pickers.
    private var dateFilterSection: some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(ManagePostsViewModel.RelativeDateOption.allCases, id: \.self) { option in
                        Button {
                            if viewModel.relativeDateFilter == option {
                                viewModel.relativeDateFilter = nil
                                viewModel.fromDate = nil
                                viewModel.toDate = nil
                            } else {
                                viewModel.relativeDateFilter = option
                                viewModel.fromDate = option.dateFrom
                                viewModel.toDate = option == .allTime ? nil : Date()
                            }
                        } label: {
                            Text(loc(option.label))
                                .font(.caption)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(viewModel.relativeDateFilter == option ? Color.accentColor : Color(.systemGray6))
                                .foregroundStyle(viewModel.relativeDateFilter == option ? Color.white : Color.primary)
                                .clipShape(Capsule())
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            if viewModel.fromDate != nil || viewModel.toDate != nil {
                dateFilterPickers
            }

            if viewModel.fromDate == nil, viewModel.toDate == nil {
                Button {
                    viewModel.fromDate = Calendar.current.date(byAdding: .month, value: -1, to: Date())
                    viewModel.toDate = Date()
                } label: {
                    HStack {
                        Image(systemName: "calendar")
                        Text(loc("profile.manage_posts.custom_range"))
                    }
                }
            }
        }
    }

    /// From/to date pickers for custom date range filtering.
    private var dateFilterPickers: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(loc("profile.posts.from_date"))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                DatePicker(
                    "",
                    selection: Binding(
                        get: { viewModel.fromDate ?? Date() },
                        set: {
                            viewModel.fromDate = $0
                            viewModel.relativeDateFilter = nil
                        }
                    ),
                    in: ...Date(),
                    displayedComponents: .date
                )
                .labelsHidden()
                .datePickerStyle(.compact)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(loc("profile.posts.to_date"))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                DatePicker(
                    "",
                    selection: Binding(
                        get: { viewModel.toDate ?? Date() },
                        set: {
                            viewModel.toDate = $0
                            viewModel.relativeDateFilter = nil
                        }
                    ),
                    in: ...Date(),
                    displayedComponents: .date
                )
                .labelsHidden()
                .datePickerStyle(.compact)
            }
        }
        .padding(.bottom, 6)
    }

    /// A single post row with optional selection checkbox.
    private func postRow(for entry: RichFeedEntry) -> some View {
        HStack(spacing: 12) {
            if viewModel.isSelecting {
                Image(
                    systemName: viewModel.selectedURIs.contains(entry.post.uri)
                        ? "checkmark.circle.fill"
                        : "circle"
                )
                .foregroundStyle(
                    viewModel.selectedURIs.contains(entry.post.uri)
                        ? AnyShapeStyle(Color.accentColor)
                        : AnyShapeStyle(.tertiary)
                )
                .font(.title3)
                .onTapGesture {
                    if viewModel.selectedURIs.contains(entry.post.uri) {
                        viewModel.selectedURIs.remove(entry.post.uri)
                    } else {
                        viewModel.selectedURIs.insert(entry.post.uri)
                    }
                }
            }
            PostRowView(
                entry: entry,
                style: .compact,
                callbacks: PostRowCallbacks(
                    onCopy: { UIPasteboard.general.string = entry.post.safeRecord.text },
                    isLiked: entry.post.isLikedByMe,
                    isReposted: entry.post.isRepostedByMe
                )
            )
        }
    }

    /// Modal overlay showing deletion progress with a progress bar.
    private func deleteProgressOverlay(progress: (current: Int, total: Int)) -> some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()
            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.5)
                Text(
                    loc("profile.manage_posts.deleting")
                        .replacingOccurrences(of: "{n}", with: "\(progress.current)")
                        .replacingOccurrences(of: "{total}", with: "\(progress.total)")
                )
                .font(.headline)
                if progress.total > 0 {
                    ProgressView(value: Double(progress.current), total: Double(progress.total))
                        .padding(.horizontal)
                }
            }
            .padding(24)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }
}
