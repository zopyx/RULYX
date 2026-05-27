import SwiftUI

struct iPadChatView: View {
    @EnvironmentObject private var accountStore: AccountStore
    @EnvironmentObject private var blueskyClient: LiveBlueskyClient
    @EnvironmentObject private var chatStore: ChatStore
    @EnvironmentObject private var localizationManager: LocalizationManager

    var body: some View {
        ChatTab()
            .environmentObject(accountStore)
            .environmentObject(blueskyClient)
            .environmentObject(chatStore)
            .environmentObject(localizationManager)
    }
}
