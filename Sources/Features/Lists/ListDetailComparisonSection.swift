import SwiftUI

extension ListDetailView {
    struct ListComparisonSection: View {
        @ObservedObject var viewModel: ListDetailViewModel
        @ObservedObject var batchState: ListBatchProgressState
        @Binding var selectedComparisonListID: String
        let currentList: BlueskyList
        let account: AppAccount
        let appPassword: String
        let diffExportFileURL: URL?
        let comparisonList: BlueskyList?
        let syncSnapshot: () -> Void

        @State private var showComparisonHelp = false
        @EnvironmentObject var accountStore: AccountStore
        @EnvironmentObject var blueskyClient: LiveBlueskyClient
        @EnvironmentObject var workspaceStore: ModerationWorkspaceStore

        private func bucketLocKey(_ bucket: ComparisonBucket) -> String {
            switch bucket {
            case .overlap: "list.compare.bucket_overlap"
            case .onlyInCurrent: "list.compare.bucket_only_current"
            case .onlyInOther: "list.compare.bucket_only_other"
            }
        }

        @EnvironmentObject private var localizationManager: LocalizationManager
        var body: some View {
            DisclosureGroup {
                if viewModel.isLoadingAvailableLists {
                    LoadingPanel(message: loc("list.compare.loading"))
                } else if viewModel.availableLists.isEmpty {
                    EmptyStatePanel(
                        title: loc("list.compare.no_lists"),
                        message: loc("list.compare.no_lists_desc")
                    )
                } else {
                    Picker("list.compare.picker_label", selection: $selectedComparisonListID) {
                        Text(loc: "list.compare.select_list").tag("")
                        ForEach(viewModel.availableLists) { list in
                            Text(list.name).tag(list.id)
                        }
                    }
                    .accessibilityHint(loc("list.compare.picker.hint"))

                    Button {
                        if let comparisonList {
                            Task {
                                await viewModel.compare(
                                    currentList: currentList,
                                    otherList: comparisonList,
                                    account: account,
                                    appPassword: appPassword,
                                    using: blueskyClient
                                )
                            }
                        }
                    } label: {
                        Label { Text(loc: "list.compare.button") } icon: { Image(systemName: "rectangle.split.3x1") }
                    }
                    .disabled(comparisonList == nil || viewModel.isComparingLists)
                    .accessibilityHint(loc("list.compare.calculate.hint"))

                    Button {
                        if let comparisonList {
                            Task {
                                await viewModel.transferSelectedMembers(
                                    from: currentList,
                                    to: comparisonList,
                                    move: false,
                                    account: account,
                                    appPassword: appPassword,
                                    using: blueskyClient
                                )
                            }
                        }
                    } label: {
                        Label { Text(loc: "list.compare.copy") } icon: { Image(systemName: "square.on.square") }
                    }
                    .disabled(comparisonList == nil || viewModel.selectedMemberIDs.isEmpty || batchState.isPerformingBulkAction)
                    .accessibilityHint(loc("list.compare.copy.hint"))

                    Button {
                        if let comparisonList {
                            Task {
                                await viewModel.transferSelectedMembers(
                                    from: currentList,
                                    to: comparisonList,
                                    move: true,
                                    account: account,
                                    appPassword: appPassword,
                                    using: blueskyClient
                                )
                            }
                        }
                    } label: {
                        Label { Text(loc: "list.compare.move") } icon: { Image(systemName: "arrow.right.square") }
                    }
                    .disabled(comparisonList == nil || viewModel.selectedMemberIDs.isEmpty || batchState.isPerformingBulkAction)
                    .accessibilityHint(loc("list.compare.move.hint"))

                    Button {
                        if let comparisonList {
                            Task {
                                await viewModel.transferSelectedMembers(
                                    from: currentList,
                                    to: comparisonList,
                                    move: true,
                                    account: account,
                                    appPassword: appPassword,
                                    using: blueskyClient
                                )
                                syncSnapshot()
                            }
                        }
                    } label: {
                        Label { Text(loc: "list.compare.move") } icon: { Image(systemName: "arrow.right.square") }
                    }
                    .disabled(comparisonList == nil || viewModel.selectedMemberIDs.isEmpty || batchState.isPerformingBulkAction)

                    if let comparisonReport = viewModel.comparisonReport {
                        comparisonSummary(report: comparisonReport)
                        comparisonToolbar

                        ForEach(ComparisonBucket.allCases, id: \.self) { bucket in
                            comparisonBucketSection(bucket)
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(loc: "list.compare.title")
                    HelpInfoButton(
                        action: { showComparisonHelp = true },
                        accessibilityLabel: loc("list.compare.help_title")
                    )
                }
            }
            .sheet(isPresented: $showComparisonHelp) {
                NavigationStack {
                    List {
                        Section {
                            Text(loc("list.compare.help_tooltip"))
                                .font(.body)
                        }
                    }
                    .listStyle(.insetGrouped)
                    .navigationTitle(Text(loc("list.compare.help_title")))
                    .toolbarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            ToolbarCloseButton()
                        }
                    }
                }
            }
        }

