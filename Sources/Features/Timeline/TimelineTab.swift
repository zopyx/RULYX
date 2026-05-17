import SwiftUI

struct TimelineTab: View {
    @EnvironmentObject var accountStore: AccountStore
    @EnvironmentObject var blueskyClient: LiveBlueskyClient
    @EnvironmentObject var workspaceStore: ModerationWorkspaceStore
    @EnvironmentObject var mutedWordsStore: MutedWordsStore
    @EnvironmentObject var analyticsStore: AnalyticsStore
    @StateObject private var viewModel = FeedTimelineViewModel()

    var body: some View {
        FeedTimelineView(viewModel: viewModel)
            .environmentObject(accountStore)
            .environmentObject(blueskyClient)
            .environmentObject(workspaceStore)
            .environmentObject(mutedWordsStore)
            .environmentObject(analyticsStore)
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
