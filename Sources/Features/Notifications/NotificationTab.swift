import Observation
import SwiftUI

// MARK: - NotificationTab

struct NotificationTab: View {
    @EnvironmentObject var accountStore: AccountStore
    @EnvironmentObject var container: BlueskyServiceContainerWrapper
    @State private var viewModel = NotificationViewModel()
    @State private var selectedActor: BlueskyActor?
    @State private var navigationPath = NavigationPath()
    @EnvironmentObject private var localizationManager: LocalizationManager
    @EnvironmentObject private var workspaceStore: ModerationWorkspaceStore
    @EnvironmentObject private var mutedWordsStore: MutedWordsStore
    @EnvironmentObject private var analyticsStore: AnalyticsStore
    @EnvironmentObject private var internalListStore: InternalListStore
    @State private var availableTargetLists: [BlueskyList] = []

    // MARK: - Body

    var body: some View {
        NavigationStack(path: $navigationPath) {
            Group {
                switch viewModel.state {
                case .initialLoading:
                    skeletonContent
                case .empty:
                    ContentUnavailableView(
                        loc("notifications.empty"),
                        systemImage: "bell.slash",
                        description: Text(loc: "tab.notifications")
                    )
                case let .failed(msg):
                    ContentUnavailableView(
                        loc("list.detail.alert_title"),
                        systemImage: "exclamationmark.bubble",
                        description: Text(msg)
                    )
                default:
                    listContent
                }
            }
            .pageTitle(loc("notifications.title"))
            .navigationDestination(for: TimelineRoute.self) { route in
                switch route {
                case let .thread(postURI):
                    ThreadView(postURI: postURI)
                        .environmentObject(accountStore)
                        .environmentObject(container.blueskyClient)
                        .environmentObject(workspaceStore)
                        .environmentObject(mutedWordsStore)
                        .environmentObject(analyticsStore)
                }
            }
            .sheet(item: $selectedActor) { actor in
                NavigationStack {
                    BlueskyProfileView(
                        member: BlueskyListMember(
                            recordURI: "profile:\(actor.did)",
                            actor: actor
                        ),
                        list: nil
                    )
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button(loc("actions.done")) { selectedActor = nil }
                        }
                    }
                }
            }
        }
        .task {
            guard let account = accountStore.activeAccount,
                  let appPassword = accountStore.appPassword(for: account)
            else { return }
            await viewModel.load(account: account, appPassword: appPassword, using: container.blueskyClient)
            await viewModel.updateUnreadCount(account: account, appPassword: appPassword, using: container.blueskyClient)
            await loadTargetLists(account: account, appPassword: appPassword)
        }
        .onChange(of: accountStore.activeAccount?.did) { _, _ in
            viewModel.reset()
        }
        .badge(viewModel.unreadCount > 0 ? viewModel.unreadCount : 0)
    }

    /// Paginated list of notification rows with load-more on last item appear.
    private var listContent: some View {
        List {
            ForEach(viewModel.entries) { entry in
                NotificationRow(
                    notification: entry.notification,
                    relatedPost: entry.relatedPost,
                    onAuthorTap: {
                        openProfile(for: entry)
                    },
                    onPostTap: {
                        if let uri = entry.relatedPost?.uri ?? entry.relatedPostURI {
                            navigationPath.append(TimelineRoute.thread(postURI: uri))
                        }
                    },
                    onBlockAuthor: makeAuthorCallbacks(author: entry.relatedPost?.author, accountStore: accountStore, blueskyClient: container.blueskyClient, internalListStore: internalListStore).onBlock,
                    onAddAuthorToList: makeAuthorCallbacks(author: entry.relatedPost?.author, accountStore: accountStore, blueskyClient: container.blueskyClient, internalListStore: internalListStore).onAddToList,
                    availableTargetLists: availableTargetLists
                )
                .onAppear {
                    if entry.id == viewModel.entries.last?.id {
                        loadMore()
                    }
                }
            }
        }
        .listStyle(.plain)
        .refreshable {
            await refresh()
        }
    }

    /// Sets the selected actor to open the profile sheet.
    private func openProfile(for entry: NotificationEntry) {
        selectedActor = BlueskyActor(
            did: entry.notification.author.did,
            handle: entry.notification.author.handle,
            displayName: entry.notification.author.displayName,
            avatarURL: URL(string: entry.notification.author.avatar ?? "")
        )
    }

    /// Placeholder skeleton UI shown during initial load.
    private var skeletonContent: some View {
        VStack(spacing: 16) {
            ForEach(0 ..< 10, id: \.self) { _ in
                HStack(spacing: 12) {
                    Circle()
                        .fill(.tertiary.opacity(0.2))
                        .frame(width: 36, height: 36)
                    VStack(alignment: .leading, spacing: 6) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(.tertiary.opacity(0.2))
                            .frame(width: 180, height: 12)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(.tertiary.opacity(0.15))
                            .frame(width: 100, height: 10)
                    }
                    Spacer()
                }
                .padding(.horizontal)
            }
        }
        .padding(.top)
    }

    private func loadTargetLists(account: AppAccount, appPassword: String) async {
        var lists: [BlueskyList] = []
        do {
            lists = try await container.list.fetchLists(for: account, appPassword: appPassword)
        } catch {
            AppLogger.moderation.error("Failed to load target lists: \(error.localizedDescription, privacy: .public)")
        }
        let internalLists = internalListStore.lists.map { internalList in
            BlueskyList(
                id: "internal:\(internalList.id.uuidString)",
                name: internalList.name,
                description: "Internal",
                memberCount: internalList.memberCount,
                kind: .internal,
                cid: nil
            )
        }
        lists.append(contentsOf: internalLists)
        availableTargetLists = lists.sorted { lhs, rhs in
            if lhs.kind != rhs.kind {
                return lhs.kind.sortOrder < rhs.kind.sortOrder
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    /// Pull-to-refresh: marks all read then reloads.
    private func refresh() async {
        guard let account = accountStore.activeAccount,
              let appPassword = accountStore.appPassword(for: account)
        else { return }
        await viewModel.markAllRead(account: account, appPassword: appPassword, using: container.blueskyClient)
        await viewModel.refresh(account: account, appPassword: appPassword, using: container.blueskyClient)
        await viewModel.updateUnreadCount(account: account, appPassword: appPassword, using: container.blueskyClient)
    }

    /// Triggers pagination load of older notifications.
    private func loadMore() {
        guard let account = accountStore.activeAccount,
              let appPassword = accountStore.appPassword(for: account)
        else { return }
        Task { await viewModel.loadMore(account: account, appPassword: appPassword, using: container.blueskyClient) }
    }
}
