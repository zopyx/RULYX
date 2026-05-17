import SwiftUI

func configureCache() {
    let cache = URLCache(memoryCapacity: 50 * 1024 * 1024, diskCapacity: 200 * 1024 * 1024, diskPath: "bluesky-cache")
    URLCache.shared = cache
}

@main
struct BlueskyModerationApp: App {
    @UIApplicationDelegateAdaptor(BlueskyAppDelegate.self) private var appDelegate
    @StateObject private var deps = AppDependencies()
    @StateObject private var appLockManager = AppLockManager.shared
    @State private var showSplash = true

    var body: some Scene {
        WindowGroup {
            ZStack {
                RootView()
                    .environmentObject(deps.accountStore)
                    .environmentObject(deps.workspaceStore)
                    .environmentObject(deps.blueskyClient)
                    .environmentObject(deps.localizationManager)
                    .environmentObject(deps.mutedWordsStore)
                    .environmentObject(deps.analyticsStore)
                    .environmentObject(deps.chatStore)
                    .environmentObject(appLockManager)
                    .environmentObject(iCloudAccountSync.shared)
                    .onAppear {
                        configureCache()
                    }
                    .animation(UIAccessibility.isReduceMotionEnabled ? nil : .default, value: appLockManager.isLocked)
                    .task {
                        await deps.blueskyClient.restoreSessions(for: deps.accountStore.accounts)
                    }
                    .task {
                        deps.pushNotificationCoordinator.start()
                    }
                    .task(id: deps.accountStore.activeAccountID) {
                        let appPassword = deps.accountStore.activeAccount.flatMap { deps.accountStore.appPassword(for: $0) }
                        deps.chatStore.setAccount(deps.accountStore.activeAccount, appPassword: appPassword)
                        deps.chatStore.startPolling()
                        await deps.chatStore.loadConvos()
                        deps.pushNotificationCoordinator.syncAccounts()
                    }
                    .onReceive(deps.accountStore.$accounts) { _ in
                        deps.pushNotificationCoordinator.syncAccounts()
                    }
                    .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
                        appLockManager.appDidEnterBackground()
                    }
                    .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                        appLockManager.appDidBecomeActive()
                        deps.pushNotificationCoordinator.start()
                        deps.chatStore.startPolling()
                    }

                if showSplash {
                    SplashScreenView(isActive: $showSplash)
                        .transition(.opacity)
                        .zIndex(100)
                }
            }
        }
    }
}
