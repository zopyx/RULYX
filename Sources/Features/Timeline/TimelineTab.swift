import SwiftUI

// MARK: - TimelineTab

struct TimelineTab: View {
    @EnvironmentObject var accountStore: AccountStore
    @EnvironmentObject var blueskyClient: LiveBlueskyClient
    @EnvironmentObject var workspaceStore: ModerationWorkspaceStore
    @EnvironmentObject var mutedWordsStore: MutedWordsStore
    @EnvironmentObject var analyticsStore: AnalyticsStore
    @StateObject private var viewModel = FeedTimelineViewModel()
    @State private var navigationPath = NavigationPath()

    // MARK: - Body

    var body: some View {
        NavigationStack(path: $navigationPath) {
            FeedTimelineView(viewModel: viewModel, navigationPath: $navigationPath)
                .environmentObject(accountStore)
                .environmentObject(blueskyClient)
                .environmentObject(workspaceStore)
                .environmentObject(mutedWordsStore)
                .environmentObject(analyticsStore)
                .navigationDestination(for: TimelineRoute.self) { route in
                    switch route {
                    case let .thread(postURI):
                        ThreadView(postURI: postURI)
                            .environmentObject(accountStore)
                            .environmentObject(blueskyClient)
                            .environmentObject(workspaceStore)
                            .environmentObject(mutedWordsStore)
                            .environmentObject(analyticsStore)
                    }
                }
        }
        .onAppear {
            syncFeedStore()
        }
        .onChange(of: accountStore.activeAccount?.did) { _, _ in
            viewModel.prepareForAccountChange()
            syncFeedStore()
        }
    }

    /// Ensures the feed store uses the current active account's DID.
    private func syncFeedStore() {
        guard let account = accountStore.activeAccount else { return }
        viewModel.feedStore.setAccount(did: account.did)
    }
}

#Preview {
    TimelineTab()
        .environmentObject(AccountStore(preview: true))
        .environmentObject(PreviewBlueskyClient())
}
