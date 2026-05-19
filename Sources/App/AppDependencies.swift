import Foundation

@MainActor
final class AppDependencies: ObservableObject {
    let accountStore: AccountStore
    let workspaceStore: ModerationWorkspaceStore
    let blueskyClient: LiveBlueskyClient
    let localizationManager: LocalizationManager
    let mutedWordsStore: MutedWordsStore
    let analyticsStore: AnalyticsStore
    let chatStore: ChatStore
    let pushNotificationCoordinator: PushNotificationCoordinator
    let httpRequestDebugStore: HTTPRequestDebugStore
    let clearskyHeartbeat: ClearskyHeartbeatService

    init() {
        httpRequestDebugStore = HTTPRequestDebugStore.shared
        clearskyHeartbeat = ClearskyHeartbeatService.shared
        if CommandLine.arguments.contains("--uitesting") {
            UserDefaults.standard.set(true, forKey: "hasSeenOnboarding")
            UserDefaults.standard.set("en", forKey: "selectedLanguage")
            accountStore = AccountStore(preview: true)
            let requestExecutor = BlueskyRequestExecutor()
            let sessionService = BlueskySessionService(requestExecutor: requestExecutor, keychain: KeychainService())
            workspaceStore = ModerationWorkspaceStore()
            blueskyClient = PreviewBlueskyClient()
            localizationManager = LocalizationManager.shared
            mutedWordsStore = MutedWordsStore()
            analyticsStore = AnalyticsStore()
            chatStore = ChatStore(chatService: ChatService(requestExecutor: requestExecutor, sessionService: sessionService))
            pushNotificationCoordinator = PushNotificationCoordinator(
                pushService: BlueskyPushNotificationService(requestExecutor: requestExecutor, sessionService: sessionService),
                accountStore: accountStore,
                workspaceStore: workspaceStore,
                chatStore: chatStore
            )
        } else {
            let requestExecutor = BlueskyRequestExecutor()
            let keychain = KeychainService()
            let sessionService = BlueskySessionService(requestExecutor: requestExecutor, keychain: keychain)

            accountStore = AccountStore(keychain: keychain)
            workspaceStore = ModerationWorkspaceStore()
            blueskyClient = LiveBlueskyClient(
                requestExecutor: requestExecutor,
                sessionService: sessionService
            )
            localizationManager = LocalizationManager.shared
            mutedWordsStore = MutedWordsStore()
            analyticsStore = AnalyticsStore()
            chatStore = ChatStore(chatService: ChatService(requestExecutor: requestExecutor, sessionService: sessionService))
            pushNotificationCoordinator = PushNotificationCoordinator(
                pushService: BlueskyPushNotificationService(requestExecutor: requestExecutor, sessionService: sessionService),
                accountStore: accountStore,
                workspaceStore: workspaceStore,
                chatStore: chatStore
            )
        }
    }
}
