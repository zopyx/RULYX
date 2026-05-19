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
        let isUITesting = CommandLine.arguments.contains("--uitesting")
        if isUITesting {
            UserDefaults.standard.set(true, forKey: "hasSeenOnboarding")
            UserDefaults.standard.set("en", forKey: "selectedLanguage")
        }

        let requestExecutor = BlueskyRequestExecutor()
        let keychain = KeychainService()
        let sessionService = BlueskySessionService(requestExecutor: requestExecutor, keychain: keychain)

        httpRequestDebugStore = HTTPRequestDebugStore.shared
        clearskyHeartbeat = ClearskyHeartbeatService.shared
        accountStore = isUITesting ? AccountStore(preview: true) : AccountStore(keychain: keychain)
        workspaceStore = ModerationWorkspaceStore()
        blueskyClient = isUITesting
            ? PreviewBlueskyClient()
            : LiveBlueskyClient(requestExecutor: requestExecutor, sessionService: sessionService)
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
