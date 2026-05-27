import SwiftUI

/// Thin wrapper that always delegates to `ListsView` for the Moderation tab.
/// Previously used `NavigationSplitView` for iPad; now iPhone-only with a direct
/// `ListsView` pass-through.
struct ModerationSplitView: View {
    @EnvironmentObject private var accountStore: AccountStore
    @EnvironmentObject private var blueskyClient: LiveBlueskyClient
    @EnvironmentObject private var workspaceStore: ModerationWorkspaceStore
    @EnvironmentObject private var localizationManager: LocalizationManager

    @StateObject private var viewModel = ListsViewModel()

    var body: some View {
        ListsView()
            .environmentObject(accountStore)
            .environmentObject(blueskyClient)
            .environmentObject(workspaceStore)
            .environmentObject(localizationManager)
    }
}

#Preview {
    ModerationSplitView()
        .environmentObject(AccountStore(preview: true))
        .environmentObject(PreviewBlueskyClient())
        .environmentObject(ModerationWorkspaceStore(preview: true))
        .environmentObject(LocalizationManager.shared)
}
