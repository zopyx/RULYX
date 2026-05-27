import SwiftUI

/// Thin wrapper that delegates to `ListsView` for the Moderation tab.
/// On iPad (regular width), the sidebar takes over navigation and this
/// simply passes through to the lists content. On iPhone (compact width),
/// it embeds `ListsView` directly in a `NavigationStack`.
struct ModerationSplitView: View {
    @EnvironmentObject private var accountStore: AccountStore
    @EnvironmentObject private var blueskyClient: LiveBlueskyClient
    @EnvironmentObject private var workspaceStore: ModerationWorkspaceStore
    @EnvironmentObject private var localizationManager: LocalizationManager

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @StateObject private var viewModel = ListsViewModel()

    var body: some View {
        if horizontalSizeClass == .regular {
            ListsView()
                .environmentObject(accountStore)
                .environmentObject(blueskyClient)
                .environmentObject(workspaceStore)
                .environmentObject(localizationManager)
        } else {
            ListsView()
                .environmentObject(accountStore)
                .environmentObject(blueskyClient)
                .environmentObject(workspaceStore)
                .environmentObject(localizationManager)
        }
    }
}

#Preview {
    ModerationSplitView()
        .environmentObject(AccountStore(preview: true))
        .environmentObject(PreviewBlueskyClient())
        .environmentObject(ModerationWorkspaceStore(preview: true))
        .environmentObject(LocalizationManager.shared)
}