        private func comparisonSummary(report: ListComparisonReport) -> some View {
            VStack(alignment: .leading, spacing: 10) {
                Text(loc("list.compare.compared_with").replacingOccurrences(of: "{name}", with: report.otherList.name))
                    .font(.subheadline.weight(.semibold))

                Text(loc("list.compare.overlap_count").replacingOccurrences(of: "{count}", with: "\(report.overlap.count)"))
                Text(loc("list.compare.only_current").replacingOccurrences(of: "{name}", with: currentList.name).replacingOccurrences(of: "{count}", with: "\(report.onlyInCurrent.count)"))
                Text(loc("list.compare.only_other").replacingOccurrences(of: "{name}", with: report.otherList.name).replacingOccurrences(of: "{count}", with: "\(report.onlyInOther.count)"))
            }
        }

        private var comparisonToolbar: some View {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Menu("list.compare.menu_bucket") {
                        ForEach(ComparisonBucket.allCases, id: \.self) { bucket in
                            Button(loc(bucketLocKey(bucket))) {
                                viewModel.selectComparisonBucket(bucket)
                            }
                        }
                    }
                    .accessibilityHint(loc("list.compare.filter_bucket.hint"))

                    Button("list.compare.clear_diff") {
                        viewModel.clearComparisonSelection()
                    }
                    .disabled(viewModel.selectedComparisonActorDIDs.isEmpty)
                    .accessibilityHint(loc("list.compare.clear_diff.hint"))

                    Spacer()

                    if !viewModel.selectedComparisonActorDIDs.isEmpty {
                        Text(verbatim: loc("list.members.selected_count").replacingOccurrences(of: "{count}", with: "\(viewModel.selectedComparisonActorDIDs.count)"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Button {
                    Task {
                        await viewModel.bulkAddComparisonSelection(
                            to: currentList,
                            account: account,
                            appPassword: appPassword,
                            using: blueskyClient
                        )
                        syncSnapshot()
                    }
                } label: {
                    Label { Text(loc: "list.compare.add_here") } icon: { Image(systemName: "arrow.down.left.and.arrow.up.right") }
                }
                .disabled(viewModel.selectedComparisonActorDIDs.isEmpty || batchState.isPerformingBulkAction)
                .accessibilityHint(loc("list.compare.add_here.hint"))

                if let diffExportFileURL {
                    ShareLink(item: diffExportFileURL) {
                        Label { Text(loc: "list.compare.export_csv") } icon: { Image(systemName: "arrow.down.doc") }
                    }
                    .accessibilityHint(loc("list.compare.export_csv.hint"))
                }
            }
            .padding(.vertical, 4)
        }

        private func comparisonBucketSection(_ bucket: ComparisonBucket) -> some View {
            let members = viewModel.comparisonMembers(for: bucket)

            return Group {
                if !members.isEmpty {
                    Section {
                        ForEach(members) { member in
                            Button {
                                viewModel.toggleComparisonSelection(for: member.actor.did)
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: viewModel.selectedComparisonActorDIDs.contains(member.actor.did) ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(viewModel.selectedComparisonActorDIDs.contains(member.actor.did) ? Color.skyPrimary : Color.secondary.opacity(0.45))
                                    BlueskyActorRow(actor: member.actor)
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(
                                viewModel.selectedComparisonActorDIDs.contains(member.actor.did)
                                    ? loc("list.compare.deselect_actor.label").replacingOccurrences(of: "{handle}", with: member.actor.handle)
                                    : loc("list.compare.select_actor.label").replacingOccurrences(of: "{handle}", with: member.actor.handle)
                            )
                            .accessibilityHint(loc("list.compare.toggle_actor.hint"))
                        }
                    } header: {
                        Text(verbatim: loc(bucketLocKey(bucket)))
                    }
                }
            }
        }
    }
}
