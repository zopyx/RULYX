import SwiftUI

struct iPadListsView: View {
    @EnvironmentObject private var accountStore: AccountStore
    @EnvironmentObject private var blueskyClient: LiveBlueskyClient
    @EnvironmentObject private var workspaceStore: ModerationWorkspaceStore
    @EnvironmentObject private var localizationManager: LocalizationManager
    @EnvironmentObject private var navState: iPadNavigationState
    @EnvironmentObject var internalListStore: InternalListStore

    @StateObject private var viewModel = ListsViewModel()

    @State private var showCreateList = false
    @State private var showInternalListCreate = false

    var body: some View {
        Group {
            if accountStore.accounts.isEmpty {
                emptyAccountView
            } else {
                listSelectionView
            }
        }
        .task {
            await viewModel.load(
                for: accountStore.activeAccount,
                appPassword: accountStore.activeAccount.flatMap { accountStore.appPassword(for: $0) },
                using: blueskyClient
            )
        }
    }

    private var emptyAccountView: some View {
        ContentUnavailableView(
            loc("lists.no_account.title"),
            systemImage: "person.crop.circle.badge.exclamationmark",
            description: Text(loc("lists.no_account.desc"))
        )
    }

    private var listSelectionView: some View {
        List(selection: $navState.selectedList) {
            if let activeAccount = accountStore.activeAccount {
                Section {
                    AccountSummaryCard(
                        account: activeAccount,
                        avatarURL: viewModel.activeProfile?.avatarURL
                    )
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                    .listRowBackground(Color.clear)
                }
            }

            let sortedKinds: [BlueskyList.Kind] = [.moderation, .regular, .internal]
            ForEach(sortedKinds, id: \.self) { kind in
                let lists = viewModel.listsByKind[kind] ?? []
                if !lists.isEmpty || kind == .internal {
                    Section {
                        ForEach(lists) { list in
                            listRow(list)
                                .tag(list)
                        }
                        if kind == .internal {
                            internalListRows
                        }
                    } header: {
                        HStack {
                            Text(listKindTitle(kind))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(lists.count + (kind == .internal ? internalListStore.lists.count : 0))")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle(loc("sidebar.all_lists"))
        .toolbarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button(loc("lists.new_list")) { showCreateList = true }
                    Button(loc("internal_list.new")) { showInternalListCreate = true }
                } label: {
                    Image(systemName: "plus")
                        .accessibilityLabel(loc("lists.create"))
                }
            }
        }
        .sheet(isPresented: $showCreateList) {
            ListTemplatesView(onListCreated: { list in
                viewModel.addList(list)
                navState.selectedList = list
            })
            .environmentObject(accountStore)
            .environmentObject(blueskyClient)
            .environmentObject(workspaceStore)
            .environmentObject(localizationManager)
        }
        .sheet(isPresented: $showInternalListCreate) {
            internalListCreateSheet
        }
    }

    private func listRow(_ list: BlueskyList) -> some View {
        HStack(spacing: 10) {
            Image(systemName: list.kind.symbolName)
                .font(.title3)
                .foregroundStyle(list.kind == .moderation ? Color.skyPrimary : .secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(list.name)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                if let count = list.memberCount {
                    Text("\(count) members")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var internalListRows: some View {
        let lists = internalListStore.lists
        return ForEach(lists, id: \.id) { list in
            HStack(spacing: 10) {
                Circle()
                    .fill(list.color.colorValue)
                    .frame(width: 12, height: 12)
                VStack(alignment: .leading, spacing: 2) {
                    Text(list.name)
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                    Text("\(list.memberCount) members")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var internalListCreateSheet: some View {
        NavigationStack {
            List {
                TextField(loc("internal_list.name_placeholder"), text: .constant(""))
                ColorPicker(loc("internal_list.color"), selection: .constant(.blue))
            }
            .navigationTitle(loc("internal_list.new"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(loc("actions.cancel")) { showInternalListCreate = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(loc("actions.save")) { showInternalListCreate = false }
                }
            }
        }
    }

    private func listKindTitle(_ kind: BlueskyList.Kind) -> String {
        switch kind {
        case .moderation: loc("list.kind.moderation")
        case .regular: loc("list.kind.regular")
        case .internal: loc("list.kind.internal")
        }
    }
}
