import SwiftUI

// MARK: - NotificationTab

struct NotificationTab: View {
    @EnvironmentObject var accountStore: AccountStore
    @EnvironmentObject var blueskyClient: LiveBlueskyClient
    @StateObject private var viewModel = NotificationViewModel()
    @State private var selectedActor: BlueskyActor?
    @EnvironmentObject private var localizationManager: LocalizationManager

    // MARK: - Body

    var body: some View {
        NavigationStack {
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
                        ToolbarItem(placement: .topBarTrailing) {
                            ToolbarCloseButton(action: { selectedActor = nil })
                        }
                    }
                }
            }
        }
        .task {
            guard let account = accountStore.activeAccount,
                  let appPassword = accountStore.appPassword(for: account)
            else { return }
            await viewModel.load(account: account, appPassword: appPassword, using: blueskyClient)
            await viewModel.updateUnreadCount(account: account, appPassword: appPassword, using: blueskyClient)
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
                    }
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

    /// Pull-to-refresh: marks all read then reloads.
    private func refresh() async {
        guard let account = accountStore.activeAccount,
              let appPassword = accountStore.appPassword(for: account)
        else { return }
        await viewModel.markAllRead(account: account, appPassword: appPassword, using: blueskyClient)
        await viewModel.refresh(account: account, appPassword: appPassword, using: blueskyClient)
        await viewModel.updateUnreadCount(account: account, appPassword: appPassword, using: blueskyClient)
    }

    /// Triggers pagination load of older notifications.
    private func loadMore() {
        guard let account = accountStore.activeAccount,
              let appPassword = accountStore.appPassword(for: account)
        else { return }
        Task { await viewModel.loadMore(account: account, appPassword: appPassword, using: blueskyClient) }
    }
}
