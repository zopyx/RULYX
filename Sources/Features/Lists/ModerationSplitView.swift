import SwiftUI

/// Thin wrapper that delegates to `ListsView` for the Moderation tab.
///
/// On iPad (regular width), shows a `NavigationSplitView` with a sidebar
/// of moderation lists and a detail column for the selected list.
/// On iPhone (compact width), embeds `ListsView` directly.
struct ModerationSplitView: View {
    @EnvironmentObject private var accountStore: AccountStore
    @EnvironmentObject private var container: BlueskyServiceContainerWrapper
    @EnvironmentObject private var workspaceStore: ModerationWorkspaceStore
    @EnvironmentObject private var localizationManager: LocalizationManager
    @EnvironmentObject private var internalListStore: InternalListStore
    @EnvironmentObject private var mutedWordsStore: MutedWordsStore
    @EnvironmentObject private var analyticsStore: AnalyticsStore

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var viewModel = ListsViewModel()

    @State private var selectedList: BlueskyList?
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        if horizontalSizeClass == .regular {
            regularBody
        } else {
            ListsView()
                .environmentObject(accountStore)
                .environmentObject(container.blueskyClient)
                .environmentObject(workspaceStore)
                .environmentObject(localizationManager)
                .environmentObject(internalListStore)
                .environmentObject(mutedWordsStore)
                .environmentObject(analyticsStore)
        }
    }

    // MARK: - Regular (iPad landscape)

    private var regularBody: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebarContent
                .navigationTitle(loc("lists.title"))
                .toolbarTitleDisplayMode(.large)
        } content: {
            if let list = selectedList {
                ListDetailView(list: list) { updatedList in
                    selectedList = updatedList
                }
                    .environmentObject(accountStore)
                    .environmentObject(container.blueskyClient)
                    .environmentObject(workspaceStore)
                    .environmentObject(localizationManager)
                    .environmentObject(internalListStore)
                    .environmentObject(mutedWordsStore)
                    .environmentObject(analyticsStore)
                    .id(list.id)
            } else {
                ContentUnavailableView(
                    loc("lists.select_list"),
                    systemImage: "checklist.checked",
                    description: Text(loc: "lists.select_list_desc")
                )
            }
        } detail: {
            ContentUnavailableView(
                loc("lists.detail.select_member"),
                systemImage: "person.circle",
                description: Text(loc: "lists.detail.select_member_desc")
            )
        }
        .task {
            guard let account = accountStore.activeAccount else { return }
            let appPassword = accountStore.appPassword(for: account)
            await viewModel.load(for: account, appPassword: appPassword, using: container.blueskyClient)
        }
    }

    // MARK: - Sidebar

    private var sidebarContent: some View {
        List(selection: $selectedList) {
            if viewModel.isLoading, viewModel.listsByKind.isEmpty {
                ForEach(0 ..< 8) { _ in
                    VStack(alignment: .leading, spacing: 4) {
                        Rectangle().fill(.quaternary).frame(height: 16)
                        Rectangle().fill(.quaternary.opacity(0.5)).frame(height: 10)
                    }
                    .padding(.vertical, 4)
                    .listRowSeparator(.hidden)
                }
                .disabled(true)
            } else if viewModel.listsByKind.values.allSatisfy(\.isEmpty) {
                Text(loc("lists.no_lists"))
                    .foregroundStyle(.secondary)
            } else {
                if let moderation = viewModel.listsByKind[.moderation], !moderation.isEmpty {
                    Section {
                        ForEach(moderation) { list in
                            listRow(list)
                                .tag(list)
                        }
                    } header: {
                        Text(loc("lists.kind.moderation"))
                    }
                }

                if let regular = viewModel.listsByKind[.regular], !regular.isEmpty {
                    Section {
                        ForEach(regular) { list in
                            listRow(list)
                                .tag(list)
                        }
                    } header: {
                        Text(loc("lists.kind.regular"))
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }

    private func listRow(_ list: BlueskyList) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Image(systemName: list.kind == .moderation ? "shield" : "list.bullet")
                    .foregroundStyle(list.kind == .moderation ? Color.skyPrimary : .secondary)
                Text(list.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
            }
            Text(String.localized("lists.member_count", replacements: ["n": "\(list.memberCount ?? 0)"]))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    ModerationSplitView()
        .environmentObject(AccountStore(preview: true))
        .environmentObject(PreviewBlueskyClient())
        .environmentObject(ModerationWorkspaceStore(preview: true))
        .environmentObject(LocalizationManager.shared)
}
