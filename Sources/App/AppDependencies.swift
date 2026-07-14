import Foundation

// MARK: - Protocol Seams

/// Protocol for dependency injection of account-related services.
@MainActor
protocol AccountServicing: AnyObject {
    var accountStore: AccountStore { get }
    var localizationManager: LocalizationManager { get }
}

/// Protocol for dependency injection of moderation-related services.
@MainActor
protocol ModerationServicing: AnyObject {
    var blueskyClient: LiveBlueskyClient { get }
    var workspaceStore: ModerationWorkspaceStore { get }
    var mutedWordsStore: MutedWordsStore { get }
    var analyticsStore: AnalyticsStore { get }
}

/// Protocol for dependency injection of AI-related services.
@MainActor
protocol AIServicing: AnyObject {
    var aiService: LiveAIService { get }
}

/// Protocol for dependency injection of chat and push notification services.
@MainActor
protocol ChatServicesProtocol: AnyObject {
    var chatStore: ChatStore { get }
    var pushNotificationCoordinator: PushNotificationCoordinator { get }
}

// MARK: - Wiring

/// Root dependency container. Creates and holds all singleton services and stores
/// used throughout the app. Injected into the SwiftUI environment via `@EnvironmentObject`.
///
/// Initialization branches on launch arguments:
/// - `--uitesting`: Enables English language, preview accounts, and mock services.
///   Onboarding is controlled by sub-flags:
///   - `-UITestSkipOnboarding` (with `--uitesting`): Skips onboarding.
///   - `-UITestFreshOnboarding` (with `--uitesting`): Resets onboarding flag.
///   - `-showBetaFeatures` (with `--uitesting`): Enables beta feature flags.
/// - `--test-account`: Uses `LiveBlueskyClient` + real `AccountStore` for screenshot tests.
/// - Default (no flags): Normal app launch with live services.
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
    let aiService: LiveAIService
    let autoBlockBackService: AutoBlockBackService
    let serviceContainer: BlueskyServiceContainerWrapper

    // MARK: - Init

    init() {
        let isUITesting = CommandLine.arguments.contains("--uitesting")
        if isUITesting {
            // Default: skip onboarding in UI tests for faster test execution.
            // -UITestFreshOnboarding explicitly resets the flag so the
            // onboarding sheet appears for onboarding-specific tests.
            if CommandLine.arguments.contains("-UITestFreshOnboarding") {
                UserDefaults.standard.removeObject(forKey: "hasSeenOnboarding")
            } else {
                UserDefaults.standard.set(true, forKey: "hasSeenOnboarding")
            }
            UserDefaults.standard.set("en", forKey: "selectedLanguage")

            // -showBetaFeatures enables beta feature flags for testing.
            if CommandLine.arguments.contains("-showBetaFeatures") {
                UserDefaults.standard.set(true, forKey: "showBetaFeatures")
            }
        }

        let requestExecutor = BlueskyRequestExecutor()
        let keychain = KeychainService()
        let sessionService = BlueskySessionService(requestExecutor: requestExecutor, keychain: keychain)

        httpRequestDebugStore = HTTPRequestDebugStore.shared
        clearskyHeartbeat = ClearskyHeartbeatService.shared
        let useRealAccount = isUITesting && CommandLine.arguments.contains("--test-account")
        accountStore = useRealAccount ? AccountStore(keychain: keychain) : (isUITesting ? AccountStore(preview: true) : AccountStore(keychain: keychain))
        workspaceStore = ModerationWorkspaceStore()
        blueskyClient = useRealAccount
            ? LiveBlueskyClient(requestExecutor: requestExecutor, sessionService: sessionService)
            : (isUITesting ? PreviewBlueskyClient() : LiveBlueskyClient(requestExecutor: requestExecutor, sessionService: sessionService))
        localizationManager = LocalizationManager.shared
        mutedWordsStore = MutedWordsStore()
        analyticsStore = AnalyticsStore()
        chatStore = ChatStore(chatService: ChatService(requestExecutor: requestExecutor, sessionService: sessionService))
        internalListStore = InternalListStore()
        aiService = LiveAIService()
        autoBlockBackService = AutoBlockBackService(
            clearskyService: blueskyClient,
            profileService: blueskyClient,
            listService: blueskyClient,
            socialService: blueskyClient,
            accountStore: accountStore,
            internalListStore: internalListStore
        )
        pushNotificationCoordinator = PushNotificationCoordinator(
            pushService: BlueskyPushNotificationService(requestExecutor: requestExecutor, sessionService: sessionService),
            accountStore: accountStore,
            workspaceStore: workspaceStore,
            chatStore: chatStore
        )
        serviceContainer = BlueskyServiceContainerWrapper(liveClient: blueskyClient, accountStore: accountStore)
    }
}

// MARK: - Conformance

extension AppDependencies: AccountServicing {}
extension AppDependencies: ModerationServicing {}
extension AppDependencies: AIServicing {}
extension AppDependencies: ChatServicesProtocol {}
