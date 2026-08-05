import SwiftUI

struct iPadChatView: View {
    @EnvironmentObject private var accountStore: AccountStore
    @EnvironmentObject private var container: BlueskyServiceContainerWrapper
    @EnvironmentObject private var chatStore: ChatStore
    @EnvironmentObject private var localizationManager: LocalizationManager

    var body: some View {
        ChatTab()
            .environmentObject(accountStore)
            .environmentObject(chatStore)
            .environmentObject(localizationManager)
    }
}
