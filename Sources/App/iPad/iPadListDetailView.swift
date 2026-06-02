import SwiftUI

struct iPadListDetailView: View {
    let list: BlueskyList

    @EnvironmentObject private var accountStore: AccountStore
    @EnvironmentObject private var blueskyClient: LiveBlueskyClient
    @EnvironmentObject private var workspaceStore: ModerationWorkspaceStore
    @EnvironmentObject private var localizationManager: LocalizationManager
    @EnvironmentObject private var navState: iPadNavigationState

    @StateObject private var detailVM = ListDetailViewModel()

    @State private var searchQuery = ""
    @State private var showExport = false
    @State private var showMerge = false

    var body: some View {
        VStack(spacing: 0) {
            listHeader
            Divider()
            memberList
        }
        .task {
            await detailVM.loadMembers(
                for: list,
                account: accountStore.activeAccount!,
                appPassword: accountStore.activeAccount.flatMap { accountStore.appPassword(for: $0) } ?? "",
                using: blueskyClient
            )
        }
        .pageTitle(list.name)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { showExport = true } label: {
                    Image(systemName: "square.and.arrow.up")
                        .accessibilityLabel(loc("lists.export"))
                }
                Button { showMerge = true } label: {
                    Image(systemName: "arrow.left.arrow.right")
                        .accessibilityLabel(loc("lists.merge"))
                }
            }
        }
    }

    private var listHeader: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: list.kind.symbolName)
                    .font(.title2)
                    .foregroundStyle(list.kind == .moderation ? Color.skyPrimary : .secondary)
                Text(list.name)
                    .font(.title2.weight(.semibold))
                Spacer()
                Text("\(detailVM.members.count)")
                    .font(.title.weight(.bold))
                    .foregroundStyle(Color.skyPrimary)
                    + Text(" members")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !list.description.isEmpty {
                Text(list.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 12) {
                listActionButton(loc("lists.add_actor"), icon: "person.badge.plus") {
                    navState.selectedList = nil
                }
                listActionButton(loc("lists.remove"), icon: "person.fill.badge.minus") {
                    navState.selectedList = nil
                }
                listActionButton(loc("lists.import"), icon: "square.and.arrow.down") {
                    navState.selectedList = nil
                }
                listActionButton(loc("lists.export"), icon: "square.and.arrow.up") {
                    showExport = true
                }
            }
            .padding(.vertical, 4)
        }
        .padding()
    }

    private func listActionButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.title3)
                    .frame(height: 20)
                Text(title)
                    .font(.caption2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(.fill.quaternary)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
    }

    private var memberList: some View {
        Group {
            if detailVM.isLoadingMembers {
                VStack(spacing: 16) {
                    ProgressView()
                    Text(loc("lists.loading"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if detailVM.members.isEmpty {
                ContentUnavailableView(
                    loc("lists.no_members"),
                    systemImage: "person.2.slash",
                    description: Text(loc("lists.no_members_desc"))
                )
            } else {
                List {
                    ForEach(filteredMembers) { member in
                        memberRow(member)
                    }
                    if detailVM.hasMoreMembers {
                        HStack {
                            Spacer()
                            ProgressView()
                                .onAppear {
                                    Task {
                                        await detailVM.loadMoreMembersIfNeeded(
                                            currentMember: detailVM.members.last,
                                            list: list,
                                            account: accountStore.activeAccount!,
                                            appPassword: accountStore.activeAccount.flatMap { accountStore.appPassword(for: $0) } ?? "",
                                            using: blueskyClient
                                        )
                                    }
                                }
                            Spacer()
                        }
                    }
                }
                .listStyle(.inset)
                .searchable(text: $searchQuery, prompt: loc("lists.search_members"))
            }
        }
    }

    private var filteredMembers: [BlueskyListMember] {
        if searchQuery.isEmpty {
            return detailVM.members
        }
        return detailVM.members.filter { member in
            member.actor.handle.localizedCaseInsensitiveContains(searchQuery)
                || (member.actor.displayName?.localizedCaseInsensitiveContains(searchQuery) ?? false)
        }
    }

    private func memberRow(_ member: BlueskyListMember) -> some View {
        Button {
            navState.selectedProfileDID = member.actor.did
        } label: {
            HStack(spacing: 12) {
                AsyncImage(url: member.actor.avatarURL) { phase in
                    switch phase {
                    case let .success(image):
                        image.resizable().scaledToFill()
                    default:
                        Image(systemName: "person.crop.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                }
                .frame(width: 40, height: 40)
                .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(member.actor.title)
                        .font(.body.weight(.medium))
                    Text("@\(member.actor.handle)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if let createdAt = member.createdAt {
                    Text(createdAt, style: .date)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .buttonStyle(.plain)
        .padding(.vertical, 2)
        .contextMenu {
            Button(loc("context.open_in_new_window")) {
                let pasteboard = UIPasteboard.general
                pasteboard.string = member.actor.did
            }
            Button(loc("context.copy_handle")) {
                UIPasteboard.general.string = member.actor.handle
            }
            Divider()
            Button(loc("context.block_actor"), role: .destructive) {
                Task {
                    try? await blueskyClient.blockActor(
                        did: member.actor.did,
                        account: accountStore.activeAccount!,
                        appPassword: accountStore.activeAccount.flatMap { accountStore.appPassword(for: $0) }
                    )
                }
            }
        }
    }
}
