import SwiftUI

extension ListDetailView {
    struct ListSearchSection: View {
        @ObservedObject var viewModel: ListDetailViewModel
        @ObservedObject var batchState: ListBatchProgressState
        @Binding var searchQuery: String
        let currentList: BlueskyList
        let account: AppAccount
        let appPassword: String
        @Binding var isShowingImportSheet: Bool
        @Binding var isShowingImportFilePicker: Bool
        let exportFileURL: URL?
        let syncSnapshot: () -> Void

        @EnvironmentObject var accountStore: AccountStore
        @EnvironmentObject var blueskyClient: LiveBlueskyClient
        @EnvironmentObject var workspaceStore: ModerationWorkspaceStore
        @EnvironmentObject private var localizationManager: LocalizationManager

        var body: some View {
            searchSection
        }

        @FocusState private var searchFieldFocused: Bool

        private var searchSection: some View {
            Section {
                TextField("list.search.placeholder", text: $searchQuery)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityLabel("list.search.field.label")
                    .focused($searchFieldFocused)

                if !viewModel.searchResults.isEmpty || viewModel.hasMoreSearchResults {
                    Text(viewModel.searchResultSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if !viewModel.searchResults.isEmpty {
                    bulkAddToolbar
                }

                if viewModel.isSearching {
                    LoadingPanel(message: String(localized: "list.search.searching"))
                } else if !searchQuery.isEmpty, searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).count < 2 {
                    EmptyStatePanel(
                        title: String(localized: "list.search.keep_typing"),
                        message: String(localized: "list.search.keep_typing_desc")
                    )
                } else if !viewModel.searchResults.isEmpty {
                    ForEach(viewModel.searchResults) { actor in
                        ActorSearchResultRow(
                            actor: actor,
                            isSelected: viewModel.isSelectedForBulkAdd(actor),
                            isAdding: viewModel.isAdding(actor)
                        ) {
                            viewModel.toggleSearchSelection(for: actor)
                        } addAction: {
                            Task {
                                await viewModel.add(
                                    actor: actor,
                                    to: currentList,
                                    account: account,
                                    appPassword: appPassword,
                                    using: blueskyClient
                                )
                                syncSnapshot()
                            }
                        }
                    }

                    if viewModel.isLoadingMoreSearchResults {
                        HStack {
                            ProgressView()
                            Text("list.search.loading_more")
                                .foregroundStyle(.secondary)
                        }
                    } else if viewModel.hasMoreSearchResults {
                        Button("list.search.load_more") {
                            Task {
                                await viewModel.loadMoreSearchResults(
                                    account: account,
                                    appPassword: appPassword,
                                    using: blueskyClient
                                )
                            }
                        }
                        .accessibilityLabel("list.search.load_more.label")
                        .accessibilityHint("list.search.load_more.hint")
                    }
                } else if !searchQuery.isEmpty, !viewModel.isSearching {
                    if let errorMsg = viewModel.searchErrorMessage {
                        ErrorRetryBanner(message: errorMsg) {
                            Task {
                                await viewModel.search(
                                    query: searchQuery,
                                    account: account,
                                    appPassword: appPassword,
                                    using: blueskyClient
                                )
                            }
                        }
                    } else {
                        EmptyStatePanel(
                            title: String(localized: "list.search.no_results"),
                            message: String(localized: "list.search.no_results_desc")
                        )
                    }
                }
            } header: {
                Text("list.search.section")
            }
        }

        private var bulkAddToolbar: some View {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Button(viewModel.selectedSearchActorIDs.count == viewModel.searchResults.count && !viewModel.searchResults.isEmpty ? String(localized: "list.search.clear_selection") : String(localized: "list.search.select_all")) {
                        if viewModel.selectedSearchActorIDs.count == viewModel.searchResults.count, !viewModel.searchResults.isEmpty {
                            viewModel.clearSearchSelection()
                        } else {
                            viewModel.selectAllSearchResults()
                        }
                    }
                    .disabled(batchState.isPerformingBulkAction)
                    .accessibilityHint(viewModel.selectedSearchActorIDs.count == viewModel.searchResults.count && !viewModel.searchResults.isEmpty ? String(localized: "list.search.deselect_all.hint") : String(localized: "list.search.select_all.hint"))

                    Spacer()

                    if !viewModel.selectedSearchActorIDs.isEmpty {
                        Text(verbatim: String(localized: "list.search.selected").replacingOccurrences(of: "{count}", with: "\(viewModel.selectedSearchActorIDs.count)"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Button {
                    Task {
                        await viewModel.bulkAddSelectedActors(
                            to: currentList,
                            account: account,
                            appPassword: appPassword,
                            using: blueskyClient
                        )
                        syncSnapshot()
                    }
                } label: {
                    Label { Text("list.search.add_selected") } icon: { Image(systemName: "person.crop.circle.badge.plus") }
                }
                .disabled(viewModel.selectedSearchActorIDs.isEmpty || batchState.isPerformingBulkAction)
                .accessibilityHint("list.search.add_selected.hint")
            }
        }

        private var workflowToolsSection: some View {
            DisclosureGroup("list.search.tools") {
                Button {
                    isShowingImportSheet = true
                } label: {
                    Label { Text("list.search.paste") } icon: { Image(systemName: "square.and.pencil") }
                }
                .accessibilityLabel("list.search.paste.label")
                .accessibilityHint("list.search.paste.hint")

                Button {
                    isShowingImportFilePicker = true
                } label: {
                    Label { Text("list.search.import_file") } icon: { Image(systemName: "arrow.down.doc") }
                }
                .accessibilityLabel("list.search.import_file.label")
                .accessibilityHint("list.search.import_file.hint")

                if let exportFileURL {
                    ShareLink(item: exportFileURL) {
                        Label { Text("list.search.export_csv") } icon: { Image(systemName: "arrow.down.doc") }
                    }
                    .accessibilityLabel("list.search.export_csv.label")
                    .accessibilityHint("list.search.export_csv.hint")
                }
            }
        }
    }
}
