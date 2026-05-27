import SwiftUI

struct iPadTimelineView: View {
    @EnvironmentObject private var accountStore: AccountStore
    @EnvironmentObject private var blueskyClient: LiveBlueskyClient
    @EnvironmentObject private var workspaceStore: ModerationWorkspaceStore
    @EnvironmentObject private var localizationManager: LocalizationManager

    var body: some View {
        TimelineTab()
            .environmentObject(accountStore)
            .environmentObject(blueskyClient)
            .environmentObject(workspaceStore)
            .environmentObject(localizationManager)
    }
}
