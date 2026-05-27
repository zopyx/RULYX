import SwiftUI

/// Configures a larger shared URL cache (50MB memory, 200MB disk) for caching
/// Bluesky API responses, reducing network requests on repeat views.
func configureCache() {
    let cache = URLCache(memoryCapacity: 50 * 1024 * 1024, diskCapacity: 200 * 1024 * 1024, diskPath: "bluesky-cache")
    URLCache.shared = cache
}

// MARK: - App Entry Point

/// The `@main` entry point for the RULYX app.
///
/// ## Lifecycle Coordination
/// The `.task` modifiers execute in a guaranteed order to ensure dependencies
/// are ready before dependent operations begin. Step 5 is keyed to
/// `activeAccountID` so it re-runs when the active account changes:
///
/// 1. **Session restore** — Restores AT Protocol sessions from Keychain for all
///    saved accounts. Must complete before any authenticated call.
/// 2. **Test account** — When launched via UI screenshot tests (`--test-account`),
///    reads env vars and creates a live test account.
/// 3. **Push notifications** — Registers with APNs and syncs the device token
///    with the Bluesky PDS.
/// 4. **Clearsky heartbeat** — Polls the Clearsky API health endpoint to detect
///    outages and show a warning banner.
/// 5. **Chat** — Configures the chat store for the active account and starts
///    polling for direct messages.
///
/// ## Dependency Injection
/// All services, stores, and managers are created within `AppDependencies`
/// (held as `@StateObject`) and injected into `RootView` and its descendants
/// as `@EnvironmentObject`, keeping the view hierarchy free of singletons.
///
/// ## Account Switching
/// When `activeAccountID` changes (via `AccountTabView`), step 5 automatically
/// re-runs, tearing down the previous chat connection and setting up the new one.
@main
struct RULYXApp: App {
    // MARK: - Properties

    /// Handles push notification registration callbacks from UIApplicationDelegate.
    @UIApplicationDelegateAdaptor(BlueskyAppDelegate.self) private var appDelegate

    /// Central dependency container that creates and owns all service instances,
    /// stores, and managers used throughout the app.
    @StateObject private var deps = AppDependencies()

    /// Singleton managing biometric app lock (Face ID / Touch ID) and auto-lock timeout.
    @ObservedObject private var appLockManager = AppLockManager.shared

    /// UserDefaults key `"hasSplashed"`: tracks whether the splash animation
    /// has been shown at least once. On subsequent launches, the splash is
    /// shown briefly (0.5s) then fades out.
    @AppStorage("hasSplashed") private var hasSplashed = false

    /// Controls whether the splash screen overlay is currently rendered on top
    /// of the main content.
    @State private var showSplash = true

    // MARK: - Scene

