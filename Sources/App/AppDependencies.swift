import Foundation

// MARK: - Protocol Seams

@MainActor
protocol AccountServicing: AnyObject {
    var accountStore: AccountStore { get }
    var localizationManager: LocalizationManager { get }
}

@MainActor
protocol ModerationServicing: AnyObject {
    var blueskyClient: LiveBlueskyClient { get }
    var workspaceStore: ModerationWorkspaceStore { get }
    var mutedWordsStore: MutedWordsStore { get }
    var analyticsStore: AnalyticsStore { get }
}

@MainActor
protocol ChatServicesProtocol: AnyObject {
    var chatStore: ChatStore { get }
    var pushNotificationCoordinator: PushNotificationCoordinator { get }
}

// MARK: - Wiring

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
    let internalListStore: InternalListStore

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
        internalListStore = InternalListStore()
        pushNotificationCoordinator = PushNotificationCoordinator(
            pushService: BlueskyPushNotificationService(requestExecutor: requestExecutor, sessionService: sessionService),
            accountStore: accountStore,
            workspaceStore: workspaceStore,
            chatStore: chatStore
        )
    }
}

// MARK: - Conformance

extension AppDependencies: AccountServicing {}
extension AppDependencies: ModerationServicing {}
extension AppDependencies: ChatServicesProtocol {}
