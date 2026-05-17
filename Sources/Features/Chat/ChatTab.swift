import SwiftUI

struct ChatTab: View {
    @EnvironmentObject var accountStore: AccountStore
    @EnvironmentObject var chatStore: ChatStore

    var body: some View {
        ConversationListView()
            .environmentObject(chatStore)
            .environmentObject(accountStore)
            .onChange(of: accountStore.activeAccount?.did) { _, _ in
                let pw = accountStore.activeAccount.flatMap { accountStore.appPassword(for: $0) }
                chatStore.setAccount(accountStore.activeAccount, appPassword: pw)
                Task { await chatStore.loadConvos() }
            }
    }
}

#Preview {
    ChatTab()
        .environmentObject(AccountStore(preview: true))
        .environmentObject(ChatStore(chatService: ChatService(
            requestExecutor: BlueskyRequestExecutor(),
            sessionService: BlueskySessionService(requestExecutor: BlueskyRequestExecutor(), keychain: KeychainService())
        )))
}
