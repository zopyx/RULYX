import SwiftUI

struct TimelineTab: View {
    @EnvironmentObject var accountStore: AccountStore
    @EnvironmentObject var blueskyClient: LiveBlueskyClient
    @EnvironmentObject var workspaceStore: ModerationWorkspaceStore
    @EnvironmentObject var mutedWordsStore: MutedWordsStore
    @EnvironmentObject var analyticsStore: AnalyticsStore
    @StateObject private var viewModel = FeedTimelineViewModel()
    @State private var navigationPath = NavigationPath()

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
                    case .thread(let postURI):
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