    var body: some Scene {
        WindowGroup {
            ZStack {
                RootView()

                    // MARK: Environment Injection

                    .environmentObject(deps.accountStore)
                    .environmentObject(deps.workspaceStore)
                    .environmentObject(deps.blueskyClient)
                    .environmentObject(deps.localizationManager)
                    .environment(\.locale, deps.localizationManager.locale)
                    .environmentObject(deps.mutedWordsStore)
                    .environmentObject(deps.analyticsStore)
                    .environmentObject(deps.chatStore)
                    .environmentObject(deps.httpRequestDebugStore)
                    .environmentObject(deps.clearskyHeartbeat)
                    .environmentObject(deps.internalListStore)
                    .environmentObject(deps.aiService)
                    .environmentObject(appLockManager)
                    .environmentObject(iCloudAccountSync.shared)

                    // MARK: iCloud Privacy Alert

                    // Prompts the user for consent before enabling iCloud account sync.
                    // Shows a privacy explanation alert with cancel/confirm buttons.
                    .alert(Text(loc: "settings.icloud.privacy.title"), isPresented: Binding(get: { iCloudAccountSync.shared.showPrivacyAlert }, set: { if !$0 { iCloudAccountSync.shared.showPrivacyAlert = false } })) {
                        Button(loc("settings.icloud.privacy.cancel"), role: .cancel) {
                            iCloudAccountSync.shared.cancelEnable()
                        }
                        Button(loc("settings.icloud.privacy.confirm")) {
                            iCloudAccountSync.shared.confirmEnable()
                        }
                    } message: {
                        Text(loc: "settings.icloud.privacy.message")
                    }

                    // MARK: Lifecycle — URL Cache

                    // Sets up the shared URL cache with increased capacity on first appearance.
                    .onAppear {
                        DispatchQueue.main.async {
                            configureCache()
                        }
                    }

                    // Suppresses the lock/unlock transition animation when Reduce Motion
                    // is enabled in Accessibility settings.
                    .animation(UIAccessibility.isReduceMotionEnabled ? nil : .default, value: appLockManager.isLocked)

                    // MARK: Lifecycle — Step 1: Session Restoration

                    // Restores AT Protocol sessions from Keychain for all saved accounts.
                    // Must complete before any authenticated API call.
                    .task {
                        await deps.blueskyClient.restoreSessions(for: deps.accountStore.accounts)
                    }

                    // MARK: Lifecycle — Step 2: Test Account (UI Tests)

                    // When launched with `--test-account` (screenshot tests), reads
                    // `TEST_HANDLE`, `TEST_PASSWORD`, and optional `TEST_PDS` from the
                    // environment to create a live test account.
                    .task {
                        guard CommandLine.arguments.contains("--test-account"),
                              let handle = ProcessInfo.processInfo.environment["TEST_HANDLE"],
                              let password = ProcessInfo.processInfo.environment["TEST_PASSWORD"] else { return }
                        guard !deps.accountStore.accounts.contains(where: { $0.handle == handle }) else { return }
                        let pdsURL = ProcessInfo.processInfo.environment["TEST_PDS"].flatMap { URL(string: $0) }
                        _ = await deps.accountStore.addAccount(handle: handle, appPassword: password, entrywayURL: pdsURL, client: deps.blueskyClient)
                    }

                    // MARK: Lifecycle — Step 3: Push Notifications

                    // Starts the push notification coordinator, which registers with APNs
                    // and syncs the device token with the Bluesky PDS for remote updates.
                    .task {
                        DispatchQueue.main.async {
                            deps.pushNotificationCoordinator.start()
                        }
                    }

                    // MARK: Lifecycle — Step 4: Clearsky Heartbeat

                    // Begins periodic health checks on the Clearsky API. When Clearsky is
                    // unreachable, the app displays a red warning banner and disables
                    // Clearsky-dependent features.
                    .task {
                        DispatchQueue.main.async {
                            deps.clearskyHeartbeat.start()
                        }
                    }

                    // MARK: Lifecycle — Step 5: Chat (per Active Account)

                    // Configures the chat store for the currently active account.
                    // Re-runs whenever `activeAccountID` changes (user switches account).
                    // Sets credentials, starts polling, loads conversations, and syncs push state.
                    .task(id: deps.accountStore.activeAccountID) {
                        let appPassword = deps.accountStore.activeAccount.flatMap { deps.accountStore.appPassword(for: $0) }
                        deps.chatStore.setAccount(deps.accountStore.activeAccount, appPassword: appPassword)
                        deps.chatStore.startPolling()
                        await deps.chatStore.loadConvos()
                        deps.pushNotificationCoordinator.syncAccounts()
                    }

                    // MARK: Lifecycle — Push Account Sync

                    // Syncs push notification device tokens whenever the accounts list
                    // changes (account added, removed, or active account switched).
                    .onReceive(deps.accountStore.$accounts) { _ in
                        DispatchQueue.main.async {
                            deps.pushNotificationCoordinator.syncAccounts()
                        }
                    }

                    // MARK: Lifecycle — Background / Foreground

                    // On entering background: locks the app (if biometric lock is enabled),
                    // stops the Clearsky heartbeat, and pauses chat polling to save resources.
                    .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
                        DispatchQueue.main.async {
                            appLockManager.appDidEnterBackground()
                            deps.clearskyHeartbeat.stop()
                            deps.chatStore.stopPolling()
                        }
                    }
                    // On becoming active: attempts biometric unlock, resumes the Clearsky
                    // heartbeat, re-registers push notifications, and resumes chat polling.
                    .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                        DispatchQueue.main.async {
                            appLockManager.appDidBecomeActive()
                            deps.clearskyHeartbeat.start()
                            deps.pushNotificationCoordinator.start()
                            deps.chatStore.startPolling()
                        }
                    }

                // MARK: Splash Screen

                // Splash animation overlay rendered above the main content (`zIndex: 100`).
                // On first-ever launch, plays the full animation. On subsequent launches,
                // shows briefly (0.5s) then fades out for a snappier feel.
                if showSplash {
                    SplashScreenView(isActive: $showSplash)
                        .transition(.opacity)
                        // Ensures the splash is always rendered above the main ZStack content.
                        .zIndex(100)
                        .onAppear {
                            if hasSplashed {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                    withAnimation { showSplash = false }
                                }
                            }
                            hasSplashed = true
                        }
                }
            }
        }
    }
}
